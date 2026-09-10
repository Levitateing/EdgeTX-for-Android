# Verify generated assets exist under radio/src/targets/android/generated/ (no staging to main tree).
param(
    [string]$Display = "2400x1440"
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths

if ($Display -eq "800x480") {
    Write-Host "800x480 uses stock upstream colorlcd assets in main tree."
    exit 0
}

$null = Test-ResolutionString $Display
$parts = $Display.Split("x")
$w = [int]$parts[0]
$fontDir = Get-EdgeTxFontDirName -Width $w -Height ([int]$parts[1])

$bmp = Join-Path $p.GeneratedRoot "bitmaps\$Display\mask_icon_edgetx.png"
$font = Join-Path $p.GeneratedRoot "fonts\lvgl\$fontDir\lv_font_en_STD.c"

if (-not (Test-Path $bmp)) {
    throw "Bitmaps not found: $bmp`nRun: powershell -NoProfile -File radio\src\targets\android\scripts\generate-display-assets.ps1 -Resolution $Display -Force"
}
else {
    Write-Host "Bitmaps OK: $bmp"
}
if (-not (Test-Path $font)) {
    throw "Fonts not found: $font`nRun: powershell -NoProfile -File radio\src\targets\android\scripts\generate-display-assets.ps1 -Resolution $Display -Force"
}
else {
    Write-Host "Fonts OK: $font"
}
