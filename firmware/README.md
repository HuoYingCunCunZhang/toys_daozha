# 道闸玩具 · 固件

两个独立 ESP-IDF 工程，共用 `common/gate_proto.h` 里的 ESP-NOW 包定义。

| 目录 | 芯片 | 干什么 |
|---|---|---|
| `gate/` | ESP32-S3-DevKitC-1 **N16R8** | 状态机、电机、限位、按键、蜂鸣器、ESP-NOW 收、**语音（ESP-SR）** |
| `remote/` | ESP32-C3 SuperMini | 按键唤醒 → 发一条 ESP-NOW → 接着深睡 |
| `common/` | — | 12 字节 `gate_pkt_t`、CRC16、命令码。**改这里两边一起改** |

方案依据：[`../道闸玩具_电路与结构设计方案_v2.md`](../道闸玩具_电路与结构设计方案_v2.md) §4 引脚 / §7 固件。
引脚的唯一事实源是[底板网表基准](../道闸玩具_底板网表基准_v2.md) §3，代码里不许自定义引脚。

---

## 环境

本机装的是 **ESP-IDF v6.1-beta1**（用 eim 装的，不是 v5.4）：

| | |
|---|---|
| 框架 | `D:\esp\v6.1-beta1\esp-idf` |
| 工具 | `D:\Espressif\tools` |
| 激活脚本 | `C:\Espressif\tools\Microsoft.v6.1-beta1.PowerShell_profile.ps1` |

```powershell
& "C:\Espressif\tools\Microsoft.v6.1-beta1.PowerShell_profile.ps1"
```

> ⚠ **v6 的组件名和 v5.x 不一样**，`main/CMakeLists.txt` 的 `REQUIRES` 是按 v6 写的：
> `driver` 元组件被拆散，gpio/ledc 要点名 **`esp_driver_gpio` / `esp_driver_ledc`**。
> 退回 v5.x 的话这里要改回 `driver`。
> （另一条与版本无关：**没有叫 `esp_now` 的组件**，`esp_now.h` 一直在 `esp_wifi` 里。）

## 编译烧录

```powershell
cd D:\workspace_zc\toys_daozha\firmware\gate
idf.py set-target esp32s3      # 只在第一次、或换芯片时跑
idf.py build
idf.py -p COM# flash monitor    # 退出 monitor 是 Ctrl+]
```

遥控器同理，`set-target esp32c3`，目录换 `firmware\remote`。

