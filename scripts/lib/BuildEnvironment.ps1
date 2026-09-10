# EdgeTX Android build environment - portable installs under radio/src/targets/android/.tools
$ErrorActionPreference = "Stop"

$script:AndroidRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script:AppRoot = $script:AndroidRoot
$script:RepoRoot = (Resolve-Path (Join-Path $script:AndroidRoot "..\..\..\..")).Path
$script:ToolsDir = Join-Path $script:AndroidRoot ".tools"
$script:GeneratedRoot = Join-Path $script:AndroidRoot "generated"

$script:ToolchainVersions = @{
    CmakeVersion = "3.31.6"
    NinjaVersion = "1.12.1"
    GradleVersion = "8.11.1"
    JdkVersion = "17.0.13+11"
    NdkVersion = "27.0.12077973"
    SdkPlatform = "android-35"
    BuildTools = "35.0.0"
    ArmGccVersion = "14.2.rel1"
}

function Get-EdgeTxConfiguredDisplay {
    param([string]$Fallback = "2400x1440")
    $p = Get-EdgeTxPaths
    $cache = Join-Path $p.BuildDirArm64 "CMakeCache.txt"
    if (Test-Path $cache) {
        foreach ($line in Get-Content $cache) {
            if ($line -match '^EDGE_TX_DISPLAY:STRING=(.+)$') {
                $val = $Matches[1].Trim()
                if ($val -match '^\d+x\d+$') { return $val }
            }
        }
    }
    $hw = Join-Path $p.BuildDirArm64 "edge_tx_display\display_hw.json"
    if (Test-Path $hw) {
        try {
            $j = Get-Content $hw -Raw | ConvertFrom-Json
            $w = [int]$j.display.lcd_w
            $h = [int]$j.display.lcd_h
            if ($w -gt 0 -and $h -gt 0) { return "${w}x${h}" }
        } catch { }
    }
    return $Fallback
}

function Get-EdgeTxPaths {
    $t = $script:ToolsDir
    @{
        ToolsDir = $t
        AndroidRoot = $script:AndroidRoot
        AppRoot = $script:AppRoot
        RepoRoot = $script:RepoRoot
        GeneratedRoot = $script:GeneratedRoot
        BuildDirArm64 = Join-Path $script:AndroidRoot "build-android-arm64"
        AndroidAbi = "arm64-v8a"
        OutputDir = Join-Path $script:AndroidRoot "output"
        OutputApk = Join-Path $script:AndroidRoot "output\EdgeTX.apk"
        # Radio firmware staged next to the APK (board-tagged).
        OutputFirmwareTx16s = Join-Path $script:AndroidRoot "output\firmware-tx16s.bin"
        OutputFirmwareH750 = Join-Path $script:AndroidRoot "output\firmware-h750.bin"
        CmakeExe = Join-Path $t "cmake-$($script:ToolchainVersions.CmakeVersion)-windows-x86_64\bin\cmake.exe"
        NinjaExe = Join-Path $t "ninja.exe"
        SdkRoot = Join-Path $t "android-sdk"
        NdkDir = Join-Path $t "android-sdk\ndk\$($script:ToolchainVersions.NdkVersion)"
        NdkToolchain = Join-Path $t "android-sdk\ndk\$($script:ToolchainVersions.NdkVersion)\build\cmake\android.toolchain.cmake"
        GradleBat = Join-Path $t "gradle-$($script:ToolchainVersions.GradleVersion)\bin\gradle.bat"
        ResvgExe = Join-Path $t "resvg\resvg.exe"
        NodeExe = Join-Path $t "node-portable\node.exe"
        LvFontConv = Join-Path $t "font-tools\node_modules\.bin\lv_font_conv.cmd"
        ArmGccRoot = Join-Path $t "arm-gnu-toolchain-$($script:ToolchainVersions.ArmGccVersion)-mingw-w64-i686-arm-none-eabi"
        ArmGccExe = Join-Path $t "arm-gnu-toolchain-$($script:ToolchainVersions.ArmGccVersion)-mingw-w64-i686-arm-none-eabi\bin\arm-none-eabi-gcc.exe"
    }
}

