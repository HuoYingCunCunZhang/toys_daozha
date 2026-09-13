// 主机（ESP32-S3-DevKitC-1 N16R8）引脚与电气常数
// 唯一事实源：../../../道闸玩具_底板网表基准_v2.md §3、设计方案 v2 §4.1
// ⚠ 改这里之前先改网表文档，不许在代码里自定义引脚。
#pragma once

#include "driver/gpio.h"

/* ---- 麦克风 INMP441，I2S0（M5 语音才用）---- N20/N21/N22 */
#define PIN_MIC_SCK      GPIO_NUM_4
#define PIN_MIC_WS       GPIO_NUM_5
#define PIN_MIC_SD       GPIO_NUM_6

/* ---- 电机 DRV8833 ---- N9/N10/N11 */
#define PIN_M_AIN1       GPIO_NUM_9
#define PIN_M_AIN2       GPIO_NUM_10
#define PIN_M_SLEEP      GPIO_NUM_11   /* 高=工作。模块内部下拉 -> 上电默认休眠 */

/* ---- 限位微动 ---- N16/N17。内部上拉 + 常闭(NC)接法，公共端到 J2.1(GND)
 * 未压合 = NC 闭合 = 读到 0；压到位 = NC 断开 = 读到 1。
 * 断线也读 1（=到位）-> 电机停，失效方向是安全的。
 * ⚠ 接线：J2 第 2 脚接【落杆】限位、第 3 脚接【起杆】限位（PCB 定稿时对调过，
 *   见 底板机械约束 §七之三）。GPIO 侧不受影响。 */
#define PIN_LIMIT_UP     GPIO_NUM_12   /* 抬到位 90° */
#define PIN_LIMIT_DN     GPIO_NUM_13   /* 落到位 0°  */
#define LIMIT_ACTIVE_LEVEL   1

/* ---- 按键 ---- N18/N19。按下接 GND，内部上拉 */
#define PIN_BTN_UP       GPIO_NUM_17
#define PIN_BTN_DN       GPIO_NUM_18
#define BTN_ACTIVE_LEVEL     0

/* ---- 有源蜂鸣器 ---- N23：GPIO -> R5 -> Q1(S8050 NPN) -> LS1。高=响 */
#define PIN_BUZZER       GPIO_NUM_2

/* ---- 电池采样 ---- N15：VBAT --100k--+--100k-- GND，中点进 ADC1_CH0 */
#define PIN_VBAT_DIV     GPIO_NUM_1
#define VBAT_DIV_RATIO   2.0f          /* 100k/100k */

/* ================= 电机标定 =================
 * 🔴 MOTOR_INVERT 在 M1 阶段（USB 供电、手动点动）实测确定：
 *    先按 0 烧进去，按抬杆键看闸杆是不是往上走；反了就改成 1 重烧。
 *    电机引线焊反、或转毂装到另一侧，都会翻转。别猜。 */
#define MOTOR_INVERT     0

/* PWM。20kHz 以下电机啸叫刺耳（方案 §7.3）。
 * 11 bit 分辨率上限 80MHz/2048 = 39kHz，20kHz 有余量 */
#define MOTOR_PWM_HZ         20000
#define MOTOR_PWM_RES_BITS   11
#define MOTOR_DUTY_MAX       ((1 << MOTOR_PWM_RES_BITS) - 1)

/* 占空比档位（百分比）*/
#define DUTY_RUN         85    /* 正常行程 */
#define DUTY_SOFT_START  40    /* 软启动起点，200ms 线性升到 DUTY_RUN */

#define SOFT_START_MS    200
#define BRAKE_MS         300   /* AIN1=AIN2=高 刹车，之后拉低 nSLEEP */

/* ================= 走多久 =================
 * 🔴 2026-09-11 起控制模型改成「长按走、松手停」：
 *    限位开关装不到精确位置，所以它不再是动作的依据，只是「碰到就停」的加分项。
 *    走多远由操作的人盯着，固件只兜底：
 *      JOG_MAX_MS      —— 按住不放的上限。抬杆侧有机械止挡，按住 = 电机堵转发热
 *      JOG_DEADMAN_MS  —— 多久没收到「还在按着」就停。底座键 50ms 投一次、遥控 100ms 发一次
 *      TIMED_TRAVEL_MS —— 语音「起杆/落杆」没法长按，就走这么久。
 *                         初值取自 2026-09-10 那轮标定收敛到的 T=2243ms
 * 原来那套 T 标定 / 1.15T 防砸 / 1.5T 超时 / 0.85T 缓停 全部作废：
 * 没有可靠限位就量不出 T，量不出 T 那些系数就没有参照物。防砸是**有意放弃**的。 */
#define JOG_MAX_MS          5000
#define JOG_DEADMAN_MS       300
#define TIMED_TRAVEL_MS     2200

#define MOTION_TICK_MS       5      /* 状态机轮询周期，也是限位采样周期 */

/* 双键同时长按 3s = 复位（方案 §7.1）*/
#define BTN_DEBOUNCE_MS      20
#define BTN_RESET_HOLD_MS    3000

/* 开机后这段时间内受理遥控器配对广播 */
#define PAIR_WINDOW_MS       60000
