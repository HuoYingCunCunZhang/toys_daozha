// 事件总线。所有任务只往 g_evt_q 投事件，
// motion_task 是唯一能命令电机的地方（方案 §7.2，防止语音和遥控抢电机）。
#pragma once

#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

/* 两类输入：
 *   JOG_*  = 「有人正按着」。谁按着谁就得持续投，motion 收不到就停（看门狗）。
 *            底座按键 input.c 每 50ms 投一个，遥控器每 100ms 发一个，同一套机制。
 *   CMD_*  = 「走一段」。语音用：往某个方向走固定时长（TIMED_TRAVEL_MS）。 */
typedef enum {
    EVT_JOG_UP = 0,
    EVT_JOG_DN,
    EVT_STOP,        /* 松手，立即停（不等看门狗） */
    EVT_CMD_OPEN,    /* 定时走 */
    EVT_CMD_CLOSE,
    EVT_CMD_RESET,   /* 清故障 + 急停 */
} evt_type_t;

typedef enum {
    SRC_BUTTON = 0,
    SRC_REMOTE,
    SRC_VOICE,
} evt_src_t;

typedef struct {
    uint8_t type;   /* evt_type_t */
    uint8_t src;    /* evt_src_t  */
    uint16_t arg;
} evt_t;

extern QueueHandle_t g_evt_q;

/* 任何上下文都能调（含 ISR 之外的回调）。队列满就丢，命令是幂等的 */
void evt_post(evt_type_t type, evt_src_t src, uint16_t arg);
