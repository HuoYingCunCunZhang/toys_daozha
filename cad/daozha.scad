// =====================================================================
//  道闸玩具 v2.3 · 参数化结构件
//  依据: 道闸玩具_电路与结构设计方案_v2.md
//
//  坐标约定 (OpenSCAD Z 朝上):
//    X  = 前后。-X = 长脚侧(按键 / Type-C)，+X = 闸杆伸出侧(道路)
//    Y  = 车辆行驶方向 (对应设计文档里的 Z 轴)
//    Z  = 高度，Z=0 为底座底面
//
//  v2.1 -> v2.2 修复:
//    - 闸体内腔挖穿顶面 -> 补回 2mm 顶盖
//    - 闸体底面被整个切开导致螺柱/托架悬空 -> 补回 2mm 底板 + 走线孔
//    - 微动开关座悬空 -> 改为贴内壁的整体托板
//    - 底座/遥控器内部特征被内腔减掉 -> 移出 difference() 之后再并集
//    - 电机托架 X 未居中、让位孔够不到 -> 重建
//    - 机械止挡筋是空块 -> 补建
//    - 新增 layout 视图, 可看内部元件排布
//
//  v2.2 -> v2.3 修复 (装配性):
//    [1] base_top / rc_top 的螺丝孔不是通孔 —— 沉头孔只从 z=-1 开始, 而两块
//        盖板背面都有 2mm 止口凸台(z=-2..0), 于是孔底留了 1mm 皮, 打完还得手工
//        捅穿。改成 csk(h, deep) 连止口一起打穿; 闸体固定孔的沉窝也移到止口
//        真正的背面 z=-2, 否则沉头埋在实体里。顺带把沉窝改成标准 90°。
//    [2] base_tray / rc_bottom 的螺柱顶面做到了与外沿等高(17), 没给上盖背面
//        2mm 止口让位 -> 上下盖压根扣不上。螺柱顶面下移到 外沿 - LIP_T - 0.2。
//    [3] hub 闸杆插槽的长宽装反了 —— 槽在装配坐标里是"竖 5.5 / 横 8.5",
//        闸杆(宽5 高8)只能宽面朝下躺着装; 横穿螺丝也跟着穿在竖直方向。
//        改为 竖 8.5 / 横 5.5, 螺丝改沿装配 Y 向穿杆的 5mm 窄边 —— 闸杆窄面
//        朝下、8mm 立起来受弯。同时把插槽加深到 20mm, 补上根本没落在实体里的
//        配重仓。
//    [4] 附带发现: house_r 侧没有对拧导向柱, 螺丝要在 21mm 空腔里悬空,
//        补 φ4.4 导向柱从 +Y 内壁撑到分模面。
//    [5] 闸杆自攻底孔 φ1.9 对 M2 太松 -> 统一为 BOSS_PILOT(1.7)。
//
//  紧固件规格见: ../道闸玩具_紧固件清单_v1.md
// =====================================================================

// GUI 里改这个字符串:
part = "assembly";
// assembly | layout | base_tray | base_top | house_l | house_r | hub
// bar_a | bar_b | rc_bottom | rc_top

// 命令行用数字 (避开 shell 传引号的麻烦):
//   openscad -D p=3 -o stl/house_l.stl daozha.scad
p = 0;
PARTS = ["assembly", "layout", "base_tray", "base_top", "house_l",
         "house_r", "hub", "bar_a", "bar_b", "rc_bottom", "rc_top"];
sel = (p == 0) ? part : PARTS[p];

$fn = 48;

/* ============ 通用配合参数 ============ */
WALL       = 2.0;
GAP        = 0.25;
BOSS_OD    = 4.4;
BOSS_PILOT = 1.7;             // M2 自攻底孔 (塑件)
SCREW_CLR  = 2.4;             // M2 过孔
HEAD_D     = 4.4;             // M2 沉头沉窝口径 (实际头 φ3.8, 留 0.6 余量)
LIP_T      = 2.0;             // 上盖背面止口凸台高度 (base_top / rc_top 共用)
BOSS_CLR   = 0.2;             // 螺柱顶面相对止口底面的让空, 保证外沿先贴合

/* ============ 底座 ============ */
BASE_L = 150;  BASE_W = 55;
// v2.5: 20 -> 22。为的是让 U1/U2/U4 的 8.5mm 排母装得下 —— 20mm 时板面以上
// 只有 11.4mm, DevKit 插排母叠高 13.2mm, 差 1.8mm。加高 2mm 后净空 13.4mm,
// 选型锁定和已连线校验的原理图一个字都不用改。
// 转轴离地 42 由 PIVOT_ABS 反推自动保持, 杆顶仍 46mm, 锁定约束不破。
BASE_H = 22;
TOP_T  = 3;
TRAY_H = BASE_H - TOP_T;      // 19
BASE_R = 3;

// 内腔: x ±73, y ±25.5, 地板面 z=2, 天花板(上盖背面) z=17
// v2.3 的"止口"是 rbox 生成的**实心板**, 145.5×50.5×2 整块压在 15~17mm,
// 把内腔净高从 15 砍到 13 —— ESP32 装不进去的真因。改成环形。
LIP_W    = 6.5;                                    // 止口环宽
LIP_IN_X = (BASE_L - 2*WALL - 2*GAP)/2 - LIP_W;    // 66.25
LIP_IN_Y = (BASE_W - 2*WALL - 2*GAP)/2 - LIP_W;    // 18.75
// => 中央净空区 x ±66.25 / y ±18.75, 净高 15mm; 环下方净高 13mm

// 角螺柱: 必须待在止口环正下方(沉窝才有料可埋), 且要让开电池。
// φ6 是为了嵌进 x=±73 / y=±25.5 两侧内壁, 否则 13.8mm 高的细柱会立不稳。
CORNER_OD = 6.0;
BASE_BOSS = [[-70.5, 23], [-70.5, -23], [70.5, 23], [70.5, -23]];

