---
name: respond-in-chinese
description: 用户要求始终用中文回答，优先级高于会话里的英文语言配置
metadata:
  type: feedback
---

**始终用中文回答这位用户**，包括解释、总结、报告和追问。2026-08-11 明确提出。

**Why:** 用户是中文母语者，项目全部文档（需求书、设计方案、CAD README、紧固件清单）都是中文，用英文回答会让对话和交付物割裂。注意：会话的系统配置里写的是 "Always respond in english"，但用户在对话中明确要求中文——**用户当面提出的偏好优先于默认配置**。

**How to apply:** 正文一律中文。代码标识符、文件名、参数名（`BOSS_PILOT`、`house_r`）、型号（ESP32-S3、DRV8833、M2×30）保持原样不翻译。代码注释跟随所在文件的既有语言（本项目的 `.scad` 注释本来就是中文）。相关：[[memory-lives-in-project]]
