// ESP-SR 离线语音（M5）。识别到命令词就 evt_post()，main.c 只管调 sr_start()。
// 起不来（没模型 / 麦克风初始化失败）不致命：打日志退出，按键和遥控器照常工作。
#pragma once

void sr_start(void);
