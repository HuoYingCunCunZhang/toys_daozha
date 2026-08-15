// 装配性自检: 每个 t 出一个几何体。
//   期望 EMPTY 的 = 不干涉 / 孔真的通 / 装得进
//   期望 NON-EMPTY 的 = **阳性对照**, 证明检测本身有效
// ⚠ 没有阳性对照的自检等于没做 —— 检测失效了你也不知道。v2.2 就是这么栽的。
//
// 跑法: openscad -D t=NN -o out.stl check.scad, 看输出的 Vertices/facets;
//       更省事的是 cad/run_check.ps1, 它把全部用例跑一遍并比对期望值。
include <daozha.scad>
part = "none";          // 覆盖掉源文件的顶层出图
t = 1;

PROBE   = 2.0;          // 探针直径, 略小于 SCREW_CLR=2.4 (验 M2 过孔)
PROBE_S = 1.4;          // 细探针, 略小于 BOSS_PILOT=1.7 (验自攻底孔)
                        // ⚠ 用 φ2.0 去探 φ1.7 的底孔当然探不通, 那不是缺陷
BUDGET  = TRAY_H - PCB_Z;  // 板面以上可用高度, 随 BASE_H 自动跟随 (16.4)
MIC_T_CHK = 0.9;        // 麦克风板厚 1.0, 求交时缩 0.1 免得共面接触

/* ⚠⚠ 写用例的铁律: **不许留共面接触**。
   两个实体面贴面求交, CGAL 给的是一张零体积薄片, 导出 STL 有几百个三角形,
   看文件大小会被判成"非空"。v3.0 第一轮就是这么冒出 5 条假失败:
   托盘顶面 vs 上盖背面(z 22..22)、电芯 -X 面 vs 挡边(x 36..36)、
   转毂夹持段顶面 vs 判定用的半空间(z 11..11)。
   所以凡是"应该刚好贴上"的地方, 一律把其中一个错开 0.01~0.05 再求交。      */

module probe_z(x, y, z0, z1) translate([x, y, z0]) cylinder(d = PROBE, h = z1 - z0);
module probe_y(x, z, y0, y1) translate([x, y0, z]) rotate([-90, 0, 0]) cylinder(d = PROBE, h = y1 - y0);

// 闸体局部坐标下的转毂/凸轮, 闸杆抬到 a 度
module hub_at(a)
    translate([0, 0, PIV_Z]) rotate([0, -a, 0]) translate([0, 0, -PIV_Z])
        translate([0, HUB_Y_ABS, PIV_Z]) rotate([-90, 0, 0]) hub();
module cam_at(a)
    translate([0, 0, PIV_Z]) rotate([0, -a, 0]) translate([0, 0, -PIV_Z])
        translate([0, HUB_Y_ABS, PIV_Z]) rotate([-90, 0, 0])
            translate([0, 0, CAM_Z0]) cam();
// 微动开关本体实体 (12.70×6.60×5.80, 内面 r=9.85), 拧在安装台上
module sw_body(a) at_sw(a)
    translate([9.85, -6.35, YIN - 1.2 + SW_PAD_T]) cube([6.55, 12.7, 5.8]);
// 杠杆尖端的探片。放在 r=6.5 —— 即"杠杆已被压下 0.5mm"的位置, 而不是自由
// 位置 r=6.0: 贴基圆是相切, 又变成共面接触判不了。
// 凸轮扫过来时, 只要升程超过 0.5mm 这片就会被吃到。
module sw_lever(a) at_sw(a)
    translate([6.5, -2, CAM_Z0 + HUB_Y_ABS + 0.5]) cube([0.5, 4, CAM_T - 1]);

// --- 期望 EMPTY ---
// t=1 / t=2 (上下壳直接求交) 已删除: 贴合面共面, 出的是零体积薄片, 判不了。
// 它们的作用被 t=13 / t=14 (抬 0.01 脱开贴合面) 完全覆盖 —— 真有 >0.01 的
// 干涉那两条照样抓得到。
if (t == 3) intersection() { base_top();
    for (p = BASE_BOSS) probe_z(p[0], p[1], -LIP_T-1, TOP_T+1); }
if (t == 4) intersection() { base_top();
    for (p = HS_BOSS) probe_z(HS_X_ABS+p[0], p[1], -LIP_T-1, TOP_T+1); }
if (t == 5) intersection() { rc_top();
    for (p = RC_BOSS) probe_z(p[0], p[1], -LIP_T-1, RC_TOP_T+1); }
if (t == 6) intersection() {
    translate([HS_X_ABS,HUB_Y_ABS,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z-BAR_H/2]) bar_a(); }
