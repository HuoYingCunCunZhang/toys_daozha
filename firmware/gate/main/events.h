// 事件总线。所有任务只往 g_evt_q 投事件，
// motion_task 是唯一能命令电机的地方（方案 §7.2，防止语音和遥控抢电机）。
#pragma once

#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

typedef enum {
    EVT_CMD_OPEN = 0,
    EVT_CMD_CLOSE,
    EVT_CMD_RESET,
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
