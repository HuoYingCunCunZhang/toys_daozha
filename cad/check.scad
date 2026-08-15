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
// 24/25: **支撑柱的自攻底孔是否对准承载底板的安装孔**。
//   CAD 里的 PCB 模型没画孔, 这条以前从来没验过 —— 柱心与板孔用的是同一个
//   常量 PCB_MNT, 但"用同一个常量"不等于"几何上真对得上"。
//   φ1.4 探针从板面之上一路探到柱底: 底孔 φ1.7 从 z=0.6 开始, 所以到 z=1 必须畅通。
if (t == 24) intersection() { base_tray();
    for (p = PCB_MNT) translate([p[0], p[1], 1]) cylinder(d = PROBE_S, h = 9); }
// 25: 阳性对照 —— 探针偏 1.5mm 必须撞在柱体上 -> NON-EMPTY
if (t == 25) intersection() { base_tray();
    for (p = PCB_MNT) translate([p[0] + 1.5, p[1], 1]) cylinder(d = PROBE_S, h = 9); }

if (t == 3) intersection() { base_top();
    for (p = BASE_BOSS) probe_z(p[0], p[1], -LIP_T-1, TOP_T+1); }
if (t == 4) intersection() { base_top();
    for (p = HS_BOSS) probe_z(HS_X_ABS+p[0], p[1], -LIP_T-1, TOP_T+1); }
// t=5 (遥控上盖螺丝孔) 已删除: RC_BOSS 改成 PCB 坐标后它没加 RC_PCB_DY 偏移,
//     而且 rc_top 已不带止口环。作用由 t=67 完全覆盖。
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
// 21: 承载底板 vs 托盘 (抬 0.01 脱开支撑柱贴合面) —— 期望 EMPTY,
//     验证 -X 两角的 45°×7 倒角(PCB_CHAMFER, 与 EDA 板框逐点一致)避开角螺柱。
//     ⚠ 曾经这里建成 5×5 方缺口, 挖掉的料比真板多, 于是一直"通过"——
//        偏乐观的错误比报错更危险, 见 daozha-toy-scope 教训 #5。
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
module motor_box(grow = 0)
    translate([-MOT_W/2 - grow, MOT_Y0, PIV_Z - MOT_H/2 - grow])
        cube([MOT_W + 2*grow, MOT_L, MOT_H + 2*grow]);
// 32: N20 机身 10×12×MOT_L 装得进电机座 -> EMPTY
//     ⚠ 必须传 crush=false: 压筋是**故意**过盈的, 带着它测这条永远非空。
//     这条测的是"隧道本身尺寸对不对", 压筋归 t=88/89 管。
if (t == 32) intersection() { motor_seat(false); motor_box(); }
// 33: 阳性对照 —— 旧版假设的 12.5 方形必须装不进 -> NON-EMPTY
if (t == 33) intersection() { motor_seat(false);
    translate([-12.5/2, MOT_Y0, PIV_Z - 12.5/2]) cube([12.5, MOT_L, 12.5]); }
// 34/35: 机械止挡。闸杆摆到 ang, 与止挡块求交。
//        t=34 用 STOP_ANG-1 -> 必须 EMPTY;  t=35 用 STOP_ANG+1 -> 必须 NON-EMPTY
if (t == 34) intersection() { hub_at(STOP_ANG - 1); stop_rib(); }
if (t == 35) intersection() { hub_at(STOP_ANG + 1); stop_rib(); }

/* ===== 遥控器 (v3.1, 按 PCB 定稿反推) =====
   PCB 坐标 -> 外壳坐标只差 Y 偏移 RC_PCB_DY, 下面一律用 rcx() 换算,
   免得两套坐标混用。                                                     */
/* 承载板实体。**必须带四个螺柱缺口** —— 螺柱本来就是从缺口里穿上去的,
   拿一块没缺口的方板去求交, 撞的是我自己画的测试模型, 不是设计缺陷。
   (第一版就是这么误报的。) shrink 用 offset 让整圈缩进, 脱开贴合面。 */
module rc_pcb_solid(shrink = 0, dz = 0)
    translate([0, RC_PCB_DY, RC_PCB_Z0 + dz])
        linear_extrude(RC_PCB_T) offset(delta = -shrink) rc_pcb_outline();

