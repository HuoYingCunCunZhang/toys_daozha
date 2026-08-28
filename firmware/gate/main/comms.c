#include "comms.h"

#include "board.h"
#include "buzzer.h"
#include "events.h"
#include "gate_proto.h"
#include "motion.h"

#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "esp_now.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "nvs.h"

static const char *TAG = "comms";
static const char *NVS_NS = "gate";
static const char *NVS_KEY_PEER = "peer_mac";

static const uint8_t BCAST[ESP_NOW_ETH_ALEN] = { 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

static uint8_t s_peer[ESP_NOW_ETH_ALEN];
static bool s_paired;
static uint32_t s_last_seq;
static int64_t s_boot_us;

static bool mac_eq(const uint8_t *a, const uint8_t *b)
{
    return memcmp(a, b, ESP_NOW_ETH_ALEN) == 0;
}

static void peer_add(const uint8_t *mac)
{
    esp_now_peer_info_t p = { .channel = GATE_ESPNOW_CHAN, .ifidx = WIFI_IF_STA, .encrypt = false };
    memcpy(p.peer_addr, mac, ESP_NOW_ETH_ALEN);
    if (esp_now_is_peer_exist(mac)) esp_now_mod_peer(&p);
    else esp_now_add_peer(&p);
}

static void peer_save(const uint8_t *mac)
{
    memcpy(s_peer, mac, ESP_NOW_ETH_ALEN);
    s_paired = true;
    peer_add(mac);

    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_blob(h, NVS_KEY_PEER, mac, ESP_NOW_ETH_ALEN);
        nvs_commit(h);
        nvs_close(h);
    }
    ESP_LOGI(TAG, "已配对 " MACSTR, MAC2STR(mac));
}

static void peer_load(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return;
    size_t len = ESP_NOW_ETH_ALEN;
    if (nvs_get_blob(h, NVS_KEY_PEER, s_peer, &len) == ESP_OK && len == ESP_NOW_ETH_ALEN) {
        s_paired = true;
        ESP_LOGI(TAG, "NVS 里的遥控器 " MACSTR, MAC2STR(s_peer));
    }
    nvs_close(h);
}

static void send_ack(const uint8_t *mac, uint32_t seq)
{
    gate_pkt_t ack = { .cmd = GATE_CMD_ACK, .seq = seq, .arg = (uint16_t)motion_state() };
    gate_pkt_seal(&ack);
    esp_now_send(mac, (const uint8_t *)&ack, sizeof(ack));
}

static void on_recv(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    gate_pkt_t pkt;
    if (len != (int)sizeof(pkt)) return;
    memcpy(&pkt, data, sizeof(pkt));
    if (!gate_pkt_valid(&pkt, sizeof(pkt))) {
        ESP_LOGW(TAG, "丢弃：magic/ver/crc 不符");
        return;
    }

    const uint8_t *src = info->src_addr;

    if (pkt.cmd == GATE_CMD_PAIR) {
        /* 配对只在开机后 PAIR_WINDOW_MS 内受理：
         * 否则邻居家一按遥控器就把主机抢走了 */
        if (esp_timer_get_time() - s_boot_us > (int64_t)PAIR_WINDOW_MS * 1000) {
            ESP_LOGW(TAG, "配对窗口已关闭，忽略 " MACSTR, MAC2STR(src));
            return;
        }
        peer_add(src);
        send_ack(src, pkt.seq);
        peer_save(src);
        buzzer_play(BEEP_PAIRED);
        return;
    }

    if (s_paired && !mac_eq(src, s_peer)) {
        ESP_LOGW(TAG, "非配对遥控器 " MACSTR "，忽略", MAC2STR(src));
        return;
    }
    if (!s_paired) {          /* 还没配过就认第一个说得上话的 */
        peer_add(src);
        peer_save(src);
    }

    if (pkt.seq == s_last_seq && pkt.cmd != GATE_CMD_PING) {
        return;               /* 遥控器为抗丢包会连发同一条，去重 */
    }
    s_last_seq = pkt.seq;

    switch (pkt.cmd) {
    case GATE_CMD_OPEN:  evt_post(EVT_CMD_OPEN,  SRC_REMOTE, 0); break;
    case GATE_CMD_CLOSE: evt_post(EVT_CMD_CLOSE, SRC_REMOTE, 0); break;
    case GATE_CMD_RESET: evt_post(EVT_CMD_RESET, SRC_REMOTE, 0); break;
    case GATE_CMD_PING:  break;
    default: return;
    }
    send_ack(src, pkt.seq);
}

void comms_start(void)
{
    s_boot_us = esp_timer_get_time();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());
    /* 不连路由器，固定信道 1（方案 §7.6）。两边不一致就完全收不到 */
    ESP_ERROR_CHECK(esp_wifi_set_channel(GATE_ESPNOW_CHAN, WIFI_SECOND_CHAN_NONE));

    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_register_recv_cb(on_recv));

    peer_load();
    if (s_paired) peer_add(s_peer);
    peer_add(BCAST);          /* 收配对广播 */

    uint8_t mac[6];
    esp_wifi_get_mac(WIFI_IF_STA, mac);
    ESP_LOGI(TAG, "主机 MAC " MACSTR "，信道 %d，配对窗口 %ds",
             MAC2STR(mac), GATE_ESPNOW_CHAN, PAIR_WINDOW_MS / 1000);
}
