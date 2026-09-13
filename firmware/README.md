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

装的是 **ESP-IDF v6.1**（用 eim 装的，不是 v5.4）：

| | |
|---|---|
| 框架 | `C:\esp\v6.1\esp-idf` |
| 工具 | `C:\Espressif\tools` |
| 激活脚本 | `C:\Espressif\tools\Microsoft.v6.1.PowerShell_profile.ps1` |

```powershell
& "C:\Espressif\tools\Microsoft.v6.1.PowerShell_profile.ps1"
```

> **换机器时这张表要重填**，路径不是固定的（2026-08-29 换机：`D:\esp\v6.1-beta1` → `C:\esp\v6.1`，
> beta1 → 正式版）。eim 的**命令行模式默认按 target `all` 装**，xtensa 和 riscv32 两套编译器都有，
> 不用开 GUI 勾芯片。当前安装的登记在 `C:\Espressif\tools\eim_idf.json`。

> ⚠ **v6 的组件名和 v5.x 不一样**，`main/CMakeLists.txt` 的 `REQUIRES` 是按 v6 写的：
> `driver` 元组件被拆散，gpio/ledc 要点名 **`esp_driver_gpio` / `esp_driver_ledc`**。
> 退回 v5.x 的话这里要改回 `driver`。
> （另一条与版本无关：**没有叫 `esp_now` 的组件**，`esp_now.h` 一直在 `esp_wifi` 里。）

## 编译烧录

### 🔴 不能在仓库原地编译 —— 项目路径有中文

`D:\玩具\01.道闸门\` 里的中文会让 cmake 在 configure 阶段直接崩掉，
**报的不是编译错误，是 `exit code 3221226505`（`0xC0000409`，STATUS_STACK_BUFFER_OVERRUN）**。
`build\log\idf_py_stderr_output_*` 里能看到路径被拆坏的样子：

```
D:\鐜╁叿\01.閬撻椄闂╘firmware\gate     ← 本该是 D:\玩具\01.道闸门\firmware\gate
```

`玩具` 的 UTF-8 字节被按 GBK 解码，而且 `门` 的尾字节把后面的 `\f` 一起吞了。
**和 OpenSCAD 在中文路径下渲染不了是同一类问题**（CAD 那边的对策是工作副本放 `D:\cad\`）。

所以固件也走**工作副本**，仓库只存源码：

```powershell
# 1. 同步到 ASCII 路径（改完源码就重跑一次；/MIR 会删掉副本里的多余文件）
robocopy "D:\玩具\01.道闸门\firmware" "D:\fw" /MIR /XD build .git

# 2. 激活环境
& "C:\Espressif\tools\Microsoft.v6.1.PowerShell_profile.ps1"

