# Restore upstream files saved before overlay apply (does not delete originals).
param(
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\OverlayBackup.ps1")

Restore-OverlayFromBackup -WhatIf:$WhatIf
