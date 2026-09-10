# Sanity-check generated fonts/bitmaps/wallpaper for resolution consistency.
param(
    [string[]]$Resolutions = @("2400x1440", "2560x1440")
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths

function Get-FontProbeSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return -1 }
    return (Get-Item $Path).Length
}

$fail = @()
Write-Host "=== Verify generated Android assets ==="
Write-Host ""

foreach ($res in $Resolutions) {
    if ($res -notmatch '^(\d+)x(\d+)$') { throw "Bad resolution: $res" }
    $w = [int]$Matches[1]

    $fontDir = Join-Path $p.AndroidRoot "generated\fonts\lvgl\disp$w"
    $fontProbe = Join-Path $fontDir "lv_font_en_bold_XXL.c"
    $bmDir = Join-Path $p.AndroidRoot "generated\bitmaps\$res"
    $bmProbe = Join-Path $bmDir "mask_icon_edgetx.png"
    $cmake = Join-Path $bmDir "CMakeLists.txt"
    $wall = Join-Path $p.AndroidRoot "SD-Card-Files\THEMES\EdgeTX\background_$res.png"

    Write-Host "[$res]"
    if (-not (Test-Path $fontProbe)) {
        Write-Host "  FAIL missing font probe: $fontProbe"
        $fail += "$res fonts"
    } else {
        $sz = (Get-Item $fontProbe).Length
        Write-Host "  OK   font probe size: $sz bytes ($fontProbe)"
    }

    if (-not (Test-Path $bmProbe)) {
        Write-Host "  FAIL missing bitmap probe: $bmProbe"
        $fail += "$res bitmaps"
    } else {
        Write-Host "  OK   bitmap probe: $bmProbe"
    }

    if (Test-Path $cmake) {
        $txt = Get-Content $cmake -Raw
        if ($txt -match '8bits"') {
            Write-Host '  FAIL CMakeLists typo 8bits"'
            $fail += "$res cmake typo"
        } else {
            Write-Host "  OK   CMakeLists masks line"
        }
    }

    if (Test-Path $wall) {
        Write-Host "  OK   wallpaper: $wall"
    } else {
        Write-Host "  WARN no bundled wallpaper (run generate-wallpaper.ps1 -Display $res)"
    }
    Write-Host ""
}

# Cross-check: same display height => same font scale (disp2400 vs disp2560 both H=1440).
$p2400 = Join-Path $p.AndroidRoot "generated\fonts\lvgl\disp2400\lv_font_en_bold_XXL.c"
$p2560 = Join-Path $p.AndroidRoot "generated\fonts\lvgl\disp2560\lv_font_en_bold_XXL.c"
if ((Test-Path $p2400) -and (Test-Path $p2560)) {
    $s2400 = (Get-Item $p2400).Length
    $s2560 = (Get-Item $p2560).Length
    if ($s2560 -ne $s2400) {
        Write-Host "WARN disp2560 XXL ($s2560) differs from disp2400 XXL ($s2400); same H=1440 expects equal scale"
    } else {
        Write-Host "OK   disp2560/disp2400 fonts match (same height 1440)"
    }
}

Write-Host ""
if ($fail.Count -gt 0) {
    throw "Asset verification failed: $($fail -join ', ')"
}
Write-Host "All checks passed."
