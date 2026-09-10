# EdgeTX Android build wizard (GUI). Prefer: Build-EdgeTX-GUI.pyw / Build-EdgeTX-GUI.bat
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\GuiDialogs.ps1")

$paths = Get-EdgeTxPaths
$script:IsBusy = $false

$script:Strings = @{
    en = @{
        Title             = "EdgeTX Android Build Tool"
        LanguageLabel     = "语言"
        SectionEnv        = "[1] Environment && toolchain"
        SectionRes        = "[2] Pre-compiled display assets"
        SectionLog        = "[3] Build log"
        BtnRecheck        = "Re-check"
        BtnInstall        = "Install missing"
        BtnAddRes         = "Add resolution"
        BtnBuild          = "Start build"
        BtnClose          = "Close"
        ColComponent      = "Component"
        ColStatus         = "Status"
        ColPath           = "Path / note"
        ColSize           = "Size"
        ColResolution     = "Resolution"
        ColBitmaps        = "Icons"
        ColFonts          = "Fonts"
        StatusOk          = "OK"
        StatusMissing     = "MISSING"
        StatusPartial     = "PARTIAL"
        StatusStock       = "stock"
        ToolsHint         = "Prefer installing tools yourself (see docs/TOOLCHAIN.md). Optional one-click Install missing runs in the background; watch the log for download progress."
        ResHint           = "Select a resolution, then Start build. Right-click a row to delete (800x480 is protected)."
        LblWidth          = "Width:"
        LblHeight         = "Height:"
        AssetNeedGen      = "Assets will be generated at configure (first run is slow)."
        LogReady          = "EdgeTX Android build wizard ready."
        LogToolsDir       = "Tools dir: {0}"
        LogMissingInit    = "{0} missing item(s) - install yourself (TOOLCHAIN.md) or use Install missing."
        LogEnvOk          = "Environment OK. Select a resolution and Start build."
        LogEnvCheck       = "=== Environment check ==="
        LogAllReady       = "All required tools ready."
        LogMissingItems   = "{0} item(s) missing. Install yourself or click Install missing."
        LogInstallStart   = "=== Installing missing tools (background) ==="
        LogInstallDone    = "=== Install pass finished ==="
        LogInstallFailed  = "Install failed: {0}"
        LogBuildStart     = "EdgeTX build started - {0}"
        LogStep1          = '>>> [1/2] Native firmware (build-android-native.ps1) ...'
        LogStep2          = '>>> [2/2] APK (build-apk.ps1) ...'
        LogSucceeded      = "Build succeeded!"
        LogApk            = "APK: {0}"
        LogSize           = "Size: {0:N1} MB"
        LogFailed         = "Build failed: {0}"
        LogOverlayRestored = "Upstream main tree restored from overlay backup."
        LogOverlayRestoreFailed = "Overlay restore failed: {0}"
        LogResAdded       = "Added resolution {0} to list."
        LogResDeleted     = "Deleted resources for {0}."
        LogResScan        = "=== Display assets scan ==="
        MsgNothingInstall = "Nothing to install."
        MsgInstallTitle   = "Confirm install"
        MsgInstallBody    = "Preferred: install large tools yourself (see docs/TOOLCHAIN.md).`n`nOptional one-click downloads into radio\src\targets\android\.tools (or pip):`n`n{0}`n`nNDK ~1.5 GB. UI stays responsive; watch the log for progress. Continue?"
        MsgCannotBuild    = "{0} required tool(s) missing. Install them first."
        MsgResTitle       = "Resolution"
        MsgNoSelection    = "Select a resolution from the list first."
        MsgResExists      = "Resolution {0} is already in the list."
        MsgBuildTitle     = "Confirm build"
        MsgBuildBody      = @"
Start full build?

  Resolution: {0}
  Icons: {1}
  Fonts: {2}

  Step 1: libedgetx_sim.a (~15-25 min)
  Step 2: output/EdgeTX.apk
{3}
Continue?
"@
        ReuseExisting    = "reuse existing"
        AutoGenerate     = "auto-generate"
        GenerateAtCfg    = "generate at configure"
        MsgSuccessTitle  = "Success"
        MsgSuccessBody   = "Build completed.`n`n{0}"
        MsgBuildFailed   = "Build failed"
        MsgInstallFailed = "Install failed"
        MsgDeleteTitle   = "Delete resolution"
        MsgDeleteBody    = @"
Delete resolution {0} and its generated assets?

  Bitmaps: radio\src\targets\android\generated\bitmaps\{0}\
  Fonts:   radio\src\targets\android\generated\fonts\lvgl\{1}\

This cannot be undone.
"@
        MsgCannotDeleteStock = "800x480 is the stock upstream colorlcd source resolution and cannot be deleted."
        MnuDeleteRes     = "Delete resolution..."
        ErrWidth         = "Width must be a positive integer"
        ErrHeight        = "Height must be a positive integer"
        ErrTooSmall      = "Resolution too small (min 320x240)"
        ErrTooLarge      = "Resolution too large (max 3840x2160)"
        ErrLandscape     = "Landscape only (width must exceed height)"
        ErrFatal         = "Fatal error"
    }
    zh = @{
        Title             = "EdgeTX Android 编译工具"
        LanguageLabel     = "Language"
        SectionEnv        = "[1] 环境 && 工具链"
        SectionRes        = "[2] 已预编译资源"
        SectionLog        = "[3] 编译日志"
        BtnRecheck        = "重新检测"
        BtnInstall        = "安装缺失项"
        BtnAddRes         = "添加分辨率"
        BtnBuild          = "开始编译"
        BtnClose          = "关闭"
        ColComponent      = "组件"
        ColStatus         = "状态"
        ColPath           = "路径 / 说明"
        ColSize           = "大小"
        ColResolution     = "分辨率"
        ColBitmaps        = "图标"
        ColFonts          = "字库"
        StatusOk          = "就绪"
        StatusMissing     = "缺失"
        StatusPartial     = "不完整"
        StatusStock       = "原始"
        ToolsHint         = "建议自行安装工具链（见 docs/TOOLCHAIN.md）。也可点「安装缺失项」后台下载到 .tools，进度见下方日志。"
        ResHint           = "选择列表中的分辨率后点击 [开始编译]。右键可删除 (800x480 为原始资源，禁止删除)。"
        LblWidth          = "宽度:"
        LblHeight         = "高度:"
        AssetNeedGen      = "首次配置时将自动生成资源 (较慢)。"
        LogReady          = "EdgeTX Android 编译向导已就绪。"
        LogToolsDir       = "工具目录: {0}"
        LogMissingInit    = "有 {0} 项缺失 — 请自行安装（TOOLCHAIN.md）或使用「安装缺失项」。"
        LogEnvOk          = "环境就绪。请选择分辨率后点击 [开始编译]。"
        LogEnvCheck       = "=== 环境检测 ==="
        LogAllReady       = "所有必需工具已就绪。"
        LogMissingItems   = "有 {0} 项缺失，请自行安装或点击「安装缺失项」。"
        LogInstallStart   = "=== 正在安装缺失工具（后台） ==="
        LogInstallDone    = "=== 安装阶段完成 ==="
        LogInstallFailed  = "安装失败: {0}"
        LogBuildStart     = "开始编译 EdgeTX - {0}"
        LogStep1          = '>>> [1/2] 原生固件 (build-android-native.ps1) ...'
        LogStep2          = '>>> [2/2] APK (build-apk.ps1) ...'
        LogSucceeded      = "编译成功！"
        LogApk            = "APK: {0}"
        LogSize           = "大小: {0:N1} MB"
        LogFailed         = "编译失败: {0}"
        LogOverlayRestored = "已从 overlay 备份还原官方 main 树。"
        LogOverlayRestoreFailed = "overlay 还原失败: {0}"
        LogResAdded       = "已添加分辨率 {0} 到列表。"
        LogResDeleted     = "已删除分辨率 {0} 的相关资源。"
        LogResScan        = "=== 资源扫描 ==="
        MsgNothingInstall = "没有需要安装的项目。"
        MsgInstallTitle   = "确认安装"
        MsgInstallBody    = "建议大件（JDK/SDK/NDK）按 docs/TOOLCHAIN.md 自行安装。`n`n也可一键下载到 radio\src\targets\android\.tools（或 pip）：`n`n{0}`n`nNDK 约 1.5 GB。界面不卡死，进度在日志中显示。是否继续？"
        MsgCannotBuild    = "有 {0} 个必需工具缺失，请先安装。"
        MsgResTitle       = "分辨率"
        MsgNoSelection    = "请先在列表中选择一个分辨率。"
        MsgResExists      = "分辨率 {0} 已在列表中。"
        MsgBuildTitle     = "确认编译"
        MsgBuildBody      = @"
开始完整编译？

  分辨率: {0}
  图标: {1}
  字库: {2}

  步骤 1: libedgetx_sim.a (约 15-25 分钟)
  步骤 2: output/EdgeTX.apk
{3}
是否继续？
"@
        ReuseExisting    = "复用已有"
        AutoGenerate     = "自动生成"
        GenerateAtCfg    = "配置时生成"
        MsgSuccessTitle  = "完成"
        MsgSuccessBody   = "编译完成。`n`n{0}"
        MsgBuildFailed   = "编译失败"
        MsgInstallFailed = "安装失败"
        MsgDeleteTitle   = "删除分辨率"
        MsgDeleteBody    = @"
删除分辨率 {0} 及其生成的资源？

  位图: radio\src\targets\android\generated\bitmaps\{0}\
  字库: radio\src\targets\android\generated\fonts\lvgl\{1}\

此操作不可恢复。
"@
        MsgCannotDeleteStock = "800x480 为 upstream 原始 colorlcd 资源，禁止删除。"
        MnuDeleteRes     = "删除分辨率..."
        ErrWidth         = "宽度必须为正整数"
        ErrHeight        = "高度必须为正整数"
        ErrTooSmall      = "分辨率过小 (最小 320x240)"
        ErrTooLarge      = "分辨率过大 (最大 3840x2160)"
        ErrLandscape     = "仅支持横屏 (宽度须大于高度)"
        ErrFatal         = "严重错误"
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

$form = New-Object System.Windows.Forms.Form
$form.Text = T "Title"
$form.Size = New-Object System.Drawing.Size(920, 800)
$form.StartPosition = "CenterScreen"
Set-GuiMainForm $form
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.MinimumSize = New-Object System.Drawing.Size(820, 700)

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

$lblSection1 = New-Label (T "SectionEnv") 12 36 320
$btnCheckEnv = New-Object System.Windows.Forms.Button
$btnCheckEnv.Text = T "BtnRecheck"
$btnCheckEnv.Location = New-Object System.Drawing.Point(12, 60)
$btnCheckEnv.Size = New-Object System.Drawing.Size(100, 28)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = T "BtnInstall"
$btnInstall.Location = New-Object System.Drawing.Point(120, 60)
$btnInstall.Size = New-Object System.Drawing.Size(110, 28)

$lvTools = New-Object System.Windows.Forms.ListView
$lvTools.Location = New-Object System.Drawing.Point(12, 96)
$lvTools.Size = New-Object System.Drawing.Size(880, 140)
$lvTools.View = "Details"
$lvTools.FullRowSelect = $true
$lvTools.GridLines = $true
$lvTools.Anchor = "Top,Left,Right"
$colComponent = New-Object System.Windows.Forms.ColumnHeader
$colComponent.Text = T "ColComponent"
$colComponent.Width = 180
$colStatus = New-Object System.Windows.Forms.ColumnHeader
$colStatus.Text = T "ColStatus"
$colStatus.Width = 70
$colPath = New-Object System.Windows.Forms.ColumnHeader
$colPath.Text = T "ColPath"
$colPath.Width = 420
$colSize = New-Object System.Windows.Forms.ColumnHeader
$colSize.Text = T "ColSize"
$colSize.Width = 90
$lvTools.Columns.AddRange(@($colComponent, $colStatus, $colPath, $colSize))

$lblToolsHint = New-Label (T "ToolsHint") 12 240 700
$lblToolsHint.ForeColor = [System.Drawing.Color]::DimGray

$lblSection2 = New-Label (T "SectionRes") 12 266 420
$lvRes = New-Object System.Windows.Forms.ListView
$lvRes.Location = New-Object System.Drawing.Point(12, 290)
$lvRes.Size = New-Object System.Drawing.Size(880, 130)
$lvRes.View = "Details"
$lvRes.FullRowSelect = $true
$lvRes.GridLines = $true
$lvRes.HideSelection = $false
$lvRes.Anchor = "Top,Left,Right"
$colRes = New-Object System.Windows.Forms.ColumnHeader
$colRes.Text = T "ColResolution"
$colRes.Width = 120
$colBmp = New-Object System.Windows.Forms.ColumnHeader
$colBmp.Text = T "ColBitmaps"
$colBmp.Width = 120
$colFnt = New-Object System.Windows.Forms.ColumnHeader
$colFnt.Text = T "ColFonts"
$colFnt.Width = 120
$lvRes.Columns.AddRange(@($colRes, $colBmp, $colFnt))

$ctxRes = New-Object System.Windows.Forms.ContextMenuStrip
$mnuDeleteRes = $ctxRes.Items.Add((T "MnuDeleteRes"))
$lvRes.ContextMenuStrip = $ctxRes

$lblWidth = New-Label (T "LblWidth") 12 430 45
$txtWidth = New-Object System.Windows.Forms.TextBox
$txtWidth.Location = New-Object System.Drawing.Point(55, 426)
$txtWidth.Size = New-Object System.Drawing.Size(70, 24)
$txtWidth.MaxLength = 4

$lblHeight = New-Label (T "LblHeight") 135 430 45
$txtHeight = New-Object System.Windows.Forms.TextBox
$txtHeight.Location = New-Object System.Drawing.Point(178, 426)
$txtHeight.Size = New-Object System.Drawing.Size(70, 24)
$txtHeight.MaxLength = 4

$btnAddRes = New-Object System.Windows.Forms.Button
$btnAddRes.Text = T "BtnAddRes"
$btnAddRes.Location = New-Object System.Drawing.Point(260, 424)
$btnAddRes.Size = New-Object System.Drawing.Size(120, 28)

$lblResHint = New-Label (T "ResHint") 12 456 860
$lblResHint.ForeColor = [System.Drawing.Color]::DimGray

$lblSection3 = New-Label (T "SectionLog") 12 482 200
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(12, 506)
$txtLog.Size = New-Object System.Drawing.Size(880, 170)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Anchor = "Top,Bottom,Left,Right"

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 684)
$progress.Size = New-Object System.Drawing.Size(880, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Style = "Continuous"
$progress.Visible = $false
$progress.Anchor = "Bottom,Left,Right"

$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = T "BtnBuild"
$btnBuild.Location = New-Object System.Drawing.Point(12, 712)
$btnBuild.Size = New-Object System.Drawing.Size(120, 34)
$btnBuild.Anchor = "Bottom,Left"

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = T "BtnClose"
$btnClose.Location = New-Object System.Drawing.Point(772, 712)
$btnClose.Size = New-Object System.Drawing.Size(120, 34)
$btnClose.Anchor = "Bottom,Right"

$form.Controls.AddRange(@(
    $lblLang, $cmbLang, $lblSection1,
    $btnCheckEnv, $btnInstall, $lvTools, $lblToolsHint,
    $lblSection2, $lvRes, $lblWidth, $txtWidth, $lblHeight, $txtHeight, $btnAddRes, $lblResHint,
    $lblSection3, $txtLog, $progress, $btnBuild, $btnClose
))

function Append-GuiLog([string]$line) {
    $box = $txtLog
    if ($null -eq $box -or $box.IsDisposed) { return }
    if ($box.InvokeRequired) {
        [void]$box.BeginInvoke([Action[string]] { param($s) Append-GuiLog $s }, $line)
        return
    }
    $box.AppendText("$line`r`n")
    $box.SelectionStart = $box.Text.Length
    $box.ScrollToCaret()
}

$script:LogBlock = {
    param($line)
    Append-GuiLog $line
}

$script:BuildProgressTimer = New-Object System.Windows.Forms.Timer
$script:BuildProgressTimer.Interval = 250
$script:BuildProgressPulse = 5
$script:BuildProgressCap = 80
$script:BuildProgressTimer.Add_Tick({
    if (-not $script:IsBusy) { return }
    if ($script:BuildProgressPulse -lt $script:BuildProgressCap) {
        $script:BuildProgressPulse += 1
        $progress.Value = $script:BuildProgressPulse
    }
})

function Set-BuildProgress {
    param(
        [int]$Value,
        [int]$Cap = 100
    )
    $script:BuildProgressPulse = $Value
    $script:BuildProgressCap = $Cap
    $progress.Value = [Math]::Min(100, [Math]::Max(0, $Value))
    [System.Windows.Forms.Application]::DoEvents()
}

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
}

function Set-Busy([bool]$busy) {
    $script:IsBusy = $busy
    $btnCheckEnv.Enabled = -not $busy
    $btnInstall.Enabled = -not $busy
    $btnAddRes.Enabled = -not $busy
    $txtWidth.Enabled = -not $busy
    $txtHeight.Enabled = -not $busy
    $btnBuild.Enabled = -not $busy
    $lvRes.Enabled = -not $busy
    $cmbLang.Enabled = -not $busy
    $progress.Visible = $busy
    if ($busy) {
        $script:BuildProgressTimer.Start()
    } else {
        $script:BuildProgressTimer.Stop()
        $progress.Value = 0
    }
    $form.Cursor = if ($busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
}

function Format-AssetStateLabel([string]$State) {
    switch ($State) {
        "ok" { return T "StatusOk" }
        "missing" { return T "StatusMissing" }
        "partial" { return T "StatusPartial" }
        "stock" { return T "StatusStock" }
        default { return $State }
    }
}

function Get-RowStateColor([string]$BmpState, [string]$FntState) {
    if ($BmpState -eq "stock" -or $FntState -eq "stock") {
        return [System.Drawing.Color]::DarkSlateGray
    }
    if ($BmpState -eq "ok" -and $FntState -eq "ok") {
        return [System.Drawing.Color]::DarkGreen
    }
    if ($BmpState -eq "missing" -and $FntState -eq "missing") {
        return [System.Drawing.Color]::DarkRed
    }
    return [System.Drawing.Color]::DarkOrange
}

function Parse-ResolutionInput {
    $wText = $txtWidth.Text.Trim()
    $hText = $txtHeight.Text.Trim()
    if ($wText -notmatch '^\d+$') { throw (T "ErrWidth") }
    if ($hText -notmatch '^\d+$') { throw (T "ErrHeight") }
    $w = [int]$wText
    $h = [int]$hText
    if ($w -lt 320 -or $h -lt 240) { throw (T "ErrTooSmall") }
    if ($w -gt 3840 -or $h -gt 2160) { throw (T "ErrTooLarge") }
    if ($w -le $h) { throw (T "ErrLandscape") }
    return "${w}x${h}"
}

function Get-SelectedResolution {
    if ($lvRes.SelectedItems.Count -eq 0) { return $null }
    return $lvRes.SelectedItems[0].Text
}

function Update-ToolList {
    $lvTools.Items.Clear()
    foreach ($t in Get-EdgeTxToolStatus) {
        $item = New-Object System.Windows.Forms.ListViewItem($t.Name)
        [void]$item.SubItems.Add($(if ($t.Ok) { T "StatusOk" } else { T "StatusMissing" }))
        $detail = if ($t.Path) { $t.Path } else { $t.Scope }
        if ($t.SizeHint -and -not $t.Ok) { $detail += " [$($t.SizeHint)]" }
        [void]$item.SubItems.Add($detail)
        [void]$item.SubItems.Add($(if ($t.SizeHint) { $t.SizeHint } else { "" }))
        if (-not $t.Ok) { $item.ForeColor = [System.Drawing.Color]::DarkRed }
        [void]$lvTools.Items.Add($item)
    }
}

function Update-ResolutionList {
    param([string]$SelectResolution)

    $prev = Get-SelectedResolution
    $lvRes.Items.Clear()
    $resolutions = @(Get-EdgeTxKnownResolutions)
    foreach ($res in $resolutions) {
        $row = Get-EdgeTxDisplayAssetRow $res
        $item = New-Object System.Windows.Forms.ListViewItem($res)
        [void]$item.SubItems.Add((Format-AssetStateLabel $row.BitmapsState))
        [void]$item.SubItems.Add((Format-AssetStateLabel $row.FontsState))
        $item.ForeColor = Get-RowStateColor $row.BitmapsState $row.FontsState
        $item.Tag = $row
        [void]$lvRes.Items.Add($item)
    }

    if ($PSBoundParameters.ContainsKey('SelectResolution')) {
        $pick = $SelectResolution
    } else {
        $pick = $prev
    }
    if (-not $pick -and ($resolutions -contains "2400x1440")) { $pick = "2400x1440" }
    if (-not $pick -and $resolutions.Count -gt 0) { $pick = $resolutions[0] }

    if ($pick) {
        foreach ($item in $lvRes.Items) {
            if ($item.Text -eq $pick) {
                $item.Selected = $true
                $item.Focused = $true
                $lvRes.EnsureVisible($item.Index)
                break
            }
        }
    }
}

function Apply-UiLanguage {
    $form.Text = T "Title"
    $lblLang.Text = T "LanguageLabel"
    $lblSection1.Text = T "SectionEnv"
    $lblSection2.Text = T "SectionRes"
    $lblSection3.Text = T "SectionLog"
    $btnCheckEnv.Text = T "BtnRecheck"
    $btnInstall.Text = T "BtnInstall"
    $btnAddRes.Text = T "BtnAddRes"
    $btnBuild.Text = T "BtnBuild"
    $btnClose.Text = T "BtnClose"
    $lblToolsHint.Text = T "ToolsHint"
    $lblResHint.Text = T "ResHint"
    $lblWidth.Text = T "LblWidth"
    $lblHeight.Text = T "LblHeight"
    $colComponent.Text = T "ColComponent"
    $colStatus.Text = T "ColStatus"
    $colPath.Text = T "ColPath"
    $colSize.Text = T "ColSize"
    $colRes.Text = T "ColResolution"
    $colBmp.Text = T "ColBitmaps"
    $colFnt.Text = T "ColFonts"
    $mnuDeleteRes.Text = T "MnuDeleteRes"
    Update-ToolList
    Update-ResolutionList
}

$cmbLang.Add_SelectedIndexChanged({
    $script:Lang = if ($cmbLang.SelectedIndex -eq 0) { "en" } else { "zh" }
    Apply-UiLanguage
})

$ctxRes.Add_Opening({
    if ($lvRes.SelectedItems.Count -eq 0) {
        $_.Cancel = $true
        return
    }
    $res = $lvRes.SelectedItems[0].Text
    $mnuDeleteRes.Enabled = -not (Test-EdgeTxResolutionProtected $res)
})

$mnuDeleteRes.Add_Click({
    if ($script:IsBusy) { return }
    if ($lvRes.SelectedItems.Count -eq 0) { return }
    $res = $lvRes.SelectedItems[0].Text
    if (Test-EdgeTxResolutionProtected $res) {
        Show-GuiMessageBox ((T "MsgCannotDeleteStock")) ((T "MsgDeleteTitle")) ("OK") ("Warning") | Out-Null
        return
    }
    $row = $lvRes.SelectedItems[0].Tag
    $msg = (T "MsgDeleteBody") -f $res, $row.FontDir
    $r = Show-GuiMessageBox ($msg) ((T "MsgDeleteTitle")) ("YesNo") ("Warning")
    if ($r -ne "Yes") { return }

    Set-Busy $true
    try {
        $removed = Remove-EdgeTxDisplayAssets -Resolution $res
        & $script:LogBlock ((T "LogResDeleted") -f $res)
        foreach ($path in $removed) { & $script:LogBlock "  - $path" }
        Update-ResolutionList -SelectResolution ""
    } catch {
        Show-GuiMessageBox ($_.Exception.Message) ((T "MsgDeleteTitle")) ("OK") ("Error") | Out-Null
    } finally { Set-Busy $false }
})

$btnAddRes.Add_Click({
    if ($script:IsBusy) { return }
    try {
        $res = Parse-ResolutionInput
    } catch {
        Show-GuiMessageBox ($_.Exception.Message) ((T "MsgResTitle")) ("OK") ("Error") | Out-Null
        return
    }
    if (@(Get-EdgeTxKnownResolutions) -contains $res) {
        Show-GuiMessageBox (((T "MsgResExists") -f $res)) ((T "MsgResTitle")) ("OK") ("Information") | Out-Null
        Update-ResolutionList -SelectResolution $res
        return
    }
    Add-EdgeTxDisplayResolution $res
    & $script:LogBlock ((T "LogResAdded") -f $res)
    Update-ResolutionList -SelectResolution $res
})

$btnCheckEnv.Add_Click({
    if ($script:IsBusy) { return }
    Set-Busy $true
    try {
        & $script:LogBlock (T "LogEnvCheck")
        Update-ToolList
        $missing = @(Get-EdgeTxToolStatus | Where-Object { -not $_.Ok })
        if ($missing.Count -eq 0) {
            & $script:LogBlock (T "LogAllReady")
        } else {
            & $script:LogBlock ((T "LogMissingItems") -f $missing.Count)
        }
        & $script:LogBlock (T "LogResScan")
        Update-ResolutionList
    } finally { Set-Busy $false }
})

$btnInstall.Add_Click({
    if ($script:IsBusy) { return }
    $missing = @(Get-EdgeTxToolStatus | Where-Object { -not $_.Ok -and $_.Installable })
    if ($missing.Count -eq 0) {
        Show-GuiMessageBox ((T "MsgNothingInstall")) ((T "Title")) ("OK") ("Information") | Out-Null
        return
    }
    $lines = ($missing | ForEach-Object { "  - $($_.Name) $($_.SizeHint) -> $($_.Scope)" }) -join "`n"
    $msg = (T "MsgInstallBody") -f $lines
    $r = Show-GuiMessageBox ($msg) ((T "MsgInstallTitle")) ("YesNo") ("Question")
    if ($r -ne "Yes") { return }

    Set-Busy $true
    & $script:LogBlock (T "LogInstallStart")
    $envLib = (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1").Replace("'", "''")
    $jobBody = @"
. '$envLib'
try {
  Install-EdgeTxMissingTools -OnLog {
    param(`$m)
    Write-GuiJobLog `$m
  }
  Write-GuiJobLog 'INSTALL_OK'
  exit 0
} catch {
  Write-GuiJobLog (`$_.Exception.Message)
  exit 1
}
"@
    Start-GuiPowerShellJob -ScriptText $jobBody -WorkingDirectory $paths.AndroidRoot `
        -OnLogLine { param($line) & $script:LogBlock $line } `
        -OnExit {
            param($code)
            try {
                if ($code -ne 0) {
                    & $script:LogBlock ((T "LogInstallFailed") -f "exit $code")
                    Show-GuiMessageBox ("Install failed (exit $code). See log.") ((T "MsgInstallFailed")) ("OK") ("Error") | Out-Null
                } else {
                    Update-ToolList
                    & $script:LogBlock (T "LogInstallDone")
                }
            } finally {
                Set-Busy $false
            }
        } | Out-Null
})

$btnBuild.Add_Click({
    if ($script:IsBusy) { return }

    $res = Get-SelectedResolution
    if (-not $res) {
        Show-GuiMessageBox ((T "MsgNoSelection")) ((T "Title")) ("OK") ("Warning") | Out-Null
        return
    }

    $requiredMissing = @(Get-EdgeTxToolStatus | Where-Object { $_.Required -and -not $_.Ok })
    if ($requiredMissing.Count -gt 0) {
        Show-GuiMessageBox (((T "MsgCannotBuild") -f $requiredMissing.Count)) ((T "Title")) ("OK") ("Warning") | Out-Null
        return
    }

    $row = Get-EdgeTxDisplayAssetRow $res
    $assets = $row.AssetStatus

    $genNote = if ($assets.NeedsGeneration) { "`n`n$(T 'AssetNeedGen')" } else { "" }
    $bmpNote = if ($row.BitmapsState -eq "ok" -or $row.BitmapsState -eq "stock") { T "ReuseExisting" } else { T "AutoGenerate" }
    $fntNote = if ($row.FontsState -eq "ok" -or $row.FontsState -eq "stock") { T "ReuseExisting" }
                     elseif ($row.FontsState -eq "partial") { T "AutoGenerate" }
                     else { T "GenerateAtCfg" }
    $confirm = (T "MsgBuildBody") -f $res, $bmpNote, $fntNote, $genNote
    $r = Show-GuiMessageBox ($confirm) ((T "MsgBuildTitle")) ("YesNo") ("Question")
    if ($r -ne "Yes") { return }

    $forceAssets = ($row.FontsState -eq "partial") -or (-not $assets.BitmapsReady) -or (-not $assets.FontsReady)

    Set-Busy $true
    try {
        & $script:LogBlock "========================================"
        & $script:LogBlock ((T "LogBuildStart") -f $res)
        & $script:LogBlock "========================================"
        & $script:LogBlock ""
        Set-BuildProgress -Value 2 -Cap 80
        & $script:LogBlock (T "LogStep1")

        $onProgress = {
            if ($script:BuildProgressPulse -lt $script:BuildProgressCap) {
                Set-BuildProgress -Value ($script:BuildProgressPulse + 1) -Cap $script:BuildProgressCap
            }
        }
        if ($forceAssets) {
            Invoke-EdgeTxNativeBuild -Display $res -ForceAssets -OnLog $script:LogBlock -OnProgress $onProgress
        } else {
            Invoke-EdgeTxNativeBuild -Display $res -OnLog $script:LogBlock -OnProgress $onProgress
        }

        Set-BuildProgress -Value 85 -Cap 95
        & $script:LogBlock ""
        & $script:LogBlock (T "LogStep2")
        Invoke-EdgeTxApkBuild -Display $res -OnLog $script:LogBlock -OnProgress $onProgress

        Set-BuildProgress -Value 100 -Cap 100
        $apk = $paths.OutputApk
        & $script:LogBlock ""
        & $script:LogBlock "========================================"
        & $script:LogBlock (T "LogSucceeded")
        & $script:LogBlock ((T "LogApk") -f $apk)
        if (Test-Path $apk) {
            $mb = (Get-Item $apk).Length / 1MB
            & $script:LogBlock ((T "LogSize") -f $mb)
        }
        & $script:LogBlock "========================================"

        Update-ResolutionList -SelectResolution $res

        Show-GuiMessageBox (((T "MsgSuccessBody") -f $apk)) ((T "MsgSuccessTitle")) ("OK") ("Information") | Out-Null
    } catch {
        $errMsg = Format-EdgeTxExceptionMessage $_
        & $script:LogBlock ""
        & $script:LogBlock ((T "LogFailed") -f $errMsg)
        try {
            . (Join-Path $PSScriptRoot "lib\OverlayBackup.ps1")
            if (Restore-OverlayIfBackedUp -Reason ">>> Restoring upstream main tree after build failure...") {
                & $script:LogBlock (T "LogOverlayRestored")
            }
        } catch {
            & $script:LogBlock ((T "LogOverlayRestoreFailed") -f $_.Exception.Message)
        }
        Show-GuiMessageBox ($errMsg) ((T "MsgBuildFailed")) ("OK") ("Error") | Out-Null
    } finally { Set-Busy $false }
})

$btnClose.Add_Click({ $form.Close() })

$form.Add_FormClosing({
    if ($script:IsBusy) { $_.Cancel = $true }
})

$form.Add_Load({
    Update-LanguageLayout
    Update-BottomLayout
})
$form.Add_Resize({
    Update-LanguageLayout
    Update-BottomLayout
})

Update-ToolList
Update-ResolutionList
& $script:LogBlock (T "LogReady")
& $script:LogBlock ((T "LogToolsDir") -f $paths.ToolsDir)
$missingInit = @(Get-EdgeTxToolStatus | Where-Object { -not $_.Ok })
if ($missingInit.Count -gt 0) {
    & $script:LogBlock ((T "LogMissingInit") -f $missingInit.Count)
} else {
    & $script:LogBlock (T "LogEnvOk")
}

try {
    [void]$form.ShowDialog()
    exit 0
} catch {
    Show-GuiMessageBox ($_.Exception.Message) ((T "ErrFatal")) ("OK") ("Error") | Out-Null
    exit 1
}
