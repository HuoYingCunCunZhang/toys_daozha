// 装配性自检: 每个 t 出一个交集。
//   期望 EMPTY 的 = 不干涉 / 孔真的通
//   期望 NON-EMPTY 的 = 阳性对照, 证明检测本身有效
include <daozha.scad>
part = "none";          // 覆盖掉源文件的顶层出图
t = 1;

PROBE = 2.0;            // 探针直径, 略小于 SCREW_CLR=2.4
BUDGET = TRAY_H - (WALL + PCB_SO + PCB_T);   // 板面以上可用高度, 随 BASE_H 自动跟随

module probe_z(x, y, z0, z1) translate([x, y, z0]) cylinder(d = PROBE, h = z1 - z0);
module probe_y(x, z, y0, y1) translate([x, y0, z]) rotate([-90, 0, 0]) cylinder(d = PROBE, h = y1 - y0);

// --- 期望 EMPTY ---
if (t == 1) intersection() { base_tray(); translate([0,0,TRAY_H]) base_top(); }
if (t == 2) intersection() { rc_bottom(); translate([0,0,RC_H-RC_TOP_T]) rc_top(); }
if (t == 3) intersection() { base_top();
    for (p = BASE_BOSS) probe_z(p[0], p[1], -LIP_T-1, TOP_T+1); }
if (t == 4) intersection() { base_top();
    for (p = HS_BOSS) probe_z(HS_X_ABS+p[0], p[1], -LIP_T-1, TOP_T+1); }
if (t == 5) intersection() { rc_top();
    for (p = RC_BOSS) probe_z(p[0], p[1], -LIP_T-1, RC_TOP_T+1); }
if (t == 6) intersection() {
    translate([HS_X_ABS,-35,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z-BAR_H/2]) bar_a(); }
if (t == 7) intersection() {
    translate([HS_X_ABS,-35,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    probe_y(HS_X_ABS+BAR_PIN_X, BASE_H+PIV_Z, -40, -20); }
if (t == 8) intersection() { house_l(); house_r(); }
if (t == 9) intersection() { house_r();
    for (p = HS_JOIN) probe_y(p[0], p[1], 0, HS_W/2+1); }
if (t == 10) intersection() {
    translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z-BAR_H/2]) bar_a();
    probe_y(HS_X_ABS+BAR_PIN_X, BASE_H+PIV_Z, -40, -20); }

// 13/14: 把上盖抬 0.01mm 脱开贴合面, 排除"共面接触"造成的零体积假阳性
if (t == 13) intersection() { base_tray(); translate([0,0,TRAY_H+0.01]) base_top(); }
if (t == 14) intersection() { rc_bottom(); translate([0,0,RC_H-RC_TOP_T+0.01]) rc_top(); }

// 15: 横穿螺丝同轴性 —— φ1.4 探针要同时穿过转毂 φ2.4 过孔和闸杆 φ1.7 底孔
if (t == 15) intersection() {
    union() {
        translate([HS_X_ABS,-35,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
        translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z-BAR_H/2]) bar_a();
    }
    translate([HS_X_ABS+BAR_PIN_X, -40, BASE_H+PIV_Z]) rotate([-90,0,0])
        cylinder(d = 1.4, h = 20); }
// 16: 转毂转起来不能刮到闸体
if (t == 16) intersection() {
    translate([HS_X_ABS,-35,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    translate([HS_X_ABS, 0, BASE_H]) union() { house_l(); house_r(); } }

// --- 阳性对照, 期望 NON-EMPTY ---
// 11: 右壳导向柱确实存在 (在 y=2..20 段上, 螺丝孔外圈应有料)
if (t == 11) intersection() { house_r();
    translate([HS_JOIN[0][0], 2, HS_JOIN[0][1]]) rotate([-90,0,0]) cylinder(d = BOSS_OD, h = 18); }
// 12: 闸杆若按错误姿态(宽面朝下, 绕 X 转 90°)插入, 必须插不进去
if (t == 12) intersection() {
    translate([HS_X_ABS,-35,BASE_H+PIV_Z]) rotate([-90,0,0]) hub();
    translate([HS_X_ABS, BAR_Y_ABS, BASE_H+PIV_Z]) rotate([90,0,0])
        translate([0,0,-BAR_H/2]) bar_a(); }

// 17: 开关底孔是否打穿闸体外表面 (探针取壁厚段 y=-23..-21.5)
//     EMPTY = 打穿了(那段是孔), NON-EMPTY = 外壁完好
if (t == 17) intersection() { house_l();
    for (q = SW_HOLES) translate([q[0], -23.5, PIV_Z + q[1]]) rotate([-90,0,0])
        cylinder(d = 1.4, h = 2.0); }

// 18/19: 逐孔判定 —— 止挡筋恰好盖住 SW_HOLES[2], 会污染整组判定
if (t == 18) intersection() { house_l();
    for (i = [0,1,3]) translate([SW_HOLES[i][0], -23.5, PIV_Z + SW_HOLES[i][1]])
        rotate([-90,0,0]) cylinder(d = 1.4, h = 2.0); }
if (t == 19) intersection() { house_l();
    translate([SW_HOLES[2][0], -23.5, PIV_Z + SW_HOLES[2][1]])
        rotate([-90,0,0]) cylinder(d = 1.4, h = 2.0); }

/* ===== v2.4 排布自检 ===== */
// 20: 电芯实体 vs 托盘内部特征 (角螺柱/围挡/支撑柱) —— 期望 EMPTY
if (t == 20) intersection() { base_tray();
    translate([(BAT_X0+BAT_X1)/2 - BAT_L/2, -BAT_W/2, WALL])
        cube([BAT_L, BAT_W, BAT_T]); }
// 21: 承载底板 vs 托盘 (抬 0.01 脱开支撑柱贴合面) —— 期望 EMPTY, 验证切角避开角螺柱
if (t == 21) intersection() { base_tray();
    translate([0,0,WALL+PCB_SO+0.01]) linear_extrude(PCB_T) pcb_outline(); }
// 22: 板面以上 (BUDGET-0.1) 元件包络 vs 上盖 —— 期望 EMPTY, 验证中央区净高够
if (t == 22) intersection() { translate([0,0,TRAY_H]) base_top();
    intersection() {
        translate([0,0,WALL+PCB_SO+PCB_T]) linear_extrude(BUDGET - 0.1) pcb_outline();
        translate([-LIP_IN_X, -LIP_IN_Y, 0]) cube([2*LIP_IN_X, 2*LIP_IN_Y, 40]);
    } }
// 23: 阳性对照 —— 同样的包络加到 BUDGET+0.2 必须撞上盖(证明 22 不是白跑)
if (t == 23) intersection() { translate([0,0,TRAY_H]) base_top();
    intersection() {
        translate([0,0,WALL+PCB_SO+PCB_T]) linear_extrude(BUDGET + 0.2) pcb_outline();
        translate([-LIP_IN_X, -LIP_IN_Y, 0]) cube([2*LIP_IN_X, 2*LIP_IN_Y, 40]);
    } }