// 按键 [x, y]: 必须同时满足三条, 位置是被夹出来的不是随便挑的 ——
//   1) x < 2   : 闸体占 x=2..48, 按键不能被闸体压住
//   2) |y| ≤ 15.5 : φ6.5 孔要整个待在止口环以内(|y|<18.75), 否则 6×6×12 的
//                   顶杆会在 z=15 撞上环, 根本按不下去
//   3) 让开 U1 DevKit 和 U3 TP4056 在板上的占位
BTN_POS = [[-40, 10], [-20, 10]];
BTN_D = 6.5;

USB_W = 10;  USB_H = 5;  USB_Z = 8;  USB_Y = 0;
// PSW 从 19 挪到 15: 19 时开口(y=15~23)会啃进角螺柱(y=20~26)
PSW_W = 8;   PSW_H = 4;  PSW_Y = 15;

/* --- v2.4 排布翻转 --------------------------------------------------
   v2.3 之前: 电池占 -X, 四个模块散放 +X。两个硬伤——
     a) 前端面的 Type-C / 总开关开口后面坐着电池, 而 TP4056 在 x=+57,
        离开口 132mm, 接口对不上;
     b) 两个按键(x=-50/-30)正压在电池顶上, 电池顶 12mm、上盖背面 15mm,
        中间只剩 3mm, 放不下 6×6 轻触开关。
   加上底板选型已锁定为**单块承载底板**(U1 DevKit 插板上, 模块全部上板),
   老的"每个模块四根限位柱"架构已经作废。
   现在按"接口在哪、板子就在哪"翻过来: 承载底板占 -X 半场正对前端面开口,
   电池挪到 +X 半场。按键位置不动, 自然落到底板上方。                    */

// 电池 103450 卧放 (50×34×10), 仓比电芯每边放 1mm
BAT_L = 50;  BAT_W = 34;  BAT_T = 10;
BAT_X0 = 21;  BAT_X1 = 73;    // 电池仓 x 范围 (52)
BAT_YH = 18;                  // 电池仓 y 半宽 (36)

// 承载底板 (工程"道闸玩具承载底板", 见 道闸玩具_底板选型锁定_v1.md)
PCB_X0    = -71;  PCB_X1 = 16;   // 87 长
PCB_YH    = 23.5;                // ±23.5 -> 47 宽
PCB_T     = 1.6;
PCB_SO    = 2.0;                 // 支撑柱净高 -> 板底 z=4, 板面 z=5.6
PCB_NOTCH = 4;                   // -X 两角让开角螺柱的缺口
PCB_MNT   = [[-63, 19.5], [-63, -19.5], [11, 19.5], [11, -19.5]];
// 板面以上可用高度 = TRAY_H - 5.6 = 13.4mm (中央区); 见 道闸玩具_底板机械约束_v1.md
// PCB_SO 不要往上加: 它每加 1mm, 板面以上就少 1mm
// U1 叠高 = 排母 + DevKit 排针隔片 2.5 + PCB 1.57 + 模组 3.1
//   标准 8.5 排母 -> 15.67  ✗ 超 2.3mm, 且 BASE_H 被开关托板卡在 ≤22.5 救不回来
//   低背 5.0 排母 -> 12.17  ✓ 余 1.2mm  <- 采用这个
U1_STACK  = 12.2;

/* ============ 闸体 (局部原点 = 闸体底面中心, 绝对 X = +25) ============ */
HS_L = 46;  HS_W = 46;  HS_H = 62;  HS_R = 3;
HS_X_ABS = 25;
// 转轴离地 42 是锁定约束(用户小车最矮 50mm, 杆顶 46 必须低于它)。
// PIV_Z 由它反推, 这样改 BASE_H 时转轴高度自动保持不变 —— 以前写死 22,
// 一旦把底座加高就会连带把转轴顶上去, 违反锁定尺寸。
PIVOT_ABS = 42;
PIV_Z = PIVOT_ABS - BASE_H;   // 22mm 底座 -> 20
// 上限提醒: 开关托板底面 = PIV_Z - SW_HOLE_R - 5, 必须 >= 闸体地板 WALL,
// 即 PIV_Z >= 19.5, 于是 BASE_H <= 22.5。想再加高底座就得先缩开关托板。

WIRE_D = 8;
WIRE_P = [0, -16.5];          // 走线孔 (闸体局部 XY), 避开螺柱与电机座

HUB_J_D    = 8;
CAM_BASE_D = 12;
CAM_LOBE_D = 18;
CAM_ARC    = 25;
SW_HOLE_R  = 12.5;            // 微动开关安装孔半径 (需实物微调)
SW_SPACING = 9.5;
MIC_Z      = 38;

/* --- N20 减速电机 ---------------------------------------------------
   通用 N20 微型金属减速电机 (= Pololu micro metal gearmotor 外形)。
   ⚠ v2.5 之前这里是错的:
     · 机身按 φ12.4 **圆柱**建模, 但 N20 机身是 10×12 **方形**, 对角线
       15.6mm, 根本塞不进 φ12.4 的圆槽;
     · 减速箱按 12.6 方形建模, 实际 10×12, 一个方向松了 2.6mm;
     · README 让人调的 MOT_TOTAL 参数在源码里根本不存在。
   ⚠ 收到实物必须卡尺复核, 尤其 MOT_L —— 随减速比在 24~30mm 之间变。      */
MOT_W    = 10.0;   // 截面宽 (装配 X 向)
MOT_H    = 12.0;   // 截面高 (装配 Z 向)
MOT_L    = 26.0;   // 总长(机身+减速箱)。上限 32, 再长顶到 +Y 内壁
MOT_CLR  = 0.4;    // 电机四周配合间隙
// 减速箱前端面 Y。下限被凸轮卡住: 凸轮占 y=-19..-13, 电机不能越过 -13
MOT_Y0   = -12.5;

