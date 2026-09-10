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
