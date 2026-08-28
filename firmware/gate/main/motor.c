#include "motor.h"

#include "board.h"
#include "driver/ledc.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "motor";

#define LEDC_MODE     LEDC_LOW_SPEED_MODE
#define CH_AIN1       LEDC_CHANNEL_0
#define CH_AIN2       LEDC_CHANNEL_1
#define TIMER_SEL     LEDC_TIMER_0

static uint32_t pct_to_duty(uint8_t pct)
{
    if (pct > 100) pct = 100;
    return (uint32_t)MOTOR_DUTY_MAX * pct / 100u;
}

static void set_ch(ledc_channel_t ch, uint32_t duty)
{
    ledc_set_duty(LEDC_MODE, ch, duty);
    ledc_update_duty(LEDC_MODE, ch);
}

void motor_init(void)
{
    gpio_config_t slp = {
        .pin_bit_mask = 1ULL << PIN_M_SLEEP,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&slp);
    gpio_set_level(PIN_M_SLEEP, 0);   /* 先保证休眠，再配 PWM */

    ledc_timer_config_t tcfg = {
        .speed_mode      = LEDC_MODE,
        .timer_num       = TIMER_SEL,
        .duty_resolution = MOTOR_PWM_RES_BITS,
        .freq_hz         = MOTOR_PWM_HZ,
        .clk_cfg         = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&tcfg));

    const gpio_num_t pins[2] = { PIN_M_AIN1, PIN_M_AIN2 };
    const ledc_channel_t chs[2] = { CH_AIN1, CH_AIN2 };
    for (int i = 0; i < 2; i++) {
        ledc_channel_config_t ccfg = {
            .gpio_num   = pins[i],
            .speed_mode = LEDC_MODE,
            .channel    = chs[i],
            .timer_sel  = TIMER_SEL,
            .duty       = 0,
            .hpoint     = 0,
        };
        ESP_ERROR_CHECK(ledc_channel_config(&ccfg));
    }
    ESP_LOGI(TAG, "PWM %d Hz / %d bit, MOTOR_INVERT=%d", MOTOR_PWM_HZ, MOTOR_PWM_RES_BITS, MOTOR_INVERT);
}

void motor_drive(motor_dir_t dir, uint8_t duty_pct)
{
    if (dir == MOTOR_STOP || duty_pct == 0) {
        set_ch(CH_AIN1, 0);
        set_ch(CH_AIN2, 0);
        return;
    }

    gpio_set_level(PIN_M_SLEEP, 1);

    /* 单脚 PWM + 另一脚拉低 = 快衰减。MOTOR_INVERT 只在这一处生效 */
    bool up = (dir == MOTOR_UP);
#if MOTOR_INVERT
    up = !up;
#endif
    uint32_t duty = pct_to_duty(duty_pct);
    set_ch(up ? CH_AIN1 : CH_AIN2, duty);
    set_ch(up ? CH_AIN2 : CH_AIN1, 0);
}

void motor_brake(void)
{
    gpio_set_level(PIN_M_SLEEP, 1);
    set_ch(CH_AIN1, MOTOR_DUTY_MAX);
    set_ch(CH_AIN2, MOTOR_DUTY_MAX);
}

void motor_stop_and_sleep(void)
{
    motor_brake();
    vTaskDelay(pdMS_TO_TICKS(BRAKE_MS));
    set_ch(CH_AIN1, 0);
    set_ch(CH_AIN2, 0);
    gpio_set_level(PIN_M_SLEEP, 0);
}

void motor_kill(void)
{
    set_ch(CH_AIN1, 0);
    set_ch(CH_AIN2, 0);
    gpio_set_level(PIN_M_SLEEP, 0);
}