SHAFT_D    = 3.0;  // D 形轴直径
SHAFT_FLAT = 2.5;  // D 形轴"对边"尺寸(平面到对侧圆弧) -> 平面距轴心 = 2.5-1.5 = 1.0
SHAFT_L    = 9.0;  // 轴伸出长度
SHAFT_CLR  = 0.15; // 轴孔间隙。要传扭矩, 不能用 GAP=0.25 那么松

/* --- 机械止挡 ---
   不再手摆角度。改用"扫掠差集": 毛坯减去转臂 0..STOP_ANG 扫过的区域,
   剩下的正好是抬到 STOP_ANG 之前绝不会碰到的料, 闸杆到 STOP_ANG 时与它相切。
   v2.5 之前是把一个方块转到 100° 摆在半径 9~15 处, 但方块侧面距转轴只有
   3.5mm 而转臂侧面在 7mm —— 挡块整个埋在转臂扫掠包络里, 实测闸杆抬到
   35~40° 就撞死, 根本到不了 90°。                                       */
STOP_ANG   = 100;
STOP_R0    = 15;   // 止挡毛坯内半径
// 外半径压在转臂尖端回转半径 √(20²+7²)=21.19 以内。取 22 的话, 21.19~22
// 那圈料转臂永远够不着, 白留一条又薄又弱的悬边。
STOP_R1    = 21;
STOP_SPAN  = 45;   // 毛坯扇形张角
STOP_OUT   = 9;    // 沿 -Y 伸出长度 (从内壁 y=-21 起算)

// 调试开关: 全部默认 true。-D FEAT=false 只出裸壳; F1~F4 可单独关掉排查
FEAT = true;
F1 = true;   // 底部固定螺柱
F2 = true;   // 左右壳对拧螺柱
F3 = true;   // 电机座
F4 = true;   // 微动开关托板

// 闸体底部固定螺柱: 4 角对称, 每半壳各 2 个, 立在底板上
HS_BOSS = [[15, 15], [15, -15], [-15, 15], [-15, -15]];
// 左右壳对拧螺柱: 必须贴到侧壁 + 底板/顶盖, 否则会悬空
// x=±19.2 使 φ4.4 螺柱嵌进 x=±21 内壁
// z 取 3.5 / 58.5 让螺柱真正插进底板和顶盖 —— 不能取"刚好相切"的 4.2 / 57.8,
// 相切接触会产生非流形边 (Simple: no)
HS_JOIN = [[-19.2, 3.5], [19.2, 3.5], [-19.2, 58.5], [19.2, 58.5]];

/* ============ 闸杆 ============ */
BAR_W = 5;  BAR_H = 8;  BAR_WALL = 1.2;
BAR_A_BODY = 150;  BAR_B = 150;  BAR_LAP = 20;  BAR_ROOT = 20;
STRIPE = 37.5;  STRIPE_D = 0.4;

/* ============ 转毂夹持段 ============
   转毂建模用的是"局部"坐标, 装配时 rotate([-90,0,0]) 转过去, 映射关系是:
       局部 +X -> 装配 +X   (闸杆伸出方向)
       局部 +Y -> 装配 -Z   (竖直)
       局部 +Z -> 装配 +Y   (转轴方向, 由外向内指向闸体)
   所以插槽在局部 Y 上的尺寸 = 闸杆的"高", 在局部 Z 上的尺寸 = 闸杆的"宽"。
   v2.2 正好写反了, 导致闸杆只能宽面(8mm)朝下躺着装。                       */
HUB_D        = 16;                        // 毂体直径
HUB_CLAMP_H  = 11;                        // 夹持段轴向长度 (局部 Z)
HUB_ARM_X0   = -16;                       // 配重端
HUB_ARM_X1   = 20;                        // 插杆端 (插入深度 20mm, 正好吃满闸杆实心根部)
HUB_ARM_W    = BAR_H + 2*GAP + 2*2.75;    // 夹持臂在局部 Y 上的外形 = 14
SLOT_V       = BAR_H + 2*GAP;             // 8.5 -> 装配后竖直, 闸杆 8mm 高立起来受弯
SLOT_H       = BAR_W + 2*GAP;             // 5.5 -> 装配后水平, 闸杆 5mm 窄面朝下
SLOT_Z0      = (HUB_CLAMP_H - SLOT_H) / 2;// 2.75, 槽在夹持段内居中
BAR_PIN_X    = 6;                         // 横穿螺丝距杆根 6mm, 与 bar_a 的底孔对齐
HUB_J_Z0     = HUB_CLAMP_H;               // 轴颈起点
HUB_J_Z1     = 16;                        // 轴颈终点 = 凸轮起点
HUB_Y_ABS    = -35;                       // 转毂原点的绝对 Y
BAR_Y_ABS    = HUB_Y_ABS + HUB_CLAMP_H/2; // 装配预览用: 闸杆中心的绝对 Y
// D 形轴孔的深度由电机位置反推: 轴从 MOT_Y0 往 -Y 伸 SHAFT_L
// 局部 z = 绝对 y - HUB_Y_ABS
BORE_Z0      = MOT_Y0 - SHAFT_L - HUB_Y_ABS - 0.5;   // 13.0, 多 0.5 不让轴顶死
BORE_Z1      = MOT_Y0 - HUB_Y_ABS + 1;               // 23.5
SETSCREW_Z   = 19;                        // 顶丝高度, 落在凸轮段(16~22)正中

/* ============ 遥控器 ============ */
RC_L = 60;  RC_W = 30;  RC_H = 20;  RC_R = 4;  RC_TOP_T = 3;
RC_BTN_X = [-18, 0, 18];
RC_BTN_D = 6;

/* =====================================================================
   通用模块
   ===================================================================== */
module rbox(l, w, h, r) {
    hull() for (x = [-l/2 + r, l/2 - r], y = [-w/2 + r, w/2 - r])
        translate([x, y, 0]) cylinder(r = r, h = h);
}

// 螺柱: 底孔从本地 z=0 面开口 (螺丝从该面拧入)
module boss_open(h) {
    difference() {
        cylinder(d = BOSS_OD, h = h);
        translate([0, 0, -0.5]) cylinder(d = BOSS_PILOT, h = h);
    }
}

