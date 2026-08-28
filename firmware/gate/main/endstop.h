// 限位微动。⚠ 这个文件不叫 limits.h：main 目录在 include path 上，
// 叫 limits.h 会盖掉 C 标准库的 <limits.h>，报错点会离现场很远。
#pragma once

#include <stdbool.h>

void endstop_init(void);

/* 已消抖的当前状态。true = 压到位 */
bool endstop_up(void);
bool endstop_dn(void);

/* 采样一次并更新消抖状态，由 motion_task 每 MOTION_TICK_MS 调一次 */
void endstop_poll(void);

/* 两个限位同时到位 = 不可能的物理状态（0° 和 90° 不能同时成立），
 * 只可能是接线错或 NC/NO 接反 -> 直接 FAULT，别让电机去试 */
bool endstop_conflict(void);