> `set-target` 会先跑 `fullclean`，而它拒绝清理"不像 CMake 构建目录"的残留 —— 上一次
> configure 失败留下的半成品 `build\` 就属于这种。手工 `rm -rf build` 再来。

**当前编译状态**：主机 ✅ / 遥控器 ✅，都是 `-Wall -Wextra -Werror` 零警告。
`daozha_gate.bin` **2.29MB**（加了 ESP-SR 之后从 788KB 涨上来的，4MB app 分区还剩 45%）、
`srmodels.bin` **2.90MB**（烧到 0x810000 的 `model` 分区，6MB 够）、
`daozha_remote.bin` ≈798KB。

> ⚠ **C3 没有 RTC IO**（`SOC_RTCIO_PIN_COUNT == 0`）—— `rtc_gpio_*` 那套函数在这颗芯片上
> 根本不存在，不用也不能手工去开 RTC 上拉。深睡期间的上拉由
> `ESP_SLEEP_GPIO_ENABLE_INTERNAL_RESISTORS`（默认开，已确认 sdkconfig 里是 `y`）
> 在 `esp_deep_sleep_start()` 里按唤醒模式自动配。
> 深睡唤醒 API 在 v6 也改名了：`esp_deep_sleep_enable_gpio_wakeup` →
> **`esp_sleep_enable_gpio_wakeup_on_hp_periph_powerdown`**。

> 🔴 **烧遥控器之前先把拨动开关拨到关。**
> C3 板上 Type-C 的 5V 直通 5V 脚，开关不关的话 USB 的 5V 会顺着 5V 脚倒灌回
> TP4056 的 OUT+（OUT+ 与 B+ 直连，保护只切负极）= 拿 5V 怼电池。

---

## 引脚（抄自网表，别在这里改）

### 主机 ESP32-S3

| 功能 | 脚 | 网络 | 电气 |
|---|---|---|---|
| 电机 AIN1 / AIN2 | 9 / 10 | N9 / N10 | LEDC PWM 20kHz，11 bit |
| 电机 nSLEEP | 11 | N11 | 高=工作。模块内部下拉 → 上电默认休眠 |
| 限位·抬到位 90° | 12 | N16 | 内部上拉 + **NC 接法**：未压合读 0，到位读 1 |
| 限位·落到位 0° | 13 | N17 | 同上。断线读 1（=到位）→ 停机，失效方向安全 |
| 按键·抬杆 / 落杆 | 17 / 18 | N18 / N19 | 按下接 GND，内部上拉 |
| 蜂鸣器 | 2 | N23 | → R5 → Q1(S8050) → LS1，高=响 |
| 电池采样 | 1 | N15 | ADC1_CH0，12dB 衰减，100k/100k 分压 |
| 麦克风 SCK/WS/SD | 4 / 5 / 6 | N20~N22 | INMP441，I2S0 标准模式，16kHz/32bit/单声道 |

> ⚠ **接线**：J2 第 **2** 脚接**落杆**限位、第 **3** 脚接**起杆**限位 —— PCB 布线时把
> 原理图上这两个端口对调过（[机械约束 §七之三](../道闸玩具_底板机械约束_v1.md)），GPIO 侧不受影响。

### 遥控器 ESP32-C3

| 功能 | 脚 | 备注 |
|---|---|---|
| 抬杆 / 落杆 / 复位 | 4 / 3 / 1 | 必须在 GPIO0~5（只有这些支持深睡唤醒），且避开 strapping 脚 GPIO2 |

复位键焊在板上但**上盖是实心面板、按不到**（2026-08-15 拍板：三个键对 6~10 岁太容易误触）。
固件仍然处理它，拆壳调试时可用。

---

## 交互

| 操作 | 结果 |
|---|---|
| 底座单键（松手时触发） | 抬杆 / 落杆 |
| 底座双键同时按住 3s | 复位 → 清故障，回到「位置未知」，不转电机 |
| 遥控器单键 | 抬杆 / 落杆 |
| 遥控器抬+落同时按住 3s | 发配对广播（**主机必须在开机后 60s 内**） |
| 喊"你好小智" → 再说"起杆/落杆/复位" | 语音控制。唤醒后蜂鸣器短鸣一声表示在听 |

**单键要等松手才动作**，因为两个键不可能真正同时按下 —— 按下即动作的话，双键复位一定会先误触发一次抬杆或落杆。

**配对窗口只有开机后 60s**，否则邻居家一按遥控器就能把主机抢走。配对成功蜂鸣器升调两声。

蜂鸣（毫秒序列见 `buzzer.c` 的 `SEQ_*`）：

| 场景 | 节奏 |
|---|---|
| 收到命令 / 唤醒应答 | 一短声 40ms |
| 到位 | 两声 60-80-60 |
| 防砸反转 | 急促三声 |
| **故障** | **响 400ms、停 300ms，无限循环**（听起来是"嘀..嘀..嘀.."，不是一条长音）|
| 配对成功 | 升调两声 |

**故障鸣叫只有复位或断电能停。** 最常见的触发是**限位没接**：两个限位 GPIO 内部上拉、
悬空都读 1 = 两个都"到位"，0° 和 90° 不可能同时成立 → 上电自检判定接线错，
拒绝转电机。接上 J2 就自己好了。
**唤醒应答借用"一短声"** —— 整机没喇叭，这是唯一能告诉小孩"我在听"的通道。

---

## 状态机

```
上电 → UNKNOWN（位置不明，不动，等命令）
         │ 抬杆 ──► OPENING ──► OPEN(90°)
         │ 落杆 ──► CLOSING ──► CLOSED
      CLOSED ⇄ OPENING → OPEN(90°) ⇄ CLOSING → CLOSED
                                         ↓ 落杆超 1.15×T
                                    立即反向 → OPENING（防砸）
