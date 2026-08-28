// 底座两个按键 + 电池采样。方案 §7.2 的 input_task。
#pragma once

void input_start(void);
float input_battery_v(void);   /* 最近一次采样的电池电压，未采样过返回 -1 */
