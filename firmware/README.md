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
| 底座单键**按住** | 往那个方向转；**松手就停** |
| 底座双键同时按住 3s | 复位 / 急停 |
| 遥控器单键**按住** | 同上（按住每 100ms 发一个 JOG 保活包，松手发 STOP） |
| 遥控器抬+落同时按住 3s | 发配对广播（**主机必须在开机后 60s 内**） |
| 喊"你好小智" → 再说"起杆/落杆" | 语音没法"按住"，改为**定时走** `TIMED_TRAVEL_MS`（2200ms） |
| 喊"你好小智" → "复位" | 急停 + 清故障 |

### 🔴 控制模型：长按走、松手停（2026-09-11）

限位开关装不到精确位置（凸轮相位 / 开关安装台都难调准），所以**它不再是动作的依据**。
走多远由操作的人盯着，固件只兜底：

| 谁在兜 | 触发 | 值 |
|---|---|---|
| 限位开关 | 动作中开关**从没压到变成压到** → 停，两声 | 只认边沿。起步时已压着的不认，所以开关卡住/断线/没接都**不阻止启动** |
| 看门狗 | `JOG_DEADMAN_MS` 没收到"还按着" → 停 | 300ms。底座键 50ms 投一次、遥控 100ms 发一次，容忍连丢 2 包 |
| 按住上限 | 按满 `JOG_MAX_MS` → 强制停，急促三声 | 5s。抬杆侧有机械止挡，按住 = 堵转发热。**松手再按才能继续** |
| 定时走 | 语音命令走满 `TIMED_TRAVEL_MS` → 停 | 2200ms（初值取自 09-10 那轮标定收敛的 T=2243） |

**三个输入源共用一套机制**：谁持续喂 JOG 谁就在控制，喂断了就停。遥控器掉线、走出范围、没电，
杆子都不会一直转 —— 这一条是遥控器能做"长按"的前提，不能省。

**有意放弃的**：T 标定、1.15T 防砸、1.5T 超时、0.85T 缓停、开机自检。
它们全都以"有可靠限位"为前提，没有这个前提就没有参照物。以后开关装准了可以再加回来。

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
IDLE ──JOG_UP / CMD_OPEN──► UP ──限位边沿 / 看门狗 / 按满 5s / 定时走完──► IDLE
IDLE ──JOG_DN / CMD_CLOSE─► DOWN ──同上──► IDLE
任意态 ──复位──► IDLE（急停）
FAULT：现在没有自动触发源，留着给语音"复位"当急停用
```

没有回零、没有已知位置。**固件不知道杆在哪，也不需要知道** —— 每条命令都是
"往这个方向走，直到有人让它停"。

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
