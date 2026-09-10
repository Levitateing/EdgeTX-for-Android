# Install Arm GNU Toolchain (arm-none-eabi) into radio/src/targets/android/.tools
# Used to build PCB=ANDROID radio firmware (e.g. ANDROID_HW=TX16S).
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")

$ver = "14.2.rel1"
$pkgName = "arm-gnu-toolchain-$ver-mingw-w64-i686-arm-none-eabi"
$url = "https://armkeil.blob.core.windows.net/developer/Files/downloads/gnu/$ver/binrel/$pkgName.zip"

$p = Get-EdgeTxPaths
$t = $p.ToolsDir
$dest = Join-Path $t $pkgName
$gcc = Join-Path $dest "bin\arm-none-eabi-gcc.exe"

if ((Test-Path $gcc) -and -not $Force) {
    Write-Host "Arm GNU Toolchain already present:"
    Write-Host "  $gcc"
    & $gcc --version | Select-Object -First 2
    exit 0
}

New-Item -ItemType Directory -Force -Path $t | Out-Null
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$zip = Join-Path $t "$pkgName.$stamp.zip"
$extract = Join-Path $t "_extract_arm_gcc_$stamp"

Write-Host "Downloading Arm GNU Toolchain $ver (~300+ MB) ..."
Write-Host "  $url"
Write-Host "  -> $zip"

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curl) { throw "curl.exe not found (required for reliable large download)" }

& curl.exe -L --retry 3 --retry-delay 2 --fail -o $zip $url
if ($LASTEXITCODE -ne 0) { throw "curl download failed: $LASTEXITCODE" }

$zipSize = (Get-Item $zip).Length
Write-Host ("Downloaded {0:N1} MB" -f ($zipSize / 1MB))
if ($zipSize -lt 100MB) {
    throw "Download looks truncated ($zipSize bytes). Delete $zip and retry."
}

if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extract | Out-Null
Write-Host "Extracting ..."
# Official zip lays out bin/ + arm-none-eabi/ at archive root (no versioned wrapper).
Expand-Archive -Path $zip -DestinationPath $extract -Force
Remove-Item $zip -Force -ErrorAction SilentlyContinue

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

$probeGcc = Join-Path $extract "bin\arm-none-eabi-gcc.exe"
$dirs = @(Get-ChildItem $extract -Directory)
if (Test-Path $probeGcc) {
    # Flat layout: move whole extract tree to dest
    Move-Item $extract $dest
} elseif ($dirs.Count -ge 1 -and (Test-Path (Join-Path $dirs[0].FullName "bin\arm-none-eabi-gcc.exe"))) {
    Move-Item $dirs[0].FullName $dest
    Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
} else {
    throw "Unrecognized toolchain zip layout under $extract"
}

Get-ChildItem $t -Filter "$pkgName*.zip" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
Get-ChildItem $t -Filter "arm-gcc-download*.zip" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

if (-not (Test-Path $gcc)) {
    throw "arm-none-eabi-gcc.exe missing after extract: $gcc"
}

Write-Host ""
Write-Host "Installed to: $dest"
& $gcc --version | Select-Object -First 3
Write-Host ""
Write-Host "build-android-radio.ps1 will pick this up automatically from .tools"
