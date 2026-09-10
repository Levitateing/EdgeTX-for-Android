# Generate COLORLCD assets for a compile-time resolution (optional pre-build step).
param(
    [Parameter(Mandatory = $true)]
    [string]$Resolution,
    [switch]$Force,
    [switch]$FontsOnly,
    [switch]$BitmapsOnly
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths
if ($Resolution -notmatch '^(\d+)x(\d+)$') { throw "Resolution must be WIDTHxHEIGHT" }
$lcdW = [int]$Matches[1]
$lcdH = [int]$Matches[2]

$utilDir = Join-Path $p.AndroidRoot "util"

if (-not $FontsOnly) {
    & (Join-Path $PSScriptRoot "ensure-resvg.ps1")
    $script = Join-Path $utilDir "generate_display_assets.py"
    $pyArgs = @($script, $Resolution)
    if ($Force) { $pyArgs += "--force" }
    python @pyArgs
    if ($LASTEXITCODE -ne 0) { throw "generate_display_assets failed" }
    Write-Host "OK: bitmaps archived under generated/bitmaps/$Resolution"
}

if (-not $BitmapsOnly) {
    $fontScript = Join-Path $utilDir "generate_display_fonts.py"
    $fontArgs = @($fontScript, "$lcdW")
    if ($Force) { $fontArgs += "--force" }
    $fontArgs += "--lcd-h"; $fontArgs += "$lcdH"
    & (Join-Path $PSScriptRoot "ensure-font-tools.ps1")
    python @fontArgs
    if ($LASTEXITCODE -ne 0) { throw "generate_display_fonts failed" }
}

& (Join-Path $PSScriptRoot "stage-generated-assets.ps1") -Display $Resolution
Write-Host "OK: assets under generated/ (bitmaps/$Resolution, fonts/lvgl/...)"
