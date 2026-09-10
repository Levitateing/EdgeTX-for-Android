# Shared WinForms dialog helpers — center popups on the GUI form (same monitor), not the primary screen.
# Usage: . (Join-Path $PSScriptRoot "lib\GuiDialogs.ps1")   # or from scripts\lib

$script:GuiMainForm = $null

function Set-GuiMainForm {
    param([System.Windows.Forms.Form]$Form)
    $script:GuiMainForm = $Form
}

function Show-GuiMessageBox {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Text,
        [Parameter(Position = 1)]
        [string]$Caption = "",
        [Parameter(Position = 2)]
        [string]$Buttons = "OK",
        [Parameter(Position = 3)]
        [string]$Icon = "Information"
    )
    $owner = $null
    if ($script:GuiMainForm -and -not $script:GuiMainForm.IsDisposed) {
        $owner = $script:GuiMainForm
    }
    if ($owner) {
        return [System.Windows.Forms.MessageBox]::Show(
            $owner, $Text, $Caption, $Buttons, $Icon)
    }
    return [System.Windows.Forms.MessageBox]::Show($Text, $Caption, $Buttons, $Icon)
}

function Show-GuiCommonDialog {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.CommonDialog]$Dialog
    )
    $owner = $null
    if ($script:GuiMainForm -and -not $script:GuiMainForm.IsDisposed) {
        $owner = $script:GuiMainForm
    }
    if ($owner) {
        return $Dialog.ShowDialog($owner)
    }
    return $Dialog.ShowDialog()
}

function Start-GuiPowerShellJob {
    <#
    .SYNOPSIS
      Run PowerShell work in a child process so the WinForms UI stays responsive.
      Progress is tailed from a UTF-8 log file onto the UI thread via a Timer.
    .PARAMETER ScriptText
      Body executed by powershell.exe -Command (or -File wrapper). Should write progress
      lines with Add-Content to the provided log path (see $env:EDGETX_GUI_JOB_LOG).
    .PARAMETER OnLogLine
      Called on UI thread for each new log line: & $OnLogLine $line
    .PARAMETER OnExit
      Called on UI thread when the process exits: & $OnExit $exitCode
    #>
    param(
        [Parameter(Mandatory = $true)][string]$ScriptText,
        [Parameter(Mandatory = $true)][scriptblock]$OnLogLine,
        [Parameter(Mandatory = $true)][scriptblock]$OnExit,
        [string]$WorkingDirectory = ""
    )
    $form = $script:GuiMainForm
    $stamp = Get-Date -Format "yyyyMMddHHmmssfff"
    $logFile = Join-Path $env:TEMP "edgetx-gui-job-$stamp.log"
    $wrapper = Join-Path $env:TEMP "edgetx-gui-job-$stamp.ps1"
    [System.IO.File]::WriteAllText($logFile, "", [System.Text.UTF8Encoding]::new($false))

    $header = @"
`$ErrorActionPreference = 'Stop'
`$env:EDGETX_GUI_JOB_LOG = '$($logFile.Replace("'", "''"))'
function Write-GuiJobLog([string]`$Message) {
  `$line = if (`$Message) { `$Message } else { '' }
  Add-Content -LiteralPath `$env:EDGETX_GUI_JOB_LOG -Value `$line -Encoding UTF8
}
"@
    Set-Content -LiteralPath $wrapper -Value ($header + "`r`n" + $ScriptText) -Encoding UTF8

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$wrapper`""
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $script:CurrentGuiJob = @{
        Proc       = $proc
        LogFile    = $logFile
        Wrapper    = $wrapper
        Offset     = 0L
        OnLogLine  = $OnLogLine
        OnExit     = $OnExit
        Finishing  = $false
        Timer      = $null
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 300
    $script:CurrentGuiJob.Timer = $timer
    $timer.Add_Tick({
        $job = $script:CurrentGuiJob
        if ($null -eq $job -or $job.Finishing) { return }
        try {
            $logPath = $job.LogFile
            if ($logPath -and (Test-Path -LiteralPath $logPath)) {
                $fs = [System.IO.File]::Open($logPath, "Open", "Read", "ReadWrite")
                try {
                    if ($fs.Length -gt $job.Offset) {
                        [void]$fs.Seek($job.Offset, "Begin")
                        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true, 4096, $true)
                        $chunk = $sr.ReadToEnd()
                        $sr.Close()
                        $job.Offset = $fs.Position
                        if ($chunk) {
                            foreach ($line in ($chunk -split "`r?`n")) {
                                if ($line.Length -gt 0) { & $job.OnLogLine $line }
                            }
                        }
                    }
                } finally { $fs.Close() }
            }

            if (-not $job.Proc.HasExited) { return }

            $job.Finishing = $true
            try { $job.Timer.Stop() } catch { }
            if ($logPath -and (Test-Path -LiteralPath $logPath)) {
                try {
                    $fs2 = [System.IO.File]::Open($logPath, "Open", "Read", "ReadWrite")
                    try {
                        if ($fs2.Length -gt $job.Offset) {
                            [void]$fs2.Seek($job.Offset, "Begin")
                            $sr2 = New-Object System.IO.StreamReader($fs2, [System.Text.Encoding]::UTF8, $true, 4096, $true)
                            $chunk2 = $sr2.ReadToEnd()
                            $sr2.Close()
                            if ($chunk2) {
                                foreach ($line in ($chunk2 -split "`r?`n")) {
                                    if ($line.Length -gt 0) { & $job.OnLogLine $line }
                                }
                            }
                        }
                    } finally { $fs2.Close() }
                } catch { }
            }
            $code = $job.Proc.ExitCode
            try { $job.Proc.Dispose() } catch { }
            Remove-Item -LiteralPath $job.Wrapper -Force -ErrorAction SilentlyContinue
            $script:CurrentGuiJob = $null
            & $job.OnExit $code
            try { $job.Timer.Dispose() } catch { }
        } catch {
            # Keep UI alive even if tailing fails.
        }
    })
    $timer.Start()
    return $script:CurrentGuiJob
}
