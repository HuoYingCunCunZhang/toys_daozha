# 道闸玩具 · 固件

两个独立 ESP-IDF 工程，共用 `common/gate_proto.h` 里的 ESP-NOW 包定义。

| 目录 | 芯片 | 干什么 |
|---|---|---|
| `gate/` | ESP32-S3-DevKitC-1 **N16R8** | 状态机、电机、限位、按键、蜂鸣器、ESP-NOW 收、语音（M5 待做） |
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

**当前编译状态**（2026-08-29，ESP-IDF v6.1 正式版，`D:\fw\` 下冷编译）：
主机 ✅ / 遥控器 ✅，`-Wall -Wextra -Werror` 零警告零错误。
`daozha_gate.bin` **773.4KB**（16MB flash / 八线 PSRAM / 自定义分区表已回读 `sdkconfig` 核过生效，
app 分区 4MB 用掉 19%）、`daozha_remote.bin` **783.4KB**（1MB app 分区用掉 77%）。
比 v6.1-beta1 时各小十几 KB，是编译器版本差异。

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
| 麦克风 SCK/WS/SD | 4 / 5 / 6 | N20~N22 | INMP441，I2S0（M5 才用） |

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
| 底座双键同时按住 3s | 复位 → 重新回零 |
| 遥控器单键 | 抬杆 / 落杆 |
| 遥控器抬+落同时按住 3s | 发配对广播（**主机必须在开机后 60s 内**） |

**单键要等松手才动作**，因为两个键不可能真正同时按下 —— 按下即动作的话，双键复位一定会先误触发一次抬杆或落杆。

**配对窗口只有开机后 60s**，否则邻居家一按遥控器就能把主机抢走。配对成功蜂鸣器升调两声。

蜂鸣：收到命令一短声 / 到位两声 / 防砸急促三声 / 故障连续长鸣（复位才停）。

---

## 状态机

```
BOOT → HOMING（慢速落杆，8s 未触限位 → FAULT）
         ↓
      CLOSED ⇄ OPENING → OPEN(90°) ⇄ CLOSING → CLOSED
                                         ↓ 落杆超 1.15×T
                                    立即反向 → OPENING（防砸）
任意态 ──故障──► FAULT（断电机、连续长鸣，只有复位能出来）
```

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
3. **M1 供电：USB 供主控，但电机那一路必须另外喂。**
   ⚠ 原来这条写的是"必须 USB 供电"，**不成立**（2026-08-29 改正）。看网表：
   `U4.OUT+ →〔N5 +5V〕→ D1 →〔N6 5V_MCU〕→ U1.5V`，而 **`U2.VM` 挂在 N5**。
   DevKit 的 USB 只能把 5V 送到 **N6**，D1 方向是 N5→N6，**反过来截止 → VM 没电、电机不转**。
   D1 本来就是为这个存在的（电机拉低 +5V 时截止，C3 独立顶住主控），代价就是 USB 喂不到电机。
   所以 M1 要么**电池+升压轨照常工作**（USB 只用来烧录和看日志，两路由 D1 天然隔开、不冲突），
   要么**从外部往 N5 灌 5V**。原意"别让电源问题和电机逻辑问题混在一起"仍然对 —— 
   办法是先把升压调准并确认稳定，不是不接它。

---

## 里程碑对照（方案 §8）

| 阶段 | 目标 | 固件状态 |
|---|---|---|
| M0 | 环境，S3 跑通，PSRAM 识别 | ✅ 工程骨架就绪，`sdkconfig.defaults` 已开八线 PSRAM |
| M1 | USB 供电控制 N20 正反转，触限位自动停 | ✅ `motor.c` / `endstop.c`，待实测定 `MOTOR_INVERT` |
| M2 | 2 按键走完整行程，含软启动/缓停/超时/双键复位 | ✅ `motion.c` / `input.c` |
| M3 | 标定 T，手挡闸杆能在 1.15×T 反转 | ✅ 逻辑已写，阈值待实测校 |
| M4 | 遥控器 ESP-NOW + 配对 + 深睡 <20µA | ✅ `remote/`，深睡电流待实测 |
| **M5** | **ESP-SR 三条命令词** | 🔴 **`gate/main/sr.c` 是桩**，接口已钉死，实现后 `main.c` 不用动 |
| M6/M7 | 结构装配、电池装机联调 | — 不是固件的事 |

M5 落地要做的（都写在 `sr.c` 的注释里）：`idf.py add-dependency "espressif/esp-sr"`，
I2S0 读 INMP441 → AFE → WakeNet9 唤醒 → MultiNet7 中文命令词 → `evt_post()`。
模型烧进 `model` 分区（6MB，见 `gate/partitions.csv`）。

---

## 代码里两个不显眼的坑

- **限位模块叫 `endstop.h` 不叫 `limits.h`** —— `main/` 在 include path 上，
  叫 `limits.h` 会盖掉 C 标准库的 `<limits.h>`，报错点会离现场很远。
- **只有 `motion.c` 能调 `motor_*`**（方案 §7.2 的规矩）。其它任务一律 `evt_post()`，
  否则语音和遥控会抢电机。
