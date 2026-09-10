// 状态机 + 电机。方案 §7.1 / §7.3。
// 铁律：只有这个模块碰 motor_*，其它任务一律走 evt_post()。
#pragma once

#include <stdbool.h>
#include <stdint.h>

/* 🔴 没有 HOMING。开机不知道闸杆在哪，就老实说不知道，等命令 —— 别自己转。
 * 2026-09-10 拿掉的，理由三条：
 *   ① 开机回零把「凸轮相位差一点」变成「一开机就 FAULT 长鸣、整机不可用」
 *   ② 拨开关瞬间杆子自己动，对 6~10 岁玩家是惊吓
 *   ③ 回零是往落杆方向走，而落杆侧没有机械止挡（止挡只在抬杆侧），
 *      落位开关一失效就只剩超时一道保护 —— 风险最高的动作被放在最没人盯着的时刻
 * 位置未知不是问题：每条命令都是「往某个方向走到限位为止」，本来就不需要知道起点。 */
typedef enum {
    ST_UNKNOWN = 0,   /* 开机态 / 复位后：位置不明，不动，两个方向都放行 */
    ST_CLOSED,
    ST_OPENING,
    ST_OPEN,
    ST_CLOSING,
    ST_FAULT,
} gate_state_t;

void motion_start(void);            /* 建任务；开机停在 UNKNOWN，不转电机 */
gate_state_t motion_state(void);
uint32_t motion_travel_ms(void);    /* 当前标定出来的 T */
const char *motion_state_name(gate_state_t s);