任意态 ──故障──► FAULT（断电机、报警鸣叫，只有复位能出来）
复位 → 回到 UNKNOWN（清故障，不转电机）
```

### 🔴 没有开机回零（2026-09-10 拿掉的）

原设计是上电自动 HOMING —— 慢速往落杆方向走到限位为止。**已删除**，三条理由：

1. **它把机械问题变成了开机就报警**：凸轮相位差一点、开关位置偏一点，
   一开机就是 FAULT 长鸣、整机不可用
2. **拨开关瞬间杆子自己动**，对 6~10 岁玩家是惊吓
3. **回零往落杆方向走，而落杆侧没有机械止挡**（止挡只做在抬杆侧）。
   落位开关一失效，这个方向就只剩超时一道保护 ——
   风险最高的动作被安排在最没人盯着的时刻

> ⚠ 常见误解：「位置未知」不需要回零来消除。**每条命令本来就是
> 「往这个方向走到限位为止」，压根不需要知道起点。** UNKNOWN 态两个方向都放行，
> 第一条命令自然就走到某个限位、状态自己就明确了。

**停止靠三道闸门**（层层兜底）：

| 闸门 | 触发 | 备注 |
|---|---|---|
| ① 微动开关 | 对应方向的限位被压 | 正常路径。**NC 接法下断线读「到位」→ 立刻停，失效方向安全** |
| ② 超时 | 超 `1.5×T` → FAULT 断电 | 兜的是「开关卡住 / 凸轮压不到」这类读不到「到位」的失效 |
| ③ 机械止挡 | 硬顶 | **只有抬杆侧有，落杆侧没有** |

> 🔴 因为 ③ 在落杆侧缺席，**②的超时值不能设宽**。`TRAVEL_MS_DEFAULT` 现在是标定期的
> 宽松值 5000（→ 1.5T = 7.5s），实测出真 T 之后**必须收紧**，
> 否则落位开关一失效，杆子会往下顶满 7.5 秒。

**保留的是接线自检**：两个限位同时报「到位」物理上不可能，只可能是接线错或 NC 接成 NO
→ 直接 FAULT。它检的是**接线**不是**位置**，正常接好时永不触发；
少了它的话，任何命令都会在第一个 tick 就「立刻到位」，变成静默失效。

**T = 单程行程时间**，出厂缺省 1400ms（N20 6V 15rpm 经 5V 驱动 ≈12.5rpm，90° 约 1.4s），
真值由实测标定后写 NVS。

> **偏离方案文档一处**：§7.1 写的是「首次 HOMING 时标定 T」。但 HOMING 是从**未知角度**
> 走到落位限位，量到的是残段不是全程，拿它当 T 会把 T 校得偏小 —— 而 T 偏小 = 防砸阈值偏小
> = 正常落杆被误判成夹到东西。改成**只采纳「从一个限位干净地跑到另一个限位」的行程**
> （`s_from_full_travel`），并用 EMA 平滑，单次异常带不偏。

**防砸**没有电流检测（成品 DRV8833 不引出 AISEN），只能靠时间：
落杆超 `1.15×T` → 反转 + 蜂鸣；超 `1.5×T` → FAULT 断电。
真实响应延迟 0.2~1.6s，压紧力约 1.3N —— 这是方案已知并接受的代价。

**上电自检**：两个限位同时读到「到位」是物理上不可能的（0° 和 90° 不能同时成立），
只可能是接线错或 NC 接成了 NO。这种情况直接 FAULT，不转电机去试。

---

## 🔴 第一次上电必须先确认的三件事

1. **`MOTOR_INVERT`（`gate/main/board.h`）** —— 现在是 `0`，**这是猜的**。
   按抬杆键，闸杆往下走就改成 `1` 重烧。电机引线焊反、或转毂装到另一侧都会翻转。
2. **限位的 NC/NO 极性** —— 代码按 **NC**（未压合=闭合=读 0）写。买到 NO 的话
   `LIMIT_ACTIVE_LEVEL` 要改 `0`，否则上电就是「两个限位同时到位」→ FAULT（这时候 FAULT 是对的，它在保护结构）。
3. **调试姿势：USB 插着看日志 + 拨动开关打开给电机供电，两个同时。**
   🔴 **光插 USB 电机绝对不转** —— 电源链是
   `电池 → TP4056 → SW3 → MT3608 升压 → +5V → U2.VM`，而 `D1` 是单向的
   （`+5V → 5V_MCU`），DevKit 的 USB 只供 U1 自己，**倒不回 +5V**。
   拨动开关关着的话 `U2.VM` 没电：GPIO 侧 PWM 照发、日志一切正常，
   最后就是「回零超时 8s 未触落位限位」。
   （旧版这里写的是"M1 铁律：必须 USB 供电"，会让人以为拨开关该关着 —— 是错的。
   本意只是"别拔了 USB 纯电池跑"，那样看不到日志。）

---

## 里程碑对照（方案 §8）

| 阶段 | 目标 | 固件状态 |
|---|---|---|
| M0 | 环境，S3 跑通，PSRAM 识别 | ✅ 工程骨架就绪，`sdkconfig.defaults` 已开八线 PSRAM |
| M1 | USB 供电控制 N20 正反转，触限位自动停 | ✅ `motor.c` / `endstop.c`，待实测定 `MOTOR_INVERT` |
| M2 | 2 按键走完整行程，含软启动/缓停/超时/双键复位 | ✅ `motion.c` / `input.c` |
| M3 | 标定 T，手挡闸杆能在 1.15×T 反转 | ✅ 逻辑已写，阈值待实测校 |
| M4 | 遥控器 ESP-NOW + 配对 + 深睡 <20µA | ✅ `remote/`，深睡电流待实测 |
| **M5** | **ESP-SR 三条命令词** | ✅ **`gate/main/sr.c` 已实现**，识别率待实测 |
| M6/M7 | 结构装配、电池装机联调 | — 不是固件的事 |

---

## 语音（M5，`sr.c`）

```
INMP441 --I2S0--> feed_task --> AFE --> detect_task --> MultiNet7 中文 --> evt_post(SRC_VOICE)

