# 导出全部 STL
# 用法:  .\export_stl.ps1
# 注意:  路径不能含中文，否则 OpenSCAD 无法渲染

$scad = "F:\Program Files\OpenSCAD\openscad.exe"
if (-not (Test-Path $scad)) {
    $c = Get-Command openscad -ErrorAction SilentlyContinue
    if ($c) { $scad = $c.Source } else {
        Write-Output "找不到 OpenSCAD，请先安装并修改本脚本顶部的路径"
        exit 1
    }
}

$src = Join-Path $PSScriptRoot "daozha.scad"
$out = Join-Path $PSScriptRoot "stl"
if (-not (Test-Path $out)) { New-Item -ItemType Directory -Path $out | Out-Null }

# 用数字选择器 p=N，避开 PowerShell 向原生程序传引号的坑
$map = @{ base_tray = 2; base_top = 3; house_l = 4; house_r = 5; hub = 6;
          bar_a = 7; bar_b = 8; rc_bottom = 9; rc_top = 10;
          cam = 11; btn_cap = 12; rc_btn_cap = 14 }

foreach ($k in $map.Keys) {
    Write-Output "导出 $k ..."
    $log = & $scad -o (Join-Path $out "$k.stl") -D "p=$($map[$k])" $src 2>&1 | Out-String
    # 几何合法性: 必须 Volumes=2 / Simple=yes (单一封闭实体、无游离体、2-manifold)
    $g = ($log -split "`n" | Select-String -Pattern 'Simple:|Volumes:') -join '  '
    Write-Output "   $($g.Trim())"
}

Write-Output ""
Write-Output "全部导出到 $out"
