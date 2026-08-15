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
- ⚠️ **`sch_Netlist.getNetlist()` 会挂起**（三种 type 都 >30s 超时，超过桥的 30s 上限）。

**2026-08-13 补充的坑（都会静默给错结果）：**

- 🔴 **导线的 `getState_Net()` 已经全部返回空字符串**，`getAll("GND")` 也返回 0 条（2026-08-11 时还能用）。**网络名只存在于网络端口符号上**，连接关系只能靠坐标几何重建：每根导线的全部顶点并为一个连通块 → 把落在任意线段上的引脚点并进去（含 T 型接点）→ 连通块内的端口符号给出网络名。同名的多个连通块是同一条逻辑网络（星型接法）。
- **校验工具必须先复现已知基准、且必须带阳性对照**（故意挪开一个引脚坐标，确认它掉出网络）。否则工具坏了都不知道。
- **执行上下文里没有枚举对象**，`EPCB_*` 一律 undefined，只能传字面值；而**字面值和成员名对不上**：`RECTANGLE→"RECT"`、`OBLONG→"OVAL"`、`REGULAR_POLYGON→"NGON"`。必须去 `references/enums/` 查反引号里的实际值。
- **`"ELLIPSE"` 画不出椭圆**：`["ELLIPSE",86.6,70.9]` 被静默压成 70.9×70.9 正圆。长短轴不等要用 `"OVAL"`。只有回读焊盘尺寸才发现。
- **系统库封装无法 `openInEditor`**（返回 `false`，随后 PCB 接口因当前文档仍是原理图而抛 `Cannot read properties of null (reading 'map')`）。要看/改系统库封装，先 `lib_Footprint.copy` 到**个人库**（`getPersonalLibraryUuid()`）；目标库传 `getProjectLibraryUuid()` 返回的 `"project"` 会失败。
- **换器件只能删了重建**：`sch_PrimitiveComponent.modify()` 改不了 symbol/footprint/device，属性表里根本没有这几项。重建后 `create()` 返回的对象是旧快照，`designator` 要另外 `modify()` 再 `get()` 回读确认。
- **`lib_Device.create(lib, name, cls, association, ...)`** 的 `association` 可以直接引用**系统库的符号 + 个人库的封装**，所以自建器件时符号可以借现成的，不必画。
- 🔴 **符号 uuid 有两套，靠长度区分**：`association.symbol.uuid` 必须是**库里的 32 位 uuid**（来源：`lib_Device.search()` 结果的 `symbolUuid` 字段）。原理图元件 `getState_Symbol().uuid` 返回的是**文档局部 id，只有 16 位**，传进去 `create` 必抛错，而错误序列化出来只有 `[object Object]`，完全看不出原因。**32 位=库 uuid，16 位=文档局部 id。** `getState_Component()` / `getState_Footprint()` 的 uuid 同理。
- **破坏性脚本要把"新建"排在"删除"之前**。上面那个 create 失败时删除还没执行，原理图毫发无伤；反过来写就会删完才发现建不出来。
- **`pcb_Document.importChanges()` 是异步的**：返回 `true` 后元件不会立刻出现，要另起一次调用再查。而且它**按位号匹配已有元件、不会换封装**——改了封装要先把 PCB 里那个元件删掉再导入；整批重来最保险（板框和焊盘图元不受影响）。导入同样可能弹确认框。
- **`getPrimitivesBBox()` 把位号文字算进去**，不能当实体尺寸用（自画 18.1 宽的丝印，包围盒报 21.08）。要实体尺寸就用封装文档里的实测值。
- **元件间距不能只比单轴**：两个盒子 X、Y 都不重叠时是对角相邻，真实间距是对角线长度，只看 X 会把 13mm 误报成 0.34mm。
- `lib_Footprint.modify` / `lib_Device.modify` 的 `classification` **传 `null` 会抛** `Cannot destructure property 'primaryClassificationUuid'`，要传 `undefined`。
- 层 id：`TOP=1` `BOTTOM=2` `TOP_SILKSCREEN=3` `BOARD_OUTLINE=11` `MULTI=12`（THT 焊盘用 12）。非金属化孔靠 `metallization=false`，没有专门的 padType。
- 🔴 **API 调用会被 EDA 的模态对话框卡住 → 表现为"超时 30000ms"，不是 bug。** `sch_PrimitiveComponent.create` 在库版本比工程库新时会弹「发现这个器件有更新，是否先更新掉工程库里的这个器件？」，一直等到用户点按钮。**连续超时时先让用户看一眼 EDA 界面有没有弹窗**，别去猜 API 坏了。
- **工程库会存一份封装/符号的副本，改个人库的原件不自动传导。** 副本的 uuid 是 16 位。点了「更新」之后：器件名会刷新（连已放置的元件也跟着变），但**封装副本的名字仍是旧的**；副本 `openInEditor` 打不开（`"project"` 和 `undefined` 都抛错），**几何无法用 API 查证**。要核实只能等落到 PCB 文档里再读。
- 建封装时**不要重编焊盘号**，只把编号 N 的焊盘搬到目标位置 N，避免瞬时编号冲突。
- 保存：原理图 `sch_Document.save()`，封装编辑器（documentType 4）用 `pcb_Document.save()`。

