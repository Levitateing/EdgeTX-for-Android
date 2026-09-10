# Ensure Build-Radio-Gui.ps1 is UTF-8 with BOM (required on Chinese Windows + PS 5.1)
$ErrorActionPreference = "Stop"
$gui = Join-Path $PSScriptRoot "Build-Radio-Gui.ps1"
if (-not (Test-Path $gui)) { exit 0 }
$bytes = [System.IO.File]::ReadAllBytes($gui)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    exit 0
}
$content = [System.IO.File]::ReadAllText($gui)
$enc = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($gui, $content, $enc)