// 60: 承载板放进腔里不撞任何内部特征 -> EMPTY
//     ⚠ 板要**同时**缩 0.05(脱开螺柱侧壁)和抬 0.05(脱开承托肩顶面)。
//        只缩不抬时交集是 z[7.10..7.10] 的零厚度薄片 —— 那是板本来就该坐上去的
//        贴合面, 不是干涉。这个坑主机 t=1 踩过一次了。
if (t == 60) intersection() { rc_bottom(); rc_pcb_solid(0.05, 0.05); }
// 61: 阳性对照 —— 板往下沉 1mm(压到电池仓围挡上)必须撞 -> NON-EMPTY
if (t == 61) intersection() { rc_bottom();
    translate([0,0,-1]) rc_pcb_solid(0.05); }
// 62: 电池实体放进电池仓 -> EMPTY (六面各缩 0.05 避开共面)
if (t == 62) intersection() { rc_bottom();
    translate([RC_BAT_X0 + 0.05, -RC_BAT_W/2 + RC_PCB_DY + 0.05, WALL + 0.05])
        cube([RC_BAT_L - 0.1, RC_BAT_W - 0.1, RC_BAT_T - 0.1]); }
// 63: 阳性对照 —— 按旧文档的 7mm 厚电池必须装不下(会顶到板) -> NON-EMPTY
if (t == 63) intersection() {
    translate([RC_BAT_X0 + 0.05, -RC_BAT_W/2 + RC_PCB_DY + 0.05, WALL + 0.05])
        cube([RC_BAT_L - 0.1, RC_BAT_W - 0.1, 7 - 0.1]);
    rc_pcb_solid(0.05); }
// 64: U1 叠高包络(22.52×18×11.7, 立在板面上) vs 上盖 -> EMPTY
module rc_u1_env(h) translate([16 - 22.52/2, -5.5 + RC_PCB_DY - 18/2, RC_PCB_Z])
    cube([22.52, 18, h]);
if (t == 64) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    rc_u1_env(RC_U1_STACK); }
// 65: 阳性对照 —— 叠高再加 1mm 必须撞上盖(证明 64 不是白跑) -> NON-EMPTY
if (t == 65) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    rc_u1_env(RC_U1_STACK + 1); }
// 66: 上下壳求交(抬 0.01 脱开贴合面) -> EMPTY
if (t == 66) intersection() { rc_bottom();
    translate([0,0,RC_H-RC_TOP_T+0.01]) rc_top(); }
// 67: 上盖螺丝孔真的通(探针从沉窝穿到背面) -> EMPTY
if (t == 67) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    for (p = RC_BOSS) translate([p[0], p[1] + RC_PCB_DY, RC_H-RC_TOP_T-1])
        cylinder(d = PROBE, h = RC_TOP_T + 2); }
// 68: 按键帽坐进上盖 (下沉 0.01 脱开法兰贴合面) -> EMPTY
//     ⚠ 帽只有两顶(RC_BTN_CAP_POS), 复位那颗不开孔
if (t == 68) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    for (b = RC_BTN_CAP_POS) translate([b[0], b[1] + RC_PCB_DY, RC_CAP_BOT_Z - 0.01]) rc_btn_cap(); }
// 69: 阳性对照 —— 帽往上拔 1mm, 法兰必须被沉孔挡住 -> NON-EMPTY
if (t == 69) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    for (b = RC_BTN_CAP_POS) translate([b[0], b[1] + RC_PCB_DY, RC_CAP_BOT_Z + 1]) rc_btn_cap(); }
/* ===== 抬杆到 90° 时配重端 vs 上盖 (t=93/94) =================================
   转轴在 z=42, 配重端 HUB_ARM_X0 抬到竖直时正指向下, 落点 z = 42 + HUB_ARM_X0。
   上盖顶面 25。原来 X0=-16 -> 落到 26, **只剩 1mm**, 打印公差 + 面板下挠就擦上了。
   削到 -13 -> 4.0mm。
   ⚠ 这条布尔求交只答"碰没碰上", 答不出"还剩多少"。阳性对照要把上盖垫**超过净距**
     才碰得上 —— 第一版取 3mm, 结果 94 是 EMPTY(没碰上)。那不是失败, 恰恰证明净距
     >3mm、和手算的 4.0 对得上; 是**对照本身标定错了**。改成 5mm。 */
module raised_hub(a = 90) at_house() translate([0, HUB_Y_ABS, PIVOT_ABS])
    rotate([0, -a, 0]) rotate([-90, 0, 0]) hub();