function Find-ArmNoneEabiGcc {
    $p = Get-EdgeTxPaths
    if (Test-Path $p.ArmGccExe) { return $p.ArmGccExe }
    $cmd = Get-Command arm-none-eabi-gcc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe",
        "C:\Program Files\Arm GNU Toolchain arm-none-eabi\*\bin\arm-none-eabi-gcc.exe",
        "$env:USERPROFILE\AppData\Local\Programs\ArmGNUToolchain\*\bin\arm-none-eabi-gcc.exe"
    )
    foreach ($pat in $candidates) {
        $hit = Get-Item $pat -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Write-BuildLog {
    param(
        [string]$Message,
        [scriptblock]$OnLog
    )
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    if ($OnLog) { & $OnLog $line } else { Write-Host $line }
}

function Invoke-DownloadFileWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [scriptblock]$OnLog,
        [int]$ProgressStepPercent = 5,
        [double]$ProgressIntervalSec = 2.0
    )
    $dir = Split-Path -Parent $OutFile
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }

    Write-BuildLog "Downloading: $Url" $OnLog
    Write-BuildLog "  -> $OutFile" $OnLog

    # Prefer HttpClient: reliable file write + percent progress (curl ProcessStartInfo
    # quoting is fragile on Windows and redirected stdio can exit with no file).
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object System.Net.Http.HttpClient $handler
    $client.Timeout = [TimeSpan]::FromHours(3)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd("EdgeTX-Android-Build/1.0")
    try {
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $([int]$response.StatusCode) $($response.ReasonPhrase)"
        }
        $total = $response.Content.Headers.ContentLength
        if ($total) {
            Write-BuildLog ("  size: {0:N1} MB" -f ($total / 1MB)) $OnLog
        }
        $inStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outStream = [System.IO.File]::Create($OutFile)
        try {
            $buffer = New-Object byte[] (256KB)
            $totalRead = 0L
            $lastPct = -1
            $lastLog = Get-Date
            while (($n = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outStream.Write($buffer, 0, $n)
                $totalRead += $n
                $now = Get-Date
                if ($total -and $total -gt 0) {
                    $pct = [int]([Math]::Floor(100.0 * $totalRead / $total))
                    if ($pct -ge ($lastPct + $ProgressStepPercent) -or ($now - $lastLog).TotalSeconds -ge $ProgressIntervalSec) {
                        Write-BuildLog ("  ... {0}% ({1:N1} / {2:N1} MB)" -f $pct, ($totalRead / 1MB), ($total / 1MB)) $OnLog
                        $lastPct = $pct
                        $lastLog = $now
                    }
                } elseif (($now - $lastLog).TotalSeconds -ge $ProgressIntervalSec) {
                    Write-BuildLog ("  ... downloaded {0:N1} MB" -f ($totalRead / 1MB)) $OnLog
                    $lastLog = $now
                }
            }
            $outStream.Flush()
        } finally {
            $outStream.Dispose()
            $inStream.Dispose()
            $response.Dispose()
        }
    } catch {
        if (Test-Path -LiteralPath $OutFile) {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        }
        throw "Download failed: $($_.Exception.Message)"
    } finally {
        $client.Dispose()
        $handler.Dispose()
    }

    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "Download finished but file missing: $OutFile"
    }
    $final = (Get-Item -LiteralPath $OutFile).Length
    if ($final -le 0) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "Download produced empty file: $OutFile"
    }
    Write-BuildLog ("Download complete: {0:N1} MB" -f ($final / 1MB)) $OnLog
}

