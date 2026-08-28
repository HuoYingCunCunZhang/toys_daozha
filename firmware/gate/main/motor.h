// DRV8833 A 通道驱动。只有 motion 模块能调这里。
#pragma once

#include <stdint.h>

typedef enum {
    MOTOR_STOP = 0,
    MOTOR_UP,      /* 抬杆 */
    MOTOR_DOWN,    /* 落杆 */
} motor_dir_t;

void motor_init(void);

/* duty_pct 0~100。dir=MOTOR_STOP 等于滑行（两脚拉低）*/
void motor_drive(motor_dir_t dir, uint8_t duty_pct);

/* 两脚同时拉高 = 刹车。持续 BRAKE_MS 由调用方控制 */
void motor_brake(void);

/* 刹车 BRAKE_MS 后拉低 nSLEEP，模块进待机（阻塞）*/
void motor_stop_and_sleep(void);

/* 出故障时立刻断电，不刹车（避免带着故障硬扛）*/
void motor_kill(void);
