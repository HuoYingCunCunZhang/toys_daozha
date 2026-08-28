// 道闸玩具 · 遥控器固件（ESP32-C3 SuperMini）
//
// 全流程就一件事：被按键从深睡唤醒 -> 发一条 ESP-NOW -> 接着睡。
// 不建常驻任务，醒着的时间越短越好 —— 电池只有 250mAh，
// 而且没有电量检测（100k/100k 分压静态就 18.5µA，把深睡预算全吃了）。
#include "board.h"
#include "gate_proto.h"

#include <string.h>

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_now.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "rc";
static const char *NVS_NS = "rc";
static const char *NVS_KEY_PEER = "gate_mac";
static const char *NVS_KEY_SEQ = "seq";

static const uint8_t BCAST[ESP_NOW_ETH_ALEN] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

static uint8_t s_gate[ESP_NOW_ETH_ALEN];
static bool s_have_gate;
static volatile bool s_acked;

/* ---------- NVS ---------- */

static uint32_t seq_next(void)
{
    uint32_t seq = 0;
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) == ESP_OK) {
        nvs_get_u32(h, NVS_KEY_SEQ, &seq);
        seq++;
        nvs_set_u32(h, NVS_KEY_SEQ, seq);
        nvs_commit(h);
        nvs_close(h);
    }
    return seq;
}

static void gate_load(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return;
    size_t len = ESP_NOW_ETH_ALEN;
    s_have_gate = (nvs_get_blob(h, NVS_KEY_PEER, s_gate, &len) == ESP_OK && len == ESP_NOW_ETH_ALEN);
    nvs_close(h);
}

static void gate_save(const uint8_t *mac)
{
    memcpy(s_gate, mac, ESP_NOW_ETH_ALEN);
    s_have_gate = true;
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_blob(h, NVS_KEY_PEER, mac, ESP_NOW_ETH_ALEN);
        nvs_commit(h);
        nvs_close(h);
    }
    ESP_LOGI(TAG, "记住主机 " MACSTR, MAC2STR(mac));
}

/* ---------- 按键 ---------- */

static void buttons_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = BTN_WAKE_MASK,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&cfg);
}

static bool pressed(gpio_num_t pin)
{
    return gpio_get_level(pin) == BTN_ACTIVE_LEVEL;
}

static bool any_pressed(void)
{
    return pressed(PIN_BTN_UP) || pressed(PIN_BTN_DN) || pressed(PIN_BTN_RST);
}

/* ---------- ESP-NOW ---------- */

static void on_recv(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    gate_pkt_t pkt;
    if (len != (int)sizeof(pkt)) return;
    memcpy(&pkt, data, sizeof(pkt));
    if (!gate_pkt_valid(&pkt, sizeof(pkt))) return;
    if (pkt.cmd != GATE_CMD_ACK) return;

    if (!s_have_gate || memcmp(info->src_addr, s_gate, ESP_NOW_ETH_ALEN) != 0) {
        gate_save(info->src_addr);
    }
    s_acked = true;
    ESP_LOGI(TAG, "收到 ACK，主机状态=%u", pkt.arg);
}

static void peer_add(const uint8_t *mac)
{
    esp_now_peer_info_t p = { .channel = GATE_ESPNOW_CHAN, .ifidx = WIFI_IF_STA, .encrypt = false };
    memcpy(p.peer_addr, mac, ESP_NOW_ETH_ALEN);
    if (!esp_now_is_peer_exist(mac)) esp_now_add_peer(&p);
}

static void radio_up(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));   /* 别写 flash，省时间也省寿命 */
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_channel(GATE_ESPNOW_CHAN, WIFI_SECOND_CHAN_NONE));

    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_register_recv_cb(on_recv));

    peer_add(BCAST);
    if (s_have_gate) peer_add(s_gate);
}

