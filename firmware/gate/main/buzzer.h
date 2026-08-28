// 有源蜂鸣器（φ9×5.5 3V）。取消爆闪灯后这是唯一的反馈通道。
// 全部非阻塞：调用只是把节奏排进队列，由自己的定时器播。
#pragma once

typedef enum {
    BEEP_TICK = 0,   /* 短促一声：收到命令 */
    BEEP_ARRIVE,     /* 两声：到位 */
    BEEP_PINCH,      /* 急促三声：防砸反转 */
    BEEP_FAULT,      /* 连续长鸣，直到 buzzer_stop() */
    BEEP_PAIRED,     /* 升调两声：配对成功 */
} beep_t;

void buzzer_init(void);
void buzzer_play(beep_t pattern);
void buzzer_stop(void);