# 3. 编译
cd D:\fw\gate
idf.py build
idf.py -p COM# flash monitor    # 退出 monitor 是 Ctrl+]
```

遥控器同理，目录换 `D:\fw\remote`。

> `sdkconfig.defaults` 里已经写死了 `CONFIG_IDF_TARGET`，**全新的 `build\` 不用先跑 `set-target`**，
> 直接 `idf.py build` 就会按它选芯片。真要跑 `set-target` 的话注意它会先 `fullclean`，
> 而 `fullclean` 拒绝清理"不像 CMake 构建目录"的残留（上次 configure 失败留下的半成品 `build\`
> 就属于这种）—— 手工删掉再来。

> ⚠ **改完代码记得先跑第 1 步再编译**，否则编的是旧副本。反过来，
> **不要在 `D:\fw\` 里改代码**，`/MIR` 下次同步会直接覆盖掉。

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

### 🔴 遥控器三键短路 —— 已定案（2026-09-13）

症状：三个键**没按就全读 0**，遥控器一醒就以为抬+落都按着 → 等 3s 发配对 → 等松手 8s 超时 → 睡 →
立刻又醒，**每 11.4s 循环一次**（实测 COM 口枚举周期 11.38s，和主机日志里"已配对"每 11.4s 一条对得上）。

**真因：轻触开关内部相通的是间距 6.1mm 的那一对，不是 4.5mm 那一对。**
而 PCB 上 `pad1`(信号) 与 `pad2`(GND) 正好相差 6.101mm = 内部同一根铜片的两端 → **按不按都短路**，三颗同错。
详见[遥控器网表基准 §封装几何](../道闸玩具_遥控器网表基准_v1.md)的 2026-09-13 更正。

**PCB 设计侧五项全查过、全干净**：封装焊盘编号 ✅ 原理图接法 ✅ DRC 零错 ✅ 覆铜对焊盘间距 ✅ 覆铜对走线间距 ✅。
错的只有"封装内部谁和谁相通"这一条 —— **这正是 EDA 查不出来的那一类**：在它眼里 pad3/pad4 只是没连网络的
孤立焊盘，它不知道内部连着谁。

**怎么定的案**（过程比结论值钱，见 `rcdiag/README.md`）：
- 万用表**断电量通断连着测错两轮** —— 不上电量芯片引脚会被内部 ESD 钳位二极管骗（蜂鸣档开路电压能让它导通）；
  进了下载模式再量电压，ROM 不配上拉，读到 0V 同样什么都证明不了。**两轮读数互相矛盾**。
- 换成 `rcdiag` 诊断固件，用芯片内部上拉/下拉当阻抗表，**并设板上没接东西的 GPIO5 当对照脚**，一屏定案。
- 弱驱探测（5mA 输出高读回 0）证明是**金属级死短**（<约 100Ω），排除助焊剂/漏电那一类 kΩ 级原因。
- `pad9(GPIO0)` / `pad11(GPIO2)` 在 PCB 上无网络、物理位置就夹在中招的脚中间却完全健康 →
  **故障严格沿网络走**，排除模块底下整排的连锡/污染。

### 现有三块板怎么改（硬件待办）

四个焊盘是 6.1 × 4.5 的长方形；`pad1`=有细走线的(信号)、`pad2`=融在 GND 铜里的、`pad3/pad4`=空。
必须让**信号和 GND 分属两个触点**。三条路，任选：

| | 做法 | 代价 |
|---|---|---|
| **转 90°**（最干净） | 把开关四条腿弯成 4.5×6.1 再装，触点从"沿 x 排"变"沿 y 排" → `pad1+pad3` 一组、`pad2+pad4` 一组 | 3 颗 × 4 条腿 = 12 次精细折弯，可能弄裂本体。**孔 φ≈1.2mm、腿约 0.5mm，单边约 0.35mm 富余**兜着 |
| 剪腿 + 飞线 | 剪掉插 `pad1` 的那条腿，再从 `pad1` 孔飞 4.5mm 到 `pad3` 孔 | 要拆焊四脚直插件；**飞线必须带绝缘**，两孔之间隔着 GND 覆铜 |
| 割走线 + 飞线 | 割断 `pad1` 的走线，从 `pad3` 飞到 U1 对应焊盘（SW1→pad13 / SW2→pad12 / SW3→pad10） | 走线只有 0.25mm 宽、对覆铜间距 0.12mm，割起来手要稳 |

⚠ **转 180° 没用**：只是 `pad1↔pad4`、`pad2↔pad3` 对调，那个 6.1mm 的触点照样横跨"信号+GND"。

**验收判据（用 `rcdiag` 读）**：旧开关拆掉后那一行应变 `OK(free)`（同时证明走线和模块清白）→
装好新开关后**不按 `OK(free)`、按住 `PINNED LOW`、松手弹回**。**一次只改一颗**，改完验一颗。

**下一版原理图的正确接法不是"转 90°"**，而是照实物触点分组连：**信号接 pad1+pad2、GND 接 pad3+pad4**。
那样新板子开关正插就是对的，还顺带消掉"无网络焊盘"。（尚未动工）

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

## 配对与距离

两边固定 **信道 1**（`GATE_ESPNOW_CHAN`），不连路由器，ESP-NOW 不加密。

**配对步骤**：① 先给主机上电（只配对的话 USB 就够，不用电池/电机）→ ② **60 秒内**在遥控器上同时按住
**抬杆+落杆 3 秒** → ③ 主机蜂鸣器**升调两声** = 成功。两边都写进 NVS，断电不丢，**只需配一次**。

🔴 **配对窗口只有主机开机后 60 秒**（`PAIR_WINDOW_MS = 60000`），过了不受理 —— 防止邻居家一按遥控器
把主机抢走。错过就把主机断电重开。主机若从未配过，会认第一个说得上话的。

**距离：从来没有实测过，固件也没做任何射频调优。** 现在跑的是默认 802.11b/g/n 速率、默认发射功率，
**没开 LR 长距模式**。同类配置的经验值（不是本机实测）：同房间无遮挡 30~50m、隔一两堵墙 10~20m、
室外直视 100m+。对客厅里的玩具余量很大。真不够的话
`esp_wifi_set_protocol(WIFI_IF_STA, WIFI_PROTOCOL_LR)` 能显著拉长，**但两端必须同时开**。

⚠ **待验：板载天线下面可能压着覆铜。** C3 SuperMini 的天线在模块一端，而遥控器板的 GND 覆铜是一整块矩形
（x 从 −27.305 铺到 +27.686），模块占 x 7.11~24.89 —— 覆铜很可能一直铺到天线正下方。板载天线下有地平面
会严重失谐。**天线在模块上的确切位置尚未核实**，所以只记为待验。联机测试时若发现"隔一堵墙就断"，
**第一个查这条**，标准解法是在天线投影区挖掉覆铜做 keep-out。

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
