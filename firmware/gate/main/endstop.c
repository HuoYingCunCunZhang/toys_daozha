#include "endstop.h"

#include "board.h"
#include "driver/gpio.h"
#include "esp_log.h"

#define STABLE_TICKS  3   /* 3 × MOTION_TICK_MS = 15ms 连续一致才认 */

typedef struct {
    gpio_num_t pin;
    bool state;
    bool cand;
    uint8_t cnt;
} sw_t;

static const char *TAG = "endstop";

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

    int up = gpio_get_level(PIN_LIMIT_UP);
    int dn = gpio_get_level(PIN_LIMIT_DN);
    /* 上电原始电平。NC 接法下：未压合=0（没到位）、压到位或断线=1。
     * 两个都是 1 -> 多半是根本没接、或接到了 NO 脚上。 */
    ESP_LOGI(TAG, "上电读数 起杆(GPIO%d)=%d 落杆(GPIO%d)=%d，%d 表示到位",
             PIN_LIMIT_UP, up, PIN_LIMIT_DN, dn, LIMIT_ACTIVE_LEVEL);

    s_up.state = s_up.cand = (up == LIMIT_ACTIVE_LEVEL);
    s_dn.state = s_dn.cand = (dn == LIMIT_ACTIVE_LEVEL);
}

void endstop_poll(void)
{
    sw_poll(&s_up);
    sw_poll(&s_dn);
}

bool endstop_up(void) { return s_up.state; }
bool endstop_dn(void) { return s_dn.state; }
bool endstop_conflict(void) { return s_up.state && s_dn.state; }
