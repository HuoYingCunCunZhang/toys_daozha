#include "motion.h"

#include "board.h"
#include "buzzer.h"
#include "endstop.h"
#include "events.h"
#include "motor.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"

static const char *TAG = "motion";
static const char *NVS_NS = "gate";
static const char *NVS_KEY_T = "travel_ms";

static gate_state_t s_state = ST_BOOT;
static uint32_t s_travel_ms = TRAVEL_MS_DEFAULT;

static int64_t s_move_start_us;   /* 本段运动的起点 */
static bool s_pinched;            /* 这次抬杆是防砸反转来的，不是用户要的 */
static bool s_from_full_travel;   /* 起点是限位（不是半路反转）-> 到位时可用于标定 */

const char *motion_state_name(gate_state_t s)
{
    static const char *N[] = { "BOOT", "HOMING", "CLOSED", "OPENING", "OPEN", "CLOSING", "FAULT" };
    return (s <= ST_FAULT) ? N[s] : "?";
}

gate_state_t motion_state(void) { return s_state; }
uint32_t motion_travel_ms(void) { return s_travel_ms; }

static uint32_t elapsed_ms(void)
{
    return (uint32_t)((esp_timer_get_time() - s_move_start_us) / 1000);
}

/* ---------- T 的标定与持久化 ---------- */

static void travel_load(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return;
    uint32_t v = 0;
    if (nvs_get_u32(h, NVS_KEY_T, &v) == ESP_OK && v >= TRAVEL_MS_MIN && v <= TRAVEL_MS_MAX) {
        s_travel_ms = v;
        ESP_LOGI(TAG, "NVS 里的行程时间 T=%lums", (unsigned long)v);
    }
    nvs_close(h);
}

/* 只有“从一个限位干净地跑到另一个限位”才配当标定样本。
 * 半路反转、防砸反转、HOMING 都是不完整行程，拿来标定会把 T 越校越短，
 * 而 T 变短 = 防砸阈值变短 = 正常行程被误判成夹到东西。 */
static void travel_calibrate(uint32_t ms)
{
    if (!s_from_full_travel) return;
    if (ms < TRAVEL_MS_MIN || ms > TRAVEL_MS_MAX) {
        ESP_LOGW(TAG, "行程 %lums 超出 [%d,%d]，不采纳", (unsigned long)ms, TRAVEL_MS_MIN, TRAVEL_MS_MAX);
        return;
    }
    uint32_t old = s_travel_ms;
    s_travel_ms = (old * 3 + ms) / 4;   /* EMA，单次异常不会一把带偏 */
    if (s_travel_ms == old) return;

    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) == ESP_OK) {
        nvs_set_u32(h, NVS_KEY_T, s_travel_ms);
        nvs_commit(h);
        nvs_close(h);
    }
    ESP_LOGI(TAG, "行程标定 %lums -> T=%lums", (unsigned long)ms, (unsigned long)s_travel_ms);
}

/* ---------- 占空比曲线 ---------- */

static uint8_t duty_profile(uint32_t ms)
{
    /* 软启动：DUTY_SOFT_START 起，SOFT_START_MS 内线性升到 DUTY_RUN */
    uint8_t duty = DUTY_RUN;
    if (ms < SOFT_START_MS) {
        duty = DUTY_SOFT_START + (DUTY_RUN - DUTY_SOFT_START) * ms / SOFT_START_MS;
    }
    /* 末端缓停：0.85T 之后压到 DUTY_ENDGAME。
     * 90° 位重力不再帮忙减速，不降速会撞 100° 的机械止挡 */
    if (ms > s_travel_ms * ENDGAME_K / 100 && duty > DUTY_ENDGAME) {
        duty = DUTY_ENDGAME;
    }
    return duty;
}

/* ---------- 状态迁移 ---------- */

static void enter(gate_state_t st)
{
    ESP_LOGI(TAG, "%s -> %s", motion_state_name(s_state), motion_state_name(st));
    s_state = st;
    s_move_start_us = esp_timer_get_time();
}

static void go_fault(const char *why)
{
    motor_kill();
    ESP_LOGE(TAG, "FAULT: %s", why);
    buzzer_play(BEEP_FAULT);
    enter(ST_FAULT);
}

static void arrive(gate_state_t rest)
{
    uint32_t ms = elapsed_ms();
    motor_stop_and_sleep();          /* 刹车 BRAKE_MS 再断电 */
    travel_calibrate(ms);
    enter(rest);
    buzzer_play(BEEP_ARRIVE);
}

