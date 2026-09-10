# Download resvg CLI for SVG -> PNG (convert-gfx / display assets).
param(
    [scriptblock]$OnLog
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths
$Tools = $p.ToolsDir
$ResvgDir = Join-Path $Tools "resvg"
$ResvgExe = Join-Path $ResvgDir "resvg.exe"

function Write-ResvgLog([string]$msg) {
    if ($OnLog) { Write-BuildLog $msg $OnLog } else { Write-Output $msg }
}

if (Test-Path $ResvgExe) {
    Write-ResvgLog "resvg: $ResvgExe"
    return
}

$Zip = Join-Path $Tools "resvg-win64.zip"
$Url = "https://github.com/linebender/resvg/releases/download/v0.44.0/resvg-win64.zip"
New-Item -ItemType Directory -Force -Path $Tools | Out-Null
Invoke-DownloadFileWithProgress -Url $Url -OutFile $Zip -OnLog $OnLog
$Extract = Join-Path $Tools "resvg-extract"
if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
Write-ResvgLog "Extracting resvg..."
Expand-Archive -Path $Zip -DestinationPath $Extract -Force
New-Item -ItemType Directory -Force -Path $ResvgDir | Out-Null
$found = Get-ChildItem $Extract -Recurse -Filter "resvg.exe" | Select-Object -First 1
if (-not $found) { throw "resvg.exe not found in archive" }
Copy-Item $found.FullName $ResvgExe -Force
Remove-Item $Extract -Recurse -Force
Remove-Item $Zip -Force -ErrorAction SilentlyContinue
Write-ResvgLog "OK: $ResvgExe"
