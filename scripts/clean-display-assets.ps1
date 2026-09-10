# Remove generated bitmaps/fonts for a compile-time resolution so the next build regenerates them.
param(
    [Parameter(Mandatory = $true)]
    [string]$Resolution,
    [switch]$IncludeBuildDirs,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")

if ($WhatIf) {
    Write-Host "[WhatIf] Would remove assets for $Resolution"
    if ($IncludeBuildDirs) { Write-Host "[WhatIf] Also build-android-* and jniLibs/*.a" }
    exit 0
}

$removed = Remove-EdgeTxDisplayAssets -Resolution $Resolution -IncludeBuildDirs:$IncludeBuildDirs
if ($removed.Count -eq 0) {
    Write-Host "Nothing on disk to remove for $Resolution (removed from saved list if present)."
} else {
    foreach ($path in $removed) { Write-Host "Removed $path" }
}
Write-Host ""
Write-Host "Done. Rebuild with:"
Write-Host "  powershell -NoProfile -File radio\src\targets\android\scripts\build-android-native.ps1 -Display $Resolution -ForceAssets"
Write-Host "  powershell -NoProfile -File radio\src\targets\android\scripts\build-apk.ps1"