// 螺柱: 底孔从顶面开口
module boss_top(h, d = BOSS_OD) {
    difference() {
        cylinder(d = d, h = h);
        translate([0, 0, 0.5]) cylinder(d = BOSS_PILOT, h = h);
    }
}

// 沉头过孔。
//   h    = 沉窝所在面 (本地 z=h) 到本地 z=0 的板厚
//   deep = z=0 以下还要继续打穿的深度 (盖板背面止口凸台就靠这个参数打穿)
// 沉窝取标准 90°: 每深 1mm 直径收 2mm, 螺钉头才能真正坐平而不是卡在孔口。
CSK_H = (HEAD_D - SCREW_CLR) / 2;      // = 1.0

// D 形轴孔: 圆 **交** 半空间。平面距轴心 = SHAFT_FLAT - SHAFT_D/2, 再放 CLR。
// 千万不要写成 圆 **并** 方块 —— 那样孔比轴还大, D 面失效, 轴会空转。
FLAT_OFF = SHAFT_FLAT - SHAFT_D/2 + SHAFT_CLR;   // 1.0 + 0.15
module d_bore(h) {
    intersection() {
        cylinder(d = SHAFT_D + 2*SHAFT_CLR, h = h);
        translate([-SHAFT_D, -SHAFT_D, -1])
            cube([2*SHAFT_D, SHAFT_D + FLAT_OFF, h + 2]);
    }
}

module csk(h, deep = 0) {
    translate([0, 0, -deep - 1]) cylinder(d = SCREW_CLR, h = h + deep + 2);
    translate([0, 0, h - CSK_H]) cylinder(d1 = SCREW_CLR, d2 = HEAD_D, h = CSK_H + 0.01);
}

/* =====================================================================
   1. 底座下托盘
      注意: 内腔在 difference 里挖，内部特征在 difference 之后加
   ===================================================================== */
module base_tray() {
    // --- 壳体 ---
    difference() {
        rbox(BASE_L, BASE_W, TRAY_H, BASE_R);
        translate([0, 0, WALL])
            rbox(BASE_L - 2*WALL, BASE_W - 2*WALL, TRAY_H, BASE_R - 0.6);
        // Type-C (前端面, 对准 U3 TP4056 自带的 Type-C 座)
        translate([-BASE_L/2 - 1, USB_Y - USB_W/2, USB_Z - USB_H/2])
            cube([WALL + 2, USB_W, USB_H]);
        // 总电源开关 (前端面)
        translate([-BASE_L/2 - 1, PSW_Y - PSW_W/2, USB_Z - PSW_H/2])
            cube([WALL + 2, PSW_W, PSW_H]);
    }
    // --- 内部特征: 一律从 z=WALL-1 起长, 往底板里埋 1mm 实体互穿 ---
    Z0 = WALL - 1;
    // 角螺柱: 顶面让开止口环底面(15), 柱身嵌进两侧内壁
    for (p = BASE_BOSS) translate([p[0], p[1], Z0])
        boss_top(TRAY_H - LIP_T - BOSS_CLR - Z0, CORNER_OD);

    // --- 电池仓 (+X 半场) ---
    // -X 挡边 + 前后两条; +X 端直接靠内壁挡住, 少一条筋
    translate([BAT_X0 - 3, -BAT_YH - 3, Z0]) cube([3, 2*BAT_YH + 6, BAT_T + 1]);
    for (s = [-1, 1])
        translate([BAT_X0 - 3, s > 0 ? BAT_YH : -BAT_YH - 3, Z0])
            cube([BAT_X1 - BAT_X0 + 4, 3, BAT_T + 1]);   // 伸进 +X 内壁 1mm

    // --- 承载底板支撑柱 (-X 半场) ---
    // 板子拧死在柱子上, 不再靠上盖压。柱子从 z=0 起长(整块吃穿底板厚度),
    // 底孔留 0.6mm 不打穿, 这样 M2 才有 3.4mm 咬合深度 —— 只从 Z0 起长的话
    // 咬合只剩 2.5mm, M2 自攻拧两次就滑。
    for (p = PCB_MNT) translate([p[0], p[1], 0]) difference() {
        cylinder(d = BOSS_OD, h = WALL + PCB_SO);
        translate([0, 0, 0.6]) cylinder(d = BOSS_PILOT, h = WALL + PCB_SO);
    }
}

/* =====================================================================
   2. 底座上盖板
   ===================================================================== */
module base_top() {
    difference() {
        union() {
            rbox(BASE_L, BASE_W, TOP_T, BASE_R);
            // 止口: 环形。原来是实心 rbox, 等于给内腔加了一层 2mm 天花板,
            // 净高被吃掉 2mm。挖空中央后只留 LIP_W 宽的一圈定位环。
            translate([0, 0, -LIP_T]) difference() {
                rbox(BASE_L - 2*WALL - 2*GAP, BASE_W - 2*WALL - 2*GAP,
                     LIP_T + 0.01, BASE_R - 0.6);
                translate([-LIP_IN_X, -LIP_IN_Y, -1])
                    cube([2*LIP_IN_X, 2*LIP_IN_Y, LIP_T + 3]);
            }
        }
        // 按键孔
        for (b = BTN_POS) translate([b[0], b[1], -4]) cylinder(d = BTN_D, h = TOP_T + 8);
        // 走线孔 (与闸体底板对齐)
        translate([HS_X_ABS + WIRE_P[0], WIRE_P[1], -4]) cylinder(d = WIRE_D, h = TOP_T + 8);
        // 角螺丝沉头孔: 这 4 点在止口环正下方, 板厚 = TOP_T + LIP_T = 5
        for (p = BASE_BOSS) translate([p[0], p[1], 0]) csk(TOP_T, LIP_T);
        // 闸体固定孔 (从盖板底面往上拧进闸体螺柱, 闸体外表面无螺丝)
        // 这 4 点落在止口环**以内**, 背面就是 3mm 面板, 沉窝在 z=0 —— 止口
        // 改成环以后再按 TOP_T+LIP_T 算, 沉窝就悬在空气里了。
        for (p = HS_BOSS) translate([HS_X_ABS + p[0], p[1], TOP_T]) rotate([180, 0, 0])
            csk(TOP_T);
    }
}

