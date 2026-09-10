# Install Arm GNU Toolchain (arm-none-eabi) into radio/src/targets/android/.tools
# Used to build PCB=ANDROID radio firmware (e.g. ANDROID_HW=TX16S).
param(
    [switch]$Force,
    [scriptblock]$OnLog
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

function Write-ArmLog([string]$msg) {
    if ($OnLog) { Write-BuildLog $msg $OnLog } else { Write-Host $msg }
}

if ((Test-Path $gcc) -and -not $Force) {
    Write-ArmLog "Arm GNU Toolchain already present:"
    Write-ArmLog "  $gcc"
    & $gcc --version | Select-Object -First 2 | ForEach-Object { Write-ArmLog "$_" }
    exit 0
}

New-Item -ItemType Directory -Force -Path $t | Out-Null
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$zip = Join-Path $t "$pkgName.$stamp.zip"
$extract = Join-Path $t "_extract_arm_gcc_$stamp"

Write-ArmLog "Downloading Arm GNU Toolchain $ver (~300+ MB) ..."
Invoke-DownloadFileWithProgress -Url $url -OutFile $zip -OnLog $OnLog

$zipSize = (Get-Item $zip).Length
Write-ArmLog ("Downloaded {0:N1} MB" -f ($zipSize / 1MB))
if ($zipSize -lt 100MB) {
    throw "Download looks truncated ($zipSize bytes). Delete $zip and retry."
}

if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extract | Out-Null
Write-ArmLog "Extracting ..."
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

Write-ArmLog ""
Write-ArmLog "Installed to: $dest"
& $gcc --version | Select-Object -First 3 | ForEach-Object { Write-ArmLog "$_" }
Write-ArmLog ""
Write-ArmLog "Add to PATH for this shell:"
Write-ArmLog ("  `$env:Path = `"{0}\bin;`$env:Path`"" -f $dest)
