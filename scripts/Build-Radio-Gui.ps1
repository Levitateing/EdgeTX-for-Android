# EdgeTX ANDROID radio firmware build wizard (GUI).
# Layout mirrors Build-EdgeTX-Gui.ps1. Prefer launch: Build-Radio-GUI.pyw
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\GuiDialogs.ps1")

$paths = Get-EdgeTxPaths
$script:IsBusy = $false
$script:BuildProc = $null
$script:LogFile = $null
$script:LogOffset = 0L
$script:BuildHw = "TX16S"

$script:Strings = @{
    en = @{
        Title             = "EdgeTX Radio Firmware Build"
        LanguageLabel     = "语言"
        SectionEnv        = "[1] Environment && toolchain"
        SectionBoard      = "[2] Board && output"
        SectionLog        = "[3] Build log"
        BtnRecheck        = "Re-check"
        BtnInstall        = "Install missing"
        BtnOpenOut        = "Open output"
        BtnBuild          = "Start build"
        BtnClose          = "Close"
        ColComponent      = "Component"
        ColStatus         = "Status"
        ColPath           = "Path / note"
        ColSize           = "Size"
        ColBoard          = "Board"
        ColSoc            = "SoC"
        ColOutput         = "Output file"
        ColArtifact       = "Artifact"
        StatusOk          = "OK"
        StatusMissing     = "MISSING"
        ToolsHint         = "Radio build needs ARM GCC + CMake + Ninja (+ Python/libclang for codegen). Tools go under .tools."
        BoardHint         = "TX16S = F429 trial radio. H750 = MK3-class — do NOT flash H750 firmware to F429. Output is staged next to EdgeTX.apk."
        LogReady          = "Radio firmware wizard ready."
        LogToolsDir       = "Tools dir: {0}"
        LogMissingInit    = "{0} missing item(s) — use Install missing."
        LogEnvOk          = "Environment OK. Select a board and Start build."
        LogEnvCheck       = "=== Environment check ==="
        LogAllReady       = "All required tools ready."
        LogMissingItems   = "{0} item(s) missing. Click Install missing."
        LogInstallStart   = "=== Installing missing tools ==="
        LogInstallDone    = "=== Install pass finished ==="
        LogInstallFailed  = "Install failed: {0}"
        LogBuildStart     = "=== Radio build start {0} @ {1} ==="
        LogSucceeded      = "=== Build SUCCEEDED ==="
        LogFailed         = "=== Build FAILED (exit {0}) ==="
        MsgNothingInstall = "Nothing to install."
        MsgInstallTitle   = "Confirm install"
        MsgInstallBody    = "The following will be downloaded into radio\src\targets\android\.tools (or pip):`n`n{0}`n`nContinue?"
        MsgCannotBuild    = "{0} required tool(s) missing. Install them first."
        MsgNoBoard        = "Select a board from the list first."
        MsgBuildTitle     = "Confirm build"
        MsgBuildBody      = @"
Start radio firmware build?

  PCB = ANDROID
  ANDROID_HW = {0}
  Overlay apply + restore = yes

  Output: output\firmware-{1}.bin
  Typical time: 5–15 min

Continue?
"@
        MsgSuccessTitle   = "Success"
        MsgSuccessBody    = "Build completed.`n`n{0}"
        MsgSuccessMissing = "Build ok, but output\firmware-{0}.bin is missing — check the log."
        MsgBuildFailed    = "Build failed"
        MsgInstallFailed  = "Install failed"
        MsgBusyTitle      = "Busy"
        MsgBusyBody       = "Build still running. Exit anyway?"
        MsgGccMissing     = "ARM GCC missing"
        ErrFatal          = "Fatal error"
        BoardTx16sNote    = "F429 trial (your TX16S)"
        BoardH750Note     = "MK3-class (not for F429)"
    }
    zh = @{
        Title             = "EdgeTX 遥控固件编译工具"
        LanguageLabel     = "Language"
        SectionEnv        = "[1] 环境 && 工具链"
        SectionBoard      = "[2] 板型 && 产物"
        SectionLog        = "[3] 编译日志"
        BtnRecheck        = "重新检测"
        BtnInstall        = "安装缺失项"
        BtnOpenOut        = "打开产物目录"
        BtnBuild          = "开始编译"
        BtnClose          = "关闭"
        ColComponent      = "组件"
        ColStatus         = "状态"
        ColPath           = "路径 / 说明"
        ColSize           = "大小"
        ColBoard          = "板型"
        ColSoc            = "SoC"
        ColOutput         = "产物文件"
        ColArtifact       = "产物状态"
        StatusOk          = "OK"
        StatusMissing     = "缺失"
        ToolsHint         = "遥控固件需要 ARM GCC + CMake + Ninja（以及 Python/libclang 做代码生成）。工具安装到 .tools。"
        BoardHint         = "TX16S = F429 试验机。H750 = MK3 类 —— 切勿把 H750 固件刷进 F429。产物与 EdgeTX.apk 同目录。"
        LogReady          = "遥控固件编译向导已就绪。"
        LogToolsDir       = "工具目录: {0}"
        LogMissingInit    = "缺少 {0} 项 — 请点「安装缺失项」。"
        LogEnvOk          = "环境正常。选择板型后点「开始编译」。"
        LogEnvCheck       = "=== 环境检测 ==="
        LogAllReady       = "所需工具已就绪。"
        LogMissingItems   = "缺少 {0} 项。请点「安装缺失项」。"
        LogInstallStart   = "=== 开始安装缺失工具 ==="
        LogInstallDone    = "=== 安装流程结束 ==="
        LogInstallFailed  = "安装失败: {0}"
        LogBuildStart     = "=== 开始编译 {0} @ {1} ==="
        LogSucceeded      = "=== 编译成功 ==="
        LogFailed         = "=== 编译失败 (exit {0}) ==="
        MsgNothingInstall = "没有需要安装的项目。"
        MsgInstallTitle   = "确认安装"
        MsgInstallBody    = "将下载到 radio\src\targets\android\.tools（或 pip）：`n`n{0}`n`n继续？"
        MsgCannotBuild    = "缺少 {0} 项必需工具，请先安装。"
        MsgNoBoard        = "请先在列表中选择板型。"
        MsgBuildTitle     = "确认编译"
        MsgBuildBody      = @"
开始编译遥控固件？

  PCB = ANDROID
  ANDROID_HW = {0}
  Overlay 应用 + 还原 = 是

  产物: output\firmware-{1}.bin
  预计: 5–15 分钟

继续？
"@
        MsgSuccessTitle   = "成功"
        MsgSuccessBody    = "编译完成。`n`n{0}"
        MsgSuccessMissing = "编译成功，但未找到 output\firmware-{0}.bin — 请查看日志。"
        MsgBuildFailed    = "编译失败"
        MsgInstallFailed  = "安装失败"
        MsgBusyTitle      = "忙碌中"
        MsgBusyBody       = "仍在编译。确定退出？"
        MsgGccMissing     = "缺少 ARM GCC"
        ErrFatal          = "致命错误"
        BoardTx16sNote    = "F429 试验机（你的 TX16S）"
        BoardH750Note     = "MK3 类（勿刷 F429）"
    }
}

