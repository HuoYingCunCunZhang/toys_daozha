#include "endstop.h"

#include "board.h"
#include "driver/gpio.h"

#define STABLE_TICKS  3   /* 3 × MOTION_TICK_MS = 15ms 连续一致才认 */

typedef struct {
    gpio_num_t pin;
    bool state;
    bool cand;
    uint8_t cnt;
} sw_t;

static sw_t s_up = { .pin = PIN_LIMIT_UP };
static sw_t s_dn = { .pin = PIN_LIMIT_DN };

static void sw_poll(sw_t *s)
{
    bool raw = (gpio_get_level(s->pin) == LIMIT_ACTIVE_LEVEL);
    if (raw != s->cand) {
        s->cand = raw;
        s->cnt = 0;
    } else if (s->state != s->cand && ++s->cnt >= STABLE_TICKS) {
        s->state = s->cand;
    }
}

void endstop_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = (1ULL << PIN_LIMIT_UP) | (1ULL << PIN_LIMIT_DN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,   /* NC 接法靠这个上拉抬高“已到位”电平 */
    };
    gpio_config(&cfg);

    s_up.state = s_up.cand = (gpio_get_level(PIN_LIMIT_UP) == LIMIT_ACTIVE_LEVEL);
    s_dn.state = s_dn.cand = (gpio_get_level(PIN_LIMIT_DN) == LIMIT_ACTIVE_LEVEL);
}

void endstop_poll(void)
{
    sw_poll(&s_up);
    sw_poll(&s_dn);
}

bool endstop_up(void) { return s_up.state; }
bool endstop_dn(void) { return s_dn.state; }
bool endstop_conflict(void) { return s_up.state && s_dn.state; }
