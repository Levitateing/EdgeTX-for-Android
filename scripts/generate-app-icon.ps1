# Generate Android launcher icons from app/icon-source/edgetx_launcher.png
# Single flat PNG set only (no adaptive layers) so launcher and Settings show the same icon.
param(
    [string]$Source = (Join-Path $PSScriptRoot "..\app\icon-source\edgetx_launcher.png")
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) {
    throw "Icon source missing: $Source"
}

$OutRoot = Join-Path $PSScriptRoot "..\app\src\main\res"
$PyScript = Join-Path $PSScriptRoot "generate-app-icon.py"

python $PyScript $Source $OutRoot
if ($LASTEXITCODE -ne 0) { throw "generate-app-icon failed" }

# Remove adaptive-icon leftovers that cause dual icon paths on Android 8+.
$anydpi = Join-Path $OutRoot "mipmap-anydpi-v26"
Remove-Item (Join-Path $anydpi "ic_launcher.xml") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $anydpi "ic_launcher_round.xml") -Force -ErrorAction SilentlyContinue
Get-ChildItem -Path (Join-Path $OutRoot "mipmap-*") -Filter "ic_launcher_foreground.png" -ErrorAction SilentlyContinue |
    Remove-Item -Force
Get-ChildItem -Path (Join-Path $OutRoot "drawable-*") -Filter "ic_launcher_foreground.png" -ErrorAction SilentlyContinue |
    Remove-Item -Force
Remove-Item (Join-Path $OutRoot "drawable\ic_launcher_foreground.xml") -Force -ErrorAction SilentlyContinue
