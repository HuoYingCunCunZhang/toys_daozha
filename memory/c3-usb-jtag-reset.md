---
name: c3-usb-jtag-reset
description: ESP32-C3 原生 USB-Serial-JTAG 的 DTR/RTS 含义与 S3 那条笔记相反，脉冲 RTS 等于按 BOOT
metadata:
  node_type: memory
  type: project
---

**在 ESP32-C3 SuperMini（原生 USB-Serial-JTAG）上用 .NET `SerialPort` 复位，`DtrEnable=$false` + 脉冲 `RtsEnable` 会把芯片送进下载模式，不是正常启动。**

芯片内的 USB-Serial-JTAG 外设模拟的是经典两管自动复位电路：

| DTR | RTS | EN | IO0/GPIO9 |
|---|---|---|---|
| 0 | 0 | 高 | 高 |
| 0 | **1** | 高 | **低 = 按住 BOOT** |
| **1** | 0 | **低 = 复位** | 高 |
| 1 | 1 | 高 | 高 |

所以 `DTR=0 + 脉冲 RTS` 正好是"按住 BOOT"，每次都锁存成 `boot:0x5 (DOWNLOAD)`，串口随后一片死寂（下载模式只在启动那一下打印 `waiting for download`）。

**Why:** [[daozha-toy-scope]] 里记的"`DtrEnable=$false` + 脉冲 RTS 才是正常启动"是在**主机 ESP32-S3** 上得到的，那条**不能套到 C3 上**。2026-09-13 因此误判了一轮，还差点把"芯片卡在下载模式"当成 GPIO9 被板子拉低的硬件故障去查，并且冤枉用户按着 BOOT 键——实际是我自己的复位脉冲干的。

**How to apply:**
- 判据看启动横幅：`boot:0xd (SPI_FAST_FLASH_BOOT)` 才是跑程序，`boot:0x5 (DOWNLOAD)` 是卡在 ROM。
- **最可靠的复位是让用户拔插一次 USB**，物理上电一定是正常启动，不受任何 DTR/RTS 状态影响。
- 芯片复位后原生 USB 会**整个重新枚举**，之前打开的 `SerialPort` 句柄当场作废、读到 0 字节。要读日志就写成"反复重开端口累加"的循环，别开一次读到底。