function Invoke-DownloadAndExpand {
    param(
        [string]$Url,
        [string]$ZipPath,
        [string]$ExtractDir,
        [scriptblock]$OnLog
    )
    Invoke-DownloadFileWithProgress -Url $Url -OutFile $ZipPath -OnLog $OnLog
    Write-BuildLog "Extracting: $ZipPath" $OnLog
    if (Test-Path $ExtractDir) { Remove-Item $ExtractDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Write-BuildLog "Extract done: $ExtractDir" $OnLog
}

function Test-PythonModule {
    param([string]$ModuleName)
    try {
        python -c "import $ModuleName" 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    } catch { return $false }
}

function Get-EdgeTxToolStatus {
    $p = Get-EdgeTxPaths
    $jdk = Get-ChildItem $p.ToolsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "jdk-17*" } | Select-Object -First 1
    $sdkPlatformPath = Join-Path $p.SdkRoot "platforms\$($script:ToolchainVersions.SdkPlatform)"

    @(
        @{ Id = "python"; Name = "Python 3"; Required = $true
           Scope = "system PATH (existing install OK)"
           Path = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
           Ok = [bool](Get-Command python -ErrorAction SilentlyContinue)
           Installable = $false; SizeHint = "" },
        @{ Id = "pillow"; Name = "Python: Pillow"; Required = $true
           Scope = "pip (existing env OK)"; Path = ""
           Ok = (Test-PythonModule "PIL"); Installable = $true; SizeHint = "~5 MB" },
        @{ Id = "libclang"; Name = "Python: libclang"; Required = $true
           Scope = "pip (existing env OK)"; Path = ""
           Ok = (Test-PythonModule "clang"); Installable = $true; SizeHint = "~30 MB" },
        @{ Id = "lz4"; Name = "Python: lz4"; Required = $true
           Scope = "pip (existing env OK)"; Path = ""
           Ok = (Test-PythonModule "lz4"); Installable = $true; SizeHint = "~1 MB" },
        @{ Id = "cmake"; Name = "CMake $($script:ToolchainVersions.CmakeVersion)"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.CmakeExe
           Ok = (Test-Path $p.CmakeExe); Installable = $true; SizeHint = "~45 MB" },
        @{ Id = "ninja"; Name = "Ninja"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.NinjaExe
           Ok = (Test-Path $p.NinjaExe); Installable = $true; SizeHint = "~0.3 MB" },
        @{ Id = "jdk"; Name = "JDK 17 (Temurin)"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = if ($jdk) { $jdk.FullName } else { "" }
           Ok = [bool]$jdk; Installable = $true; SizeHint = "~180 MB" },
        @{ Id = "gradle"; Name = "Gradle $($script:ToolchainVersions.GradleVersion)"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.GradleBat
           Ok = (Test-Path $p.GradleBat); Installable = $true; SizeHint = "~130 MB" },
        @{ Id = "sdk"; Name = "Android SDK $($script:ToolchainVersions.SdkPlatform)"; Required = $true
           Scope = "radio\src\targets\android\.tools\android-sdk"; Path = $sdkPlatformPath
           Ok = (Test-Path $sdkPlatformPath); Installable = $true; SizeHint = "~50 MB" },
        @{ Id = "ndk"; Name = "Android NDK $($script:ToolchainVersions.NdkVersion)"; Required = $true
           Scope = "radio\src\targets\android\.tools\android-sdk"; Path = $p.NdkToolchain
           Ok = (Test-Path $p.NdkToolchain); Installable = $true; SizeHint = "~1.5 GB" },
        @{ Id = "resvg"; Name = "resvg (SVG to PNG)"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.ResvgExe
           Ok = (Test-Path $p.ResvgExe); Installable = $true; SizeHint = "~5 MB" },
        @{ Id = "fonttools"; Name = "lv_font_conv + Node.js"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.LvFontConv
           Ok = (Test-Path $p.LvFontConv); Installable = $true; SizeHint = "~80 MB" }
    )
}

function Test-ResolutionString {
    param([string]$Text)
    if ($Text -notmatch '^(\d+)x(\d+)$') {
        throw "Resolution must be WIDTHxHEIGHT, e.g. 2400x1440"
    }
    $w = [int]$Matches[1]
    $h = [int]$Matches[2]
    if ($w -lt 320 -or $h -lt 240) { throw "Resolution too small (min 320x240)" }
    if ($w -gt 3840 -or $h -gt 2160) { throw "Resolution too large (max 3840x2160)" }
    if ($w -le $h) { throw "Landscape only (width must exceed height)" }
    return "${w}x${h}"
}

