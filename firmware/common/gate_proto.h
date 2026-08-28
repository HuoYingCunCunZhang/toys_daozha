// 道闸玩具 · ESP-NOW 协议（主机与遥控器共用，改这里两边一起改）
// 依据：道闸玩具_电路与结构设计方案_v2.md §7.6 —— 12 字节包，固定信道 1
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GATE_PROTO_MAGIC   0x5A47u   /* 'ZG' */
#define GATE_PROTO_VER     1
#define GATE_ESPNOW_CHAN   1         /* 双方固定信道 1，主机不连路由器 */

/* 命令码。方案 §7.6 收敛为 OPEN/CLOSE/RESET/PING，PAIR 是配对流程用的 */
enum {
    GATE_CMD_NONE  = 0,
    GATE_CMD_OPEN  = 1,
    GATE_CMD_CLOSE = 2,
    GATE_CMD_RESET = 3,
    GATE_CMD_ACK   = 4,   /* 主机 -> 遥控器，arg = 当前状态 gate_state_t */
    GATE_CMD_PAIR  = 6,   /* 遥控器广播，主机仅在开机后 PAIR_WINDOW_MS 内受理 */
    GATE_CMD_PING  = 7,
};

typedef struct __attribute__((packed)) {
    uint16_t magic;   /* GATE_PROTO_MAGIC */
    uint8_t  ver;     /* GATE_PROTO_VER */
    uint8_t  cmd;     /* GATE_CMD_* */
    uint32_t seq;     /* 发送方自增，主机丢弃重复 seq（按键抖动会连发） */
    uint16_t arg;     /* ACK 时是状态码，其余保留 */
    uint16_t crc;     /* 前 10 字节的 CRC16-CCITT */
} gate_pkt_t;

_Static_assert(sizeof(gate_pkt_t) == 12, "gate_pkt_t 必须是 12 字节（协议冻结）");

static inline uint16_t gate_crc16(const void *buf, size_t len)
{
    const uint8_t *p = (const uint8_t *)buf;
    uint16_t crc = 0xFFFFu;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)p[i] << 8;
        for (int b = 0; b < 8; b++)
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u) : (uint16_t)(crc << 1);
    }
    return crc;
}

static inline void gate_pkt_seal(gate_pkt_t *pkt)
{
    pkt->magic = GATE_PROTO_MAGIC;
    pkt->ver   = GATE_PROTO_VER;
    pkt->crc   = gate_crc16(pkt, offsetof(gate_pkt_t, crc));
}

static inline bool gate_pkt_valid(const gate_pkt_t *pkt, size_t len)
{
    if (len != sizeof(*pkt))              return false;
    if (pkt->magic != GATE_PROTO_MAGIC)   return false;
    if (pkt->ver   != GATE_PROTO_VER)     return false;
    return pkt->crc == gate_crc16(pkt, offsetof(gate_pkt_t, crc));
}
