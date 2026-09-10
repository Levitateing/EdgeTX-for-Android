# Verify Android build path layout after migration to radio/src/targets/android/.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths

$fail = @()

function Test-LayoutPath {
    param([string]$Label, [string]$Path, [switch]$Optional)
    if (Test-Path $Path) {
        Write-Host "OK   $Label"
        Write-Host "     $Path"
    } elseif ($Optional) {
        Write-Host "SKIP $Label (optional)"
        Write-Host "     $Path"
    } else {
        Write-Host "FAIL $Label"
        Write-Host "     $Path"
        $script:fail += $Label
    }
}

Write-Host "=== EdgeTX Android path validation ==="
Write-Host ""

Test-LayoutPath "Repo root (CMakeLists.txt)" (Join-Path $p.RepoRoot "CMakeLists.txt")
Test-LayoutPath "Android root" $p.AndroidRoot
Test-LayoutPath "Portable tools: cmake" $p.CmakeExe
Test-LayoutPath "Overlay patches dir" (Join-Path $p.AndroidRoot "firmware\patches")
Test-LayoutPath "Asset util: generate_display_assets.py" (Join-Path $p.AndroidRoot "util\generate_display_assets.py")
Test-LayoutPath "SIMU headers" (Join-Path $p.RepoRoot "radio\src\targets\simu")
Test-LayoutPath "Platform CMakeLists" (Join-Path $p.AndroidRoot "CMakeLists.txt")
Test-LayoutPath "GUI launcher" (Join-Path $p.AndroidRoot "Build-EdgeTX-GUI.pyw")

$cpp = Join-Path $p.AndroidRoot "app\src\main\cpp"
$simuFromCpp = (Resolve-Path (Join-Path $cpp "..\..\..\..\..\..\targets\simu") -ErrorAction SilentlyContinue)
if ($simuFromCpp) {
    Write-Host "OK   app/cpp -> targets/simu relative path"
    Write-Host "     $simuFromCpp"
} else {
    Write-Host "FAIL app/cpp -> targets/simu relative path"
    $fail += "app/cpp simu relative path"
}

$stale = @(
    Join-Path $p.RepoRoot "android-app"
    Join-Path $p.RepoRoot "radio\src\Android"
    Join-Path $p.RepoRoot "radio\util\generate_display_assets.py"
)
foreach ($path in $stale) {
    if (Test-Path $path) {
        Write-Host "WARN stale path still present: $path"
    }
}

$patchesDir = Join-Path $p.AndroidRoot "firmware\patches"
$patchFiles = @(Get-ChildItem $patchesDir -File -Recurse)
Write-Host ""
Write-Host "=== Overlay patch inventory ==="
Write-Host "OK   $($patchFiles.Count) patch files under firmware/patches"
$critical = @(
    "radio\src\thirdparty\lvgl\src\draw\lv_img_buf.h",
    "radio\src\storage\yaml\yaml_datastructs_android.cpp",
    "radio\src\targets\simu\simulib.h",
    "tools\convert-gfx.py"
)
foreach ($rel in $critical) {
    $path = Join-Path $patchesDir ($rel -replace '/', '\')
    if (Test-Path $path) {
        Write-Host "OK   patch present: $rel"
    } else {
        Write-Host "FAIL missing patch: $rel"
        $fail += "patch $rel"
    }
}

$lvImg = Join-Path $p.RepoRoot "radio\src\thirdparty\lvgl\src\draw\lv_img_buf.h"
if (Test-Path $lvImg) {
    $txt = Get-Content $lvImg -Raw
    if ($txt -match 'w\s*:\s*12') {
        Write-Host "WARN main tree has overlay active (lv_img_buf.h w:12); run Sync-Upstream-Main.pyw before editing upstream"
    } else {
        Write-Host "OK   main tree clean (lv_img_buf.h not patched)"
    }
}

Write-Host ""
if ($fail.Count -gt 0) {
    throw "Path validation failed: $($fail -join ', ')"
}
Write-Host "All required paths OK."