$initLang = $env:EDGETX_BUILD_LANG
if ($initLang -ne "en" -and $initLang -ne "zh") { $initLang = "zh" }
$script:Lang = $initLang

function T([string]$Key) {
    return $script:Strings[$script:Lang][$Key]
}

function New-Label($text, $x, $y, $w = 200, $h = 22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    return $l
}

function Get-RadioToolStatus {
    $p = Get-EdgeTxPaths
    $gcc = Find-ArmNoneEabiGcc
    $gccOk = [bool]$gcc
    $gccPath = if ($gcc) { $gcc } else { $p.ArmGccExe }
    @(
        @{ Id = "python"; Name = "Python 3"; Required = $true
           Scope = "system PATH"; Path = (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
           Ok = [bool](Get-Command python -ErrorAction SilentlyContinue)
           Installable = $false; SizeHint = "" },
        @{ Id = "libclang"; Name = "Python: libclang"; Required = $true
           Scope = "pip"; Path = ""
           Ok = (Test-PythonModule "clang"); Installable = $true; SizeHint = "~30 MB" },
        @{ Id = "cmake"; Name = "CMake $($script:ToolchainVersions.CmakeVersion)"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.CmakeExe
           Ok = (Test-Path $p.CmakeExe); Installable = $true; SizeHint = "~45 MB" },
        @{ Id = "ninja"; Name = "Ninja"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $p.NinjaExe
           Ok = (Test-Path $p.NinjaExe); Installable = $true; SizeHint = "~0.3 MB" },
        @{ Id = "armgcc"; Name = "ARM GCC (arm-none-eabi)"; Required = $true
           Scope = "radio\src\targets\android\.tools"; Path = $gccPath
           Ok = $gccOk; Installable = $true; SizeHint = "~200 MB" }
    )
}

function Append-Log([string]$line) {
    $box = $script:UiLog
    if ($null -eq $box) { $box = $txtLog }
    if ($null -eq $box) { return }
    if ($box.InvokeRequired) {
        $box.BeginInvoke([Action[string]]{ param($s) Append-Log $s }, $line) | Out-Null
        return
    }
    $box.AppendText("$line`r`n")
    $box.SelectionStart = $box.Text.Length
    $box.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = T "Title"
$form.Size = New-Object System.Drawing.Size(920, 760)
$form.StartPosition = "CenterScreen"
Set-GuiMainForm $form
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.MinimumSize = New-Object System.Drawing.Size(820, 640)

$lblLang = New-Label "" 0 12 76 22
$lblLang.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblLang.Anchor = "Top,Right"
$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(0, 8)
$cmbLang.Size = New-Object System.Drawing.Size(100, 24)
$cmbLang.DropDownStyle = "DropDownList"
$cmbLang.Anchor = "Top,Right"
[void]$cmbLang.Items.AddRange(@("English", "中文"))
$cmbLang.SelectedIndex = if ($script:Lang -eq "en") { 0 } else { 1 }
$lblLang.Text = T "LanguageLabel"

$lblSection1 = New-Label (T "SectionEnv") 12 36 420
$btnCheckEnv = New-Object System.Windows.Forms.Button
$btnCheckEnv.Text = T "BtnRecheck"
$btnCheckEnv.Location = New-Object System.Drawing.Point(12, 60)
$btnCheckEnv.Size = New-Object System.Drawing.Size(100, 28)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = T "BtnInstall"
$btnInstall.Location = New-Object System.Drawing.Point(120, 60)
$btnInstall.Size = New-Object System.Drawing.Size(120, 28)

$lvTools = New-Object System.Windows.Forms.ListView
$lvTools.Location = New-Object System.Drawing.Point(12, 96)
$lvTools.Size = New-Object System.Drawing.Size(880, 140)
$lvTools.View = "Details"
$lvTools.FullRowSelect = $true
$lvTools.GridLines = $true
$lvTools.Anchor = "Top,Left,Right"
$colComponent = New-Object System.Windows.Forms.ColumnHeader
$colComponent.Text = T "ColComponent"
$colComponent.Width = 200
$colStatus = New-Object System.Windows.Forms.ColumnHeader
$colStatus.Text = T "ColStatus"
$colStatus.Width = 80
$colPath = New-Object System.Windows.Forms.ColumnHeader
$colPath.Text = T "ColPath"
$colPath.Width = 480
$colSize = New-Object System.Windows.Forms.ColumnHeader
$colSize.Text = T "ColSize"
$colSize.Width = 90
$lvTools.Columns.AddRange(@($colComponent, $colStatus, $colPath, $colSize))

$lblToolsHint = New-Label (T "ToolsHint") 12 240 880 36
$lblToolsHint.ForeColor = [System.Drawing.Color]::DimGray

$lblSection2 = New-Label (T "SectionBoard") 12 280 420
$lvBoard = New-Object System.Windows.Forms.ListView
$lvBoard.Location = New-Object System.Drawing.Point(12, 304)
$lvBoard.Size = New-Object System.Drawing.Size(880, 90)
$lvBoard.View = "Details"
$lvBoard.FullRowSelect = $true
$lvBoard.GridLines = $true
$lvBoard.HideSelection = $false
$lvBoard.MultiSelect = $false
$lvBoard.Anchor = "Top,Left,Right"
$colBoard = New-Object System.Windows.Forms.ColumnHeader
$colBoard.Text = T "ColBoard"
$colBoard.Width = 90
$colSoc = New-Object System.Windows.Forms.ColumnHeader
$colSoc.Text = T "ColSoc"
$colSoc.Width = 220
$colOutput = New-Object System.Windows.Forms.ColumnHeader
$colOutput.Text = T "ColOutput"
$colOutput.Width = 200
$colArtifact = New-Object System.Windows.Forms.ColumnHeader
$colArtifact.Text = T "ColArtifact"
$colArtifact.Width = 320
$lvBoard.Columns.AddRange(@($colBoard, $colSoc, $colOutput, $colArtifact))

$btnOpenOut = New-Object System.Windows.Forms.Button
$btnOpenOut.Text = T "BtnOpenOut"
$btnOpenOut.Location = New-Object System.Drawing.Point(12, 402)
$btnOpenOut.Size = New-Object System.Drawing.Size(130, 28)

$lblBoardHint = New-Label (T "BoardHint") 150 406 740 36
$lblBoardHint.ForeColor = [System.Drawing.Color]::DimGray

$lblSection3 = New-Label (T "SectionLog") 12 446 200
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(12, 470)
$txtLog.Size = New-Object System.Drawing.Size(880, 170)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Anchor = "Top,Bottom,Left,Right"

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 648)
$progress.Size = New-Object System.Drawing.Size(880, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Style = "Continuous"
$progress.Visible = $false
$progress.Anchor = "Bottom,Left,Right"

$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = T "BtnBuild"
$btnBuild.Location = New-Object System.Drawing.Point(12, 676)
$btnBuild.Size = New-Object System.Drawing.Size(120, 34)
$btnBuild.Anchor = "Bottom,Left"

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = T "BtnClose"
$btnClose.Location = New-Object System.Drawing.Point(772, 676)
$btnClose.Size = New-Object System.Drawing.Size(120, 34)
$btnClose.Anchor = "Bottom,Right"

$form.Controls.AddRange(@(
    $lblLang, $cmbLang, $lblSection1,
    $btnCheckEnv, $btnInstall, $lvTools, $lblToolsHint,
    $lblSection2, $lvBoard, $btnOpenOut, $lblBoardHint,
    $lblSection3, $txtLog, $progress, $btnBuild, $btnClose
))

# Keep UI refs in $script: so Timer event closures never see $null locals.
$script:UiForm = $form
$script:UiLog = $txtLog
$script:UiProgress = $progress
$script:UiPaths = $paths
$script:LogTailTimer = $null
$script:LogTailFinishing = $false

$script:BuildProgressTimer = New-Object System.Windows.Forms.Timer
$script:BuildProgressTimer.Interval = 250
$script:BuildProgressPulse = 5
$script:BuildProgressCap = 80
$script:BuildProgressTimer.Add_Tick({
    try {
        if (-not $script:IsBusy) { return }
        if ($null -eq $script:UiProgress) { return }
        if ($script:BuildProgressPulse -lt $script:BuildProgressCap) {
            $script:BuildProgressPulse += 1
            $script:UiProgress.Value = [Math]::Min(100, $script:BuildProgressPulse)
        }
    } catch { }
})

function Update-LanguageLayout {
    $margin = 12
    $comboW = 100
    $labelW = 76
    $gap = 8
    $clientW = $form.ClientSize.Width
    $cmbLang.Width = $comboW
    $cmbLang.Location = New-Object System.Drawing.Point(($clientW - $margin - $comboW), 8)
    $lblLang.Width = $labelW
    $lblLang.Location = New-Object System.Drawing.Point(($clientW - $margin - $comboW - $gap - $labelW), 12)
}

function Update-BottomLayout {
    $margin = 12
    $btnH = 34
    $progH = 20
    $gap = 8
    $clientH = $form.ClientSize.Height
    $clientW = $form.ClientSize.Width
    $btnY = $clientH - $margin - $btnH
    $progY = $btnY - $gap - $progH
    $btnBuild.Location = New-Object System.Drawing.Point($margin, $btnY)
    $btnClose.Location = New-Object System.Drawing.Point(($clientW - $margin - $btnClose.Width), $btnY)
    $progress.Location = New-Object System.Drawing.Point($margin, $progY)
    $progress.Width = $clientW - (2 * $margin)
    $txtLog.Height = [Math]::Max(80, $progY - $gap - $txtLog.Top)
    $txtLog.Width = $clientW - (2 * $margin)
    $lvTools.Width = $clientW - (2 * $margin)
    $lvBoard.Width = $clientW - (2 * $margin)
}

function Set-Busy([bool]$busy) {
    $script:IsBusy = $busy
    $btnCheckEnv.Enabled = -not $busy
    $btnInstall.Enabled = -not $busy
    $btnOpenOut.Enabled = -not $busy
    $btnBuild.Enabled = -not $busy
    $lvBoard.Enabled = -not $busy
    $cmbLang.Enabled = -not $busy
    if ($null -ne $script:UiProgress) {
        $script:UiProgress.Visible = $busy
        if ($busy) {
            $script:BuildProgressPulse = 5
            $script:BuildProgressCap = 85
            $script:UiProgress.Value = 5
            $script:BuildProgressTimer.Start()
        } else {
            $script:BuildProgressTimer.Stop()
            $script:UiProgress.Value = 0
        }
    }
    $form.Cursor = if ($busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
}

function Update-ToolList {
    $lvTools.Items.Clear()
    foreach ($t in Get-RadioToolStatus) {
        $item = New-Object System.Windows.Forms.ListViewItem($t.Name)
        [void]$item.SubItems.Add($(if ($t.Ok) { T "StatusOk" } else { T "StatusMissing" }))
        $detail = if ($t.Path) { $t.Path } else { $t.Scope }
        if ($t.SizeHint -and -not $t.Ok) { $detail += " [$($t.SizeHint)]" }
        [void]$item.SubItems.Add($detail)
        [void]$item.SubItems.Add($(if ($t.SizeHint) { $t.SizeHint } else { "" }))
        if (-not $t.Ok) { $item.ForeColor = [System.Drawing.Color]::DarkRed }
        $item.Tag = $t
        [void]$lvTools.Items.Add($item)
    }
}

function Update-BoardList {
    param([string]$SelectHw)
    $prev = if ($lvBoard.SelectedItems.Count -gt 0) { $lvBoard.SelectedItems[0].Text } else { $null }
    $lvBoard.Items.Clear()
    $boards = @(
        @{ Hw = "TX16S"; Soc = (T "BoardTx16sNote"); Out = "firmware-tx16s.bin" },
        @{ Hw = "H750";  Soc = (T "BoardH750Note");  Out = "firmware-h750.bin" }
    )
    foreach ($b in $boards) {
        $path = Join-Path $paths.OutputDir $b.Out
        $art = if (Test-Path $path) {
            $fi = Get-Item $path
            "{0}  ({1:N1} MB, {2})" -f (T "StatusOk"), ($fi.Length / 1MB), $fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        } else {
            T "StatusMissing"
        }
        $item = New-Object System.Windows.Forms.ListViewItem($b.Hw)
        [void]$item.SubItems.Add($b.Soc)
        [void]$item.SubItems.Add($b.Out)
        [void]$item.SubItems.Add($art)
        if (-not (Test-Path $path)) { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
        $item.Tag = $b.Hw
        [void]$lvBoard.Items.Add($item)
    }
    $pick = if ($SelectHw) { $SelectHw } elseif ($prev) { $prev } else { "TX16S" }
    foreach ($item in $lvBoard.Items) {
        if ($item.Text -eq $pick) {
            $item.Selected = $true
            $item.Focused = $true
            $lvBoard.EnsureVisible($item.Index)
            break
        }
    }
}

function Get-SelectedHw {
    if ($lvBoard.SelectedItems.Count -eq 0) { return $null }
    return [string]$lvBoard.SelectedItems[0].Tag
}

function Apply-UiLanguage {
    $form.Text = T "Title"
    $lblLang.Text = T "LanguageLabel"
    $lblSection1.Text = T "SectionEnv"
    $lblSection2.Text = T "SectionBoard"
    $lblSection3.Text = T "SectionLog"
    $btnCheckEnv.Text = T "BtnRecheck"
    $btnInstall.Text = T "BtnInstall"
    $btnOpenOut.Text = T "BtnOpenOut"
    $btnBuild.Text = T "BtnBuild"
    $btnClose.Text = T "BtnClose"
    $colComponent.Text = T "ColComponent"
    $colStatus.Text = T "ColStatus"
    $colPath.Text = T "ColPath"
    $colSize.Text = T "ColSize"
    $colBoard.Text = T "ColBoard"
    $colSoc.Text = T "ColSoc"
    $colOutput.Text = T "ColOutput"
    $colArtifact.Text = T "ColArtifact"
    $lblToolsHint.Text = T "ToolsHint"
    $lblBoardHint.Text = T "BoardHint"
    Update-ToolList
    Update-BoardList
    Update-LanguageLayout
}

function Refresh-EnvStatus {
    Append-Log (T "LogEnvCheck")
    Update-ToolList
    Update-BoardList
    $missing = @(Get-RadioToolStatus | Where-Object { $_.Required -and -not $_.Ok })
    if ($missing.Count -eq 0) {
        Append-Log (T "LogAllReady")
        Append-Log (T "LogEnvOk")
    } else {
        Append-Log ((T "LogMissingItems") -f $missing.Count)
    }
}

$cmbLang.Add_SelectedIndexChanged({
    if ($script:IsBusy) { return }
    $script:Lang = if ($cmbLang.SelectedIndex -eq 0) { "en" } else { "zh" }
    $env:EDGETX_BUILD_LANG = $script:Lang
    Apply-UiLanguage
})

$btnCheckEnv.Add_Click({
    if ($script:IsBusy) { return }
    Refresh-EnvStatus
})

$btnInstall.Add_Click({
    if ($script:IsBusy) { return }
    $missing = @(Get-RadioToolStatus | Where-Object { -not $_.Ok -and $_.Installable })
    if ($missing.Count -eq 0) {
        Show-GuiMessageBox ((T "MsgNothingInstall")) ((T "Title")) ("OK") ("Information") | Out-Null
        return
    }
    $list = ($missing | ForEach-Object { "  - $($_.Name) $($_.SizeHint)" }) -join "`n"
    $r = Show-GuiMessageBox (((T "MsgInstallBody") -f $list)) ((T "MsgInstallTitle")) ("YesNo") ("Question")
    if ($r -ne "Yes") { return }

    Set-Busy $true
    try {
        Append-Log (T "LogInstallStart")
        foreach ($t in $missing) {
            Append-Log ">>> $($t.Name)"
            if ($t.Id -eq "armgcc") {
                $ens = Join-Path $PSScriptRoot "ensure-arm-gcc.ps1"
                & $ens 2>&1 | ForEach-Object { Append-Log "$_" }
            } else {
                Install-EdgeTxTool -ToolId $t.Id -OnLog { param($m) Append-Log $m }
            }
        }
        Append-Log (T "LogInstallDone")
        Update-ToolList
    } catch {
        Append-Log ((T "LogInstallFailed") -f $_.Exception.Message)
        Show-GuiMessageBox ($_.Exception.Message) ((T "MsgInstallFailed")) ("OK") ("Error") | Out-Null
    } finally {
        Set-Busy $false
    }
})

$btnOpenOut.Add_Click({
    $dir = $paths.OutputDir
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Start-Process explorer.exe $dir
})

function Start-RadioBuild {
    if ($script:IsBusy) { return }
    $hw = Get-SelectedHw
    if (-not $hw) {
        Show-GuiMessageBox ((T "MsgNoBoard")) ((T "Title")) ("OK") ("Warning") | Out-Null
        return
    }
    $missing = @(Get-RadioToolStatus | Where-Object { $_.Required -and -not $_.Ok })
    if ($missing.Count -gt 0) {
        Show-GuiMessageBox (((T "MsgCannotBuild") -f $missing.Count)) ((T "Title")) ("OK") ("Warning") | Out-Null
        return
    }

    $hwTag = $hw.ToLower()
    $confirm = (T "MsgBuildBody") -f $hw, $hwTag
    if (Show-GuiMessageBox ($confirm) ((T "MsgBuildTitle")) ("YesNo") ("Question") -ne "Yes") {
        return
    }

    Set-Busy $true
    $txtLog.Clear()
    Append-Log ((T "LogBuildStart") -f $hw, (Get-Date -Format "HH:mm:ss"))
    Append-Log "build-android-radio.ps1 -Hw $hw"
    Append-Log ""

    $buildScript = Join-Path $PSScriptRoot "build-android-radio.ps1"
    $logFile = Join-Path $env:TEMP ("edgetx-radio-build-" + $hwTag + ".log")
    [System.IO.File]::WriteAllText($logFile, "")
    $script:LogFile = $logFile
    $script:LogOffset = 0L
    $script:BuildHw = $hw

    # Temp wrapper: keep stderr from becoming a silent abort in the GUI host.
    $wrapper = Join-Path $env:TEMP ("edgetx-radio-build-" + $hwTag + "-run.ps1")
    $wrapperBody = @"
`$ErrorActionPreference = 'Continue'
`$buildScript = '$($buildScript.Replace("'", "''"))'
`$logFile = '$($logFile.Replace("'", "''"))'
& `$buildScript -Hw $hw *>&1 | ForEach-Object {
  `$line = if (`$_ -is [System.Management.Automation.ErrorRecord]) { `$_.ToString() } else { `$_.ToString() }
  Add-Content -LiteralPath `$logFile -Value `$line -Encoding UTF8
}
exit `$LASTEXITCODE
"@
    Set-Content -LiteralPath $wrapper -Value $wrapperBody -Encoding UTF8

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$wrapper`""
    $psi.WorkingDirectory = $paths.AndroidRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $script:BuildProc = $proc
    $script:LogTailFinishing = $false

    if ($null -ne $script:LogTailTimer) {
        try { $script:LogTailTimer.Stop() } catch { }
        try { $script:LogTailTimer.Dispose() } catch { }
        $script:LogTailTimer = $null
    }

    $script:LogTailTimer = New-Object System.Windows.Forms.Timer
    $script:LogTailTimer.Interval = 300
    $script:LogTailTimer.Add_Tick({
        # Entire tick must be fail-safe — WinForms surfaces unhandled PS exceptions as a dialog.
        try {
            if ($script:LogTailFinishing) { return }

            # Tail log while running / after exit
            try {
                if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
                    $fs = [System.IO.File]::Open($script:LogFile, "Open", "Read", "ReadWrite")
                    try {
                        if ($fs.Length -gt $script:LogOffset) {
                            $fs.Seek($script:LogOffset, "Begin") | Out-Null
                            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true, 4096, $true)
                            $chunk = $sr.ReadToEnd()
                            $sr.Close()
                            $script:LogOffset = $fs.Position
                            if ($chunk) {
                                foreach ($line in ($chunk -split "`r?`n")) {
                                    if ($line.Length -gt 0) { Append-Log $line }
                                }
                            }
                        }
                    } finally { $fs.Close() }
                }
            } catch { }

            $procAlive = $false
            try {
                if ($null -ne $script:BuildProc) {
                    $procAlive = -not $script:BuildProc.HasExited
                }
            } catch { $procAlive = $false }

            if ($procAlive) { return }

            # Build process finished — finalize once
            $script:LogTailFinishing = $true
            try {
                if ($null -ne $script:LogTailTimer) {
                    $script:LogTailTimer.Stop()
                }
            } catch { }

            # Brief settle for last log flush (non-blocking-ish; short sleep OK once)
            Start-Sleep -Milliseconds 150
            try {
                if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
                    $all = Get-Content -LiteralPath $script:LogFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                    if ($null -ne $all -and $all.Length -gt $script:LogOffset) {
                        $rest = $all.Substring([int][Math]::Min($script:LogOffset, $all.Length))
                        foreach ($line in ($rest -split "`r?`n")) {
                            if ($line.Length -gt 0) { Append-Log $line }
                        }
                    }
                }
            } catch { }

            $code = -1
            try {
                if ($null -ne $script:BuildProc) { $code = $script:BuildProc.ExitCode }
            } catch { }
            $script:BuildProc = $null

            try {
                if ($null -ne $script:LogTailTimer) {
                    $script:LogTailTimer.Dispose()
                }
            } catch { }
            $script:LogTailTimer = $null

            Append-Log ""
            $hwDone = $script:BuildHw
            if (-not $hwDone) { $hwDone = "TX16S" }
            $hwTagDone = $hwDone.ToLower()
            $outDir = if ($script:UiPaths) { $script:UiPaths.OutputDir } else { $paths.OutputDir }
            $outBin = Join-Path $outDir ("firmware-" + $hwTagDone + ".bin")

            if ($code -eq 0) {
                if ($null -ne $script:UiProgress) { $script:UiProgress.Value = 100 }
                Append-Log (T "LogSucceeded")
                Update-BoardList -SelectHw $hwDone
                $body = if (Test-Path -LiteralPath $outBin) {
                    (T "MsgSuccessBody") -f $outBin
                } else {
                    (T "MsgSuccessMissing") -f $hwTagDone
                }
                Show-GuiMessageBox ($body) ((T "MsgSuccessTitle")) ("OK") ("Information") | Out-Null
            } else {
                Append-Log ((T "LogFailed") -f $code)
                Show-GuiMessageBox (((T "LogFailed") -f $code)) ((T "MsgBuildFailed")) ("OK") ("Error") | Out-Null
            }
            Set-Busy $false
        } catch {
            try { Append-Log ("Timer error: " + $_.Exception.Message) } catch { }
            try { Set-Busy $false } catch { }
            $script:LogTailFinishing = $false
            $script:BuildProc = $null
        }
    })
    $script:LogTailTimer.Start()
}

