# Generate theme wallpaper for the current compile resolution.
param(
    [string]$Display = "2400x1440"
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$paths = Get-EdgeTxPaths
$Display = Test-ResolutionString $Display
$parts = $Display -split "x"
$width = $parts[0]
$height = $parts[1]

$src = Join-Path $paths.AppRoot "Assets\background.png"
$themeDir = Join-Path $paths.AppRoot "SD-Card-Files\THEMES\EdgeTX"
$py = Join-Path $PSScriptRoot "generate-wallpaper.py"

if (-not (Test-Path $src)) {
    throw "Source wallpaper missing: $src"
}

Write-Host "Wallpaper: clearing old background*.png under SD-Card-Files\THEMES"
$themesRoot = Join-Path $paths.AppRoot "SD-Card-Files\THEMES"
Get-ChildItem $themesRoot -Recurse -Filter "background*.png" -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

Write-Host "Wallpaper: $Display from $src"
New-Item -ItemType Directory -Force -Path $themeDir | Out-Null
python $py $src $themeDir $width $height
if ($LASTEXITCODE -ne 0) { throw "generate-wallpaper.py failed ($LASTEXITCODE)" }