// 93: 抬到 90° 转毂不碰上盖 -> EMPTY
if (t == 93) intersection() { raised_hub(); translate([0, 0, TRAY_H]) base_top(); }
// 94: 阳性对照 —— 上盖垫高 5mm 必须被配重端啃上 -> NON-EMPTY
if (t == 94) intersection() { raised_hub(); translate([0, 0, TRAY_H + 5]) base_top(); }

// 92: **复位那颗的位置必须是实心面板**(证明孔真的没开) -> NON-EMPTY
//     少开一个孔这种"减法改动", 68 那种"帽装得进"的用例是抓不到的 ——
//     孔没删干净它照样过。得反过来断言那儿有料。
if (t == 92) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    translate([RC_BTN_POS[2][0], RC_BTN_POS[2][1] + RC_PCB_DY, RC_H - RC_TOP_T - 1])
        cylinder(d = 2, h = RC_TOP_T + 2); }
// 70: 轻触开关本体 6×6×9 vs 上盖(含导向凸台) -> EMPTY
//     ⚠ 这条**必须仍按三颗全查**: SW3 复位虽然不开孔了, 开关还焊在板上,
//       而且它头顶从"通孔"变成了"实心面板", 更要确认让得开(顶面 17.7, 盖背 23)。
if (t == 70) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    for (b = RC_BTN_POS) translate([b[0]-3, b[1]+RC_PCB_DY-3, RC_PCB_Z]) cube([6,6,RC_BTN_SW_H]); }
// 71: 阳性对照 —— 换成 16mm 高的开关必须顶到上盖 -> NON-EMPTY
//     (12mm 那版不成立: 板面 8.7 + 12 = 20.7 还没够到 23 的盖背面, 白设了个必过的对照)
if (t == 71) intersection() { translate([0,0,RC_H-RC_TOP_T]) rc_top();
    for (b = RC_BTN_POS) translate([b[0]-3, b[1]+RC_PCB_DY-3, RC_PCB_Z]) cube([6,6,16]); }
// 72: 拨柄能伸出外壁 —— 探针从壁外插到拨柄尖 x=-32.5 处, 必须畅通 -> EMPTY
if (t == 72) intersection() { rc_bottom();
    translate([-RC_L/2 - 1, RC_PSW_Y + RC_PCB_DY, RC_PSW_Z]) rotate([0,90,0])
        cylinder(d = 1.5, h = WALL + 2); }
// 73: 阳性对照 —— 同一探针挪到拨柄开口以外(y 偏 6mm)必须被壁挡住 -> NON-EMPTY
if (t == 73) intersection() { rc_bottom();
    translate([-RC_L/2 - 1, RC_PSW_Y + RC_PCB_DY + 6, RC_PSW_Z]) rotate([0,90,0])
        cylinder(d = 1.5, h = WALL + 2); }
// 74: 充电 Type-C 开口对得上座子 -> EMPTY
if (t == 74) intersection() { rc_bottom();
    translate([-RC_L/2 - 1, RC_USB_Y + RC_PCB_DY, RC_USB_Z]) rotate([0,90,0])
        cylinder(d = 2.5, h = WALL + 2); }
// 75: 阳性对照 —— +X 端**不该有**烧录口, 同样位置必须是实心壁 -> NON-EMPTY
if (t == 75) intersection() { rc_bottom();
    translate([RC_L/2 - WALL - 1, RC_USB_Y + RC_PCB_DY, RC_PCB_Z + RC_U1_STACK - 1.6])
        rotate([0,90,0]) cylinder(d = 2.5, h = WALL + 2); }

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
    at_house() translate([0, 0, BASE_H]) union() { house_l(); house_r(); } }
// 54: 阳性对照 —— 把闸体放回 v2.6 的 x=25, 必须撞上按键帽 -> NON-EMPTY
if (t == 54) intersection() {
    for (b = BTN_POS) translate([b[0], b[1], CAP_BOT_Z]) btn_cap();
    translate([25, 0, 0]) rotate([0, 0, HS_ROT])
        translate([0, 0, BASE_H]) union() { house_l(); house_r(); } }
// 51: 麦克风圆板 φ14×1 躺进圆窝 -> EMPTY
if (t == 51) intersection() { house_l();
    translate([-HS_L/2 + WALL - MIC_POCKET_T + 0.05, MIC_Y, MIC_Z]) rotate([0,90,0])
        cylinder(d = MIC_D, h = MIC_T_CHK); }