function Test-ResolutionParts {
    param([string]$Width, [string]$Height)
    $wText = $Width.Trim()
    $hText = $Height.Trim()
    if ($wText -notmatch '^\d+$') { throw "Width must be a positive integer" }
    if ($hText -notmatch '^\d+$') { throw "Height must be a positive integer" }
    return (Test-ResolutionString "${wText}x${hText}")
}

function Get-EdgeTxFontDirName {
    param([int]$Width, [int]$Height)
    if ($Width -eq 800 -and $Height -eq 480) { return "lrg" }
    if ($Width -le 320 -and $Height -le 240) { return "sml" }
    if ($Width -eq 480 -and $Height -eq 272) { return "std" }
    return "disp$Width"
}

function Get-DisplayAssetStatus {
    param([string]$Resolution)
    $null = Test-ResolutionString $Resolution
    $parts = $Resolution.Split("x")
    $w = [int]$parts[0]
    $h = [int]$parts[1]

    if ($w -eq 800 -and $h -eq 480) {
        return @{
            Resolution = $Resolution
            BitmapsReady = $true
            FontsReady = $true
            BitmapsPath = "upstream stock colorlcd 800x480"
            FontsPath = "upstream stock lrg fonts"
            NeedsGeneration = $false
            Summary = "Stock 800x480 assets; no generation needed."
        }
    }

    $bitmapDir = Join-Path (Join-Path $script:GeneratedRoot "bitmaps") $Resolution
    $bitmapProbe = Join-Path $bitmapDir "mask_icon_edgetx.png"
    $fontDirName = Get-EdgeTxFontDirName -Width $w -Height $h
    $fontProbe = Join-Path (Join-Path (Join-Path $script:GeneratedRoot "fonts\lvgl") $fontDirName) "lv_font_en_STD.c"

    $bitmapsReady = (Test-Path $bitmapProbe)
    $fontsReady = (Test-Path $fontProbe)
    $needsGen = -not $bitmapsReady -or -not $fontsReady
    $bmpPath = if ($bitmapsReady) { $bitmapDir } else { "(missing)" }
    $fntPath = if ($fontsReady) { $fontDirName } else { "(missing; generated at configure)" }

    $summary = if (-not $needsGen) {
        "Bitmaps and fonts ready; build will reuse them."
    } elseif (-not $bitmapsReady -and -not $fontsReady) {
        "Bitmaps and fonts missing; build will auto-generate (first time is slow)."
    } elseif (-not $bitmapsReady) {
        "Bitmaps missing; will generate. Fonts already present."
    } else {
        "Bitmaps ready; fonts missing; configure will generate $fontDirName fonts."
    }

    return @{
        Resolution = $Resolution
        BitmapsReady = $bitmapsReady
        FontsReady = $fontsReady
        BitmapsPath = $bmpPath
        FontsPath = $fntPath
        NeedsGeneration = $needsGen
        Summary = $summary
    }
}

function Get-EdgeTxDisplayResListFile {
    Join-Path $script:AppRoot "display-resolutions.json"
}

function Read-EdgeTxSavedResolutions {
    $f = Get-EdgeTxDisplayResListFile
    if (-not (Test-Path $f)) { return @() }
    @(Get-Content $f -Encoding UTF8 | ForEach-Object {
        $_.Trim().Trim([char]0xFEFF)
    } | Where-Object { $_ -match '^\d+x\d+$' })
}

function Write-EdgeTxSavedResolutions {
    param([string[]]$Resolutions)
    $sorted = @($Resolutions | ForEach-Object {
        if ($_ -match '^(\d+)x(\d+)$') {
            [PSCustomObject]@{ Res = $_; W = [int]$Matches[1]; H = [int]$Matches[2] }
        }
    } | Sort-Object W, H | ForEach-Object { $_.Res })
    $sorted | Set-Content (Get-EdgeTxDisplayResListFile) -Encoding UTF8
}

