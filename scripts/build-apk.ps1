# Build debug APK for EdgeTX UI
param(
    # Empty = match last native build (CMakeCache EDGE_TX_DISPLAY).
    [string]$Display = ""
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$paths = Get-EdgeTxPaths
$AppRoot = $paths.AppRoot
$Tools = $paths.ToolsDir

if (-not $Display) {
    $Display = Get-EdgeTxConfiguredDisplay
    Write-Host "APK display: $Display (from native build cache)"
} else {
    $Display = Test-ResolutionString $Display
    Write-Host "APK display: $Display"
}

& (Join-Path $PSScriptRoot "generate-wallpaper.ps1") -Display $Display

$jdk = Get-ChildItem $Tools -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "jdk-17*" } |
  Select-Object -First 1
if (-not $jdk) {
  throw "Portable JDK not found under radio/src/targets/android/.tools. Install JDK 17 or re-run the setup."
}

$gradle = $paths.GradleBat
if (-not (Test-Path $gradle)) {
  throw "Gradle not found at $gradle"
}

$sdk = $paths.SdkRoot
if (-not (Test-Path (Join-Path $sdk "platforms\android-35"))) {
  throw "Android SDK incomplete under $sdk"
}

$env:JAVA_HOME = $jdk.FullName
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:Path = "$($jdk.FullName)\bin;$sdk\platform-tools;" + $env:Path

Write-Host "Building..."
Set-Location $AppRoot

# Ensure stale generated SD assets cannot leak into the APK (Gradle Sync also cleans).
$genSd = Join-Path $AppRoot "app\build\generated\sdcardAssets"
if (Test-Path $genSd) {
    Write-Host "Clearing generated SD card assets cache..."
    Remove-Item $genSd -Recurse -Force
}

& $gradle assembleDebug --no-daemon
if ($LASTEXITCODE -ne 0) { throw "Gradle build failed" }

$apk = Join-Path $AppRoot "app\build\outputs\apk\debug\app-debug.apk"
$outDir = $paths.OutputDir
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$out = $paths.OutputApk
Copy-Item $apk $out -Force
Write-Host ""
Write-Host "OK: $out"
Write-Host ("Size: {0:N1} MB" -f ((Get-Item $out).Length / 1MB))
