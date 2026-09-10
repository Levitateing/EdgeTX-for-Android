# Reset official EdgeTX main tree to origin/main (keeps radio/src/targets/android/).
param(
    [switch]$SkipFetch,
    [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "lib\BuildEnvironment.ps1")
. (Join-Path $PSScriptRoot "lib\OverlayBackup.ps1")

$p = Get-EdgeTxPaths
$repo = $p.RepoRoot

function Find-GitExe {
    if ($env:EDGE_TX_GIT -and (Test-Path $env:EDGE_TX_GIT)) { return $env:EDGE_TX_GIT }
    $candidates = @(
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "git.exe not found. Install Git or set EDGE_TX_GIT."
}

function Invoke-Git {
    param([string[]]$GitArgs)
    $display = "git " + ($GitArgs -join ' ')
    if ($WhatIf) {
        Write-Host "[WhatIf] $display"
        return
    }
    & $script:Git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git failed ($LASTEXITCODE): $display"
    }
}

$Git = Find-GitExe

Write-Host "=== Sync upstream main ==="
Write-Host "Repo: $repo"
Write-Host ""

if (Test-OverlayBackupActive) {
    Write-Host "Active overlay backup detected; restoring first..."
    if ($WhatIf) {
        Write-Host "[WhatIf] Restore-OverlayFromBackup"
    } else {
        Restore-OverlayFromBackup
    }
}

Push-Location $repo
try {
    $branch = if ($WhatIf) { "main" } else { (& $Git branch --show-current).Trim() }
    if ($branch -ne "main") {
        Write-Warning "Current branch is '$branch' (expected main). Proceeding anyway."
    }

    if (-not $SkipFetch) {
        Write-Host "Fetching origin/main..."
        Invoke-Git @("fetch", "origin", "main")
    }

    Write-Host "Resetting tracked files to origin/main..."
    Invoke-Git @("reset", "--hard", "origin/main")

    Write-Host "Refreshing submodules..."
    Invoke-Git @("submodule", "update", "--init", "--recursive", "--force")
} finally {
    Pop-Location
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "[WhatIf] sync complete"
    return
}

Write-Host ""
Write-Host "=== Verification ==="
$checks = @(
    @{
        Name = "lv_img_buf.h uses 11-bit w/h"
        Path = Join-Path $repo "radio\src\thirdparty\lvgl\src\draw\lv_img_buf.h"
        Pattern = "w\s*:\s*11"
        MustMatch = $true
    },
    @{
        Name = "radio/src/CMakeLists.txt has no ANDROID"
        Path = Join-Path $repo "radio\src\CMakeLists.txt"
        Pattern = "ANDROID"
        MustMatch = $false
    },
    @{
        Name = "yaml_datastructs.cpp has no PCBANDROID"
        Path = Join-Path $repo "radio\src\storage\yaml\yaml_datastructs.cpp"
        Pattern = "PCBANDROID"
        MustMatch = $false
    },
    @{
        Name = "convert-gfx.py has no targets/android"
        Path = Join-Path $repo "tools\convert-gfx.py"
        Pattern = "targets/android"
        MustMatch = $false
    },
    @{
        Name = "root CMakeLists.txt has no NOT ANDROID guard"
        Path = Join-Path $repo "CMakeLists.txt"
        Pattern = "NOT ANDROID"
        MustMatch = $false
    }
)

$failed = 0
foreach ($c in $checks) {
    if (-not (Test-Path $c.Path)) {
        Write-Host "FAIL $($c.Name) (missing file)"
        $failed++
        continue
    }
    $hit = Select-String -Path $c.Path -Pattern $c.Pattern -Quiet
    $ok = if ($c.MustMatch) { $hit } else { -not $hit }
    if ($ok) {
        Write-Host "OK   $($c.Name)"
    } else {
        Write-Host "FAIL $($c.Name)"
        $failed++
    }
}

if (Test-OverlayBackupActive) {
    Write-Host "FAIL overlay backup still active (.overlay-backup/)"
    $failed++
} else {
    Write-Host "OK   no overlay backup residue"
}

$gitStatus = & $Git -C $repo status --short
$dirty = @($gitStatus | Where-Object { $_ -notmatch '^\?\?\s+radio/src/targets/android/' })
if ($dirty.Count -eq 0) {
    Write-Host "OK   git status clean (only targets/android/ may be untracked)"
} else {
    Write-Host "FAIL git status not clean:"
    $dirty | Select-Object -First 20 | ForEach-Object { Write-Host "     $_" }
    if ($dirty.Count -gt 20) { Write-Host "     ... and $($dirty.Count - 20) more" }
    $failed++
}

$head = (& $Git -C $repo log -1 --oneline).Trim()
Write-Host ""
Write-Host "HEAD: $head"

if ($failed -gt 0) {
    throw "Upstream sync verification failed ($failed check(s))."
}

Write-Host ""
Write-Host "Upstream main is clean. Android platform code under radio/src/targets/android/ is preserved."
