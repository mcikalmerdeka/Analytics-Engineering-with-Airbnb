# Provision the BigQuery project for the Airbnb analytics stack.
#
# Creates the raw, staging, analytics, and snapshots datasets; creates the
# Metabase reader service account; grants least-privilege IAM; and writes the
# service-account key to .secrets/. The script is idempotent and stops on the
# first error.
#
# Usage:
#   .\scripts\provision_bigquery.ps1

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

function Invoke-Gcloud {
    param([string[]]$Arguments)
    & gcloud @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Bq {
    param([string[]]$Arguments)
    & bq @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "bq $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Import-DotEnv (Join-Path $projectRoot ".env")

$project = $env:GCP_PROJECT_ID
$location = $env:BQ_LOCATION
$billingAccount = "01D852-BA4F4C-1BCBD1"
$saName = "airbnb-metabase"
$saEmail = "$saName@$project.iam.gserviceaccount.com"
$keyPath = Join-Path $projectRoot $env:BQ_METABASE_KEY_PATH

$datasets = @(
    @{ Name = $env:BQ_RAW_DATASET; Description = "Raw Airbnb CSV data loaded by bq load." },
    @{ Name = $env:BQ_STAGING_DATASET; Description = "dbt staging models, intermediate views, and seeds." },
    @{ Name = $env:BQ_ANALYTICS_DATASET; Description = "BI-facing dimensions, fact, and marts." },
    @{ Name = $env:BQ_SNAPSHOTS_DATASET; Description = "dbt SCD snapshot tables." }
)

Write-Host "Project:  $project"
Write-Host "Location: $location"
Write-Host "Billing:  $billingAccount"

gcloud config set project $project | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Could not set the active gcloud project."
}

$billing = gcloud billing projects describe $project --format=json | ConvertFrom-Json
if (-not $billing.billingEnabled) {
    throw "Billing is not enabled for $project. Enable it before provisioning BigQuery."
}

Write-Host "Ensuring the BigQuery API is enabled..."
Invoke-Gcloud @("services", "enable", "bigquery.googleapis.com", "--project=$project") | Out-Null

Write-Host "Ensuring datasets..."
$existingDatasets = @()
$datasetJson = bq ls --project_id=$project --format=json 2>$null
if ($LASTEXITCODE -eq 0 -and $datasetJson) {
    $existingDatasets = @($datasetJson | ConvertFrom-Json | ForEach-Object { $_.datasetReference.datasetId })
}

foreach ($dataset in $datasets) {
    $name = $dataset.Name
    $description = $dataset.Description
    if ($existingDatasets -contains $name) {
        Write-Host "  exists: $name"
        Invoke-Bq @("update", "--project_id=$project", "--dataset", "--default_table_expiration=0", "--description=$description", $name) | Out-Null
    }
    else {
        Write-Host "  create: $name"
        Invoke-Bq @("--project_id=$project", "mk", "--location=$location", "--dataset", "--default_table_expiration=0", "--description=$description", $name) | Out-Null
    }
    Invoke-Bq @("update", "--project_id=$project", "--dataset", "--set_label=project:airbnb-analytics", "--set_label=layer:$name", $name) | Out-Null
}

Write-Host "Ensuring service account $saEmail..."
$saExists = $true
gcloud iam service-accounts describe $saEmail --project=$project --format=json 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $saExists = $false }
if (-not $saExists) {
    Invoke-Gcloud @(
        "iam", "service-accounts", "create", $saName,
        "--display-name=Airbnb Metabase BigQuery Reader",
        "--description=Read-only BigQuery access for the Airbnb Metabase dashboards.",
        "--project=$project"
    ) | Out-Null
    Write-Host "  created: $saEmail"
}
else {
    Write-Host "  exists: $saEmail"
}

Write-Host "Ensuring project IAM roles..."
# Project-level metadataViewer lets the account enumerate tables in raw,
# staging, and snapshots. Dataset-level READER on analytics supplies the
# metadata the driver needs, so remove the broader role if it exists.
$existingRoles = gcloud projects get-iam-policy $project `
    --flatten="bindings[].members" `
    --filter="bindings.members:serviceAccount:$saEmail" `
    --format="value(bindings.role)"
if (($existingRoles -join "`n") -match "roles/bigquery.metadataViewer") {
    Invoke-Gcloud @(
        "projects", "remove-iam-policy-binding", $project,
        "--member=serviceAccount:$saEmail",
        "--role=roles/bigquery.metadataViewer",
        "--condition=None",
        "--quiet"
    ) | Out-Null
    Write-Host "  removed: roles/bigquery.metadataViewer"
}
Invoke-Gcloud @(
    "projects", "add-iam-policy-binding", $project,
    "--member=serviceAccount:$saEmail",
    "--role=roles/bigquery.jobUser",
    "--condition=None",
    "--quiet"
) | Out-Null

Write-Host "Ensuring dataset-level read access on $($env:BQ_ANALYTICS_DATASET)..."
uv run python scripts/grant_bigquery_access.py `
    --project=$project `
    --dataset=$env:BQ_ANALYTICS_DATASET `
    --email=$saEmail
if ($LASTEXITCODE -ne 0) {
    throw "Could not grant dataset-level read access."
}

# Keep raw/staging/snapshots private even from project viewers. Remove the
# default projectReaders ACL entry from each non-analytics dataset.
foreach ($dataset in @($env:BQ_RAW_DATASET, $env:BQ_STAGING_DATASET, $env:BQ_SNAPSHOTS_DATASET)) {
    if (-not $dataset) { continue }
    uv run python scripts/grant_bigquery_access.py `
        --project=$project `
        --dataset=$dataset `
        --email=$saEmail `
        --remove-project-readers
    if ($LASTEXITCODE -ne 0) {
        throw "Could not tighten dataset access for $dataset."
    }
}

$keyDirectory = Split-Path -Parent $keyPath
New-Item -ItemType Directory -Force -Path $keyDirectory | Out-Null
if (Test-Path $keyPath) {
    Write-Host "  key exists: $keyPath"
}
else {
    Invoke-Gcloud @(
        "iam", "service-accounts", "keys", "create", $keyPath,
        "--iam-account=$saEmail",
        "--project=$project"
    ) | Out-Null
    Write-Host "  key created: $keyPath"
}

Write-Host ""
Write-Host "BigQuery provisioning complete."
bq ls --project_id=$project
Write-Host ""
Write-Host "Service account roles:"
gcloud projects get-iam-policy $project `
    --flatten="bindings[].members" `
    --filter="bindings.members:serviceAccount:$saEmail" `
    --format="value(bindings.role)"
Write-Host "Dataset access:"
uv run python scripts/grant_bigquery_access.py `
    --project=$project `
    --dataset=$env:BQ_ANALYTICS_DATASET `
    --email=$saEmail
if ($LASTEXITCODE -ne 0) {
    throw "Could not verify dataset access."
}