$btnBuild.Add_Click({ Start-RadioBuild })
$btnClose.Add_Click({ $form.Close() })

$form.Add_Resize({ Update-LanguageLayout; Update-BottomLayout })
$form.Add_Shown({ Update-LanguageLayout; Update-BottomLayout })
$form.Add_FormClosing({
    if ($script:BuildProc -and -not $script:BuildProc.HasExited) {
        $r = Show-GuiMessageBox ((T "MsgBusyBody")) ((T "MsgBusyTitle")) ("YesNo") ("Warning")
        if ($r -ne "Yes") { $_.Cancel = $true; return }
        try { $script:BuildProc.Kill() } catch { }
    }
    try {
        if ($null -ne $script:LogTailTimer) {
            $script:LogTailTimer.Stop()
            $script:LogTailTimer.Dispose()
            $script:LogTailTimer = $null
        }
    } catch { }
    try { $script:BuildProgressTimer.Stop() } catch { }
})

try {
    Apply-UiLanguage
    Append-Log (T "LogReady")
    Append-Log ((T "LogToolsDir") -f $paths.ToolsDir)
    $missingInit = @(Get-RadioToolStatus | Where-Object { $_.Required -and -not $_.Ok })
    if ($missingInit.Count -gt 0) {
        Append-Log ((T "LogMissingInit") -f $missingInit.Count)
    } else {
        Append-Log (T "LogEnvOk")
    }
    [void]$form.ShowDialog()
} catch {
    Show-GuiMessageBox ($_.Exception.Message) ((T "ErrFatal")) ("OK") ("Error") | Out-Null
    throw
}