/* =====================================================================
   3. 闸体
   ===================================================================== */
// 结构顺序很关键:
//   先 (壳体 - 内腔), 再并上实体特征, 最后统一开孔。
//   如果在挖完内腔后才 union 带孔的螺柱, union 会把孔在底板段重新填实,
//   底孔就变成上下封死的盲腔 (CGAL 里表现为多出来的 volume)。
module housing_shell() {
    difference() {
        union() {
            // --- 壳体 ---
            difference() {
                union() {
                    rbox(HS_L, HS_W, HS_H, HS_R);
                    // 尾部外凸包已删除: 电机前端面定在 y=-12.5, 26mm 长的尾端
                    // 只到 y=+13.5, 离 +Y 内壁(21)还有 7.5mm, 不需要让位
                    stop_rib();
                }
                // 内腔: 底板 2mm + 顶盖 2mm 都保留
                translate([0, 0, WALL])
                    rbox(HS_L - 2*WALL, HS_W - 2*WALL, HS_H - 2*WALL, HS_R - 0.6);
                // 走线孔 (穿底板)
                translate([WIRE_P[0], WIRE_P[1], -1]) cylinder(d = WIRE_D, h = WALL + 2);
                // 轴颈孔 (-Y 壁)
                translate([0, -HS_W/2 - 1, PIV_Z]) rotate([-90, 0, 0])
                    cylinder(d = HUB_J_D + 2*GAP, h = WALL + 2);
                // 麦克风格栅 (-X 面, 朝使用者, 全部落在 -Y 半壳)
                for (i = [0 : 3])
                    translate([-HS_L/2 - 1, -13 + i*3.5, MIC_Z]) rotate([0, 90, 0])
                        cylinder(d = 1.8, h = WALL + 2);
            }
            // --- 实体特征 (不带孔) ---
            if (FEAT) {
                if (F1) for (p = HS_BOSS)
                    translate([p[0], p[1], 0]) cylinder(d = BOSS_OD, h = 12);
                if (F2) for (p = HS_JOIN)
                    translate([p[0], 0, p[1]]) rotate([90, 0, 0]) cylinder(d = BOSS_OD, h = 9);
                if (F3) motor_seat();
                if (F4) switch_plate();
            }
        }
        // --- 最后统一开孔, 保证贯穿所有材料 ---
        if (FEAT) {
            if (F1) for (p = HS_BOSS)
                translate([p[0], p[1], -1]) cylinder(d = BOSS_PILOT, h = 12);
            if (F2) for (p = HS_JOIN)
                translate([p[0], 1, p[1]]) rotate([90, 0, 0])
                    cylinder(d = BOSS_PILOT, h = 9.5);
            if (F4) switch_holes();
        }
    }
}

/* 机械止挡: STOP_ANG 软后挡, 正常工作(0~90°)不接触, 限位失效时兜底。

   位置**不是摆出来的, 是算出来的**:
     毛坯(扇形) − 转臂从 0° 扫到 STOP_ANG 所占的区域 = 止挡料
   差集的边界恰好就是转臂在 STOP_ANG 时的轮廓, 所以闸杆转到 STOP_ANG 正好
   相切, 之前一路无接触。转臂尺寸(HUB_ARM_*)一改, 挡块自动跟着走。

   注意扫掠必须用**转臂**的截面而不是闸杆的: 转臂半高 7mm 比闸杆(4mm)厚,
   包络更大, 是它先碰到挡块。                                            */

// 转臂在旋转平面内的截面, 原点 = 转轴
module arm_section()
    translate([HUB_ARM_X0, -HUB_ARM_W/2])
        square([HUB_ARM_X1 - HUB_ARM_X0, HUB_ARM_W]);

// 转臂从 a0 扫到 a1 占据的 2D 区域。
// 必须对相邻两个位置取 hull() 填缝, 不能只做并集 —— 靠近转臂尖端半径
// (r→21.19) 时, 转臂的角度覆盖收窄到只有 1.7°, 单纯并集会在相邻位置之间
// 漏出一条条没扫到的细缝, 挡块就会长出提前挡路的毛刺。实测漏缝会让闸杆
// 在 85° 就撞上。hull 把缝填掉, 弦高误差只有 r·(1−cos(step/2)) ≈ 0.005mm。
module arm_sweep(a0, a1, step = 2.5)
    for (a = [a0 : step : a1 - step])
        hull() { rotate(a) arm_section(); rotate(a + step) arm_section(); }

// 毛坯: 半径 STOP_R0~STOP_R1、从 STOP_ANG 起张 STOP_SPAN 的扇环
module stop_blank() {
    intersection() {
        difference() { circle(r = STOP_R1); circle(r = STOP_R0); }
        polygon([[0, 0],
                 [2*STOP_R1*cos(STOP_ANG),                2*STOP_R1*sin(STOP_ANG)],
                 [2*STOP_R1*cos(STOP_ANG + STOP_SPAN/2),  2*STOP_R1*sin(STOP_ANG + STOP_SPAN/2)],
                 [2*STOP_R1*cos(STOP_ANG + STOP_SPAN),    2*STOP_R1*sin(STOP_ANG + STOP_SPAN)]]);
    }
}

module stop_rib() {
    // rotate([90,0,0]) 把 2D 的 y 立成装配 Z、拉伸方向变成 -Y;
    // 先平移 HS_W/2-WALL 让筋从内壁 y=-21 起长, 埋进壁里 2mm 实体互穿
    translate([0, 0, PIV_Z]) rotate([90, 0, 0])
        translate([0, 0, HS_W/2 - WALL])
            linear_extrude(height = STOP_OUT)
                difference() {
                    stop_blank();
                    arm_sweep(0, STOP_ANG);
                }
}