**2026-08-15 新增的坑（建遥控器工程时踩的）：**

- 🔴 **网络标识（GND / 5V 这类 netflag 符号）放不进去**：`sch_PrimitiveComponent.create({libraryType:"2",...})` 放 `symbolType=18` 的符号**必定卡满 30 秒超时**（其余调用同时都正常，`1+1` 秒回）。推断是 EDA 弹了网络命名框在等点击。**绕法：重排版面让每条网络都能用普通导线连通且零交叉**，不依赖标识。
- **找 netflag 要按符号类型过滤**：`lib_Symbol.search(key, undefined, undefined, 18, n, 1)`，`ELIB_SymbolType.NET_FLAG=18`、`NET_PORT=19`，**而且要传数字 18 不是字符串 "18"**（传字符串报 `Cannot read properties of undefined (reading 'facets')`）。不过滤的话搜 "VCC" 全是无关元件。GND=`029dc91398624049926195124347581a`、Power-5V=`8a04e22374494d55957a030ec33de1cb`，库 `0819f05c4eef4c71ace90d822a990e87`。
- 🔴 **桥的 30 秒上限是按"一次 /execute"算的**，不是单个 API。一次塞十几个调用（尤其 `lib_Device.search`，很慢）就会整批超时、**前面已执行的部分却已经生效**。要么拆批，要么**跳过搜索直接构造 `{libraryType:"2", libraryUuid, uuid}`**。
- **新建工程不会自动切过去**：`createProject` 返回的是 **uuid 字符串**（不是对象），且当前工程不变；要 `dmt_Project.openProject(uuid)`。列工程用 `getAllProjectsUuid(teamUuid)`，**不传 teamUuid 返回 0 条**。
- 🔴 **新工程刚打开时没有任何文档处于激活状态**，此时调 `sch_PrimitiveComponent.create` 会**卡 30 秒超时**（症状与弹窗一模一样，容易误判）。先 `dmt_EditorControl.openDocument(原理图页 uuid)`，用 `dmt_Schematic.getCurrentSchematicInfo()` 确认不是 "none" 再动手。
- **`sch_PrimitivePin.getAll()` 恒返回 0 条**，引脚要从元件对象上取：`(await comp.getAllPins())`。
- **`getState_Line()` 读回的是按段展开的扁平数组**（每 4 个数一段 `x1,y1,x2,y2`），与 `create()` 传入的"分段数组"格式不同。写进去一条 3 折的折线，读回来是 3 段。
- `sch_Net.getAllNetsName()` 同样返回**空**——不只是导线的 `getState_Net()`。
- `lib_Footprint.get` / `lib_Footprint.copy` 对**系统库**封装都抛 `[object Object]`，几何读不出来。要核封装尺寸只能等元件落到 PCB 文档里再读焊盘坐标。

**2026-08-15 做遥控器 PCB 时新踩的：**

