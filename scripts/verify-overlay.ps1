# Verify firmware overlay is applied and includes all Android-critical patches.
param(
    [switch]$ApplyIfMissing
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths

$overlay = Join-Path $p.AndroidRoot "firmware\patches"
if (-not (Test-Path $overlay)) {
    throw "Overlay not found: $overlay"
}

$fail = @()
$warn = @()
$missing = @()
$stale = @()

Write-Host "=== EdgeTX Android overlay verification ==="
Write-Host ""

Get-ChildItem $overlay -File -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($overlay.Length + 1)
    $dest = Join-Path $p.RepoRoot $rel
    if (-not (Test-Path $dest)) {
        $missing += $rel
        return
    }
    if ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $dest).Hash) {
        $stale += $rel
    }
}

if ($missing.Count -gt 0) {
    Write-Host "FAIL overlay not applied ($($missing.Count) missing):"
    $missing | Select-Object -First 15 | ForEach-Object { Write-Host "     $_" }
    if ($missing.Count -gt 15) { Write-Host "     ... and $($missing.Count - 15) more" }
    $fail += "overlay not applied"
} elseif ($stale.Count -gt 0) {
    Write-Host "FAIL overlay stale ($($stale.Count) differ from patches):"
    $stale | Select-Object -First 10 | ForEach-Object { Write-Host "     $_" }
    if ($stale.Count -gt 10) { Write-Host "     ... and $($stale.Count - 10) more" }
    $fail += "overlay stale"
} else {
    $patchCount = (Get-ChildItem $overlay -Recurse -File).Count
    Write-Host "OK   $patchCount patch files present and match repo tree"
}

# LVGL header: required for LCD_W > 2047 (2400x1440, 2560x1440, ...).
$lvImg = Join-Path $p.RepoRoot "radio\src\thirdparty\lvgl\src\draw\lv_img_buf.h"
$lvPatch = Join-Path $overlay "radio\src\thirdparty\lvgl\src\draw\lv_img_buf.h"
if (-not (Test-Path $lvPatch)) {
    Write-Host "FAIL missing overlay patch: radio/src/thirdparty/lvgl/src/draw/lv_img_buf.h"
    $fail += "lv_img_buf patch missing from overlay folder"
} elseif (Test-Path $lvImg) {
    $txt = Get-Content $lvImg -Raw
    if ($txt -notmatch 'w\s*:\s*12.*4095 for large displays') {
        Write-Host "FAIL lv_img_buf.h not patched (need 12-bit w/h for large displays)"
        $fail += "lv_img_buf not patched"
    } else {
        Write-Host "OK   lv_img_buf.h large-display patch (12-bit w/h)"
    }
} else {
    Write-Host "WARN lv_img_buf.h not in repo tree (overlay not applied yet?)"
    $warn += "lv_img_buf absent"
}

Write-Host ""
if ($ApplyIfMissing -and ($missing.Count -gt 0 -or $stale.Count -gt 0)) {
    Write-Host "Applying overlay..."
    & (Join-Path $PSScriptRoot "apply-overlay.ps1")
    Write-Host ""
}

if ($fail.Count -gt 0) {
    if (-not $ApplyIfMissing) {
        Write-Host "Fix: powershell -NoProfile -File radio\src\targets\android\scripts\apply-overlay.ps1"
    }
    throw "Overlay verification failed: $($fail -join ', ')"
}

if ($warn.Count -gt 0) {
    Write-Host "Warnings: $($warn -join ', ')"
}
Write-Host "Overlay verification passed."