static void start_move(gate_state_t moving, bool from_limit)
{
    s_from_full_travel = from_limit;
    enter(moving);
}

static void do_reset(void)
{
    buzzer_stop();
    motor_kill();
    s_pinched = false;
    /* 复位一律重新回零：FAULT 之后位置不可信，
     * 直接当 CLOSED 会让下一次抬杆从未知角度起步 */
    start_move(ST_HOMING, false);
}

static void handle_cmd(const evt_t *e)
{
    /* 复位在任何状态下都受理，其余命令 FAULT 态一律拒绝 */
    if (e->type == EVT_CMD_RESET) {
        ESP_LOGI(TAG, "复位（src=%d）", e->src);
        do_reset();
        return;
    }
    if (s_state == ST_FAULT || s_state == ST_BOOT || s_state == ST_HOMING) {
        ESP_LOGW(TAG, "%s 态忽略命令 %d", motion_state_name(s_state), e->type);
        return;
    }

    buzzer_play(BEEP_TICK);

    if (e->type == EVT_CMD_OPEN) {
        if (s_state == ST_OPEN || s_state == ST_OPENING) return;   /* 幂等 */
        s_pinched = false;
        start_move(ST_OPENING, s_state == ST_CLOSED);
    } else if (e->type == EVT_CMD_CLOSE) {
        if (s_state == ST_CLOSED || s_state == ST_CLOSING) return;
        s_pinched = false;
        start_move(ST_CLOSING, s_state == ST_OPEN);
    }
}

static void step(void)
{
    uint32_t ms = elapsed_ms();

    switch (s_state) {
    case ST_HOMING:
        /* 位置未知，慢速往落杆方向走到限位为止 */
        if (endstop_dn()) { arrive(ST_CLOSED); break; }
        if (ms > HOMING_TIMEOUT_MS) { go_fault("回零超时 8s 未触落位限位"); break; }
        motor_drive(MOTOR_DOWN, DUTY_HOMING);
        break;

    case ST_OPENING:
        if (endstop_up()) {
            arrive(ST_OPEN);
            if (s_pinched) { s_pinched = false; buzzer_play(BEEP_PINCH); }
            break;
        }
        if (ms > s_travel_ms * FAULT_TIMEOUT_K / 100) { go_fault("抬杆超 1.5T 未到位"); break; }
        motor_drive(MOTOR_UP, duty_profile(ms));
        break;

    case ST_CLOSING:
        if (endstop_dn()) { arrive(ST_CLOSED); break; }
        /* 防砸：没有电流检测，只能靠时间。先反转，还不行才 FAULT */
        if (ms > s_travel_ms * FAULT_TIMEOUT_K / 100) { go_fault("落杆超 1.5T 未到位"); break; }
        if (ms > s_travel_ms * PINCH_REVERSE_K / 100) {
            ESP_LOGW(TAG, "防砸：落杆 %lums 超 1.15T(%lums)，反转",
                     (unsigned long)ms, (unsigned long)(s_travel_ms * PINCH_REVERSE_K / 100));
            motor_kill();
            buzzer_play(BEEP_PINCH);
            s_pinched = true;
            start_move(ST_OPENING, false);   /* 反转来的行程不参与标定 */
            break;
        }
        motor_drive(MOTOR_DOWN, duty_profile(ms));
        break;

    case ST_CLOSED:
    case ST_OPEN:
    case ST_FAULT:
    case ST_BOOT:
        break;
    }
}

static void motion_task(void *arg)
{
    endstop_init();
    motor_init();

    endstop_poll();
    if (endstop_conflict()) {
        /* 两个限位同时“到位”是物理上不可能的，
         * 只可能是接线错/NC 接成 NO。这时候转电机等于拿结构去试错 */
        go_fault("两个限位同时到位，检查 J2 接线与 NC/NO");
    } else {
        enter(ST_HOMING);
    }

    for (;;) {
        evt_t e;
        if (xQueueReceive(g_evt_q, &e, pdMS_TO_TICKS(MOTION_TICK_MS)) == pdTRUE) {
            handle_cmd(&e);
        }
        endstop_poll();
        step();
    }
}

void motion_start(void)
{
    travel_load();
    xTaskCreate(motion_task, "motion", 4096, NULL, 6, NULL);
}