- 🔴 **`pcb_MathPolygon.createPolygon` 不会自动闭合**，尽管文档明写"如果首尾不重合将会自动重合"。画板框少了最后一条边，**API 全程报成功、`zoomToBoardOutline()` 也返回 true**，是用户看图才发现的。**必须显式把首点补回末尾。**
- **`createPolygon` 只做闭合形状，不能画走线**：传开放路径直接抛"无法创建多边形图元"。走线用 `pcb_PrimitiveLine.create(net, layer, x1,y1,x2,y2, width)` 一段一段建。板框/挖槽用 `pcb_PrimitivePolyline.create(net, 11, polygon, width)`。
- **`importChanges()` 会弹确认框**：返回 `true` 但 PCB 上元件数始终是 0，而且**其余 API 全程正常响应**（不像放 netflag 那样卡超时），极易误判成"API 坏了"。要让用户去 EDA 点一下。
- **PCB 坐标单位是 mil**（原理图是 0.01 inch）。`mm = mil × 0.0254`。
- **系统库封装的几何只能落到 PCB 里才读得到**：`comp.getAllPins()` 拿相对元件中心的焊盘坐标，反算行距/跨距。`lib_Footprint.get`/`.copy` 在库里一律抛不透明错。
- **旋转 180° 会让对称封装的引脚编号对调**（SK-12D07VG7 的 1/3 脚）。改朝向之后**必须重布**碰到它的网络，光转不管走线会静默断开。
- 🔴 **`pcb_Drc.check()` 不传参返回的那个布尔值不可信，别拿它下结论。** 之前记的是"不传参返回 false"，但 2026-08-15 改完遥控器板框后同样不传参却返回 **`true`** —— 同一块板、同一个 API，两次相反。这个布尔到底编码"跑没跑成"还是"有没有错"没搞清楚，**当"零错误"的证据用就是在给自己发假通过**。一律用 `check(true, false, true)`，它返回**错误对象数组**，`length === 0` 才是干净。
- **连通性判据要用阳性对照标定**：取 0.02mm 时误报了一条真连通的网络（走线端点距焊盘中心 0.01mm），放到 0.03mm 才对。**太严造假故障、太松放过真断线**，必须用"偏移 0.1/0.3/2.0mm 都必须判断开"来标定。
- 🔴 **连通性校验必须分层**。不看层的版本把底层走线从顶层 SMD 焊盘底下穿过也算连上，**给了假通过**，是 DRC 抓到的。正确模型：节点 =（x, y, 层），同层线段连两端，**只有直插焊盘（层 12）和过孔跨层**。
- 🔴 **删走线只删 `pcb_PrimitiveLine` 会留下孤儿过孔**，重布后 DRC 报 `Connection Error` 指着不在任何走线上的过孔。删线必须**连 `pcb_PrimitiveVia` 一起清**。
- 🔴 **算板边净距必须按焊盘"铜箔边缘"，不能按中心。** 用中心距 0.45mm 当判据选出来的螺柱缺口位置，DRC 直接报 `Board Outline to TH Pad` —— THT 焊盘半径约 0.9mm，0.87mm 的中心距实际净距是 0。判据要 **中心距 ≥1.5mm**。同一类错误在这个项目里犯过三次（元件间距只比单轴、包围盒含位号文字、这次的焊盘中心）。
- **改板框之后必须重跑 DRC**：自动布线器会把板边当走线通道用（它布线时看到的是光板），后加缺口就会撞上已有走线。
- **旋转 180° 前先想清楚引脚会不会镜像到另一排**：C3 SuperMini 转 rot 90→270 之后，用到的 5 个焊盘从 y=+2.12 全部跑到 y=−13.12，碰到它的 5 条网络必须整体重布。

**2026-08-15 板框倒 R2 时新踩的：**

