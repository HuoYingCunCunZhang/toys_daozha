#include "input.h"

#include "board.h"
#include "events.h"

#include "driver/gpio.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "input";

#define POLL_MS        10
#define BAT_PERIOD_MS  10000

/* ---------- 按键 ----------
 * 单键要等松手才动作：按下就动作的话，双键复位（两个键几乎不可能同时按下）
 * 一定会先误触发一次抬杆或落杆。overlap 标记记住“这次按压期间另一个键也按过”，
 * 松手时据此丢弃。 */
typedef struct {
    gpio_num_t pin;
    evt_type_t cmd;
    bool level;       /* 已消抖：true=按下 */
    bool cand;
    uint8_t cnt;
    bool overlap;
} btn_t;

static btn_t s_btn[2] = {
    { .pin = PIN_BTN_UP, .cmd = EVT_CMD_OPEN },
    { .pin = PIN_BTN_DN, .cmd = EVT_CMD_CLOSE },
};

#define STABLE_TICKS  (BTN_DEBOUNCE_MS / POLL_MS)

static int64_t s_both_since_us;
static bool s_reset_fired;

static bool btn_poll(btn_t *b)   /* 返回 true 表示这一拍发生了“松手” */
{
    bool raw = (gpio_get_level(b->pin) == BTN_ACTIVE_LEVEL);
    bool released = false;
    if (raw != b->cand) {
        b->cand = raw;
        b->cnt = 0;
    } else if (b->level != b->cand && ++b->cnt >= STABLE_TICKS) {
        released = (b->level && !b->cand);
        b->level = b->cand;
        if (b->level) b->overlap = false;   /* 新一次按压，重新计 */
    }
    return released;
}

static void buttons_tick(void)
{
    bool rel[2];
    for (int i = 0; i < 2; i++) rel[i] = btn_poll(&s_btn[i]);

    bool both = s_btn[0].level && s_btn[1].level;
    if (both) {
        s_btn[0].overlap = s_btn[1].overlap = true;
        if (s_both_since_us == 0) s_both_since_us = esp_timer_get_time();
        if (!s_reset_fired && esp_timer_get_time() - s_both_since_us >= BTN_RESET_HOLD_MS * 1000LL) {
            ESP_LOGI(TAG, "双键长按 3s -> 复位");
            evt_post(EVT_CMD_RESET, SRC_BUTTON, 0);
            s_reset_fired = true;
        }
    } else if (!s_btn[0].level && !s_btn[1].level) {
        s_both_since_us = 0;
        s_reset_fired = false;
    }

    for (int i = 0; i < 2; i++) {
        if (rel[i] && !s_btn[i].overlap) {
            evt_post(s_btn[i].cmd, SRC_BUTTON, 0);
        }
    }
}

/* ---------- 电池采样 ---------- */

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;
static float s_vbat = -1.0f;

static void battery_init(void)
{
    adc_oneshot_unit_init_cfg_t ucfg = { .unit_id = ADC_UNIT_1 };
    if (adc_oneshot_new_unit(&ucfg, &s_adc) != ESP_OK) { s_adc = NULL; return; }

    adc_oneshot_chan_cfg_t ccfg = {
        .atten = ADC_ATTEN_DB_12,      /* VBAT 4.2V / 2 = 2.1V，落在 12dB 量程内 */
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    adc_oneshot_config_channel(s_adc, ADC_CHANNEL_0, &ccfg);   /* GPIO1 = ADC1_CH0 */

    adc_cali_curve_fitting_config_t cal = {
        .unit_id = ADC_UNIT_1,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    if (adc_cali_create_scheme_curve_fitting(&cal, &s_cali) != ESP_OK) s_cali = NULL;
}

static void battery_sample(void)
{
    if (!s_adc) return;
    int raw = 0, mv = 0;
    if (adc_oneshot_read(s_adc, ADC_CHANNEL_0, &raw) != ESP_OK) return;
    if (s_cali && adc_cali_raw_to_voltage(s_cali, raw, &mv) == ESP_OK) {
        s_vbat = mv / 1000.0f * VBAT_DIV_RATIO;
    } else {
        s_vbat = raw / 4095.0f * 3.1f * VBAT_DIV_RATIO;   /* 未校准的粗估 */
    }
    ESP_LOGI(TAG, "VBAT ≈ %.2fV", s_vbat);
}

float input_battery_v(void) { return s_vbat; }

/* ---------- 任务 ---------- */

static void input_task(void *arg)
{
    gpio_config_t cfg = {
        .pin_bit_mask = (1ULL << PIN_BTN_UP) | (1ULL << PIN_BTN_DN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    gpio_config(&cfg);
    for (int i = 0; i < 2; i++) {
        s_btn[i].level = s_btn[i].cand = (gpio_get_level(s_btn[i].pin) == BTN_ACTIVE_LEVEL);
    }

    battery_init();
    battery_sample();
    uint32_t bat_acc = 0;

    for (;;) {
        buttons_tick();
        if ((bat_acc += POLL_MS) >= BAT_PERIOD_MS) {
            bat_acc = 0;
            battery_sample();
        }
        vTaskDelay(pdMS_TO_TICKS(POLL_MS));
    }
}

void input_start(void)
{
    xTaskCreate(input_task, "input", 4096, NULL, 3, NULL);
}