function Test-EdgeTxResolutionProtected {
    param([string]$Resolution)
    return $Resolution -eq "800x480"
}

function Test-EdgeTxFontTierValid {
    param([string]$FontDirName)
    $fontDir = Join-Path (Join-Path $script:GeneratedRoot "fonts\lvgl") $FontDirName
    $required = @("lv_font_en_STD.c", "lv_font_en_bold_STD.c", "lv_font_en_XS.c", "lv_font_bl.c")
    foreach ($name in $required) {
        if (-not (Test-Path (Join-Path $fontDir $name))) { return $false }
    }
    $stdText = Get-Content (Join-Path $fontDir "lv_font_en_STD.c") -Raw -ErrorAction SilentlyContinue
    $boldText = Get-Content (Join-Path $fontDir "lv_font_en_bold_STD.c") -Raw -ErrorAction SilentlyContinue
    $xsText = Get-Content (Join-Path $fontDir "lv_font_en_XS.c") -Raw -ErrorAction SilentlyContinue
    $blText = Get-Content (Join-Path $fontDir "lv_font_bl.c") -Raw -ErrorAction SilentlyContinue
    if ($stdText -notmatch 'lv_font_en_STD') { return $false }
    if ($blText -notmatch 'lv_font_bl') { return $false }
    if ($boldText -notmatch 'const etxLz4Font') { return $false }
    if ($xsText -notmatch 'const etxLz4Font') { return $false }
    if ($boldText -notmatch '\.cmap_num = 6,') { return $false }
    if ($xsText -notmatch '\.cmap_num = 6,') { return $false }
    return $true
}

function Get-EdgeTxDisplayAssetRow {
    param([string]$Resolution)
    $status = Get-DisplayAssetStatus $Resolution
    $parts = $Resolution.Split("x")
    $w = [int]$parts[0]
    $h = [int]$parts[1]
    $fontDir = Get-EdgeTxFontDirName -Width $w -Height $h
    $protected = Test-EdgeTxResolutionProtected $Resolution

    if ($protected) {
        $bmpState = "stock"
        $fntState = "stock"
    } else {
        $bmpState = if ($status.BitmapsReady) { "ok" } else { "missing" }
        $fontProbe = Join-Path (Join-Path (Join-Path $script:GeneratedRoot "fonts\lvgl") $fontDir) "lv_font_en_STD.c"
        if (-not (Test-Path $fontProbe)) {
            $fntState = "missing"
        } elseif (Test-EdgeTxFontTierValid $fontDir) {
            $fntState = "ok"
        } else {
            $fntState = "partial"
        }
    }

    return @{
        Resolution = $Resolution
        BitmapsState = $bmpState
        FontsState = $fntState
        IsProtected = $protected
        AssetStatus = $status
        FontDir = $fontDir
    }
}

function Get-EdgeTxKnownResolutions {
    $bitmapRoot = Join-Path $script:GeneratedRoot "bitmaps"
    $fromDisk = @()
    if (Test-Path $bitmapRoot) {
        $fromDisk += @(Get-ChildItem $bitmapRoot -Directory | ForEach-Object {
            if ($_.Name -match '^(\d+)x(\d+)$') {
                $w = [int]$Matches[1]
                $h = [int]$Matches[2]
                if ($w -gt $h -and $w -ge 320 -and $h -ge 240 -and $w -le 3840 -and $h -le 2160) {
                    $probe = Join-Path $_.FullName "mask_icon_edgetx.png"
                    if (Test-Path $probe) { $_.Name }
                }
            }
        })
    }
    $saved = @(Read-EdgeTxSavedResolutions)
    $all = @("800x480") + $fromDisk + $saved
    @($all | Select-Object -Unique | ForEach-Object {
        if ($_ -match '^(\d+)x(\d+)$') {
            [PSCustomObject]@{ Res = $_; W = [int]$Matches[1]; H = [int]$Matches[2] }
        }
    } | Sort-Object W, H | ForEach-Object { $_.Res })
}