// 52: 阳性对照 —— 圆板贴在内壁面上(没沉进窝)必须被压舌挡住 -> NON-EMPTY
if (t == 52) intersection() { house_l();
    translate([-HS_L/2 + WALL, MIC_Y, MIC_Z]) rotate([0,90,0])
        cylinder(d = MIC_D, h = MIC_T_CHK); }

/* ===== Type-C 插得到底吗 (t=80..85) ==========================================
   这一组测的不是"开口对没对准座子"(那是 t=74 干的事), 而是**插头塞不塞得进去**。
   两件事必须分开测: 金属壳穿得过 ≠ 插得到底 —— 完全插入时塑料头前端面基本贴住
   座口, 所以从外壁面到座口那段死区**得由塑料头自己穿过去**。
   建模: 塑料头 = 长方块, 完全插入姿态 = 前端面贴在座口平面上, 往 -X 长出去。
   用户实测塑料头 11 x 6.5。                                                */
PLUG_W = 11;  PLUG_T = 6.5;  PLUG_BODY_L = 20;   // 塑料头往外的长度, 够长就行
MAIN_SOCKET_X = -88.23;                          // U3 本体前沿 = 座口 (EDA 复核)
RC_SOCKET_X   = -28.0;                           // 遥控 U2 本体前沿

module plug(w, thk, socket_x, y, z) {
    translate([socket_x - PLUG_BODY_L, y - w/2, z - thk/2])
        cube([PLUG_BODY_L, w, thk]);
}
// 80: 主机充电插头(含塑料头)完全插入 vs 托盘 -> EMPTY
if (t == 80) intersection() { base_tray(); plug(PLUG_W, PLUG_T, MAIN_SOCKET_X, USB_Y, USB_Z); }
// 81: 阳性对照 —— 塑料头放大到 14 x 9 必须被前端面挡住 -> NON-EMPTY
//     没有这条就证明不了 t=80 是真在测"塑料头过不过得去"。
if (t == 81) intersection() { base_tray(); plug(14, 9, MAIN_SOCKET_X, USB_Y, USB_Z); }
// 82: 遥控器同一件事 -> EMPTY
if (t == 82) intersection() { rc_bottom(); plug(PLUG_W, PLUG_T, RC_SOCKET_X, RC_USB_Y + RC_PCB_DY, RC_USB_Z); }
// 83: 阳性对照 —— 遥控器塑料头放大必须被挡住 -> NON-EMPTY
if (t == 83) intersection() { rc_bottom(); plug(14, 9, RC_SOCKET_X, RC_USB_Y + RC_PCB_DY, RC_USB_Z); }

/* ===== 拨柄露够长吗 (t=84/85) ================================================
   判据来自尺寸基准 §366: 拨柄尖要比外壁面再露 **1mm**, 手指才拨得动。
   测法: 在"外壁面往外 1mm"处放个探针, **拨柄必须还在那儿**(NON-EMPTY);
   再在拨柄尖之外放同样的探针, 必须扑空(EMPTY) —— 后者证明探针本身没问题。
   ⚠ 光测"拨柄穿过开口不撞墙"是不够的: 拨柄缩在墙里也一样不撞。   */
LEVER_TIP_X = -93.51;             // SW3 挪到 x=-84.1 之后 (EDA 复核)
OUTER_X     = -BASE_L/2;          // -91.5
module lever_solid()              // 拨柄: 从本体前面伸到尖端
    translate([LEVER_TIP_X, PSW_Y - 1.2, USB_Z - 1.0]) cube([9, 2.4, 2.0]);
module tip_probe(x)
    translate([x, PSW_Y - 0.5, USB_Z - 0.5]) cube([0.4, 1.0, 1.0]);
// 84: 外壁面外 1.0mm 处必须还有拨柄 -> NON-EMPTY
if (t == 84) intersection() { lever_solid(); tip_probe(OUTER_X - 1.0); }
// 85: 阳性对照 —— 拨柄尖再往外 0.5mm 必须扑空 -> EMPTY
if (t == 85) intersection() { lever_solid(); tip_probe(LEVER_TIP_X - 0.5); }