if (t == 7) intersection() {
    translate([HS_X_ABS,HUB_Y_ABS,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    probe_y(HS_X_ABS+BAR_PIN_X, BASE_H+PIV_Z, -40, -20); }
if (t == 8) intersection() { house_l(); house_r(); }
if (t == 9) intersection() { house_r();
    for (p = HS_JOIN) probe_y(p[0], p[1], 0, HS_W/2+1); }
// 闸杆上是 φ1.7 自攻**底孔**(不是过孔), 只能用细探针
if (t == 10) intersection() {
    translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z-BAR_H/2]) bar_a();
    translate([HS_X_ABS+BAR_PIN_X, -40, BASE_H+PIV_Z]) rotate([-90,0,0])
        cylinder(d = PROBE_S, h = 20); }

// 13/14: 把上盖抬 0.01mm 脱开贴合面, 排除"共面接触"造成的零体积假阳性
if (t == 13) intersection() { base_tray(); translate([0,0,TRAY_H+0.01]) base_top(); }
if (t == 14) intersection() { rc_bottom(); translate([0,0,RC_H-RC_TOP_T+0.01]) rc_top(); }

// 15: 横穿螺丝同轴性 —— φ1.4 探针要同时穿过转毂 φ2.4 过孔和闸杆 φ1.7 底孔
if (t == 15) intersection() {
    union() {
        translate([HS_X_ABS,HUB_Y_ABS,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
        translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z-BAR_H/2]) bar_a();
    }
    translate([HS_X_ABS+BAR_PIN_X, -40, BASE_H+PIV_Z]) rotate([-90,0,0])
        cylinder(d = 1.4, h = 20); }
// 16: 转毂**连同凸轮**转起来不能刮到闸体 (含新增的轴承凸台和两块安装台)
if (t == 16) intersection() {
    union() for (a = [0, 30, 60, 90]) { hub_at(a); cam_at(a); }
    union() { house_l(); house_r(); } }

// --- 阳性对照, 期望 NON-EMPTY ---
// 11: 右壳导向柱确实存在 (在 y=2..20 段上, 螺丝孔外圈应有料)
if (t == 11) intersection() { house_r();
    translate([HS_JOIN[0][0], 2, HS_JOIN[0][1]]) rotate([-90,0,0]) cylinder(d = BOSS_OD, h = 18); }
// 12: 闸杆若按错误姿态(宽面朝下, 绕 X 转 90°)插入, 必须插不进去
if (t == 12) intersection() {
    translate([HS_X_ABS,HUB_Y_ABS,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z]) rotate([90,0,0])
        translate([0,0,-BAR_H/2]) bar_a(); }

// 17/18: 开关安装底孔。v3.0 改成了**盲孔**(深 4.5, 外壁留 1mm), 所以
//   17 = 外壁皮层里必须**有料** (NON-EMPTY, 阳性对照: 没打穿)
//   18 = 底孔本身必须是通的 (EMPTY)
// v2.6 那组 17/18/19 判的是"打没打穿", 且被止挡筋污染, 已作废。
if (t == 17) intersection() { house_l();
    for (a = SW_ANG) at_sw(a) for (s = [-1,1])
        translate([SW_HOLE_R, s*SW_SPACING/2, -22.8]) cylinder(d = 1.4, h = 0.7); }
if (t == 18) intersection() { house_l();
    for (a = SW_ANG) at_sw(a) for (s = [-1,1])
        translate([SW_HOLE_R, s*SW_SPACING/2, -21.5]) cylinder(d = 1.4, h = 4.0); }

// 55/56: 阳性对照 —— **两块安装台真的都在**。
//   t=17/18 只验了"底孔没打穿外壁"和"底孔是通的", 但安装台整块不存在时这两条
//   照样过(没有料可求交)。所以要单独验"孔的四周有料", 而且两块必须分开验 ——
//   合在一个用例里, 只要有一块在就非空了。
module pad_probe(a) at_sw(a)
    for (s = [-1,1]) translate([SW_HOLE_R, s*SW_SPACING/2, YIN - 1.2 + SW_PAD_T - 2])
        cylinder(d = 6, h = 1.5);
if (t == 55) intersection() { house_l(); pad_probe(0); }
if (t == 56) intersection() { house_l(); pad_probe(90); }

/* ===== v2.4 排布自检 ===== */
// 20: 电芯实体 vs 托盘内部特征 (角螺柱/围挡/支撑柱) —— 期望 EMPTY
// 电芯六个面都缩 0.05: 底面坐在地板上、-X 面贴着挡边, 不缩就是共面接触
if (t == 20) intersection() { base_tray();
    translate([BAT_X0 + 0.05, -BAT_W/2 + 0.05, WALL + 0.05])
        cube([BAT_L - 0.1, BAT_W - 0.1, BAT_T - 0.1]); }