/* 电机座: 沿 Y 的 10×12 **矩形**隧道 + 尾挡筋。

   固定方式 = 轴向推入 + 合壳夹紧:
     1. 电机从分模面(y=0)沿 -Y 推进左壳的半条隧道, 直到尾端顶住尾挡筋;
     2. 右壳扣上, 另外半条隧道合拢, 26mm 长的矩形配合把电机箍住;
     3. 矩形截面本身就防转 —— N20 靠这个受扭, 不需要额外螺丝(N20 机身也
        没有安装孔)。
   为什么**没有前端挡肩**: 减速箱端面在 y=-12.5, 而凸轮占 y=-19..-13,
   任何挡肩都要伸到半径 7.8mm 以内才能挡住端面, 那里已经被凸轮占了。
   电机往 -Y 的位移由轴插进转毂孔的深度限住(轴 9mm / 孔 10.5mm, 余 1.5mm)。 */
module motor_seat() {
    PW    = MOT_W + 2*MOT_CLR;              // 10.8
    PH    = MOT_H + 2*MOT_CLR;              // 12.8
    RIB_T = 3;
    Z0    = WALL - 1.5;                     // 往底板里埋 1.5mm
    TOP_Z = PIV_Z + PH/2 + 2;               // 立板顶面, 高出电机 2mm
    difference() {
        // 立板从底板长起(打印时 Y 是层向, 立板贴着地板长, 不需要支撑)
        for (yy = [MOT_Y0 + 2, MOT_Y0 + MOT_L*0.4, MOT_Y0 + MOT_L*0.75,
                   MOT_Y0 + MOT_L + 0.5])
            translate([-PW/2 - 3, yy, Z0]) cube([PW + 6, RIB_T, TOP_Z - Z0]);
        // 电机隧道 (尾挡筋不挖, 所以只挖到 MOT_L+0.5)
        translate([-PW/2, MOT_Y0, PIV_Z - PH/2]) cube([PW, MOT_L + 0.5, PH]);
    }
}

SW_HOLES = [[ SW_HOLE_R, -SW_SPACING/2], [ SW_HOLE_R,  SW_SPACING/2],
            [-SW_SPACING/2, SW_HOLE_R],  [ SW_SPACING/2, SW_HOLE_R]];

// 微动开关托板: 3.5mm 实心板整块贴 -Y 内壁, 开关直接拧在板上。
// 不用凸起螺柱 —— 凸柱会把开关顶出凸轮的 Y 覆盖范围(凸轮只有 y=-19..-13 这 6mm)。
YIN = -HS_W/2 + WALL;

module switch_plate() {
    // 往壁里埋 1.2mm, 实体互穿而不是贴面
    translate([-SW_HOLE_R - 5, YIN - 1.2, PIV_Z - SW_HOLE_R - 5])
        cube([2*SW_HOLE_R + 10, 4.7, 2*SW_HOLE_R + 10]);
}

module switch_holes() {
    // 让开凸轮和轴颈
    translate([0, YIN - 2, PIV_Z]) rotate([-90, 0, 0])
        cylinder(d = CAM_LOBE_D + 2, h = 14);
    // 4 个 M2 自攻底孔 (贯穿托板)
    for (q = SW_HOLES)
        translate([q[0], YIN + 4, PIV_Z + q[1]]) rotate([90, 0, 0])
            cylinder(d = BOSS_PILOT, h = 6);
}

module house_l() {
    difference() {
        housing_shell();
        translate([-60, 0, -2]) cube([120, 70, HS_H + 8]);
    }
}

module house_r() {
    difference() {
        union() {
            difference() {
                housing_shell();
                translate([-60, -70, -2]) cube([120, 70, HS_H + 8]);
            }
            // 对拧导向柱: HS_JOIN 的螺柱整根长在 y<0 的左壳里, 右壳这边原本
            // 只有 2mm 外壁, 螺丝要在 21mm 空腔里悬空 21mm 才够得到左壳。
            // 补一根同径导向柱, 从 +Y 内壁一路撑到分模面 y=0。
            if (FEAT && F2) for (p = HS_JOIN)
                translate([p[0], 0, p[1]]) rotate([-90, 0, 0])
                    cylinder(d = BOSS_OD, h = HS_W/2 - WALL + 1);
        }
        // 对拧过孔: 从外表面一路打穿外壁 + 导向柱, 直到分模面
        if (FEAT && F2) for (p = HS_JOIN)
            translate([p[0], HS_W/2, p[1]]) rotate([90, 0, 0]) {
                translate([0, 0, -1]) cylinder(d = SCREW_CLR, h = HS_W/2 + 1);
                cylinder(d1 = HEAD_D, d2 = SCREW_CLR, h = CSK_H + 0.01);
            }
    }
}

/* =====================================================================
   4. 转毂 (轴套 + 凸轮 + 闸杆夹, 一件三用)
      本地 Z 轴 = 装配后的 Y 轴
      0..12 夹块 | 12..16 轴颈 | 16..22 凸轮
   ===================================================================== */