实测 AFE 流水线（上电日志里 print_pipeline 打的）：
[input] -> |VAD(WebRTC)| -> |WakeNet(wn9_nihaoxiaozhi_tts)| -> [output]
```

单麦 + `AFE_TYPE_SR` 就是这个形态：AEC/SE 用不上（无喇叭、无阵列），
**非线性降噪本来就不在 SR 通路里**（`esp_afe_config.h` 对 `AFE_TYPE_SR` 的注释写死了）。
别照着"AFE 应该有 NS/AGC"去改配置，那是 VC（语音通话）通路的形态。

**两段式**：先喊唤醒词，再说命令。唤醒词用乐鑫现成模型（自定义唤醒词是付费商业服务，
方案 §7.4），当前选的是 **你好小智**（`CONFIG_SR_WN_WN9_NIHAOXIAOZHI_TTS`）。
命令词是 **MultiNet7 中文**，**在 `sr.c` 里用拼音运行时注册**，改词不用重训模型：

| id | 拼音（任一句都算） | 事件 |
|---|---|---|
| 1 | `qi gan` / `tai gan` / `kai men` | `EVT_CMD_OPEN` |
| 2 | `luo gan` / `jiang gan` / `guan men` | `EVT_CMD_CLOSE` |
| 3 | `fu wei` | `EVT_CMD_RESET` |

唤醒后 5.76s 内没听到命令词就自动退回等唤醒；这几秒里 **WakeNet 是关掉的**
（省算力，也免得命令词里的音再触发一次唤醒）。

### 配置在哪

模型的选择全在 `gate/sdkconfig.defaults`，**不是在代码里**：

```
CONFIG_MODEL_IN_FLASH=y                  # 模型进 flash 的 model 分区
CONFIG_SR_WN_WN9_NIHAOXIAOZHI_TTS=y      # 唤醒词（多选菜单，勾几个烧几个）
CONFIG_SR_MN_CN_MULTINET7_QUANT=y        # 命令词模型
CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_240=y    # ESP-SR 要 240MHz，160 会掉帧
CONFIG_ESP32S3_INSTRUCTION_CACHE_32KB=y
CONFIG_ESP32S3_DATA_CACHE_64KB=y
CONFIG_ESP32S3_DATA_CACHE_LINE_64B=y
```

> ⚠ **改了 `sdkconfig.defaults` 必须删掉 `sdkconfig` 再编**。defaults 只在
> `sdkconfig` 里没有这一项时才生效，改 defaults 而不删 sdkconfig = 什么都没发生。

> ⚠ **分区名必须叫 `model`** —— esp-sr 的 CMake 写死了去查这个名字的分区，
> 查不到就只是打条消息、不生成也不烧 `srmodels.bin`，固件跑起来才报"没模型"。

模型占用：`mn7_cn` 2.6MB + `wn9_nihaoxiaozhi_tts` 0.3MB ≈ **2.9MB**，6MB 分区够。

### 首次上电实测（2026-09-02，COM7 / 只插 DevKit）

全部符合预期，逐条对上了：

```
esp_psram: Found 8MB PSRAM device          # 八线 PSRAM 认到
cpu_start: cpu freq: 240000000 Hz          # ESP-SR 要的 240MHz 生效
boot:  4 model  Unknown data  01 82 00810000 00600000   # model 分区 6MB
MODEL_LOADER: Successfully load srmodels
sr: 唤醒词模型 wn9_nihaoxiaozhi_tts（你好小智），命令词模型 mn7_cn
AFE: AFE Pipeline: [input] -> |VAD(WebRTC)| -> |WakeNet(wn9_nihaoxiaozhi_tts,)| -> [output]
7 active speech commands:  qi gan / tai gan / kai men / luo gan / jiang gan / guan men / fu wei
motor: PWM 20000 Hz / 11 bit, MOTOR_INVERT=0
E motion: FAULT: 两个限位同时到位，检查 J2 接线与 NC/NO
comms: 主机 MAC b8:1f:3f:c3:ba:b0，信道 1，配对窗口 60s
```

- **那条 FAULT 是对的**：限位没接 + 内部上拉 = 两个都读 1 = 两个都"到位"，
  这是物理上不可能的组合，固件按设计拒绝转电机。接上限位后应该自己消失
- **`VBAT ≈ 3.87V` 这时候没有意义**：GPIO1 悬空，读的是浮空噪声，不是电池
- **主机 MAC `b8:1f:3f:c3:ba:b0`** —— 遥控器配对时对这个

### 上电后先看这两行日志

```
sr: 唤醒词模型 wn9_nihaoxiaozhi_tts（你好小智），命令词模型 mn7_cn
sr: 唤醒（音量 -33.2 dBFS），请说命令
```

**`data_volume` 就是调麦克风增益的依据**：常态说话应落在 **−45 ~ −25 dBFS**。
偏小就把 `sr.c` 的 `MIC_GAIN_SHIFT` 调小（每 −1 增益翻倍），削顶就调大。
INMP441 是 24bit MSB 对齐塞在 32bit 槽里，`>>16` 才是数学上正确的 int16，
现在取 **14**（多给 4× 增益），超量程做饱和截断而不是回绕。

### 三个容易踩的点

- **L/R 接的是 GND**（网表 N8）→ 数据在**左**声道，`slot_mask = I2S_STD_SLOT_LEFT`。
  接反了读到的是一片 0，AFE 不报错，只是永远唤不醒
- **槽宽必须 32bit**：INMP441 一帧要 64 个 BCLK，按 16bit 配根本收不到数
- **不要把 `cfg->wakenet_model_name` 改成 `models` 里的指针**：那个字段是
  `afe_config_init` 自己 strdup 的，`afe_config_free` 会去 free 它 ——
  塞进模型表的指针进去，等于把模型表里的字符串给释放了

### 任务与核

`sr_feed` / `sr_detect` / AFE 内部任务全部**优先级 5、钉在 core 1**（方案 §7.2 的"独占一核"），
core 0 留给 WiFi/ESP-NOW。语音跟其它输入一样只 `evt_post()`，不碰电机。

---

## 代码里两个不显眼的坑

- **限位模块叫 `endstop.h` 不叫 `limits.h`** —— `main/` 在 include path 上，
  叫 `limits.h` 会盖掉 C 标准库的 `<limits.h>`，报错点会离现场很远。
- **只有 `motion.c` 能调 `motor_*`**（方案 §7.2 的规矩）。其它任务一律 `evt_post()`，
  否则语音和遥控会抢电机。
