# Show live BigQuery raw counts and warehouse table inventory.
#
# Usage:
#   .\scripts\watch_db.ps1 -Once
#   .\scripts\watch_db.ps1 -Seconds 10

[CmdletBinding()]
param(
    [int]$Seconds = 5,
    [switch]$Once
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return
    }
    foreach ($rawLine in Get-Content $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) {
            continue
        }
        $key, $value = $line.Split("=", 2)
        $key = $key.Trim()
        $value = $value.Trim().Trim('"').Trim("'")
        if (-not [Environment]::GetEnvironmentVariable($key)) {
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

function Invoke-BqTable {
    param([string]$Sql)
    $output = & bq query `
        --project_id=$env:GCP_PROJECT_ID `
        --use_legacy_sql=false `
        --format=pretty `
        --quiet `
        --maximum_bytes_billed=1000000000 `
        $Sql 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "BigQuery query failed: $Sql"
    }
    return $output
}

Import-DotEnv (Join-Path $projectRoot ".env")
if (-not $env:GCP_PROJECT_ID) {
    throw "GCP_PROJECT_ID is missing from .env or the environment."
}

function Show-Inventory {
    $rawSql = "SELECT 'raw.raw_listings' AS object_name, COUNT(*) AS row_count FROM ``$env:GCP_PROJECT_ID.raw.raw_listings`` UNION ALL SELECT 'raw.raw_hosts', COUNT(*) FROM ``$env:GCP_PROJECT_ID.raw.raw_hosts`` UNION ALL SELECT 'raw.raw_reviews', COUNT(*) FROM ``$env:GCP_PROJECT_ID.raw.raw_reviews``"
    $inventorySql = "SELECT 'staging' AS dataset, table_id AS table_name, CASE type WHEN 1 THEN 'TABLE' WHEN 2 THEN 'VIEW' ELSE CAST(type AS STRING) END AS table_type, row_count FROM ``$env:GCP_PROJECT_ID.staging.__TABLES__`` UNION ALL SELECT 'analytics', table_id, CASE type WHEN 1 THEN 'TABLE' WHEN 2 THEN 'VIEW' ELSE CAST(type AS STRING) END, row_count FROM ``$env:GCP_PROJECT_ID.analytics.__TABLES__`` UNION ALL SELECT 'snapshots', table_id, CASE type WHEN 1 THEN 'TABLE' WHEN 2 THEN 'VIEW' ELSE CAST(type AS STRING) END, row_count FROM ``$env:GCP_PROJECT_ID.snapshots.__TABLES__`` ORDER BY dataset, table_name"

    Write-Host ""
    Write-Host "=== BigQuery inventory $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
    Write-Host "--- raw exact counts ---"
    Invoke-BqTable $rawSql
    Write-Host "--- staging / analytics / snapshots (approximate row_count) ---"
    Invoke-BqTable $inventorySql
}

do {
    Show-Inventory
    if ($Once) {
        break
    }
    Start-Sleep -Seconds $Seconds
} while ($true)
