# Backup / restore upstream files touched by firmware overlay apply.
$ErrorActionPreference = "Stop"

function Get-OverlayBackupRoot {
    . (Join-Path $PSScriptRoot "BuildEnvironment.ps1") | Out-Null
    $p = Get-EdgeTxPaths
    Join-Path $p.AndroidRoot ".overlay-backup"
}

function Get-OverlayManifestPath {
    Join-Path (Get-OverlayBackupRoot) "manifest.json"
}

function Get-OverlayPatchesDir {
    . (Join-Path $PSScriptRoot "BuildEnvironment.ps1") | Out-Null
    $p = Get-EdgeTxPaths
    Join-Path $p.AndroidRoot "firmware\patches"
}

function Get-OverlayPatchRelativePaths {
    $overlay = Get-OverlayPatchesDir
    if (-not (Test-Path $overlay)) {
        throw "Overlay not found: $overlay"
    }
    Get-ChildItem $overlay -File -Recurse | ForEach-Object {
        $_.FullName.Substring($overlay.Length + 1).Replace('/', '\')
    }
}

function Test-OverlayBackupActive {
    $manifest = Get-OverlayManifestPath
    if (-not (Test-Path $manifest)) { return $false }
    try {
        $data = Get-Content $manifest -Raw | ConvertFrom-Json
        return [bool]$data.active
    } catch {
        return $false
    }
}

function Backup-OverlayTargets {
    param([switch]$WhatIf)

    . (Join-Path $PSScriptRoot "BuildEnvironment.ps1") | Out-Null
    $p = Get-EdgeTxPaths
    $backupRoot = Get-OverlayBackupRoot
    $filesRoot = Join-Path $backupRoot "files"
    $entries = @()

    if (Test-OverlayBackupActive) {
        Write-Host "Overlay backup already active; skipping re-backup."
        return
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] create overlay backup under $backupRoot"
    } else {
        if (Test-Path $backupRoot) {
            Remove-Item $backupRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $filesRoot | Out-Null
    }

    foreach ($rel in (Get-OverlayPatchRelativePaths)) {
        $dest = Join-Path $p.RepoRoot $rel
        $hadOriginal = Test-Path $dest
        $entry = [ordered]@{
            rel         = ($rel -replace '\\', '/')
            hadOriginal = $hadOriginal
        }
        $entries += $entry

        if ($WhatIf) {
            if ($hadOriginal) {
                Write-Host "[WhatIf] backup $rel"
            } else {
                Write-Host "[WhatIf] track new overlay file $rel"
            }
            continue
        }

        if ($hadOriginal) {
            $backupPath = Join-Path $filesRoot $rel
            $backupDir = Split-Path $backupPath -Parent
            New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
            Copy-Item $dest $backupPath -Force
        }
    }

    if (-not $WhatIf) {
        $manifest = [ordered]@{
            active    = $true
            repoRoot  = $p.RepoRoot
            createdAt = (Get-Date).ToString("o")
            entries   = @($entries)
        }
        ($manifest | ConvertTo-Json -Depth 5) | Set-Content (Get-OverlayManifestPath) -Encoding UTF8
        Write-Host "Backed up overlay targets -> $backupRoot"
    }
}

function Restore-OverlayIfBackedUp {
    param(
        [switch]$WhatIf,
        [string]$Reason = ""
    )

    if (-not (Test-OverlayBackupActive)) {
        return $false
    }

    if ($Reason) {
        Write-Host ""
        Write-Host $Reason
    }

    Restore-OverlayFromBackup -WhatIf:$WhatIf
    return $true
}

function Restore-OverlayFromBackup {
    param([switch]$WhatIf)

    . (Join-Path $PSScriptRoot "BuildEnvironment.ps1") | Out-Null
    $p = Get-EdgeTxPaths
    $manifestPath = Get-OverlayManifestPath
    $backupRoot = Get-OverlayBackupRoot
    $filesRoot = Join-Path $backupRoot "files"

    if (-not (Test-Path $manifestPath)) {
        Write-Warning "No overlay backup manifest; run apply-overlay.ps1 first."
        return
    }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.repoRoot -and ($manifest.repoRoot -ne $p.RepoRoot)) {
        Write-Warning "Backup repoRoot differs from current repo; proceeding anyway."
    }

    foreach ($entry in $manifest.entries) {
        $rel = ($entry.rel -replace '/', '\')
        $dest = Join-Path $p.RepoRoot $rel
        if ($entry.hadOriginal) {
            $backupPath = Join-Path $filesRoot $rel
            if (-not (Test-Path $backupPath)) {
                Write-Warning "Missing backup for $rel"
                continue
            }
            if ($WhatIf) {
                Write-Host "[WhatIf] restore $rel"
            } else {
                $destDir = Split-Path $dest -Parent
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                Copy-Item $backupPath $dest -Force
                Write-Host "Restored $rel"
            }
        } elseif (Test-Path $dest) {
            if ($WhatIf) {
                Write-Host "[WhatIf] remove overlay-only $rel"
            } else {
                Remove-Item $dest -Force
                Write-Host "Removed overlay-only $rel"
            }
        }
    }

    if (-not $WhatIf) {
        Remove-Item $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $WhatIf) {
        Write-Host ""
        Write-Host "Main tree restored from overlay backup."
    }
}
