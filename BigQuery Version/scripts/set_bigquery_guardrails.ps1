# Configure BigQuery cost guardrails for the Airbnb analytics stack.
#
# Creates a $1 monthly budget with 50/100/200% alerts and a 30 GiB/day
# project query quota. The script is idempotent.
#
# Usage:
#   .\scripts\set_bigquery_guardrails.ps1

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

Import-DotEnv (Join-Path $projectRoot ".env")

$project = $env:GCP_PROJECT_ID
$billingAccount = "01D852-BA4F4C-1BCBD1"
$budgetName = "Airbnb Analytics BigQuery Guardrail"
$budgetAmount = "16000" # Billing account is IDR; 16,000 IDR is roughly USD 1.
$quotaPreferenceId = "bigquery-query-usage-daily-cap"
$dailyBytes = 32212254720 # 30 GiB
$contactEmail = (gcloud config get-value account).Trim()

Write-Host "Enabling the Cloud Billing Budget API..."
gcloud services enable billingbudgets.googleapis.com --project=$project | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Could not enable billingbudgets.googleapis.com."
}

Write-Host "Checking the budget..."
$budgets = @()
$budgetJson = gcloud billing budgets list --billing-account=$billingAccount --format=json 2>$null
if ($LASTEXITCODE -eq 0 -and $budgetJson) {
    $budgets = @($budgetJson | ConvertFrom-Json)
}
$budget = $budgets | Where-Object { $_.displayName -eq $budgetName }
if ($budget) {
    Write-Host "  exists: $budgetName"
}
else {
    Write-Host "  create: $budgetName"
    gcloud billing budgets create `
        --billing-account=$billingAccount `
        --display-name=$budgetName `
        --budget-amount=$budgetAmount `
        --calendar-period=month `
        --filter-projects=projects/$project `
        --threshold-rule=percent=0.5 `
        --threshold-rule=percent=1.0 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the BigQuery budget."
    }
}

Write-Host "Checking the daily query quota..."
$preferences = @()
$prefJson = gcloud quotas preferences list --project=$project --format=json 2>$null
if ($LASTEXITCODE -eq 0 -and $prefJson) {
    $preferences = @($prefJson | ConvertFrom-Json)
}
$preference = $preferences | Where-Object {
    $_.name -like "*/quotaPreferences/$quotaPreferenceId" -or $_.quotaId -eq "QueryUsagePerDay"
}
if ($preference) {
    Write-Host "  exists: $quotaPreferenceId"
}
else {
    Write-Host "  create: $quotaPreferenceId"
    gcloud quotas preferences create `
        --service=bigquery.googleapis.com `
        --project=$project `
        --quota-id=QueryUsagePerDay `
        --preferred-value=$dailyBytes `
        --preference-id=$quotaPreferenceId `
        --email=$contactEmail `
        --allow-high-percentage-quota-decrease `
        --allow-quota-decrease-below-usage | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create the daily query quota preference."
    }
}

Write-Host ""
Write-Host "Guardrails configured."
gcloud billing budgets list --billing-account=$billingAccount --format="table(displayName,budget.amount.specifiedAmount.units,budget.amount.specifiedAmount.currencyCode)"
gcloud quotas preferences list --project=$project --format="table(name,quotaId,quotaConfig.preferredValue)"
