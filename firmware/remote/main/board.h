// 遥控器（ESP32-C3 SuperMini）引脚
// 唯一事实源：../../../道闸玩具_遥控器网表基准_v1.md、设计方案 v2 §4.2
#pragma once

#include "driver/gpio.h"

/* 三个键都必须落在 GPIO0~5：C3 的深睡唤醒只有这几个脚支持。
 * ⚠ GPIO2 是 strapping 脚（上电必须为高），而按键是拉低的 —— 不能用，
 *   小孩按着键去拨电源开关就起不来。避开后正好剩 0/1/3/4/5。 */
#define PIN_BTN_UP    GPIO_NUM_4   /* U1 脚 13，抬杆 */
#define PIN_BTN_DN    GPIO_NUM_3   /* U1 脚 12，落杆 */
#define PIN_BTN_RST   GPIO_NUM_1   /* U1 脚 10，复位 */

/* ⚠ 复位键 SW3 焊在板上，但上盖那块是实心面板、按不到（2026-08-15 拍板：
 *   三个按钮对 6~10 岁的孩子容易误操作，复位改走主机的语音命令）。
 *   固件仍然处理它 —— 拆壳烧录/调试时用得上。 */

#define BTN_ACTIVE_LEVEL   0       /* 按下接 GND，内部上拉 */

#define BTN_WAKE_MASK   ((1ULL << PIN_BTN_UP) | (1ULL << PIN_BTN_DN) | (1ULL << PIN_BTN_RST))

#define DEBOUNCE_MS         30
#define PAIR_HOLD_MS      3000     /* 抬杆+落杆同时按住 3s = 发配对广播 */
#define SEND_REPEAT          3     /* ESP-NOW 无重传，连发几次抗丢包 */
#define SEND_GAP_MS         20
#define ACK_WAIT_MS        250
#define RELEASE_TIMEOUT_MS 8000    /* 键卡住时别死等，超时照样睡 */
