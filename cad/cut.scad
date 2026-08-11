// 剖切检查用: openscad -D p=99 -D cutpart=4 -o png\cut.png cut.scad
include <daozha.scad>

cutpart = 4;   // 4=house_l 5=house_r 7=bar_a

keep = "bottom";   // bottom = 只留 z<27 ; top = 只留 z>27

if (cutpart == 4)
    difference() {
        house_l();
        if (keep == "top") translate([-60, -60, -3]) cube([120, 120, 30]);
        else               translate([-60, -60, 27]) cube([120, 120, 60]);
    }
else if (cutpart == 5)
    difference() { house_r();  translate([-60, -60, -3]) cube([120, 120, 30]); }
else if (cutpart == 7)
    difference() { bar_a();    translate([-5, -10, -1]) cube([60, 20, 5]); }
