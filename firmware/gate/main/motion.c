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

static const char *TAG = "motion";

static gate_state_t s_state = ST_IDLE;

static bool s_timed;               /* true=定时走（语音）, false=JOG（靠保活续命） */
static int64_t s_move_start_us;    /* 本段运动起点 */
static int64_t s_last_jog_us;      /* 最近一次收到「还按着」 */
static bool s_limit_was_hit;       /* 本段开始时目标方向的限位是否已经压着（压着 = 不认，等边沿） */
static bool s_jog_locked;          /* 按满 JOG_MAX_MS 被强制停了：松手（STOP / 看门狗超时）前不再起 */

const char *motion_state_name(gate_state_t s)
{
    static const char *N[] = { "IDLE", "UP", "DOWN", "FAULT" };
    return (s <= ST_FAULT) ? N[s] : "?";
}

gate_state_t motion_state(void) { return s_state; }

static uint32_t elapsed_ms(void)
{
    return (uint32_t)((esp_timer_get_time() - s_move_start_us) / 1000);
}

/* 目标方向那颗限位现在是不是压着 */
static bool limit_hit(gate_state_t dir)
{
    return (dir == ST_UP) ? endstop_up() : endstop_dn();
}

/* ---------- 占空比：只保留软启动 ----------
 * 原来还有 0.85T 之后的缓停，现在没有 T，也就没有「快到了」这个概念 */
static uint8_t duty_now(void)
{
    uint32_t ms = elapsed_ms();
    if (ms < SOFT_START_MS) {
        return DUTY_SOFT_START + (DUTY_RUN - DUTY_SOFT_START) * ms / SOFT_START_MS;
    }
    return DUTY_RUN;
}

/* ---------- 状态迁移 ---------- */

static void enter(gate_state_t st)
{
    ESP_LOGI(TAG, "%s -> %s", motion_state_name(s_state), motion_state_name(st));
    s_state = st;
}

static void stop(const char *why, bool brake)
{
    if (s_state != ST_UP && s_state != ST_DOWN) return;
    ESP_LOGI(TAG, "停：%s（走了 %lums）", why, (unsigned long)elapsed_ms());
    if (brake) motor_stop_and_sleep();   /* 刹车 BRAKE_MS 再断电 */
    else       motor_kill();
    enter(ST_IDLE);
}

static void start_move(gate_state_t dir, bool timed)
{
    int64_t now = esp_timer_get_time();
    if (s_state == dir) {
        /* 同方向：JOG 就续命；定时走就重新计时 */
        s_last_jog_us = now;
        if (!timed && s_timed) s_timed = false;   /* 定时走途中有人按住 -> 改由人控制 */
        return;
    }
    if (s_state == ST_UP || s_state == ST_DOWN) {
        /* 反向：先断电再起。DRV8833 扛得住瞬间反向，但没必要 */
        motor_kill();
    }
    s_timed = timed;
    s_move_start_us = now;
    s_last_jog_us = now;
    /* 起步时限位已经压着 -> 不认，只认之后的「没压到 -> 压到」边沿。
     * 否则开关卡住 / NC 断线（读作“压着”）就永远动不了那个方向 —— 这正是要避免的 */
    s_limit_was_hit = limit_hit(dir);
    if (s_limit_was_hit) {
        ESP_LOGW(TAG, "%s 方向限位起步时就压着，本段不认它，只认边沿", motion_state_name(dir));
    }
    buzzer_play(BEEP_TICK);
    enter(dir);
}

static void do_reset(void)
{
    buzzer_stop();
    motor_kill();
    enter(ST_IDLE);
}

static void handle_cmd(const evt_t *e)
{
    switch (e->type) {
    case EVT_CMD_RESET:
        ESP_LOGI(TAG, "复位/急停（src=%d）", e->src);
        do_reset();
        return;

    case EVT_STOP:
        s_jog_locked = false;
        stop("松手", true);
        return;

    default:
        break;
    }

    if (s_state == ST_FAULT) {
        ESP_LOGW(TAG, "FAULT 态忽略命令 %d（先复位）", e->type);
        return;
    }

    if (s_jog_locked && (e->type == EVT_JOG_UP || e->type == EVT_JOG_DN)) {
        s_last_jog_us = esp_timer_get_time();   /* 还按着：锁继续，但记着他还在按 */
        return;
    }

    switch (e->type) {
    case EVT_JOG_UP:    start_move(ST_UP,   false); break;
    case EVT_JOG_DN:    start_move(ST_DOWN, false); break;
    case EVT_CMD_OPEN:  start_move(ST_UP,   true);  break;
    case EVT_CMD_CLOSE: start_move(ST_DOWN, true);  break;
    default: break;
    }
}

static void step(void)
{
    int64_t now = esp_timer_get_time();

    /* 锁着但 JOG 也断了 = 松手了、只是 STOP 包丢了。解锁 */
    if (s_jog_locked && now - s_last_jog_us > (int64_t)JOG_DEADMAN_MS * 1000) {
        s_jog_locked = false;
    }

    if (s_state != ST_UP && s_state != ST_DOWN) return;

    uint32_t ms = elapsed_ms();

    /* ① 限位：碰到就停。只认边沿，见 start_move 的注释 */
    bool hit = limit_hit(s_state);
    if (hit && !s_limit_was_hit) {
        stop("限位到位", true);
        buzzer_play(BEEP_ARRIVE);
        return;
    }
    s_limit_was_hit = hit;

    if (s_timed) {
        /* ② 定时走：走满就停 */
        if (ms >= TIMED_TRAVEL_MS) { stop("定时走完", true); return; }
    } else {
        /* ② 看门狗：没人续命就停。遥控器掉线、按键抖动、任务饿死都落在这里 */
        if (now - s_last_jog_us > (int64_t)JOG_DEADMAN_MS * 1000) {
            stop("看门狗：没人按着了", true);
            return;
        }
        /* ③ 按住上限：抬杆侧有机械止挡，按住不放 = 堵转发热 */
        if (ms >= JOG_MAX_MS) {
            s_jog_locked = true;       /* 松手前不再起，见 handle_cmd */
            stop("按住太久，强制停。松手再按才能继续", true);
            buzzer_play(BEEP_PINCH);   /* 急促三声当警告用 */
            return;
        }
    }

    motor_drive(s_state == ST_UP ? MOTOR_UP : MOTOR_DOWN, duty_now());
}

static void motion_task(void *arg)
{
    (void)arg;
    endstop_init();
    motor_init();
    ESP_LOGI(TAG, "就绪。长按走、松手停；限位只做碰到就停");

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
    xTaskCreate(motion_task, "motion", 4096, NULL, 6, NULL);
}
