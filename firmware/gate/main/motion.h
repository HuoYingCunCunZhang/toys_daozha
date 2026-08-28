// 状态机 + 电机。方案 §7.1 / §7.3。
// 铁律：只有这个模块碰 motor_*，其它任务一律走 evt_post()。
#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    ST_BOOT = 0,
    ST_HOMING,
    ST_CLOSED,
    ST_OPENING,
    ST_OPEN,
    ST_CLOSING,
    ST_FAULT,
} gate_state_t;

void motion_start(void);            /* 建任务，内部自动进 HOMING */
gate_state_t motion_state(void);
uint32_t motion_travel_ms(void);    /* 当前标定出来的 T */
const char *motion_state_name(gate_state_t s);
