# Manually convert a wallpaper image to EdgeTX background_WxH.png (center crop, no stretch).
#
# Examples:
#   .\prepare-wallpaper.ps1
#   .\prepare-wallpaper.ps1 -Source "D:\pics\wall.jpg" -Display "2400x1440"
#   .\prepare-wallpaper.ps1 -Source ".\wall.png" -Theme "NEW" -Display "1280x720"
#   .\prepare-wallpaper.ps1 -Source ".\wall.png" -OutputDir "C:\temp\wall" -Display "2600x1440"
param(
    [string]$Source = "",
    [string]$Display = "2400x1440",
    [string]$Theme = "EdgeTX",
    [string]$OutputDir = "",
    [switch]$ClearAllThemes,
    [switch]$NoClear,
    [switch]$Help
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$paths = Get-EdgeTxPaths

function Show-PrepareWallpaperHelp {
    Write-Host @"
EdgeTX wallpaper tool - center-crop source image to compile resolution.

Usage:
  prepare-wallpaper.ps1 [-Source <image>] [-Display WxH] [-Theme <name>] [-OutputDir <dir>]

Options:
  -Source         Input image (png/jpg/webp). Default: Assets\background.png (under this Android dir)
  -Display        Target resolution, e.g. 2400x1440 (must match APK compile resolution)
  -Theme          Theme folder under SD-Card-Files\THEMES\ (default: EdgeTX)
  -OutputDir      Write background_WxH.png here instead of SD-Card-Files\THEMES\<Theme>
  -ClearAllThemes Remove background*.png from every theme before generating
  -NoClear        Keep existing background*.png in the target folder
  -Help           Show this help

Output file name (EdgeTX convention):
  background_<width>x<height>.png

Known compile resolutions in this project:
"@
    $listFile = Join-Path $paths.AppRoot "display-resolutions.json"
    if (Test-Path $listFile) {
        Get-Content $listFile | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  2400x1440 (default)"
    }
}

if ($Help) {
    Show-PrepareWallpaperHelp
    exit 0
}

if (-not $Source) {
    $Source = Join-Path $paths.AppRoot "Assets\background.png"
}
$Source = (Resolve-Path -LiteralPath $Source).Path

$Display = Test-ResolutionString $Display
$parts = $Display -split "x"
$width = $parts[0]
$height = $parts[1]

if ($OutputDir) {
    $themeDir = (New-Item -ItemType Directory -Force -Path $OutputDir).FullName
} else {
    $themeDir = Join-Path $paths.AppRoot "SD-Card-Files\THEMES\$Theme"
    New-Item -ItemType Directory -Force -Path $themeDir | Out-Null
}

if (-not (Test-Path $Source)) {
    throw "Source image not found: $Source"
}

$py = Join-Path $PSScriptRoot "generate-wallpaper.py"
if (-not (Test-Path $py)) {
    throw "Missing script: $py"
}

if (-not $NoClear) {
    if ($ClearAllThemes) {
        $themesRoot = Join-Path $paths.AppRoot "SD-Card-Files\THEMES"
        Write-Host "Clearing background*.png under SD-Card-Files\THEMES ..."
        Get-ChildItem $themesRoot -Recurse -Filter "background*.png" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
    } else {
        Write-Host "Clearing background*.png in $themeDir ..."
        Get-ChildItem $themeDir -Filter "background*.png" -File -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }
}

Write-Host "Source : $Source"
Write-Host "Display: $Display"
Write-Host "Output : $themeDir\background_${Display}.png"
Write-Host ""

python $py $Source $themeDir $width $height
if ($LASTEXITCODE -ne 0) { throw "generate-wallpaper.py failed ($LASTEXITCODE)" }

Write-Host ""
Write-Host "Done. Copy to phone SD tree if needed:"
Write-Host "  Android/data/org.edgetx.ui/EdgeTX/THEMES/$Theme/background_${Display}.png"
Write-Host "Or rebuild APK to bundle SD-Card-Files into the install package."