module hub() {
    difference() {
        union() {
            // 夹持段: 中心毂 + 前后伸出的臂 (+X 插闸杆, -X 放配重)
            cylinder(d = HUB_D, h = HUB_CLAMP_H);
            translate([HUB_ARM_X0, -HUB_ARM_W/2, 0])
                cube([HUB_ARM_X1 - HUB_ARM_X0, HUB_ARM_W, HUB_CLAMP_H]);
            // 轴颈 (穿闸体 -Y 壁)
            translate([0, 0, HUB_J_Z0])
                cylinder(d = HUB_J_D - 2*GAP, h = HUB_J_Z1 - HUB_J_Z0);
            // 凸轮
            translate([0, 0, HUB_J_Z1]) cylinder(d = CAM_BASE_D, h = 6);
            translate([0, 0, HUB_J_Z1]) rotate([0, 0, -CAM_ARC/2])
                rotate_extrude(angle = CAM_ARC)
                    translate([CAM_BASE_D/2 - 0.01, 0])
                        square([(CAM_LOBE_D - CAM_BASE_D)/2 + 0.01, 6]);
        }
        // --- 闸杆插槽 ---
        // 局部 Y 吃闸杆的"高"(8), 局部 Z 吃闸杆的"宽"(5) => 装配后窄面朝下。
        // 从 +X 端开口, 杆根面停在转轴 x=0, 插入深度 = HUB_ARM_X1 = 20mm。
        translate([0, -SLOT_V/2, SLOT_Z0])
            cube([HUB_ARM_X1 + 1, SLOT_V, SLOT_H]);
        // --- 闸杆横穿螺丝 ---
        // 沿局部 Z (= 装配后的 Y) 穿过闸杆 5mm 窄边; 毂两侧都是 φ2.4 过孔,
        // 螺纹只咬在闸杆的 φ1.7 底孔里。
        translate([BAR_PIN_X, 0, -1])
            cylinder(d = SCREW_CLR, h = HUB_CLAMP_H + 2);
        // 电机 D 形轴孔。
        // v2.5 之前这里是 cylinder **并** cube —— 圆孔外面再挂一个方槽,
        // 孔比轴还大一圈, D 形面根本没被包住, 轴插进去空转。
        // D 形孔的正确做法是 圆 **交** 半空间: 把圆切掉一块平面。
        translate([0, 0, BORE_Z0]) d_bore(BORE_Z1 - BORE_Z0);
        // 顶丝 (M2, 顶在 D 形平面上; 扭矩靠 D 面传, 顶丝只防轴向窜出)
        translate([0, 0, SETSCREW_Z]) rotate([90, 0, 0])
            cylinder(d = BOSS_PILOT, h = 20, center = true);
        // 配重仓 (M5 钢螺母, 平躺): 从 -X 端开口塞进去再点胶, 不再是封死的空腔
        translate([HUB_ARM_X0 - 1, -5, 2]) cube([10, 10, HUB_CLAMP_H - 4]);
    }
}

/* =====================================================================
   5. 闸杆
   ===================================================================== */
module bar_profile(len) {
    difference() {
        translate([0, -BAR_W/2, 0]) cube([len, BAR_W, BAR_H]);
        translate([-1, -(BAR_W - 2*BAR_WALL)/2, BAR_WALL])
            cube([len + 2, BAR_W - 2*BAR_WALL, BAR_H - 2*BAR_WALL]);
    }
}

// 分色凹槽 (交替 37.5mm), 用于贴反光纸或喷涂遮蔽
module stripes(x0, len) {
    n = floor(len / STRIPE) + 1;
    for (i = [0 : n])
        if (floor((x0 + i*STRIPE + 0.1) / STRIPE) % 2 == 1)
            for (s = [-1, 1])
                translate([x0 + i*STRIPE, s*(BAR_W/2 - STRIPE_D/2), BAR_H/2])
                    cube([STRIPE, STRIPE_D, BAR_H + 2], center = true);
}

module bar_a() {
    difference() {
        union() {
            // 外形实心, 中空另挖; 末端留 12mm 实心堵头, 插榫才有地方生根
            translate([0, -BAR_W/2, 0]) cube([BAR_A_BODY, BAR_W, BAR_H]);
            translate([BAR_A_BODY, -(BAR_W - 2*BAR_WALL - 2*GAP)/2, BAR_WALL + GAP])
                cube([BAR_LAP, BAR_W - 2*BAR_WALL - 2*GAP, BAR_H - 2*BAR_WALL - 2*GAP]);
        }
        // 中空段: 根部实心 20mm 之后开始, 末端实心 12mm 之前结束
        translate([BAR_ROOT, -(BAR_W - 2*BAR_WALL)/2, BAR_WALL])
            cube([BAR_A_BODY - BAR_ROOT - 12, BAR_W - 2*BAR_WALL, BAR_H - 2*BAR_WALL]);
        // 自攻底孔: 沿杆的 5mm 窄边方向, 与转毂 / bar_b 的过孔同轴
        translate([BAR_PIN_X, 0, BAR_H/2]) rotate([90, 0, 0])
            cylinder(d = BOSS_PILOT, h = 20, center = true);
        translate([BAR_A_BODY + 10, 0, BAR_H/2]) rotate([90, 0, 0])
            cylinder(d = BOSS_PILOT, h = 20, center = true);
        // 排气/排料孔: 中空腔两端各一个, 否则是完全密闭腔(树脂打印会存料)
        for (xx = [BAR_ROOT + 6, BAR_A_BODY - 18])
            translate([xx, 0, -1]) cylinder(d = 2, h = BAR_WALL + 2);
        stripes(0, BAR_A_BODY);
    }
}

module bar_b() {
    difference() {
        union() {
            bar_profile(BAR_B - 4);
            translate([BAR_B - 4, -BAR_W/2, 0]) cube([4, BAR_W, BAR_H]);
        }
        translate([10, 0, BAR_H/2]) rotate([90, 0, 0])
            cylinder(d = SCREW_CLR, h = 20, center = true);
        stripes(0, BAR_B);
    }
}

/* =====================================================================
   6. 遥控器
   ===================================================================== */
RC_BOSS = [[-RC_L/2 + 7,  RC_W/2 - 6], [-RC_L/2 + 7, -RC_W/2 + 6],
           [ RC_L/2 - 7,  RC_W/2 - 6], [ RC_L/2 - 7, -RC_W/2 + 6]];

