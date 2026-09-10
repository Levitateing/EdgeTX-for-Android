# Portable Node.js + lv_font_conv for display font generation.
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
$p = Get-EdgeTxPaths
$Tools = $p.ToolsDir
$NodeDir = Join-Path $Tools "node-portable"
$NodeExe = Join-Path $NodeDir "node.exe"
$NpmCmd = Join-Path $NodeDir "npm.cmd"
$FontTools = Join-Path $Tools "font-tools"

if (-not (Test-Path $NodeExe)) {
  $Zip = Join-Path $Tools "node-win-x64.zip"
  $Url = "https://nodejs.org/dist/v22.12.0/node-v22.12.0-win-x64.zip"
  Write-Output "Downloading Node.js portable..."
  New-Item -ItemType Directory -Force -Path $Tools | Out-Null
  Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
  $Extract = Join-Path $Tools "node-extract"
  if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
  Expand-Archive -Path $Zip -DestinationPath $Extract -Force
  $inner = Get-ChildItem $Extract -Directory | Select-Object -First 1
  if (Test-Path $NodeDir) { Remove-Item $NodeDir -Recurse -Force }
  Move-Item $inner.FullName $NodeDir
  Remove-Item $Extract -Recurse -Force
  Remove-Item $Zip -Force
}

New-Item -ItemType Directory -Force -Path $FontTools | Out-Null
if (-not (Test-Path (Join-Path $FontTools "node_modules\lv_font_conv"))) {
  Write-Output "Installing lv_font_conv..."
  & $NpmCmd install lv_font_conv --prefix $FontTools --no-save
}

$LvFontConv = Join-Path $FontTools "node_modules\.bin\lv_font_conv.cmd"
if (-not (Test-Path $LvFontConv)) { throw "lv_font_conv install failed" }
try {
  python -c "import lz4" 2>$null | Out-Null
} catch { }

if ($LASTEXITCODE -ne 0) {
  Write-Output "Installing Python lz4 for font compression..."
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  python -m pip install lz4 --quiet 2>&1 | Out-Null
  $ErrorActionPreference = $prevEap
  if ($LASTEXITCODE -ne 0) { throw "pip install lz4 failed (exit $LASTEXITCODE)" }
} else {
  Write-Output "Python lz4: already installed"
}
Write-Output "OK: $LvFontConv"
