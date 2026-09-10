# Build EdgeTX SIMU as a native static library for Android phones (arm64-v8a).
# Output: app/src/main/jniLibs/arm64-v8a/libedgetx_sim.a
param(
    # 2400x1440 = 5:3 (same as base 800x480 colorlcd); fits 3200x1440 phones with side letterbox.
    [string]$Display = "2400x1440",
    [switch]$ForceAssets,
    [switch]$SkipOverlay,
    [switch]$NoAutoRestore
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\OverlayBackup.ps1")
$paths = Get-EdgeTxPaths
$Repo = $paths.RepoRoot
$Tools = $paths.ToolsDir

try {
if (-not $SkipOverlay) {
    & (Join-Path $PSScriptRoot "apply-overlay.ps1")
    & (Join-Path $PSScriptRoot "verify-overlay.ps1")
}

$bmpProbe = Join-Path $paths.GeneratedRoot "bitmaps\$Display\mask_icon_edgetx.png"
if ($ForceAssets -or -not (Test-Path $bmpProbe)) {
    & (Join-Path $PSScriptRoot "generate-display-assets.ps1") -Resolution $Display -Force:$ForceAssets
}

& (Join-Path $PSScriptRoot "stage-generated-assets.ps1") -Display $Display

# SVG rasterizer + font tools for display assets
& (Join-Path $PSScriptRoot "ensure-resvg.ps1")
& (Join-Path $PSScriptRoot "ensure-font-tools.ps1")
$ResvgDir = Join-Path $Tools "resvg"
$env:Path = "$ResvgDir;" + $env:Path
$env:EDGE_TX_RESVG = Join-Path $ResvgDir "resvg.exe"

$CMake = $paths.CmakeExe
$Ninja = $paths.NinjaExe
$Toolchain = $paths.NdkToolchain
$OutRoot = Join-Path $paths.AppRoot "app\src\main\jniLibs"

# generate_datacopy.py needs libclang.dll on PATH (pip package clang.native).
$ClangNative = Join-Path $env:LOCALAPPDATA "Programs\Python\Python314\Lib\site-packages\clang\native"
if (-not (Test-Path (Join-Path $ClangNative "libclang.dll"))) {
  Write-Host "Installing libclang for Python codegen..."
  python -m pip install libclang --quiet
}
if (Test-Path (Join-Path $ClangNative "libclang.dll")) {
  $env:Path = "$ClangNative;" + $env:Path
} else {
  Write-Warning "libclang.dll not found; datacopy codegen may fail"
}

if (-not (Test-Path $CMake)) { throw "cmake missing: $CMake" }
if (-not (Test-Path $Ninja)) { throw "ninja missing: $Ninja" }
if (-not (Test-Path $Toolchain)) { throw "NDK toolchain missing: $Toolchain" }

$RepoFs = ($Repo -replace '\\', '/')
$NinjaFs = ($Ninja -replace '\\', '/')
$ToolchainFs = ($Toolchain -replace '\\', '/')

$env:CMAKE_GENERATOR = "Ninja"
$env:CMAKE_MAKE_PROGRAM = ($Ninja -replace '\\', '/')

$NdkSysroot = Join-Path $paths.NdkDir "toolchains\llvm\prebuilt\windows-x86_64\sysroot"
$NdkSysrootFs = ($NdkSysroot -replace '\\', '/')
# libclang codegen needs NDK sysroot headers (inttypes.h, etc.)
$SysrootArg = "-isysroot;$NdkSysrootFs"

$Abi = "arm64-v8a"
$BuildDir = $paths.BuildDirArm64
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$OutDir = Join-Path $OutRoot $Abi
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "=== Configure $Abi ==="
$cmakeArgs = @(
  "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFs"
  "-DANDROID_ABI=$Abi"
  "-DANDROID_PLATFORM=android-26"
  "-DANDROID_STL=c++_shared"
  "-DCMAKE_MAKE_PROGRAM=$NinjaFs"
  "-DEdgeTX_SUPERBUILD:BOOL=0"
  "-DNATIVE_BUILD:BOOL=1"
  "-DDISABLE_COMPANION:BOOL=1"
  "-DCMAKE_BUILD_TYPE=Release"
  "-DPCB=ANDROID"
  "-DSYSROOT_ARG=$SysrootArg"
  "-Wno-dev"
)
if ($Display) {
  $cmakeArgs += "-DEDGE_TX_DISPLAY=$Display"
  if ($ForceAssets) {
    $cmakeArgs += "-DFORCE_GENERATE_ASSETS=ON"
    Write-Host "FORCE_GENERATE_ASSETS=ON"
  }
  Write-Host "EDGE_TX_DISPLAY=$Display"
}
$ErrorActionPreference = "Continue"
& $CMake --fresh -G Ninja -S $RepoFs -B (($BuildDir -replace '\\', '/')) @cmakeArgs
$cfgExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($cfgExit -ne 0) { throw "cmake configure failed for $Abi ($cfgExit)" }

Write-Host "=== Build edgetx_sim ($Abi) ==="
$ErrorActionPreference = "Continue"
& $CMake --build (($BuildDir -replace '\\', '/')) --target edgetx_sim --parallel
$bldExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($bldExit -ne 0) { throw "cmake build failed for $Abi ($bldExit)" }

$built = Get-ChildItem $BuildDir -Recurse -Filter "libedgetx_sim.a" | Select-Object -First 1
if (-not $built) { throw "libedgetx_sim.a not found under $BuildDir" }
$dest = Join-Path $OutDir "libedgetx_sim.a"
Copy-Item $built.FullName $dest -Force
Write-Host "OK:" $dest ("{0:N1} MB" -f ($built.Length / 1MB))

Write-Host ""
Write-Host "Native SIMU libs ready under $OutRoot"
} finally {
    if (-not $NoAutoRestore) {
        Restore-OverlayIfBackedUp -Reason "Restoring upstream main tree from overlay backup..."
    }
}
