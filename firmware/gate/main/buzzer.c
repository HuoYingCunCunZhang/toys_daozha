#include "buzzer.h"

#include "board.h"
#include "driver/gpio.h"
#include "esp_timer.h"

/* 每个节奏是一串 on/off 毫秒数，0 结尾。FAULT 靠 repeat 无限循环 */
typedef struct {
    const uint16_t *seq;
    bool repeat;
} pattern_t;

static const uint16_t SEQ_TICK[]   = { 40, 0 };
static const uint16_t SEQ_ARRIVE[] = { 60, 80, 60, 0 };
static const uint16_t SEQ_PINCH[]  = { 80, 60, 80, 60, 80, 0 };
static const uint16_t SEQ_FAULT[]  = { 400, 300, 0 };
static const uint16_t SEQ_PAIRED[] = { 100, 80, 200, 0 };

static const pattern_t PATTERNS[] = {
    [BEEP_TICK]   = { SEQ_TICK,   false },
    [BEEP_ARRIVE] = { SEQ_ARRIVE, false },
    [BEEP_PINCH]  = { SEQ_PINCH,  false },
    [BEEP_FAULT]  = { SEQ_FAULT,  true  },
    [BEEP_PAIRED] = { SEQ_PAIRED, false },
};

static esp_timer_handle_t s_timer;
static const pattern_t *s_cur;
static int s_idx;

static void step(void *arg);

static void arm(uint16_t ms, int level)
{
    gpio_set_level(PIN_BUZZER, level);
    esp_timer_start_once(s_timer, (uint64_t)ms * 1000);
}

static void step(void *arg)
{
    if (!s_cur) return;
    s_idx++;
    if (s_cur->seq[s_idx] == 0) {
        if (!s_cur->repeat) { gpio_set_level(PIN_BUZZER, 0); s_cur = NULL; return; }
        s_idx = 0;
    }
    arm(s_cur->seq[s_idx], (s_idx % 2 == 0) ? 1 : 0);   /* 偶数下标=响 */
}

void buzzer_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << PIN_BUZZER,
        .mode = GPIO_MODE_OUTPUT,
    };
    gpio_config(&cfg);
    gpio_set_level(PIN_BUZZER, 0);

    const esp_timer_create_args_t args = { .callback = step, .name = "buzz" };
    esp_timer_create(&args, &s_timer);
}

void buzzer_play(beep_t pattern)
{
    esp_timer_stop(s_timer);
    s_cur = &PATTERNS[pattern];
    s_idx = 0;
    arm(s_cur->seq[0], 1);
}

void buzzer_stop(void)
{
    esp_timer_stop(s_timer);
    s_cur = NULL;
    gpio_set_level(PIN_BUZZER, 0);
}
