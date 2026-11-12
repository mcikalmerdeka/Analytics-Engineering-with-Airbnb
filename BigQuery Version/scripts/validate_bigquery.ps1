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

function Assert-Near {
    param(
        [string]$Name,
        [double]$Expected,
        [string]$Actual,
        [int]$Decimals = 2
    )
    $parsed = [double]::Parse($Actual, [Globalization.CultureInfo]::InvariantCulture)
    if ([math]::Round($parsed, $Decimals) -eq [math]::Round($Expected, $Decimals)) {
        Write-Host "PASS  $Name = $Actual"
    }
    else {
        Write-Host "FAIL  $Name expected $Expected, got $Actual"
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

Write-Host "=== Analytics row counts ==="
$rowCounts = [ordered]@{
    "dim_date"                  = @("analytics.dim_date", "4748")
    "dim_listings"              = @("analytics.dim_listings", "17499")
    "dim_hosts"                 = @("analytics.dim_hosts", "14111")
    "fct_reviews"               = @("analytics.fct_reviews", "410283")
    "mart_listing_performance"  = @("analytics.mart_listing_performance", "17499")
    "mart_host_performance"     = @("analytics.mart_host_performance", "14111")
    "mart_market_monthly"       = @("analytics.mart_market_monthly", "620")
    "mart_price_bands"          = @("analytics.mart_price_bands", "28")
    "mart_room_type_benchmark"  = @("analytics.mart_room_type_benchmark", "4")
    "mart_review_topics"        = @("analytics.mart_review_topics", "1573")
    "mart_executive_kpis"       = @("analytics.mart_executive_kpis", "155")
    "mart_full_moon_reviews"    = @("analytics.mart_full_moon_reviews", "8")
    "scd_raw_hosts"             = @("snapshots.scd_raw_hosts", "14111")
    "scd_raw_listings"          = @("snapshots.scd_raw_listings", "17499")
    "seed_full_moon_dates"      = @("staging.seed_full_moon_dates", "272")
    "seed_review_topics"        = @("staging.seed_review_topics", "11")
}
foreach ($name in $rowCounts.Keys) {
    $table, $expected = $rowCounts[$name]
    $actual = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.$table``"
    Assert-Equal $name $expected $actual
}

Write-Host "=== Data integrity ==="
$duplicateReviews = Invoke-BqScalar "SELECT COUNT(*) FROM (SELECT review_id FROM ``$project.analytics.fct_reviews`` GROUP BY review_id HAVING COUNT(*) > 1)"
Assert-Equal "fct_reviews duplicate review_id" "0" $duplicateReviews

$nullDates = Invoke-BqScalar "SELECT COUNT(*) FROM ``$project.analytics.dim_date`` WHERE date_day IS NULL"
Assert-Equal "dim_date null date_day" "0" $nullDates

$marketMin = Invoke-BqScalar "SELECT CAST(MIN(month_start) AS STRING) FROM ``$project.analytics.mart_market_monthly``"
$marketMax = Invoke-BqScalar "SELECT CAST(MAX(month_start) AS STRING) FROM ``$project.analytics.mart_market_monthly``"
Assert-Equal "mart_market_monthly first month" "2009-01-01" $marketMin
Assert-Equal "mart_market_monthly last month" "2021-11-01" $marketMax

Write-Host "=== Metabase service account scope ==="
$accessOutput = uv run python scripts/check_metabase_access.py 2>&1
$accessOk = $LASTEXITCODE -eq 0
$accessOutput | ForEach-Object { Write-Host $_ }
Assert-True "Metabase service account least privilege" $accessOk "analytics allowed; raw/staging/snapshots denied"

Write-Host "=== KPI parity ==="
$activeListings = Invoke-BqScalar "SELECT COUNTIF(is_active_last_12m) FROM ``$project.analytics.mart_listing_performance``"
Assert-Equal "active listings (12m)" "6050" $activeListings

$zeroReviewListings = Invoke-BqScalar "SELECT COUNTIF(review_count = 0) FROM ``$project.analytics.mart_listing_performance``"
Assert-Equal "zero-review listings" "3254" $zeroReviewListings

$avgPrice = Invoke-BqScalar "SELECT CAST(ROUND(AVG(price), 2) AS STRING) FROM ``$project.analytics.dim_listings`` WHERE NOT is_price_outlier"
Assert-Near "avg nightly price" 70.41 $avgPrice

$medianPrice = Invoke-BqScalar "SELECT CAST(MAX(median_price) AS STRING) FROM (SELECT PERCENTILE_CONT(price, 0.5) OVER () AS median_price FROM ``$project.analytics.dim_listings`` WHERE NOT is_price_outlier)"
Assert-Near "median nightly price" 55 $medianPrice

$positiveShare = Invoke-BqScalar "SELECT CAST(ROUND(SAFE_DIVIDE(COUNTIF(review_sentiment = 'positive'), COUNT(*)) * 100, 2) AS STRING) FROM ``$project.analytics.fct_reviews``"
Assert-Near "positive review share (%)" 56.68 $positiveShare

$negativeShare = Invoke-BqScalar "SELECT CAST(ROUND(SAFE_DIVIDE(COUNTIF(review_sentiment = 'negative'), COUNT(*)) * 100, 2) AS STRING) FROM ``$project.analytics.fct_reviews``"
Assert-Near "negative review share (%)" 7.33 $negativeShare

$avgSentiment = Invoke-BqScalar "SELECT CAST(ROUND(AVG(sentiment_score), 3) AS STRING) FROM ``$project.analytics.fct_reviews``"
Assert-Near "avg sentiment score" 0.494 $avgSentiment 3

if ($script:Failures -gt 0) {
    Write-Host ""
    Write-Host "FAILED: $script:Failures check(s) failed."
    exit 1
}
Write-Host ""
Write-Host "All requested checks passed."