module rc_bottom() {
    difference() {
        rbox(RC_L, RC_W, RC_H - RC_TOP_T, RC_R);
        translate([0, 0, WALL])
            rbox(RC_L - 2*WALL, RC_W - 2*WALL, RC_H, RC_R - 0.6);
        translate([RC_L/2 - WALL - 1, -USB_W/2, 5]) cube([WALL + 2, USB_W, USB_H]);
    }
    // 内部特征 (在 difference 之外, 往底板埋 1mm)
    // 螺柱顶面同样要让开 rc_top 背面 2mm 止口
    for (p = RC_BOSS) translate([p[0], p[1], WALL - 1])
        boss_top(RC_H - RC_TOP_T - LIP_T - BOSS_CLR - (WALL - 1));
    // C3 SuperMini 与 TP4056 之间的隔筋
    translate([-1.5, -RC_W/2 + WALL, WALL - 1]) cube([3, RC_W - 2*WALL, 7]);
    // 电池仓围挡 (502030 立放在一端)
    translate([-RC_L/2 + WALL + 20, -RC_W/2 + WALL, WALL - 1]) cube([2.5, 10, 9]);
}

module rc_top() {
    difference() {
        union() {
            rbox(RC_L, RC_W, RC_TOP_T, RC_R);
            translate([0, 0, -LIP_T])
                rbox(RC_L - 2*WALL - 2*GAP, RC_W - 2*WALL - 2*GAP, LIP_T + 0.01, RC_R - 0.6);
        }
        for (x = RC_BTN_X) translate([x, 0, -4]) cylinder(d = RC_BTN_D, h = RC_TOP_T + 8);
        // 同 base_top: 孔要连背面止口一起打穿
        for (p = RC_BOSS) translate([p[0], p[1], 0]) csk(RC_TOP_T, LIP_T);
    }
}

/* =====================================================================
   7. 内部元件排布预览 (仅示意, 不导出)
   ===================================================================== */
module part_block(sz, pos, col) {
    color(col, 0.85) translate([pos[0] - sz[0]/2, pos[1] - sz[1]/2, pos[2]])
        cube(sz);
}

// 承载底板外形 (2D): -X 两角切 4×4 缺口让开角螺柱
module pcb_outline() {
    difference() {
        translate([PCB_X0, -PCB_YH]) square([PCB_X1 - PCB_X0, 2*PCB_YH]);
        for (s = [-1, 1])
            translate([PCB_X0, s > 0 ? PCB_YH - PCB_NOTCH : -PCB_YH])
                square([PCB_NOTCH, PCB_NOTCH]);
    }
}

module layout() {
    color("DimGray", 0.35) base_tray();
    // 电池 103450 (+X 半场)
    part_block([BAT_L, BAT_W, BAT_T], [(BAT_X0 + BAT_X1)/2, 0, WALL], "ForestGreen");
    // 承载底板 (-X 半场)
    color("DarkGreen", 0.9) translate([0, 0, WALL + PCB_SO])
        linear_extrude(PCB_T) pcb_outline();
    PZ = WALL + PCB_SO + PCB_T;      // 板面 z = 5.6
    // U1 DevKitC-1 (63×25.5) 偏置到 -Y 侧, 给按键让出 y>2 的整条带
    part_block([63, 25.5, U1_STACK], [-15.5, -10.75, PZ], "SteelBlue");
    // U3 TP4056 (26×17): Type-C 悬出板前沿 2mm 顶到前端面开口
    part_block([26, 17, 4.8], [-60, 0, PZ], "Goldenrod");
    // SW3 总开关
    part_block([8, 6, 6], [-67, PSW_Y, PZ], "Silver");
    // SW1/SW2 轻触 6×6×12, 顶杆伸进上盖 φ6.5 孔
    for (b = BTN_POS) part_block([6, 6, 12], [b[0], b[1], PZ], "Crimson");
    // U2 DRV8833 / U4 升压 / LS1 蜂鸣器 (都挤在 y>2 那条带里)
    part_block([23, 14, 6.1], [8, 14, PZ], "IndianRed");
    part_block([17, 11, 6.1], [-57, 16, PZ], "MediumPurple");
    color("DarkOrange", 0.85) translate([-5, 8, PZ]) cylinder(d = 9, h = 5.5);
    // 天花板: 中央净空区上限 z=17, 止口环下方只有 15
    color("Red", 0.25) translate([-LIP_IN_X, -LIP_IN_Y, TRAY_H - 0.2])
        cube([2*LIP_IN_X, 2*LIP_IN_Y, 0.2]);
    // 走线孔位置提示 (落在电池上方 5mm 空隙里)
    color("Black", 0.5)
        translate([HS_X_ABS + WIRE_P[0], WIRE_P[1], WALL]) cylinder(d = WIRE_D, h = 15);
}

/* =====================================================================
   8. 装配预览
   ===================================================================== */
module assembly() {
    color("DimGray")   base_tray();
    color("Silver")    translate([0, 0, TRAY_H]) base_top();
    color("Goldenrod") translate([HS_X_ABS, 0, BASE_H]) { house_l(); house_r(); }
    color("SlateGray") translate([HS_X_ABS, -35, BASE_H + PIV_Z]) rotate([-90, 0, 0]) hub();
    // 闸杆: 杆根落在转轴 x=HS_X_ABS 上, 8mm 高居中于转轴, 窄面朝下
    color("Crimson")   translate([HS_X_ABS, BAR_Y_ABS, BASE_H + PIV_Z - BAR_H/2]) {
                           bar_a();
                           translate([BAR_A_BODY, 0, 0]) bar_b();
                       }
    color("DimGray")   translate([-150, 75, 0]) {
                           rc_bottom();
                           translate([0, 0, RC_H - RC_TOP_T]) rc_top();
                       }
}

/* =====================================================================
   导出分发
   ===================================================================== */
if      (sel == "assembly")   assembly();
else if (sel == "layout")     layout();
else if (sel == "base_tray")  base_tray();
else if (sel == "base_top")   base_top();
else if (sel == "house_l")    house_l();
else if (sel == "house_r")    house_r();
else if (sel == "hub")        hub();
else if (sel == "bar_a")      bar_a();
else if (sel == "bar_b")      bar_b();
else if (sel == "rc_bottom")  rc_bottom();
else if (sel == "rc_top")     rc_top();
