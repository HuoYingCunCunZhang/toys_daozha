// 道闸玩具 · 主机固件入口
// 方案：../../../道闸玩具_电路与结构设计方案_v2.md §7
#include "board.h"
#include "buzzer.h"
#include "comms.h"
#include "events.h"
#include "input.h"
#include "motion.h"
#include "sr.h"

#include "esp_attr.h"
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

static const char *TAG = "main";

/* 复位计数，放 RTC 内存里：软复位/看门狗/brownout 都不清零，只有真正断电才归零。
 * 用途：脱离 USB 跑电池时看不到日志，事后插上 USB 一读就知道刚才有没有 brownout 复位过
 * （方案 §5 早就预告：电机启动瞬间升压塌陷 → 主控 brownout → "一按遥控器整机重启"）。
 * 魔数不对 = 刚上电，先清零。 */
#define RST_MAGIC 0xB0D0C0DEu
static RTC_NOINIT_ATTR uint32_t s_rst_magic;
static RTC_NOINIT_ATTR uint32_t s_rst_total;
static RTC_NOINIT_ATTR uint32_t s_rst_brownout;

static void log_reset_reason(void)
{
    esp_reset_reason_t r = esp_reset_reason();
    if (s_rst_magic != RST_MAGIC || r == ESP_RST_POWERON) {
        s_rst_magic = RST_MAGIC;
        s_rst_total = 0;
        s_rst_brownout = 0;
    }
    s_rst_total++;
    if (r == ESP_RST_BROWNOUT) s_rst_brownout++;
    /* 数字用 ASCII 打，中文经 USB-JTAG 回来是 ??（rcdiag 那条教训） */
    ESP_LOGI(TAG, "reset_reason=%d (1=POWERON 3=SW 4=PANIC 5/6/7=WDT 9=BROWNOUT) "
             "since_poweron: resets=%lu brownouts=%lu",
             (int)r, (unsigned long)s_rst_total, (unsigned long)s_rst_brownout);
}

QueueHandle_t g_evt_q;

void evt_post(evt_type_t type, evt_src_t src, uint16_t arg)
{
    evt_t e = { .type = (uint8_t)type, .src = (uint8_t)src, .arg = arg };
    if (g_evt_q && xQueueSend(g_evt_q, &e, 0) != pdTRUE) {
        ESP_LOGW(TAG, "事件队列满，丢弃 type=%d", type);
    }
}

void app_main(void)
{
    log_reset_reason();

    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    g_evt_q = xQueueCreate(8, sizeof(evt_t));

    buzzer_init();
    motion_start();   /* 内部自动 HOMING */
    input_start();
    comms_start();
    sr_start();

    ESP_LOGI(TAG, "启动完成");

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        ESP_LOGI(TAG, "状态=%s VBAT=%.2fV",
                 motion_state_name(motion_state()), input_battery_v());
    }
}