function Add-EdgeTxDisplayResolution {
    param([string]$Resolution)
    $null = Test-ResolutionString $Resolution
    $saved = @(Read-EdgeTxSavedResolutions)
    if ($saved -notcontains $Resolution) {
        $saved += $Resolution
        Write-EdgeTxSavedResolutions $saved
    }
}

function Remove-EdgeTxDisplayAssets {
    param(
        [string]$Resolution,
        [switch]$IncludeBuildDirs
    )
    if (Test-EdgeTxResolutionProtected $Resolution) {
        throw "800x480 uses stock upstream colorlcd assets and cannot be deleted."
    }
    $null = Test-ResolutionString $Resolution
    $parts = $Resolution.Split("x")
    $w = [int]$parts[0]
    $h = [int]$parts[1]

    $bitmapDir = Join-Path (Join-Path $script:GeneratedRoot "bitmaps") $Resolution
    $fontDirName = Get-EdgeTxFontDirName -Width $w -Height $h
    $fontDir = Join-Path (Join-Path $script:GeneratedRoot "fonts\lvgl") $fontDirName

    $removed = @()
    if (Test-Path $bitmapDir) {
        Remove-Item $bitmapDir -Recurse -Force
        $removed += $bitmapDir
    }
    if ($fontDirName -ne "lrg" -and (Test-Path $fontDir)) {
        Remove-Item $fontDir -Recurse -Force
        $removed += $fontDir
    }
    if ($IncludeBuildDirs) {
        foreach ($path in @(
            (Join-Path $script:AppRoot "build-android-arm64"),
            (Join-Path $script:AppRoot "build-android-x86_64"),
            (Join-Path $script:AppRoot "app\src\main\jniLibs\arm64-v8a\libedgetx_sim.a"),
            (Join-Path $script:AppRoot "app\src\main\jniLibs\x86_64\libedgetx_sim.a")
        )) {
            if (Test-Path $path) {
                Remove-Item $path -Recurse -Force
                $removed += $path
            }
        }
    }
    Remove-EdgeTxDisplayResolutionEntry $Resolution
    return $removed
}

function Remove-EdgeTxDisplayResolutionEntry {
    param([string]$Resolution)
    if (Test-EdgeTxResolutionProtected $Resolution) { return }
    $saved = @(Read-EdgeTxSavedResolutions) | Where-Object { $_ -ne $Resolution }
    Write-EdgeTxSavedResolutions $saved
}

function Format-EdgeTxExceptionMessage {
    param($ErrorRecord)
    if ($ErrorRecord -is [System.AggregateException]) {
        return (($ErrorRecord.InnerExceptions | ForEach-Object {
            if ($_.InnerException) { $_.InnerException.Message } else { $_.Message }
        }) | Where-Object { $_ }) -join "`n"
    }
    if ($ErrorRecord -is [Exception]) {
        if ($ErrorRecord.InnerException) { return $ErrorRecord.InnerException.Message }
        return $ErrorRecord.Message
    }
    if ($ErrorRecord.Exception) {
        return Format-EdgeTxExceptionMessage $ErrorRecord.Exception
    }
    return "$ErrorRecord"
}

function Format-EdgeTxScriptInvocation {
    param(
        [string]$ScriptPath,
        [hashtable]$Params
    )
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Params.Keys | Sort-Object)) {
        $val = $Params[$key]
        if ($val -is [switch]) {
            if ($val.IsPresent) { $parts.Add("-$key") | Out-Null }
        } elseif ($val -is [bool]) {
            if ($val) { $parts.Add("-$key") | Out-Null }
        } else {
            $parts.Add("-$key") | Out-Null
            $parts.Add([string]$val) | Out-Null
        }
    }
    return "$ScriptPath $($parts -join ' ')"
}

