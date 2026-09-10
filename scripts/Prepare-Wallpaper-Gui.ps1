# EdgeTX wallpaper tool (GUI). Launch: radio\src\targets\android\Prepare-Wallpaper.pyw
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\GuiDialogs.ps1")

$paths = Get-EdgeTxPaths
$script:IsBusy = $false
$script:LastOutputFile = ""

function New-Label($text, $x, $y, $w = 200, $h = 22) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    return $l
}

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    $txtLog.AppendText("$line`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-KnownResolutions {
    $list = @()
    $listFile = Join-Path $paths.AppRoot "display-resolutions.json"
    if (Test-Path $listFile) {
        $list = @(Get-Content $listFile | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if ($list.Count -eq 0) { $list = @("2400x1440") }
    return $list
}

function Set-ResolutionFields([string]$Display) {
    if ($Display -notmatch '^(\d+)x(\d+)$') { return }
    $txtWidth.Text = $Matches[1]
    $txtHeight.Text = $Matches[2]
}

function Set-Busy([bool]$Busy) {
    $script:IsBusy = $Busy
    $btnProcess.Enabled = -not $Busy
    $btnBrowse.Enabled = -not $Busy
    $cmbPreset.Enabled = -not $Busy
    $txtWidth.Enabled = -not $Busy
    $txtHeight.Enabled = -not $Busy
    if ($Busy) {
        $progress.Style = "Marquee"
        $progress.Visible = $true
    } else {
        $progress.Visible = $false
        $progress.Style = "Continuous"
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "EdgeTX 壁纸工具"
$form.Size = New-Object System.Drawing.Size(680, 520)
$form.StartPosition = "CenterScreen"
Set-GuiMainForm $form
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.MinimumSize = New-Object System.Drawing.Size(620, 460)

$lblSource = New-Label "源图片:" 12 16 60
$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Location = New-Object System.Drawing.Point(72, 12)
$txtSource.Size = New-Object System.Drawing.Size(480, 24)
$txtSource.Anchor = "Top,Left,Right"
$txtSource.ReadOnly = $true

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "浏览..."
$btnBrowse.Location = New-Object System.Drawing.Point(560, 10)
$btnBrowse.Size = New-Object System.Drawing.Size(88, 28)
$btnBrowse.Anchor = "Top,Right"

$lblPreset = New-Label "预设分辨率:" 12 52 80
$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = New-Object System.Drawing.Point(96, 48)
$cmbPreset.Size = New-Object System.Drawing.Size(160, 24)
$cmbPreset.DropDownStyle = "DropDownList"

$lblWidth = New-Label "宽度:" 280 52 40
$txtWidth = New-Object System.Windows.Forms.TextBox
$txtWidth.Location = New-Object System.Drawing.Point(322, 48)
$txtWidth.Size = New-Object System.Drawing.Size(72, 24)
$txtWidth.MaxLength = 4

$lblHeight = New-Label "高度:" 408 52 40
$txtHeight = New-Object System.Windows.Forms.TextBox
$txtHeight.Location = New-Object System.Drawing.Point(448, 48)
$txtHeight.Size = New-Object System.Drawing.Size(72, 24)
$txtHeight.MaxLength = 4

$lblOutput = New-Label "输出目录:" 12 88 60
$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(72, 84)
$txtOutput.Size = New-Object System.Drawing.Size(576, 24)
$txtOutput.Anchor = "Top,Left,Right"
$txtOutput.ReadOnly = $true
$txtOutput.Text = $paths.OutputDir

$lblHint = New-Label "居中裁切后生成 background_宽x高.png，不变形。" 12 116 620
$lblHint.ForeColor = [System.Drawing.Color]::DimGray

$lblLog = New-Label "日志:" 12 144 60
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(12, 168)
$txtLog.Size = New-Object System.Drawing.Size(636, 220)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Anchor = "Top,Bottom,Left,Right"

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(12, 396)
$progress.Size = New-Object System.Drawing.Size(636, 18)
$progress.Visible = $false
$progress.Anchor = "Bottom,Left,Right"

$btnProcess = New-Object System.Windows.Forms.Button
$btnProcess.Text = "开始处理"
$btnProcess.Location = New-Object System.Drawing.Point(12, 424)
$btnProcess.Size = New-Object System.Drawing.Size(120, 34)
$btnProcess.Anchor = "Bottom,Left"

$btnOpenOut = New-Object System.Windows.Forms.Button
$btnOpenOut.Text = "打开输出文件夹"
$btnOpenOut.Location = New-Object System.Drawing.Point(140, 424)
$btnOpenOut.Size = New-Object System.Drawing.Size(140, 34)
$btnOpenOut.Anchor = "Bottom,Left"

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "关闭"
$btnClose.Location = New-Object System.Drawing.Point(528, 424)
$btnClose.Size = New-Object System.Drawing.Size(120, 34)
$btnClose.Anchor = "Bottom,Right"

$form.Controls.AddRange(@(
    $lblSource, $txtSource, $btnBrowse,
    $lblPreset, $cmbPreset, $lblWidth, $txtWidth, $lblHeight, $txtHeight,
    $lblOutput, $txtOutput, $lblHint, $lblLog, $txtLog,
    $progress, $btnProcess, $btnOpenOut, $btnClose
))

$knownRes = Get-KnownResolutions
[void]$cmbPreset.Items.AddRange($knownRes)
$cmbPreset.SelectedIndex = 0
if ($knownRes -contains "2400x1440") {
    $cmbPreset.SelectedItem = "2400x1440"
}
Set-ResolutionFields ($cmbPreset.SelectedItem.ToString())

$defaultSrc = Join-Path $paths.AppRoot "Assets\background.png"
if (Test-Path $defaultSrc) {
    $txtSource.Text = $defaultSrc
}

$cmbPreset.Add_SelectedIndexChanged({
    if ($cmbPreset.SelectedItem) {
        Set-ResolutionFields ($cmbPreset.SelectedItem.ToString())
    }
})

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "选择壁纸图片"
    $dlg.Filter = "图片文件|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif|所有文件|*.*"
    if ($txtSource.Text -and (Test-Path $txtSource.Text)) {
        $dlg.InitialDirectory = Split-Path $txtSource.Text -Parent
    } else {
        $assets = Join-Path $paths.AppRoot "Assets"
        if (Test-Path $assets) { $dlg.InitialDirectory = $assets }
    }
    if ((Show-GuiCommonDialog $dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSource.Text = $dlg.FileName
    }
})

$btnOpenOut.Add_Click({
    $outDir = $txtOutput.Text
    if (-not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    Start-Process explorer.exe $outDir
})

$btnProcess.Add_Click({
    if ($script:IsBusy) { return }

    $src = $txtSource.Text.Trim()
    if (-not $src -or -not (Test-Path -LiteralPath $src)) {
        Show-GuiMessageBox ("请先选择有效的源图片。") ("提示") ("OK") ("Warning") | Out-Null
        return
    }

    $display = ""
    try {
        $display = Test-ResolutionString ("{0}x{1}" -f $txtWidth.Text.Trim(), $txtHeight.Text.Trim())
    } catch {
        Show-GuiMessageBox ($_.Exception.Message) ("分辨率无效") ("OK") ("Warning") | Out-Null
        return
    }

    $parts = $display -split "x"
    $width = $parts[0]
    $height = $parts[1]
    $outDir = $txtOutput.Text.Trim()
    if (-not $outDir) {
        Show-GuiMessageBox ("输出目录不能为空。") ("提示") ("OK") ("Warning") | Out-Null
        return
    }

    $py = Join-Path $PSScriptRoot "generate-wallpaper.py"
    if (-not (Test-Path $py)) {
        Show-GuiMessageBox ("缺少脚本: generate-wallpaper.py") ("错误") ("OK") ("Error") | Out-Null
        return
    }

    Set-Busy $true
    $script:LastOutputFile = ""
    try {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Write-Log "清除旧壁纸 background*.png ..."
        Get-ChildItem $outDir -Filter "background*.png" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force

        Write-Log "源图: $src"
        Write-Log "分辨率: $display"
        Write-Log "输出: $outDir"

        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & python $py $src $outDir $width $height 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $prevEap

        foreach ($line in $output) {
            Write-Log "$line"
        }

        if ($exitCode -ne 0) {
            throw "处理失败 (exit $exitCode)"
        }

        $script:LastOutputFile = Join-Path $outDir "background_${display}.png"
        Write-Log "完成。"
        Show-GuiMessageBox ("壁纸已生成:`n$script:LastOutputFile") ("完成") ("OK") ("Information") | Out-Null
    } catch {
        Write-Log "错误: $($_.Exception.Message)"
        Show-GuiMessageBox ($_.Exception.Message) ("处理失败") ("OK") ("Error") | Out-Null
    } finally {
        Set-Busy $false
    }
})

$btnClose.Add_Click({ $form.Close() })

$form.Add_FormClosing({
    if ($script:IsBusy) { $_.Cancel = $true }
})

$form.Add_Load({
    Write-Log "EdgeTX 壁纸工具已就绪。"
    Write-Log "输出目录: $($txtOutput.Text)"
})

try {
    [void]$form.ShowDialog()
    exit 0
} catch {
    Show-GuiMessageBox ($_.Exception.Message) ("严重错误") ("OK") ("Error") | Out-Null
    exit 1
}
