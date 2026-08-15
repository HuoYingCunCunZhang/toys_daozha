# 跑 check.scad 的全部用例并与期望比对。
# 期望表就在下面 —— 改了 check.scad 记得同步, 尤其**别删阳性对照**:
# 没有阳性对照的自检失效了也不会报警 (v2.2 的教训)。
#
# 用法:  .\run_check.ps1            (在 D:\cad 这类纯 ASCII 路径下跑)
#        .\run_check.ps1 -Only 40   (只跑一条)
param([int]$Only = 0)

$exe = "F:\Program Files\OpenSCAD\openscad.exe"
$src = Join-Path $PSScriptRoot "check.scad"
$tmp = Join-Path $env:TEMP "daozha_check"
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory $tmp | Out-Null }

# t => @(期望, 说明)   E = 必须空(不干涉/装得进)   N = 必须非空(阳性对照)
# ⚠ 这是 OrderedDictionary, 用整数下标取值会被当成**位置**而不是键 ——
#   $cases[1] 拿到的是第 2 条。所以下面一律用 GetEnumerator() 遍历。
$cases = [ordered]@{
     3 = @('E','上盖角螺丝孔是通的')
     4 = @('E','上盖闸体固定孔是通的')
     5 = @('E','遥控上盖螺丝孔是通的')
     6 = @('E','转毂 vs 闸杆')
     7 = @('E','转毂横穿孔是通的')
     8 = @('E','左壳 vs 右壳')
     9 = @('E','右壳对拧过孔是通的')
    10 = @('E','闸杆横穿底孔是通的')
    11 = @('N','阳性: 右壳导向柱确实存在')
    12 = @('N','阳性: 闸杆错误姿态插不进')
    13 = @('E','托盘 vs 上盖(抬 0.01 脱开贴合面, 取代原 t=1)')
    14 = @('E','遥控上下壳(抬 0.01)')
    15 = @('E','横穿螺丝同轴')
    16 = @('E','转毂+凸轮 转 0..90 vs 闸体')
    17 = @('N','阳性: 开关底孔没打穿外壁')
    18 = @('E','开关底孔本身是通的')
    55 = @('N','阳性: 落杆位那块安装台真的存在')
    56 = @('N','阳性: 起杆位那块安装台真的存在')
    20 = @('E','电芯 vs 托盘内部特征')
    21 = @('E','承载底板 vs 托盘(验 5x5 切角)')
    22 = @('E','板面以上净空 BUDGET-0.1')
    23 = @('N','阳性: BUDGET+0.2 必须撞上盖')
    30 = @('E','D 形轴插得进转毂')
    31 = @('N','阳性: 整圆 φ3 被 D 面挡住')
    32 = @('E','N20 装得进电机座')
    33 = @('N','阳性: 12.5 方形装不进')
    34 = @('E','闸杆 STOP_ANG-1 不碰止挡')
    35 = @('N','阳性: STOP_ANG+1 撞上止挡')
    40 = @('E','**装配路径**: 转毂穿得过 φ8.5 壁孔')
    41 = @('N','阳性: 一整件(装回凸轮)穿不过壁孔')
    42 = @('E','凸轮套上轴颈键面')
    43 = @('N','阳性: 轴颈若是整圆则凸轮套不上')
    44 = @('E','凸轮扫 0..90 vs 开关本体')
    45 = @('N','阳性: 落杆位压下杠杆')
    46 = @('E','转到 45° 杠杆已释放')
    47 = @('N','阳性: 起杆位压下另一只杠杆')
    48 = @('E','按键帽坐进上盖')
    49 = @('N','阳性: 按键帽往上拔被法兰挡住')
    50 = @('E','轻触开关本体 vs 上盖导向凸台')
    53 = @('E','**按键帽 vs 闸体**(v3.0 抓到的硬伤)')
    54 = @('N','阳性: 闸体放回 x=25 必须压住按键帽')
    51 = @('E','麦克风圆板躺进圆窝')
    52 = @('N','阳性: 圆板没沉进窝会被压舌挡住')
}

$fail = 0
foreach ($e in $cases.GetEnumerator()) {
    $t = $e.Key
    if ($Only -ne 0 -and $t -ne $Only) { continue }
    $exp, $desc = $e.Value
    $stl = Join-Path $tmp "c$t.stl"
    if (Test-Path $stl) { Remove-Item $stl -Force }
    $out = & $exe -D "t=$t" -o $stl $src 2>&1 | Out-String
    $isEmpty = (-not (Test-Path $stl)) -or ((Get-Item $stl).Length -lt 200)
    $got = if ($isEmpty) { 'E' } else { 'N' }
    $ok  = ($got -eq $exp)
    if (-not $ok) { $fail++ }
    "{0,-4} {1}  期望 {2} 实得 {3}  {4}" -f $t, $(if ($ok) { 'ok  ' } else { 'FAIL' }), $exp, $got, $desc
}
""
if ($fail -eq 0) { "全部通过。" } else { "$fail 条不符合期望。" }
