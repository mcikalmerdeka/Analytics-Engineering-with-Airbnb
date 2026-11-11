# Load the Airbnb raw CSVs into BigQuery.
#
# The script is idempotent: every load uses WRITE_TRUNCATE, then verifies the
# exact row count. Raw load jobs are free in BigQuery.
#
# Usage:
#   .\scripts\load_raw_data.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Missing $Path"
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

function Invoke-BqScalar {
    param([string]$Sql)
    $output = & bq query `
        --project_id=$env:GCP_PROJECT_ID `
        --use_legacy_sql=false `
        --format=csv `
        --quiet `
        --maximum_bytes_billed=1000000000 `
        $Sql 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "BigQuery scalar query failed: $Sql"
    }
    $lines = @($output | Where-Object { $_ -match '\S' })
    if ($lines.Count -lt 2) {
        throw "No scalar result for query: $Sql"
    }
    return $lines[1].Trim()
}

function Invoke-RawLoad {
    param(
        [string]$Table,
        [string]$Schema,
        [string]$Csv,
        [int]$ExpectedRows
    )
    Write-Host "Loading $Table from $Csv ..."
    & bq load `
        --project_id=$env:GCP_PROJECT_ID `
        --location=$env:BQ_LOCATION `
        --source_format=CSV `
        --skip_leading_rows=1 `
        --allow_quoted_newlines `
        --encoding=UTF-8 `
        --replace `
        --schema=$Schema `
        "orbital-scene-422012-h0:$Table" `
        $Csv
    if ($LASTEXITCODE -ne 0) {
        throw "bq load failed for $Table with exit code $LASTEXITCODE"
    }

    $count = [int](Invoke-BqScalar "SELECT COUNT(*) FROM ``$($env:GCP_PROJECT_ID).$Table``")
    if ($count -ne $ExpectedRows) {
        throw "$Table loaded $count rows; expected $ExpectedRows"
    }
    Write-Host "  ${Table}: $count rows"
}

Import-DotEnv (Join-Path $projectRoot ".env")

Invoke-RawLoad `
    -Table "raw.raw_listings" `
    -Schema "id:INT64,listing_url:STRING,name:STRING,room_type:STRING,minimum_nights:INT64,host_id:INT64,price:STRING,created_at:TIMESTAMP,updated_at:TIMESTAMP" `
    -Csv "data/raw/raw_listings.csv" `
    -ExpectedRows 17499

Invoke-RawLoad `
    -Table "raw.raw_hosts" `
    -Schema "id:INT64,name:STRING,is_superhost:STRING,created_at:TIMESTAMP,updated_at:TIMESTAMP" `
    -Csv "data/raw/raw_hosts.csv" `
    -ExpectedRows 14111

Invoke-RawLoad `
    -Table "raw.raw_reviews" `
    -Schema "listing_id:INT64,date:TIMESTAMP,reviewer_name:STRING,comments:STRING,sentiment:STRING" `
    -Csv "data/raw/raw_reviews.csv" `
    -ExpectedRows 410284

Write-Host ""
Write-Host "Raw load complete."
