// 道闸玩具 · 主机固件入口
// 方案：../../../道闸玩具_电路与结构设计方案_v2.md §7
#include "board.h"
#include "buzzer.h"
#include "comms.h"
#include "events.h"
#include "input.h"
#include "motion.h"
#include "sr.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

static const char *TAG = "main";

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
        ESP_LOGI(TAG, "状态=%s T=%lums VBAT=%.2fV",
                 motion_state_name(motion_state()),
                 (unsigned long)motion_travel_ms(),
                 input_battery_v());
    }
}