/* ===== 跨源核对: EDA 板孔 vs CAD 支撑柱 (t=86/87) ============================
   🔴 t=24 的探针和柱子**都是从 PCB_MNT 生成的 —— 那是自洽, 不是核对**。
      PCB_MNT 整体写错, t=24 照样全过。承载底板 -X 倒角那次栽的就是这个跟头。
   这里把 2026-08-15 从 EDA **实读**的孔位硬写成字面量: 谁动了 PCB_MNT 而没同步
   EDA(或反过来改了 EDA 没同步 CAD), 这条就会红。
   来源: pcb_PrimitivePad.getAll() 里 metallization===false && !net 的四个焊盘
        (不是按预期坐标去搜的, 是让它们自己浮出来的), 孔径 ["ROUND",86.6142] mil = φ2.2000。
   ⚠ ±0.0012 是 EDA 的 mil 量化, 不是偏差。
   探针取 φ1.6 塞进 φ1.7 底孔 -> 单边只剩 0.05mm, 偏心超过 0.05 就会红;
   而真实装配的余量是 M2 φ2.0 穿板孔 φ2.2 = 0.1mm, 所以这条比装配严一倍。 */
EDA_MNT = [[-81.9988,  27.0002], [-81.9988, -27.0002],
           [ 25.9994,  27.0002], [ 25.9994, -27.0002]];
PROBE_T = 1.6;
// 86: 从 EDA 实读孔位下探针, 必须穿得过 CAD 支撑柱的底孔 -> EMPTY
if (t == 86) intersection() { base_tray();
    for (p = EDA_MNT) translate([p[0], p[1], 1]) cylinder(d = PROBE_T, h = 9); }
// 87: 阳性对照 —— 同样探针偏 0.15mm 必须撞柱体 -> NON-EMPTY (证明 86 有分辨力)
if (t == 87) intersection() { base_tray();
    for (p = EDA_MNT) translate([p[0] + 0.15, p[1], 1]) cylinder(d = PROBE_T, h = 9); }

/* ===== 电机压筋 (t=88/89) ====================================================
   这一对是**上下界**, 单独任何一条都证明不了压筋是对的:
     88 (NON-EMPTY): 压筋必须真的伸进电机轮廓里 —— 否则它就是个摆设,
                     电机照样有 3.94° 旷量(折到 300mm 杆尖 20.6mm)。
                     ⚠ 只测"隧道装得下电机"(t=32) 永远发现不了这一点。
     89 (EMPTY):     把电机每边缩 CRUSH_INT+0.05 之后必须不碰 —— 证明过盈量是
                     **有界的**(≤0.2mm/边), 是蹭平的压筋, 不是插不进去的死配合。
   两条一起才卡住"既要夹得住、又要装得进"。                                  */
// 88: 压筋必须与电机轮廓过盈 -> NON-EMPTY
if (t == 88) intersection() { motor_seat(); motor_box(); }
// 89: 过盈量有界 —— 电机每边缩 0.2 必须脱开 -> EMPTY
if (t == 89) intersection() { motor_seat(); motor_box(-(CRUSH_INT + 0.05)); }

/* ===== 遥控器充电灯窗 vs 按键导向凸台 (t=90/91) ==============================
   窗离 SW1 的 φ11.5 导向凸台很近, 稍微放大或往 +Y 挪就啃上去 ——
   凸台被啃掉一块, 按键帽的导向跨度变短, 按键会晃。
   90 测"窗没碰凸台", 91 用**用户最初给的 (-18,5)** 当阳性对照: 必须碰上,
   否则说明这条根本没在测凸台。                                              */
module rc_led_win(p) translate([p[0] - RC_LED_WIN_L/2, p[1] - RC_LED_WIN_W/2, -2])
    cube([RC_LED_WIN_L, RC_LED_WIN_W, RC_TOP_T + 4]);
module rc_btn_guide() for (b = RC_BTN_POS)
    translate([rcx(b)[0], rcx(b)[1], -RC_BTN_GUIDE_H])
        cylinder(d = RC_BTN_GUIDE_D, h = RC_BTN_GUIDE_H);
// 90: 定稿位置 (-18.7, 2.0) 的窗不碰导向凸台 -> EMPTY
if (t == 90) intersection() { rc_btn_guide(); rc_led_win(RC_LED_WIN_POS); }
// 91: 阳性对照 —— 最初拟的 (-18, 5) 必须啃上凸台 -> NON-EMPTY
if (t == 91) intersection() { rc_btn_guide(); rc_led_win([-18, 5]); }