function Invoke-EdgeTxBuildScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Params = @{},
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )
    Write-BuildLog ("Run: " + (Format-EdgeTxScriptInvocation $ScriptPath $Params)) $OnLog
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        Push-Location $script:AppRoot
        & $ScriptPath @Params 2>&1 | ForEach-Object {
            Write-BuildLog (Format-BuildOutputLine $_) $OnLog
            if ($OnProgress) { & $OnProgress }
        }
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Script failed (exit $exitCode): $ScriptPath"
        }
    } catch {
        $msg = if ($_.Exception -and $_.Exception.Message) { $_.Exception.Message } else { "$_" }
        if (-not $msg) { $msg = "Unknown error running $ScriptPath" }
        throw $msg
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEap
    }
}

function Install-EdgeTxTool {
    param(
        [string]$ToolId,
        [scriptblock]$OnLog
    )
    $p = Get-EdgeTxPaths
    $t = $script:ToolsDir
    New-Item -ItemType Directory -Force -Path $t | Out-Null

    switch ($ToolId) {
        "pillow" { Write-BuildLog "pip install pillow ..." $OnLog; python -m pip install pillow; return }
        "libclang" { Write-BuildLog "pip install libclang ..." $OnLog; python -m pip install libclang; return }
        "lz4" { Write-BuildLog "pip install lz4 ..." $OnLog; python -m pip install lz4; return }
        "cmake" {
            $ver = $script:ToolchainVersions.CmakeVersion
            $zip = Join-Path $t "cmake-$ver-win.zip"
            $url = "https://github.com/Kitware/CMake/releases/download/v$ver/cmake-$ver-windows-x86_64.zip"
            $extract = Join-Path $t "_extract_cmake"
            Invoke-DownloadAndExpand $url $zip $extract $OnLog
            $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
            $dest = Join-Path $t "cmake-$ver-windows-x86_64"
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Move-Item $inner.FullName $dest
            Remove-Item $extract -Recurse -Force
            Write-BuildLog "CMake -> $dest" $OnLog
            return
        }
        "ninja" {
            $zip = Join-Path $t "ninja-win.zip"
            $url = "https://github.com/ninja-build/ninja/releases/download/v$($script:ToolchainVersions.NinjaVersion)/ninja-win.zip"
            $extract = Join-Path $t "_extract_ninja"
            Invoke-DownloadAndExpand $url $zip $extract $OnLog
            $exe = Get-ChildItem $extract -Recurse -Filter "ninja.exe" | Select-Object -First 1
            Copy-Item $exe.FullName (Join-Path $t "ninja.exe") -Force
            Remove-Item $extract -Recurse -Force
            Write-BuildLog "Ninja -> $($p.NinjaExe)" $OnLog
            return
        }
        "jdk" {
            $zip = Join-Path $t "jdk-17.zip"
            $ver = $script:ToolchainVersions.JdkVersion
            $url = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-$([uri]::EscapeDataString($ver))/OpenJDK17U-jdk_x64_windows_hotspot_$($ver.Replace('+','_')).zip"
            $extract = Join-Path $t "_extract_jdk"
            Invoke-DownloadAndExpand $url $zip $extract $OnLog
            $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
            $dest = Join-Path $t $inner.Name
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Move-Item $inner.FullName $dest
            Remove-Item $extract -Recurse -Force
            Write-BuildLog "JDK -> $dest" $OnLog
            return
        }
        "gradle" {
            $ver = $script:ToolchainVersions.GradleVersion
            $zip = Join-Path $t "gradle-$ver-bin.zip"
            $url = "https://services.gradle.org/distributions/gradle-$ver-bin.zip"
            $extract = Join-Path $t "_extract_gradle"
            Invoke-DownloadAndExpand $url $zip $extract $OnLog
            $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
            $dest = Join-Path $t "gradle-$ver"
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Move-Item $inner.FullName $dest
            Remove-Item $extract -Recurse -Force
            Write-BuildLog "Gradle -> $dest" $OnLog
            return
        }
        "sdk" {
            $plat = $script:ToolchainVersions.SdkPlatform
            $bt = $script:ToolchainVersions.BuildTools
            Install-EdgeTxAndroidSdk -ComponentsOnly @(
                "platform-tools",
                "platforms;$plat",
                "build-tools;$bt"
            ) -OnLog $OnLog
            return
        }
        "ndk" {
            $ndk = $script:ToolchainVersions.NdkVersion
            Install-EdgeTxAndroidSdk -ComponentsOnly @("ndk;$ndk") -OnLog $OnLog
            return
        }
        "resvg" {
            & (Join-Path $script:AppRoot "scripts\ensure-resvg.ps1") -OnLog $OnLog
            return
        }
        "fonttools" {
            & (Join-Path $script:AppRoot "scripts\ensure-font-tools.ps1") -OnLog $OnLog
            return
        }
        default { throw "Unknown tool id: $ToolId" }
    }
}

