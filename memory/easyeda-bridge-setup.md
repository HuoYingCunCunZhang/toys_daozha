---
name: easyeda-bridge-setup
description: 用 Claude Code 直接操作嘉立创EDA专业版的桥接环境（已在本机跑通）
metadata: 
  node_type: memory
  type: reference
  originSessionId: 71e9ee68-c3ea-425e-adaf-0b0540f0699e
  modified: 2026-08-11T13:13:52.291Z
---

可以用 Claude Code 程序化操作嘉立创EDA（EasyEDA）专业版，链路已在本机验证通过：

```
Claude Code → HTTP 127.0.0.1:49620 → Bridge Server → WebSocket → Run API Gateway 扩展 → EDA
```

三个组成部分：
1. **EDA 侧扩展** `run-api-gateway.eext`（本机 v1.0.5，已装）。它**不监听端口**，是扫描 49620-49629 主动连出去的一端。装完必须在 EDA「高级 → 扩展管理器 → 已安装」里勾选 **「外部交互 External Interactions」**，否则不会去连。
2. **Bridge Server**：`easyeda-api` Skill 自带，装在 `C:\Users\Administrator\.claude\skills\easyeda-api`（来自 github.com/easyeda/easyeda-api-skill）。启动：`cd 该目录; node scripts/bridge-server.mjs`。需 Node 22+（本机 v22.17.0）。仅监听 127.0.0.1。
3. **调用方式**：
   - `GET http://127.0.0.1:49620/health` → 看 `edaConnected`
   - `POST /execute`，body `{"code":"return await eda.dmt_Project.getCurrentProjectInfo();"}`
   - PowerShell 调用要用 `[Text.Encoding]::UTF8.GetBytes($body)` 传 body，否则中文会乱码

API 参考文档在该 Skill 的 `references/`（120+ 类）、`guide/`、`user-guide/` 目录里。

**实测踩过的坑**（2026-08-11 验证）：
- `dmt_Project.createProject()` **不要传 teamUuid**。传 Personal 团队的 uuid 会返回 undefined，不传反而成功。
- 工程创建时会自动带一个 Board1+schematic1，**不要再调 `createBoard()`**，否则多出 Board2。`deleteBoard()` 会导致 EDA 重载、桥短暂断开（会自动重连，windowId 变化）。
- `createSchematic(boardName?)` 的参数是**板子名**不是原理图名。
- `lib_Device.search` 完整签名有 **6 个参数** `(key, libraryUuid?, classification?, symbolType?, itemsOfPage?, page?)`，但 `_quick-reference.md` 里只列了 5 个（漏了 symbolType）。按 5 个传会全部搜到 0 条。**必须读 `references/classes/` 里的完整文档，不能信快速索引。**
- 原理图坐标单位 **0.01 inch**。引脚 `getState_X/Y` 返回的是**引脚外端的连接点**（可直接作为导线端点）。
- `sch_PrimitiveWire.create(line,...)` 的 line 是**分段数组**，每个子数组是一整段的连续坐标 `[x1,y1,x2,y2,...]`。写成 `[[x1,y1],[x2,y2]]` 会因"每段只有一个点"而失败。**斜线段非法，只能水平/垂直。**
- ⚠️ **`sch_Netlist.getNetlist()` 会挂起**（三种 type 都 >30s 超时，超过桥的 30s 上限）。**替代校验方案**：`sch_PrimitiveWire.getAll()` 读每根线的 `getState_Net()` 和 `getState_Line()`，加 `component.getAllPins()` 的 `getState_X/Y`，用坐标重合判断连接——这比信任网表导出更直接。

**核心纪律**：元件放了、线画了，但引脚差一点就不算电气连接——视觉正常而网表错误。必须用上述坐标比对法逐条校验，不能靠看图。相关项目见 [[daozha-toy-scope]]。