- 🔴 **`dmt_Project.openProject()` 换不了工程，恒返回 `false`**（`openProject(uuid)`、`openProject(uuid, true)`、把工程 uuid 喂给 `openDocument` 三种都试过）。不是权限问题——`getProjectInfo(uuid)` 能跨工程读到信息。**跨工程只能让用户手点开**，而且 `dmt_Pcb.getAllPcbsInfo()` 只列当前工程，所以也拿不到别的工程的文档 uuid 来绕。**同工程内换文档正常**：`dmt_EditorControl.openDocument(docUuid)` 返回 `docUuid@projectUuid`。
- **想知道 EDA 里现在开着哪些标签**：`dmt_EditorControl.getSplitScreenTree()` 返回 `{id, tabs:[{tabId, title, data:{doctype}}]}`，`tabId` 就是 `docUuid@projectUuid`。（`getTabsBySplitScreenId()` 我没喂对参数，返回空，直接读 tree 更省事。）
- **板框不是 Region 也不是 Line，是 `pcb_PrimitivePolyline`（层 11）**。`pcb_PrimitiveRegion.getAll()` 对板框返回**空数组**，`pcb_PrimitiveLine.getAll()` 只给铜层走线。顶点在 `poly.polygon.polygon`，是**扁平数组**且夹着模式记号：`[x0,y0,"L",x1,y1,x2,y2,...]`，单位 mil。解析时遇到字符串要跳过。
- **改板框不用删了重建**：`pcb_PrimitivePolyline.modify(id, {polygon})` 原地改，图元 ID 不变（删重建还得担心孤儿过孔）。
- ⚠ **多边形数组支持 `ARC` 段，但文档自相矛盾**：正文写 `startX startY ARC angle endX endY`，示例却是 `[..., "ARC", 400, 220, 15, ...]`（角度在末位）。**这个 API 已经在"自动闭合"上骗过一次，别赌**——倒圆角改成 16 段离散化，最大偏差 0.0024mm，比铣边公差 ±0.2mm 低两个数量级。
- 🔴 **回读校验的容差不能设到 1e-6mm**：EDA 把坐标量化到 mil，回读的 −28.5 是 −28.49999888，**偏差约 1.7 nm**。我第一遍用 1e-6 当判据，23 个完全正确的顶点被报成"偏离几何"，差点当成真故障去改。**容差取 1e-3mm 量级**（仍比任何制造公差严三个数量级）。
- **验板框要带阳性对照**：光确认"新圆弧点都在 R=2 上"不够，还要确认**原来那四个直角点已经查无此点**——不然可能是在旧轮廓上又叠了一圈新点。

**2026-08-15 改主机 PCB（挪 SW3 + 让开安装孔）时踩的：**

- **`pcb_PrimitiveLine.modify()` 改端点会"自动分段"**，不是把端点搬过去。把一段 `(-82.6,17)->(-80,17)` 的起点改成 `-84.1`，读回来变成**两段** `(-84.1,17)->(-82.6,17)` + `(-82.6,17)->(-80,17)`。电气上连通、DRC 也过，但**几何比对时按"一段"去找会找不到**。改完一律重建连通性再判断，别拿段数或坐标逐条比。
- **改了走线必须 `rebuildCopperRegion()`**，否则 DRC 报 `Copper Region(Filled) to Track`。覆铜是改板框时要重建，改走线**同样**要重建。
- **覆铜范围读 `pcb_PrimitivePour.getAll()` 的 `complexPolygon`，别读 `pcb_PrimitivePoured` 的 `pourFills`**。前者是用户画的区域，常常就是一句矩形模式 `["R", x, y, w, h, rot, round]`（x/y 是**左上角**），简单可靠；后者是实际填充几何，**坐标系我没搞明白**——解析出来的包围盒只有 11.5×5.8mm 而板子是 120×65，自己的合理性检查就没过。**解析完必须拿包围盒对一下板子大小**，对不上就说明解错了，别拿错的数下结论。
- **`pourFills[].path.complexPolygon` 里的 `ARC` 是 `"ARC", 角度, endX, endY`** —— 和格式文档正文一致、和文档示例 `["ARC",400,220,15]` 不一致。**示例是错的。**
- **阳性对照的偏移方向要挑，不能只偏 X。** 校验连通性时把焊盘沿 +X 偏 2mm，`VBAT_PROT` 居然还"连通"——因为那根走线本身就是水平的，焊盘**顺着自己的线滑**了，从没离开导体。**轴对齐的走线要用斜向偏移**（x、y 同时偏）才证明得了判据有效。这条不是校验器的 bug，是对照本身设计错了。
- **GND 这类覆铜网络会被"走线连通性"判成断开**，因为它靠覆铜不靠走线（主机 GND 有 22 个焊盘、0 根走线）。**校验时要显式排除覆铜网络**，否则每次都报一条假故障，报久了就没人看了。

**核心纪律**：元件放了、线画了、**API 也报成功**，网表仍可能是错的（历史上 82 根线静默只生成 78 根；这次板框少一条边也是 API 全绿）。必须坐标比对逐条校验，不能靠看图，也不能信返回值。
**阳性对照要放一个"差一点点"的**：遥控器那次用了个距真引脚仅 5 个单位的假引脚，确认它掉出网络——只放个远处的假点，证明不了工具在判别距离。相关项目见 [[daozha-toy-scope]]。
