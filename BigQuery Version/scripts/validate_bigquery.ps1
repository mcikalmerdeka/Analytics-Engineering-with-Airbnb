# Validate BigQuery raw data, analytics row counts, and KPI parity.
#
# Usage:
#   .\scripts\validate_bigquery.ps1 -RawOnly
#   .\scripts\validate_bigquery.ps1

[CmdletBinding()]
param(
    [switch]$RawOnly
)

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

$script:Failures = 0

function Assert-Equal {
    param([string]$Name, [string]$Expected, [string]$Actual)
    if ($Expected -eq $Actual) {
        Write-Host "PASS  $Name = $Actual"
    }
    else {
        Write-Host "FAIL  $Name expected $Expected, got $Actual"
        $script:Failures++
    }
}

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        Write-Host "PASS  $Name ($Detail)"
    }
    else {
        Write-Host "FAIL  $Name ($Detail)"
        $script:Failures++
    }
}

Import-DotEnv (Join-Path $projectRoot ".env")
$project = $env:GCP_PROJECT_ID

Write-Host "=== Raw counts ==="
$listings = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.raw.raw_listings``"
$hosts = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.raw.raw_hosts``"
$reviews = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.raw.raw_reviews``"
Assert-Equal "raw.raw_listings" "17499" $listings
Assert-Equal "raw.raw_hosts" "14111" $hosts
Assert-Equal "raw.raw_reviews" "410284" $reviews

Write-Host "=== Raw edge cases ==="
$maxComment = Invoke-BqScalar "SELECT MAX(LENGTH(comments)) FROM ``$project.raw.raw_reviews``"
Assert-True "long comments preserved" ([int]$maxComment -ge 500) "max length $maxComment"

$unicodeReviews = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.raw.raw_reviews`` WHERE REGEXP_CONTAINS(comments, r'[^\x00-\x7F]')"
Assert-True "non-ASCII text preserved" ([int]$unicodeReviews -ge 100000) "$unicodeReviews reviews"

$dollarPrices = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.raw.raw_listings`` WHERE STARTS_WITH(price, '$')"
Assert-Equal "dollar-prefixed prices" "17499" $dollarPrices

$minCreated = Invoke-BqScalar "SELECT MIN(created_at) FROM ``$project.raw.raw_listings``"
$maxCreated = Invoke-BqScalar "SELECT MAX(created_at) FROM ``$project.raw.raw_listings``"
Assert-True "listing timestamps parsed" ($minCreated -match '^2009-' -and $maxCreated -match '^2021-') "$minCreated .. $maxCreated"

if ($RawOnly) {
    Write-Host ""
    if ($script:Failures -gt 0) {
        Write-Host "FAILED: $script:Failures check(s) failed."
        exit 1
    }
    Write-Host "All raw checks passed."
    exit 0
}

Write-Host ""
Write-Host "Analytics and KPI checks will be added in Task 9."
if ($script:Failures -gt 0) {
    Write-Host "FAILED: $script:Failures check(s) failed."
    exit 1
}
Write-Host "All requested checks passed."
