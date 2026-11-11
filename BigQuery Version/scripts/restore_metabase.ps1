# Restore the Metabase application database from a pg_dump backup.
#
# DESTRUCTIVE: this stops Metabase, drops the current `metabase` database, and
# restores the dump. Users, settings, questions, and dashboards return to the
# state captured in the dump. The analytics `airbnb` database is not touched.
#
# Usage:
#   .\scripts\restore_metabase.ps1 -DumpFile .\metabase\backups\metabase_20261106_120000.dump
#   .\scripts\restore_metabase.ps1 -DumpFile ... -Force
#
# Without -Force you must type RESTORE to continue.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DumpFile,
    [switch]$Force,
    [string]$MetabaseUrl = "http://localhost:3000",
    [int]$HealthTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot

try {
    $resolvedDump = (Resolve-Path $DumpFile).Path
    if (-not (Test-Path $resolvedDump -PathType Leaf)) {
        throw "Dump file not found: $resolvedDump"
    }

    if (-not $Force) {
        Write-Host "This will DELETE the current Metabase application database and"
        Write-Host "restore it from:"
        Write-Host "  $resolvedDump"
        $answer = Read-Host "Type RESTORE to continue"
        if ($answer -ne "RESTORE") {
            throw "Restore cancelled."
        }
    }

    Write-Host "Stopping Metabase..."
    docker compose stop metabase | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not stop the Metabase container."
    }

    Write-Host "Recreating the metabase application database..."
    docker compose exec -T postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
        -c "DROP DATABASE IF EXISTS metabase WITH (FORCE);"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not drop the metabase database."
    }
    docker compose exec -T postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
        -c "CREATE DATABASE metabase;"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the metabase database."
    }

    $containerFile = "/tmp/metabase_restore.dump"
    Write-Host "Copying the dump into the Postgres container..."
    docker compose cp $resolvedDump "postgres:$containerFile"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not copy the dump into the container."
    }

    Write-Host "Restoring..."
    docker compose exec -T postgres pg_restore -U postgres -d metabase `
        --no-owner --no-privileges --exit-on-error $containerFile
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore failed with exit code $LASTEXITCODE. Metabase remains stopped."
    }
    docker compose exec -T postgres rm -f $containerFile | Out-Null

    Write-Host "Starting Metabase..."
    docker compose up -d metabase | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not start the Metabase container."
    }

    Write-Host "Waiting for Metabase health..."
    $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing "$MetabaseUrl/api/health" -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Host "Metabase is healthy at $MetabaseUrl."
                return
            }
        }
        catch {
            Start-Sleep -Seconds 3
        }
    }

    Write-Warning "Metabase did not report healthy within $HealthTimeoutSeconds seconds. Check: docker compose logs metabase --tail 100"
}
finally {
    Pop-Location
}
