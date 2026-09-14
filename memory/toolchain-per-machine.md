---
name: toolchain-per-machine
description: 两台电脑的 ESP-IDF 安装位置不同（beta1 在 D:\esp、正式版在 C:\esp），仓库在 D:\workspace_zc 的那台可以原地编译不用 robocopy
metadata:
  type: project
---

用户在两台电脑之间切换，**ESP-IDF 的路径和版本按机器不同**，`firmware/README.md` 的环境表只写了其中一台：

| 机器 | 仓库路径 | IDF | 激活脚本 |
|---|---|---|---|
| A（README 里那台，2026-08-29 起） | `D:\玩具\01.道闸门\`（中文，必须 robocopy 到 `D:\fw\`） | v6.1 正式版 `C:\esp\v6.1\esp-idf` | `C:\Espressif\tools\Microsoft.v6.1.PowerShell_profile.ps1` |
| B（2026-09-14 回到这台） | `D:\workspace_zc\toys_daozha\`（**纯 ASCII，可原地 `idf.py build`**，`firmware/*/build/` 就是 09-11 原地编出来的） | **v6.1-beta1** `D:\esp\v6.1-beta1\esp-idf`，工具在 `D:\Espressif\tools`（xtensa + riscv32 都在） | `C:\Espressif\tools\Microsoft.v6.1-beta1.PowerShell_profile.ps1` |

**Why:** 换机后第一件事就是按 README 的路径激活环境，B 机上 `C:\esp\v6.1` 和 `D:\fw` 都不存在，照抄会直接报"找不到脚本"。反过来 B 机上 README 那条 robocopy 的源路径 `D:\玩具\01.道闸门\firmware` 也不存在。登记表在 `C:\Espressif\tools\eim_idf.json`，认不出是哪台机器就先 `cat` 它。

**How to apply:** 会话开始先 `Test-Path` 这两个激活脚本，哪个存在就是哪台机器。B 机直接在仓库里编，别 robocopy（`/MIR` 的源不存在会把目标清空）。两个版本编出来的 bin 有十几 KB 差异，属正常。相关：[[daozha-toy-scope]]
