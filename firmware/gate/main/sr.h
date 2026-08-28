// ESP-SR 离线语音（M5，最难的一步）。现在是桩：接口先钉死，
// 实现后 main.c 一行不用改 —— 识别到命令词就 evt_post()。
#pragma once

void sr_start(void);