static void send_cmd(uint8_t cmd, bool force_broadcast)
{
    const uint8_t *dst = (s_have_gate && !force_broadcast) ? s_gate : BCAST;
    gate_pkt_t pkt = { .cmd = cmd, .seq = seq_next(), .arg = 0 };
    gate_pkt_seal(&pkt);

    for (int i = 0; i < SEND_REPEAT && !s_acked; i++) {
        esp_now_send(dst, (const uint8_t *)&pkt, sizeof(pkt));
        vTaskDelay(pdMS_TO_TICKS(SEND_GAP_MS));
    }
    for (int w = 0; w < ACK_WAIT_MS / 10 && !s_acked; w++) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    ESP_LOGI(TAG, "cmd=%u seq=%lu -> " MACSTR " %s",
             cmd, (unsigned long)pkt.seq, MAC2STR(dst), s_acked ? "已确认" : "无应答");
}

/* ---------- 睡 ---------- */

static void go_sleep(void)
{
    /* 等所有键松开再睡，否则按住不放会被立刻唤醒、循环发命令 */
    int64_t t0 = esp_timer_get_time();
    while (any_pressed() && (esp_timer_get_time() - t0) < RELEASE_TIMEOUT_MS * 1000LL) {
        vTaskDelay(pdMS_TO_TICKS(20));
    }

    esp_now_deinit();
    esp_wifi_stop();

    /* ⚠ C3 没有 RTC IO（`SOC_RTCIO_PIN_COUNT == 0`），`rtc_gpio_*` 那套函数在这颗芯片上
     *   根本不存在 —— 不用（也不能）手工去开 RTC 上拉。
     *   深睡期间的上拉由 `ESP_SLEEP_GPIO_ENABLE_INTERNAL_RESISTORS`（默认开）在
     *   `esp_deep_sleep_start()` 里按唤醒模式自动配：低电平唤醒 -> 自动上拉。
     *   板上也确实没有外部上拉（设计方案 §4.2：三个键统一按下接 GND，用内部上拉）。
     *   静态不耗电，只有按下的瞬间流 3.3V/45k ≈ 73µA，对 <20µA 的深睡指标没影响。 */
    ESP_ERROR_CHECK(esp_sleep_enable_gpio_wakeup_on_hp_periph_powerdown(
        BTN_WAKE_MASK, ESP_GPIO_WAKEUP_GPIO_LOW));

    ESP_LOGI(TAG, "睡了");
    esp_deep_sleep_start();
}

/* ---------- 主流程 ---------- */

void app_main(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    buttons_init();
    gate_load();

    vTaskDelay(pdMS_TO_TICKS(DEBOUNCE_MS));   /* 消抖：唤醒瞬间电平还在弹 */

    bool up = pressed(PIN_BTN_UP);
    bool dn = pressed(PIN_BTN_DN);
    bool rst = pressed(PIN_BTN_RST);

    if (!up && !dn && !rst) {
        /* 噪声唤醒或已松手，什么都别发 */
        ESP_LOGI(TAG, "无按键，回去睡");
        go_sleep();
    }

    radio_up();

    if (up && dn) {
        /* 抬杆+落杆同时按住 3s = 配对。用这两个键是因为
         * 复位键在上盖背面按不到（面板是实心的）*/
        int64_t t0 = esp_timer_get_time();
        while (pressed(PIN_BTN_UP) && pressed(PIN_BTN_DN)) {
            if (esp_timer_get_time() - t0 >= PAIR_HOLD_MS * 1000LL) {
                ESP_LOGI(TAG, "发配对广播（主机需在开机 60s 内）");
                send_cmd(GATE_CMD_PAIR, true);
                go_sleep();
            }
            vTaskDelay(pdMS_TO_TICKS(20));
        }
        /* 没按满 3s 就松了一个 —— 意图不明，不猜，直接睡 */
        ESP_LOGI(TAG, "双键未按满 3s，放弃");
        go_sleep();
    }

    if (up)       send_cmd(GATE_CMD_OPEN, false);
    else if (dn)  send_cmd(GATE_CMD_CLOSE, false);
    else if (rst) send_cmd(GATE_CMD_RESET, false);

    go_sleep();
}