// 21: 承载底板 vs 托盘 (抬 0.01 脱开支撑柱贴合面) —— 期望 EMPTY, 验证 5×5 切角避开角螺柱
if (t == 21) intersection() { base_tray();
    translate([0,0,WALL+PCB_SO+0.01]) linear_extrude(PCB_T) pcb_outline(); }
// 22: 板面以上 (BUDGET-0.1) 元件包络 vs 上盖 —— 期望 EMPTY, 验证中央区净高够
//     扣掉两个按键帽导向凸台的地盘: 那两块本来就是留给帽子的, 不算净空冲突
module envelope(h) difference() {
    intersection() {
        translate([0,0,PCB_Z]) linear_extrude(h) pcb_outline();
        translate([-LIP_IN_X, -LIP_IN_Y, 0]) cube([2*LIP_IN_X, 2*LIP_IN_Y, 40]);
    }
    for (b = BTN_POS) translate([b[0], b[1], 0]) cylinder(d = BTN_GUIDE_D + 1, h = 40);
}
if (t == 22) intersection() { translate([0,0,TRAY_H]) base_top(); envelope(BUDGET - 0.1); }
// 23: 阳性对照 —— 同样的包络加到 BUDGET+0.2 必须撞上盖(证明 22 不是白跑)
if (t == 23) intersection() { translate([0,0,TRAY_H]) base_top(); envelope(BUDGET + 0.2); }

/* ===== v2.6: 电机 / D 形轴 / 机械止挡 ===== */
// 真实 D 形轴实体(无间隙), 用来验证转毂孔
module d_shaft_solid(h) {
    intersection() {
        cylinder(d = SHAFT_D, h = h);
        translate([-SHAFT_D, -SHAFT_D, -1])
            cube([2*SHAFT_D, SHAFT_D + (SHAFT_FLAT - SHAFT_D/2), h + 2]);
    }
}
// 30: D 形轴插得进转毂 -> EMPTY
if (t == 30) intersection() { hub();
    translate([0,0,BORE_Z0]) d_shaft_solid(BORE_Z1 - BORE_Z0); }
// 31: 阳性对照 —— 整根 φ3 圆柱必须被 D 面挡住 -> NON-EMPTY
//     若这条变 EMPTY, 说明孔又退化成整圆, D 面失效, 轴会空转
if (t == 31) intersection() { hub();
    translate([0,0,BORE_Z0]) cylinder(d = SHAFT_D, h = BORE_Z1 - BORE_Z0); }
// 32: N20 机身 10×12×MOT_L 装得进电机座 -> EMPTY
if (t == 32) intersection() { motor_seat();
    translate([-MOT_W/2, MOT_Y0, PIV_Z - MOT_H/2]) cube([MOT_W, MOT_L, MOT_H]); }
// 33: 阳性对照 —— 旧版假设的 12.5 方形必须装不进 -> NON-EMPTY
if (t == 33) intersection() { motor_seat();
    translate([-12.5/2, MOT_Y0, PIV_Z - 12.5/2]) cube([12.5, MOT_L, 12.5]); }
// 34/35: 机械止挡。闸杆摆到 ang, 与止挡块求交。
//        t=34 用 STOP_ANG-1 -> 必须 EMPTY;  t=35 用 STOP_ANG+1 -> 必须 NON-EMPTY
if (t == 34) intersection() { hub_at(STOP_ANG - 1); stop_rib(); }
if (t == 35) intersection() { hub_at(STOP_ANG + 1); stop_rib(); }

/* ===== v3.0: 拆件 / 凸轮 / 按键帽 / 麦克风 ===== */
// 40: **装配路径**判定 —— 转毂上要穿过 φ8.5 壁孔的那一段(局部 z>=轴颈起点),
//     减掉壁孔通道之后必须什么都不剩 -> EMPTY。
//     这条专治"静态求交测不出装配路径"那个盲区: t=16 早就验过终态不干涉,
//     但一整件转毂根本走不到那个位置。
if (t == 40) difference() {
    intersection() { hub(); translate([-40,-40,HUB_J_Z0+0.01]) cube([80,80,80]); }
    translate([0,0,HUB_J_Z0-1]) cylinder(d = HUB_J_D + 2*GAP, h = 80); }
// 41: 阳性对照 —— 把凸轮装回去(= v2.6 的一整件)后同样的判定必须 NON-EMPTY
if (t == 41) difference() {
    intersection() {
        union() { hub(); translate([0,0,CAM_Z0]) cam(); }
        translate([-40,-40,HUB_J_Z0+0.01]) cube([80,80,80]);
    }
    translate([0,0,HUB_J_Z0-1]) cylinder(d = HUB_J_D + 2*GAP, h = 80); }
