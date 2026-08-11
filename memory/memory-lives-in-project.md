---
name: memory-lives-in-project
description: 记忆文件已迁到项目目录 D:\玩具\01.道闸门\memory\，C 盘只留一个索引指针
metadata:
  type: reference
---

**记忆正文全部存放在 `D:\玩具\01.道闸门\memory\`**（2026-08-11 从 C 盘迁入，用户要求）。

**Why:** 用户希望记忆跟项目走——能随项目一起备份、查看、版本管理，而不是散落在 `C:\Users\Administrator\.claude\` 里看不见的地方。

**How to apply:**
- **读写记忆一律去项目目录** `D:\玩具\01.道闸门\memory\`，索引是该目录下的 `MEMORY.md`。
- C 盘 `C:\Users\Administrator\.claude\projects\D-----01----\memory\MEMORY.md` **必须保留**，里面只放一个指向项目目录的指针。原因：会话启动时自动加载进上下文的是 C 盘那个 `MEMORY.md`，把它一起删掉记忆就再也不会被自动读取了。C 盘不再存放任何记忆正文。
- 新增记忆：正文写进项目目录，并在项目 `MEMORY.md` 加一行索引；C 盘那个指针文件不用动。
