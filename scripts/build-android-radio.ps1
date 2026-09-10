# Build EdgeTX ANDROID radio firmware for physical boards (not phone SIMU).
# Requires: apply-overlay, arm-none-eabi GCC, cmake, ninja/make.
#
# Examples:
#   .\build-android-radio.ps1 -Hw TX16S
#   .\build-android-radio.ps1 -Hw H750
param(
    [ValidateSet("TX16S", "H750")]
    [string]$Hw = "TX16S",
    [string]$BuildDir = "",
    [switch]$SkipOverlay,
    [switch]$NoAutoRestore,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\OverlayBackup.ps1")
$paths = Get-EdgeTxPaths
$Repo = $paths.RepoRoot

function Find-ArmGcc {
    return (Find-ArmNoneEabiGcc)
}

# CMake often prints STATUS/WARNING on stderr. With $ErrorActionPreference=Stop
# (and when the GUI merges streams), those become terminating NativeCommandError
# and abort configure after the first warning (e.g. missing Git). Always check
# $LASTEXITCODE instead of treating stderr as failure.
function Invoke-CmakeLogged {
    param(
        [Parameter(Mandatory)]
        [string]$CmakeExe,
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $CmakeExe @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Host $_.Exception.Message
            } else {
                Write-Host $_
            }
        }
        return [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Ensure-GitOnPath {
    if (Get-Command git -ErrorAction SilentlyContinue) { return }
    $candidates = @(
        "C:\Program Files\Git\bin\git.exe"
        "C:\Program Files (x86)\Git\bin\git.exe"
        (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\git.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $env:Path = "$(Split-Path $c -Parent);$env:Path"
            Write-Host "Added Git to PATH: $c"
            return
        }
    }
    Write-Warning "Git not found on PATH — revision string may be unavailable (non-fatal)."
}

Ensure-GitOnPath

$gcc = Find-ArmGcc
if (-not $gcc) {
    Write-Host "Arm GCC not found in .tools or PATH. Installing into .tools ..."
    & (Join-Path $PSScriptRoot "ensure-arm-gcc.ps1")
    $gcc = Find-ArmGcc
}
if (-not $gcc) {
    throw @"
arm-none-eabi-gcc still not found after ensure-arm-gcc.ps1.
Run: powershell -NoProfile -File radio\src\targets\android\scripts\ensure-arm-gcc.ps1
"@
}
$gccBin = Split-Path $gcc -Parent
$gccBinFs = ($gccBin -replace '\\', '/')
$env:Path = "$gccBin;" + $env:Path
Write-Host "Using ARM GCC: $gcc"

# generate_datacopy.py needs libclang.dll on PATH (pip package clang).
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

try {
    if (-not $SkipOverlay) {
        & (Join-Path $PSScriptRoot "apply-overlay.ps1")
        & (Join-Path $PSScriptRoot "verify-overlay.ps1")
    }

    if (-not $BuildDir) {
        $BuildDir = Join-Path $paths.AndroidRoot "build-radio-$($Hw.ToLower())"
    }
    # Fresh configure if a previous host-cmake attempt left a bad cache
    if (Test-Path (Join-Path $BuildDir "CMakeCache.txt")) {
        Write-Host "Cleaning previous CMake cache in $BuildDir"
        Remove-Item (Join-Path $BuildDir "*") -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

    $Cmake = $paths.CmakeExe
    if (-not (Test-Path $Cmake)) { throw "cmake missing: $Cmake" }

    $Ninja = $paths.NinjaExe
    $generatorArgs = @()
    if (Test-Path $Ninja) {
        $env:CMAKE_GENERATOR = "Ninja"
        $env:CMAKE_MAKE_PROGRAM = ($Ninja -replace '\\', '/')
        $generatorArgs += @("-G", "Ninja", "-DCMAKE_MAKE_PROGRAM=$($Ninja -replace '\\','/')")
    }

    $ToolchainFile = Join-Path $Repo "cmake\toolchain\arm-none-eabi.cmake"
    $ToolchainFs = ($ToolchainFile -replace '\\', '/')
    $RepoFs = ($Repo -replace '\\', '/')

    Write-Host "=== Configure PCB=ANDROID ANDROID_HW=$Hw (arm-none-eabi direct) ==="
    # Bypass EdgeTX SUPERBUILD (needs a host compiler on Windows).
    # Point ARM_TOOLCHAIN_DIR at the toolchain bin/ directory.
    $cmakeArgs = $generatorArgs + @(
        "-DCMAKE_TOOLCHAIN_FILE=$ToolchainFs"
        "-DARM_TOOLCHAIN_DIR=$gccBinFs"
        "-DEdgeTX_SUPERBUILD=OFF"
        "-DNATIVE_BUILD=OFF"
        "-DPCB=ANDROID"
        "-DANDROID_HW=$Hw"
        "-DDEBUG=NO"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DDISABLE_COMPANION=YES"
        "-Wno-dev"
    )
    # TX16S uses native 480x272 panel — do not pass EDGE_TX_DISPLAY
    Push-Location $BuildDir
    try {
        $cfgCode = Invoke-CmakeLogged -CmakeExe $Cmake -Arguments ($cmakeArgs + @($RepoFs))
        if ($cfgCode -ne 0) { throw "cmake configure failed: $cfgCode" }
        if ($ConfigureOnly) {
            Write-Host "Configure-only done: $BuildDir"
            return
        }
        Write-Host "=== Build firmware ==="
        $buildCode = Invoke-CmakeLogged -CmakeExe $Cmake -Arguments @("--build", ".", "--target", "firmware", "-j")
        if ($buildCode -ne 0) { throw "firmware build failed: $buildCode" }

        $artifacts = Get-ChildItem $BuildDir -Recurse -Include "firmware.bin","firmware.uf2","firmware.hex" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        Write-Host ""
        Write-Host "Build dir: $BuildDir"
        if ($artifacts) {
            Write-Host "Build artifacts:"
            $artifacts | Select-Object -First 5 | ForEach-Object {
                Write-Host ("  {0}  ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB))
            }
        } else {
            Write-Host "No firmware.bin/uf2 found yet — check build log."
        }

        # Stage into output/ next to EdgeTX.apk (board-tagged names).
        $outDir = $paths.OutputDir
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        $hwTag = $Hw.ToLower()
        $staged = @()
        $binSrc = $artifacts | Where-Object { $_.Name -eq "firmware.bin" } | Select-Object -First 1
        if ($binSrc) {
            $binDst = Join-Path $outDir "firmware-$hwTag.bin"
            Copy-Item $binSrc.FullName $binDst -Force
            $staged += $binDst
        }
        $hexSrc = $artifacts | Where-Object { $_.Name -eq "firmware.hex" } | Select-Object -First 1
        if ($hexSrc) {
            $hexDst = Join-Path $outDir "firmware-$hwTag.hex"
            Copy-Item $hexSrc.FullName $hexDst -Force
            $staged += $hexDst
        }
        $uf2Src = $artifacts | Where-Object { $_.Name -eq "firmware.uf2" } | Select-Object -First 1
        if ($uf2Src) {
            $uf2Dst = Join-Path $outDir "firmware-$hwTag.uf2"
            Copy-Item $uf2Src.FullName $uf2Dst -Force
            $staged += $uf2Dst
        }
        if ($staged.Count -gt 0) {
            Write-Host ""
            Write-Host "Copied to output (same folder as EdgeTX.apk):"
            foreach ($p in $staged) {
                $fi = Get-Item $p
                Write-Host ("  {0}  ({1:N1} MB)" -f $fi.FullName, ($fi.Length / 1MB))
            }
        }
        Write-Host "Flash with EdgeTX bootloader UI or ST-Link (STM32CubeProgrammer)."
    }
    finally {
        Pop-Location
    }
}
finally {
    if (-not $NoAutoRestore -and -not $SkipOverlay) {
        & (Join-Path $PSScriptRoot "restore-overlay.ps1")
    }
}