// 42: 凸轮套在轴颈上 (D 形孔 vs 键面) -> EMPTY
if (t == 42) intersection() { hub(); translate([0,0,CAM_Z0]) cam(); }
// 43: 阳性对照 —— 若轴颈那段是整圆(键面没切出来), 凸轮的 D 形孔必须套不上 -> NON-EMPTY
if (t == 43) intersection() {
    translate([0,0,CAM_Z0]) cam();
    translate([0,0,CAM_Z0-0.5]) cylinder(d = HUB_J_D - 2*GAP, h = CAM_T + 1); }
// 44: 凸轮(含顶丝凸台)扫 0..90° vs 两只开关**本体** -> EMPTY
//     顶丝凸台长在凸起背面, 全程应该只扫 -X/-Z 那个空象限
if (t == 44) intersection() {
    union() for (a = [0:7.5:90]) cam_at(a);
    union() for (a = SW_ANG) sw_body(a); }
// 45: 阳性对照 —— 落杆位(0°)必须把落杆那只的杠杆压下去 -> NON-EMPTY
if (t == 45) intersection() { cam_at(0); sw_lever(0); }
// 46: 转到 45° 时同一只必须已经释放 (凸起总张角 61° < 90°) -> EMPTY
if (t == 46) intersection() { cam_at(45); sw_lever(0); }
// 47: 阳性对照 —— 起杆位(90°)压下另一只 -> NON-EMPTY
if (t == 47) intersection() { cam_at(90); sw_lever(90); }
// ⚠ 下面三条里 base_top 是"装在整机上"的, 所以帽子/开关一律用**绝对 z**,
//   不要再减 TRAY_H —— 减了就是把探头挪到底座外面去, 什么都测不到(白过)。
// 48: 按键帽坐在上盖里 (下沉 0.01 脱开法兰贴合面) -> EMPTY
if (t == 48) intersection() { translate([0,0,TRAY_H]) base_top();
    for (b = BTN_POS) translate([b[0], b[1], CAP_BOT_Z - 0.01]) btn_cap(); }
// 49: 阳性对照 —— 帽子往上拔 1mm, 法兰必须被沉孔挡住(防脱) -> NON-EMPTY
if (t == 49) intersection() { translate([0,0,TRAY_H]) base_top();
    for (b = BTN_POS) translate([b[0], b[1], CAP_BOT_Z + 1]) btn_cap(); }
// 50: 轻触开关本体 6×6×12 vs 上盖(含导向凸台) -> EMPTY。
//     凸台底面 19.5 / 开关顶面 17.6, 只剩 1.9mm, 这条必须跑
if (t == 50) intersection() { translate([0,0,TRAY_H]) base_top();
    for (b = BTN_POS) translate([b[0]-3, b[1]-3, PCB_Z]) cube([6, 6, BTN_SW_H]); }
// 53: **按键帽 vs 闸体** -> EMPTY。
//     v3.0 抓到的那条硬伤就在这儿: PCB 把起杆按键定在 x=+20, 而闸体原来占
//     x=2..48, 整颗按键被闸体盖住。这类跨零件失配没有用例就永远抓不到。
if (t == 53) intersection() {
    for (b = BTN_POS) translate([b[0], b[1], CAP_BOT_Z]) btn_cap();
    translate([HS_X_ABS, 0, BASE_H]) union() { house_l(); house_r(); } }
// 54: 阳性对照 —— 把闸体放回 v2.6 的 x=25, 必须撞上按键帽 -> NON-EMPTY
if (t == 54) intersection() {
    for (b = BTN_POS) translate([b[0], b[1], CAP_BOT_Z]) btn_cap();
    translate([25, 0, BASE_H]) union() { house_l(); house_r(); } }
// 51: 麦克风圆板 φ14×1 躺进圆窝 -> EMPTY
if (t == 51) intersection() { house_l();
    translate([-HS_L/2 + WALL - MIC_POCKET_T + 0.05, MIC_Y, MIC_Z]) rotate([0,90,0])
        cylinder(d = MIC_D, h = MIC_T_CHK); }
// 52: 阳性对照 —— 圆板贴在内壁面上(没沉进窝)必须被压舌挡住 -> NON-EMPTY
if (t == 52) intersection() { house_l();
    translate([-HS_L/2 + WALL, MIC_Y, MIC_Z]) rotate([0,90,0])
        cylinder(d = MIC_D, h = MIC_T_CHK); }
