// 状态机 + 电机。方案 §7.1 / §7.3（已被 2026-09-11 的「长按走、松手停」模型取代）。
// 铁律：只有这个模块碰 motor_*，其它任务一律走 evt_post()。
#pragma once

#include <stdbool.h>
#include <stdint.h>

/* 控制模型（2026-09-11）：
 *   - 没有回零、没有已知位置。固件不知道杆在哪，也不需要知道
 *   - JOG：有人持续投「还按着」就转，JOG_DEADMAN_MS 没收到就停，按满 JOG_MAX_MS 也停
 *   - 定时走：语音用，往某方向走 TIMED_TRAVEL_MS
 *   - 限位开关只做「碰到就停」：动作中开关从没压到变成压到 -> 停。
 *     它永远不阻止启动 —— 装不准、接触不良、甚至没接，都不影响能不能动
 *   - FAULT 现在没有自动触发源，留着给语音「复位」当急停用 */
typedef enum {
    ST_IDLE = 0,
    ST_UP,       /* 正在抬杆（JOG 或定时走） */
    ST_DOWN,     /* 正在落杆 */
    ST_FAULT,
} gate_state_t;

void motion_start(void);
gate_state_t motion_state(void);
const char *motion_state_name(gate_state_t s);