function Install-EdgeTxAndroidSdk {
    param(
        [string[]]$ComponentsOnly,
        [scriptblock]$OnLog
    )
    $p = Get-EdgeTxPaths
    $sdk = $p.SdkRoot
    $t = $script:ToolsDir
    New-Item -ItemType Directory -Force -Path $sdk | Out-Null

    $cmdTools = Join-Path $sdk "cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not (Test-Path $cmdTools)) {
        $zip = Join-Path $t "cmdline-tools-win.zip"
        $url = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
        $extract = Join-Path $t "_extract_cmdline"
        Invoke-DownloadAndExpand $url $zip $extract $OnLog
        $dest = Join-Path $sdk "cmdline-tools\latest"
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
        Move-Item $inner.FullName $dest
        Remove-Item $extract -Recurse -Force
        Write-BuildLog "Android cmdline-tools -> $dest" $OnLog
    }

    $env:ANDROID_SDK_ROOT = $sdk
    $env:ANDROID_HOME = $sdk
    Write-BuildLog "sdkmanager: $($ComponentsOnly -join ', ')" $OnLog
    Write-BuildLog "Large packages (esp. NDK ~1.5 GB) may take a long time; progress lines from sdkmanager follow..." $OnLog

    $yes = "y`n" * 20
    $yes | & $cmdTools --sdk_root=$sdk @ComponentsOnly 2>&1 | ForEach-Object {
        Write-BuildLog $_ $OnLog
    }
    if ($LASTEXITCODE -ne 0) { throw "sdkmanager failed ($LASTEXITCODE)" }
}

function Install-EdgeTxMissingTools {
    param([scriptblock]$OnLog)
    $status = Get-EdgeTxToolStatus
    foreach ($tool in $status) {
        if ($tool.Ok) { continue }
        if (-not $tool.Installable) {
            Write-BuildLog "Install manually: $($tool.Name)" $OnLog
            continue
        }
        if ($tool.Id -eq "python") { continue }
        Write-BuildLog ">>> Installing $($tool.Name) ..." $OnLog
        Install-EdgeTxTool -ToolId $tool.Id -OnLog $OnLog
    }
}

function Format-BuildOutputLine {
    param($Item)
    if ($Item -is [System.Management.Automation.ErrorRecord]) {
        if ($Item.Exception -and $Item.Exception.Message) { return $Item.Exception.Message }
        return $Item.ToString()
    }
    return "$Item"
}

function Invoke-EdgeTxNativeBuild {
    param(
        [string]$Display,
        [switch]$ForceAssets,
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )
    $scriptPath = Join-Path (Join-Path $script:AppRoot "scripts") "build-android-native.ps1"
    $params = @{ Display = $Display }
    if ($ForceAssets) { $params.ForceAssets = $true }
    Invoke-EdgeTxBuildScript -ScriptPath $scriptPath -Params $params -OnLog $OnLog -OnProgress $OnProgress
}

function Invoke-EdgeTxApkBuild {
    param(
        [string]$Display = "2400x1440",
        [scriptblock]$OnLog,
        [scriptblock]$OnProgress
    )
    $scriptPath = Join-Path (Join-Path $script:AppRoot "scripts") "build-apk.ps1"
    $params = @{ Display = $Display }
    Invoke-EdgeTxBuildScript -ScriptPath $scriptPath -Params $params -OnLog $OnLog -OnProgress $OnProgress
}
