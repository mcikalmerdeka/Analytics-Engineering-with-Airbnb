# Back up the Metabase application database.
#
# The Metabase app DB contains every user, collection, question, dashboard,
# setting, and session. This script writes a custom-format pg_dump to
# metabase/backups/, which is gitignored. Keep these files private: they
# contain account data and application secrets.
#
# Usage (from the project root or anywhere):
#   .\scripts\backup_metabase.ps1
#   .\scripts\backup_metabase.ps1 -OutputDir .\metabase\backups

[CmdletBinding()]
param(
    [string]$OutputDir = "metabase/backups"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

try {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $containerFile = "/tmp/metabase_$timestamp.dump"
    $localDir = Join-Path $projectRoot $OutputDir
    $localFile = Join-Path $localDir "metabase_$timestamp.dump"

    New-Item -ItemType Directory -Force -Path $localDir | Out-Null

    Write-Host "Dumping the metabase application database..."
    docker compose exec -T postgres pg_dump -U postgres -d metabase -Fc -f $containerFile
    if ($LASTEXITCODE -ne 0) {
        throw "pg_dump failed with exit code $LASTEXITCODE"
    }

    Write-Host "Copying the dump out of the container..."
    docker compose cp "postgres:$containerFile" $localFile
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose cp failed with exit code $LASTEXITCODE"
    }

    docker compose exec -T postgres rm -f $containerFile | Out-Null

    $sizeMb = [math]::Round((Get-Item $localFile).Length / 1MB, 2)
    Write-Host "Backup written: $localFile ($sizeMb MB)"
    Write-Host "Keep this file private. It is ignored by Git."
}
finally {
    Pop-Location
}
