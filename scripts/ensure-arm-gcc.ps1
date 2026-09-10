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
$gxx = Join-Path $dest "bin\arm-none-eabi-g++.exe"

function Write-ArmLog([string]$msg) {
    if ($OnLog) { Write-BuildLog $msg $OnLog } else { Write-Host $msg }
}

function Repair-ArmGccLibstdcxxBits([string]$ToolchainRoot) {
    # On Windows, arm-none-eabi-g++ can open multilib bits/c++config.h under
    # paths like .../thumb/v7e-m+fp/hard/, but later #include <bits/os_defines.h>
    # from that same tree fails (path segment '+'). Mirror multilib bits/*.h into
    # the primary c++/<ver>/bits/ so includes resolve.
    $cxxRoot = Join-Path $ToolchainRoot "arm-none-eabi\include\c++"
    if (-not (Test-Path -LiteralPath $cxxRoot)) { return 0 }
    $verDirs = @(Get-ChildItem -LiteralPath $cxxRoot -Directory -ErrorAction SilentlyContinue)
    $copied = 0
    foreach ($verDir in $verDirs) {
        $mainBits = Join-Path $verDir.FullName "bits"
        if (-not (Test-Path -LiteralPath $mainBits)) {
            New-Item -ItemType Directory -Force -Path $mainBits | Out-Null
        }
        $multiBitsDirs = @(Get-ChildItem -LiteralPath $verDir.FullName -Directory -Recurse -Filter "bits" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $mainBits -and $_.FullName -match '\\arm-none-eabi\\' })
        foreach ($mb in $multiBitsDirs) {
            Get-ChildItem -LiteralPath $mb.FullName -File -ErrorAction SilentlyContinue | ForEach-Object {
                $dst = Join-Path $mainBits $_.Name
                if (-not (Test-Path -LiteralPath $dst)) {
                    Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
                    $copied++
                }
            }
        }
    }
    return $copied
}

function Test-ArmGccLibstdcxx([string]$GxxPath) {
    if (-not (Test-Path -LiteralPath $GxxPath)) { return $false }
    $tmpCpp = Join-Path $env:TEMP ("arm-gcc-cxx-check-{0}.cpp" -f [guid]::NewGuid().ToString("N"))
    $tmpObj = "$tmpCpp.o"
    try {
        Set-Content -Path $tmpCpp -Value "#include <cstdlib>`nint main(){return 0;}`n" -Encoding ASCII
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & $GxxPath -mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 -c $tmpCpp -o $tmpObj 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmpObj))
        } finally {
            $ErrorActionPreference = $prev
        }
    } finally {
        Remove-Item -LiteralPath $tmpCpp, $tmpObj -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-ArmGccReady([string]$ToolchainRoot, [string]$GxxPath) {
    $n = Repair-ArmGccLibstdcxxBits -ToolchainRoot $ToolchainRoot
    if ($n -gt 0) {
        Write-ArmLog "Repaired libstdc++ bits headers for Windows multilib paths ($n file(s))."
    }
    if (-not (Test-ArmGccLibstdcxx -GxxPath $GxxPath)) {
        throw @"
arm-none-eabi-g++ cannot compile a trivial C++ file (missing bits/os_defines.h or similar).
Delete the toolchain folder and re-run with -Force:
  $ToolchainRoot
"@
    }
}

if ((Test-Path $gcc) -and -not $Force) {
    Write-ArmLog "Arm GNU Toolchain already present:"
    Write-ArmLog "  $gcc"
    & $gcc --version | Select-Object -First 2 | ForEach-Object { Write-ArmLog "$_" }
    Ensure-ArmGccReady -ToolchainRoot $dest -GxxPath $gxx
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
# Prefer tar: Expand-Archive is slower and more fragile on deep Windows paths.
$tar = Get-Command tar.exe -ErrorAction SilentlyContinue
if ($tar) {
    & tar.exe -xf $zip -C $extract
    if ($LASTEXITCODE -ne 0) {
        throw "tar extract failed (exit $LASTEXITCODE)"
    }
} else {
    Expand-Archive -Path $zip -DestinationPath $extract -Force
}
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

Ensure-ArmGccReady -ToolchainRoot $dest -GxxPath $gxx

Write-ArmLog ""
Write-ArmLog "Installed to: $dest"
& $gcc --version | Select-Object -First 3 | ForEach-Object { Write-ArmLog "$_" }
Write-ArmLog ""
Write-ArmLog "Add to PATH for this shell:"
Write-ArmLog ("  `$env:Path = `"{0}\bin;`$env:Path`"" -f $dest)
