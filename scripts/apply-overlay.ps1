# Copy Android firmware overlay into the EdgeTX tree (backup upstream first).
param(
    [switch]$WhatIf,
    [switch]$SkipBackup
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\OverlayBackup.ps1")
$p = Get-EdgeTxPaths

$overlay = Join-Path $p.AndroidRoot "firmware\patches"
if (-not (Test-Path $overlay)) {
    throw "Overlay not found: $overlay"
}

if (-not $SkipBackup) {
    Backup-OverlayTargets -WhatIf:$WhatIf
}

Get-ChildItem $overlay -File -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($overlay.Length + 1)
    $dest = Join-Path $p.RepoRoot $rel
    $destDir = Split-Path $dest -Parent
    if ($WhatIf) {
        Write-Host "[WhatIf] overlay -> $rel"
    } else {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item $_.FullName $dest -Force
    }
}

if (-not $WhatIf) {
    Write-Host ""
    Write-Host "Overlay applied (upstream files backed up under targets/android/.overlay-backup)."
    Write-Host "Restore with:"
    Write-Host "  powershell -NoProfile -File radio\src\targets\android\scripts\restore-overlay.ps1"
}
