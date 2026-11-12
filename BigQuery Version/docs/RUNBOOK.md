# BigQuery Version - Project Runbook

A complete local analytics stack with Google BigQuery as the warehouse:
BigQuery datasets, dbt transformations, Dagster orchestration, and Metabase
dashboards. PostgreSQL in Docker stores only the Metabase application database.

## What runs here

| Component | Version / image | Where |
| --- | --- | --- |
| BigQuery | project `orbital-scene-422012-h0` | datasets `raw`, `staging`, `analytics`, `snapshots` in `asia-southeast2` |
| Python | 3.13 (uv-managed) | `BigQuery Version/.venv` |
| dbt | dbt-core / dbt-bigquery 1.12 | `airbnb_dbt/` |
| Dagster | 1.13 | `airbnb_dagster_project/`, UI on port `3001` |
| Metabase | `metabase/metabase:v0.64.3.5` | http://localhost:3000 |
| PostgreSQL | `postgres:17-alpine` | container `airbnb-postgres`, host port `5433`, app DB `metabase` |
| pgAdmin | `dpage/pgadmin4:latest` | http://localhost:5050 |

The analytics warehouse is BigQuery. The local `airbnb` database is the
container default and is intentionally empty.

## Project map

```text
BigQuery Version/
├── .env                          # local config, gitignored
├── .secrets/                     # service account key, gitignored
├── profiles.yml                  # dbt-bigquery profile, gitignored
├── pyproject.toml                # uv workspace
├── compose.yaml                  # Postgres app DB + Metabase + pgAdmin
├── docker/
│   ├── init/01_create_metabase_db.sql
│   └── pgadmin/servers.json
├── data/raw/                     # raw CSVs, gitignored
├── airbnb_dbt/                   # dbt project
├── airbnb_dagster_project/       # Dagster project
├── metabase/                     # definitions, filters, export, backups
├── scripts/                      # provisioning, loading, validation, Metabase
├── sql/                          # ad-hoc BigQuery checks
└── docs/                         # runbook, Metabase guides, superpowers specs/plans
```

### Schema map

| Dataset | Objects | Purpose |
| --- | --- | --- |
| `raw` | `raw_listings`, `raw_hosts`, `raw_reviews` | Loaded CSV snapshots |
| `staging` | `int_listings_enriched`, `int_reviews_deduped`, `int_review_topics` (views), `seed_*` (tables) | Intermediate models and seeds |
| `analytics` | `dim_*`, `fct_reviews`, `mart_*` | BI-facing star schema |
| `snapshots` | `scd_raw_hosts`, `scd_raw_listings` | dbt SCD snapshots |

`raw`, `staging`, and `snapshots` are not exposed to Metabase. The Metabase
service account has dataset-level `READER` on `analytics` only. It cannot list
or query tables in the other three datasets; only their dataset names remain
visible at project scope through BigQuery's dataset listing.

## Prerequisites

- [uv](https://docs.astral.sh/uv/)
- Docker Desktop
- Google Cloud SDK (`gcloud` and `bq`) authenticated with access to
  `orbital-scene-422012-h0`
- Billing enabled on the project (free tier is sufficient)

Verify:

```powershell
gcloud auth list
gcloud config get-value project
bq ls --project_id=orbital-scene-422012-h0
```

## First-time setup, in order

Run all commands from `BigQuery Version/`.

```powershell
cd "BigQuery Version"

# Create local configuration (both files are gitignored)
Copy-Item .env.example .env
Copy-Item profiles.yml.example profiles.yml
# Edit .env and set a strong METABASE_ADMIN_PASSWORD.
```

The examples contain the project, datasets, location, ports, and dbt profile.
They contain no secret values; the service account key is created by
`provision_bigquery.ps1` under `.secrets/`.

### 1. Install the Python environment

```powershell
uv sync
uv run python --version
uv run dbt --version
```

### 2. Provision datasets, service account, and guardrails

```powershell
.\scripts\provision_bigquery.ps1
.\scripts\set_bigquery_guardrails.ps1
```

This creates the four datasets, the `airbnb-metabase` service account, the
least-privilege dataset ACL, `.secrets/metabase-bigquery-key.json`, the
`Airbnb Analytics BigQuery Guardrail` budget, and the daily query quota. Both
scripts are idempotent.

### 3. Load the raw CSVs

```powershell
.\scripts\load_raw_data.ps1
.\scripts\validate_bigquery.ps1 -RawOnly
```

Expected raw counts: `17,499` listings, `14,111` hosts, `410,284` reviews.

### 4. Build and test dbt

```powershell
cd airbnb_dbt
uv run dbt deps --profiles-dir ..
uv run dbt debug --profiles-dir ..
uv run dbt build --profiles-dir ..
uv run dbt test --profiles-dir ..
cd ..
```

Expected: `PASS=126 WARN=0 ERROR=0 SKIP=0 NO-OP=5 TOTAL=131` and `PASS=107`.

### 5. Validate the warehouse

```powershell
.\scripts\validate_bigquery.ps1
```

Every check prints `PASS`. The script exits `1` on failure.

### 6. Start Dagster

```powershell
cd airbnb_dagster_project
uv run dagster dev -p 3001
```

Open http://localhost:3001. The asset graph contains 22 assets (18 models,
2 seeds, 2 snapshots), dbt tests appear as asset checks, and
`materialize_dbt_models_schedule` is stopped by default. Materializing
`analytics/dim_date` runs a scoped `dbt build`.

### 7. Start the Docker stack and Metabase

```powershell
cd ..
docker compose up -d
docker compose ps
```

Open http://localhost:3000. Admin credentials are in `.env`
(`METABASE_ADMIN_EMAIL` / `METABASE_ADMIN_PASSWORD`).

### 8. Provision the Metabase connection

```powershell
uv run python scripts\setup_metabase.py
```

The script completes first-run setup if needed, creates/reuses the `git-export`
API key, connects the `Airbnb Analytics` BigQuery database
(engine `bigquery-cloud-sdk`), and syncs the `analytics` dataset. Expected:
12 tables and 150 fields, and no `raw`, `staging`, or `snapshots` schemas.

### 9. Seed cards, dashboards, and filters

```powershell
uv run python scripts\seed_metabase.py
uv run python scripts\add_dashboard_filters.py
```

Expected: 6 collections (root + 5 dashboard collections), 66 cards,
5 dashboards, and all filter mappings at their expected counts.

### 10. Export and back up

```powershell
uv run python scripts\export_metabase.py
.\scripts\backup_metabase.ps1
```

The export manifest must report 6 collections, 66 cards, and 5 dashboards.

## Daily workflow

| Task | Command |
| --- | --- |
| Sync environment | `uv sync` |
| Reload raw CSVs | `.\scripts\load_raw_data.ps1` |
| Validate counts and KPIs | `.\scripts\validate_bigquery.ps1` |
| dbt build + tests | `cd airbnb_dbt; uv run dbt build --profiles-dir ..` |
| dbt docs | `cd airbnb_dbt; uv run dbt docs generate --profiles-dir ..` |
| Dagster UI | `cd airbnb_dagster_project; uv run dagster dev -p 3001` |
| Live inventory | `.\scripts\watch_db.ps1 -Once` |
| Metabase | http://localhost:3000 |
| pgAdmin | http://localhost:5050 |
| Re-seed Metabase (idempotent) | `uv run python scripts\seed_metabase.py` |
| Re-apply filters (idempotent) | `uv run python scripts\add_dashboard_filters.py` |

## Data flow

```text
data/raw/*.csv
   │ bq load --replace
   ▼
the `raw_listings`, `raw_hosts`, and `raw_reviews` tables in the `raw` dataset
   │ dbt staging (ephemeral) and intermediate (views in staging)
   ▼
analytics.dim_date / dim_listings / dim_hosts / fct_reviews / mart_*
   │
   ├──► Metabase (read-only service account, analytics only)
   └──► Dagster (dbt asset graph, daily schedule stopped by default)
```

All timestamps stay UTC. Review dates are normalized to `DATE`. `dim_date`
covers 2009-01-01 through 2021-12-31 (4,748 rows).

## Analytics model map

| Model | Grain | Rows |
| --- | --- | ---: |
| `dim_date` | one row per day | 4,748 |
| `dim_listings` | one row per listing | 17,499 |
| `dim_hosts` | one row per host | 14,111 |
| `fct_reviews` | one row per distinct review | 410,283 |
| `mart_listing_performance` | one row per listing | 17,499 |
| `mart_host_performance` | one row per host | 14,111 |
| `mart_market_monthly` | month × room type | 620 |
| `mart_price_bands` | price band × room type | 28 |
| `mart_room_type_benchmark` | one row per room type | 4 |
| `mart_review_topics` | month × topic | 1,573 |
| `mart_executive_kpis` | one row per month | 155 |
| `mart_full_moon_reviews` | full-moon flag × sentiment | 8 |

KPI parity targets: 17,499 listings; 14,111 hosts; 410,283 reviews; 6,050 active
listings; 3,254 zero-review listings; avg nightly price 70.41; median 55;
positive share 56.68%; negative share 7.33%; avg sentiment 0.494.

## How dbt and Dagster fit together

- dbt owns all transformation SQL, tests, seeds, and snapshots.
- Dagster creates one asset per dbt node and streams `dbt build` output.
- `airbnb_dagster_project/project.py` points at `airbnb_dbt/` and the root
  `profiles.yml`.
- The schedule `0 0 * * *` uses `dbt_select="fqn:*"` and starts stopped.
- Only `analytics` is exposed to Metabase.

## Reset and reload

`raw`, `staging`, `analytics`, and `snapshots` are BigQuery datasets. To reset:

```powershell
# Reload raw CSVs (truncate + reload, idempotent)
.\scripts\load_raw_data.ps1

# Rebuild every dbt object
cd airbnb_dbt
uv run dbt build --profiles-dir ..
```

To reset Metabase content, restore an application-database backup:

```powershell
.\scripts\restore_metabase.ps1 -DumpFile .\metabase\backups\<timestamp>.dump -Force
```

To recreate only the local Docker containers without deleting volumes:

```powershell
docker compose down
docker compose up -d
```

Do not delete the BigQuery datasets to "reset" the project; reloading the raw
CSVs and rebuilding dbt is faster and preserves guardrails.

## Command reference

### BigQuery

```powershell
bq ls --project_id=orbital-scene-422012-h0
bq show --format=json orbital-scene-422012-h0:analytics
bq query --use_legacy_sql=false "SELECT COUNT(*) FROM ``orbital-scene-422012-h0.analytics.dim_listings``"
```

### dbt

```powershell
cd airbnb_dbt
uv run dbt deps --profiles-dir ..
uv run dbt build --profiles-dir ..
uv run dbt test --profiles-dir ..
uv run dbt build --select fct_reviews --profiles-dir ..
uv run dbt docs generate --profiles-dir ..
```

### Docker and Metabase

```powershell
docker compose up -d
docker compose ps
docker compose logs metabase --tail 100
uv run python scripts\setup_metabase.py
uv run python scripts\seed_metabase.py --dry-run
uv run python scripts\add_dashboard_filters.py --dry-run
uv run python scripts\export_metabase.py
.\scripts\backup_metabase.ps1
```

### Cost guardrails

```powershell
gcloud billing budgets list --billing-account=01D852-BA4F4C-1BCBD1 `
  --format="table(displayName,budget.amount.specifiedAmount.units)"
gcloud quotas preferences list --project=orbital-scene-422012-h0 `
  --format="table(name,quotaId,quotaConfig.preferredValue)"
```

Guardrails: 16,000 IDR (~$1) monthly budget with 50%/100% alerts, 30 GiB/day
`QueryUsagePerDay` quota, and a 1 GiB per-query cap in `profiles.yml`.

## Local configuration files

| File | Contains | Committed? |
| --- | --- | --- |
| `.env` | project IDs, ports, Metabase admin and API key | No |
| `profiles.yml` | dbt-bigquery connection | No |
| `.secrets/metabase-bigquery-key.json` | service account key | No |
| `compose.yaml` | Postgres app DB, Metabase, pgAdmin | Yes |
| `metabase/definitions.json` | 66 cards / 5 dashboards | Yes |
| `metabase/dashboard_filters.json` | filter specs for 5 dashboards | Yes |
| `metabase/export/` | cleaned JSON export | Yes |
| `metabase/backups/*.dump` | full app DB dump | No |

The Docker volumes are BigQuery-scoped (`airbnb_bigquery_*`) so this stack does
not reuse the Postgres version's analytics schemas or Metabase content.

## Troubleshooting

### `dbt debug` fails or BigQuery returns access denied

```powershell
gcloud auth application-default login
bq query --use_legacy_sql=false "SELECT 1"
```

Confirm the active project is `orbital-scene-422012-h0`.

### `bq load` fails

Check the CSV files exist and are UTF-8. Rerun
`.\scripts\load_raw_data.ps1`; it uses `--replace`, so partial loads are safe to
retry.

### Metabase does not show the database or tables

```powershell
docker compose logs metabase --tail 100
uv run python scripts\setup_metabase.py
```

Confirm the service account can read `analytics`:

```powershell
bq query --use_legacy_sql=false `
  "SELECT COUNT(*) FROM ``orbital-scene-422012-h0.analytics.dim_listings``"
```

### A Field Filter returns `Unrecognized name: \`analytics.table\``

Native cards must alias their tables and each template tag must store the full
`table.column` alias. Re-run:

```powershell
uv run python scripts\convert_metabase_sql.py
uv run python scripts\seed_metabase.py
```

### Dagster is not reachable on port 3001

```powershell
Get-NetTCPConnection -LocalPort 3001 -State Listen
cd airbnb_dagster_project
uv run dagster dev -p 3001
```

### Metabase is unhealthy after a restore

```powershell
docker compose logs metabase --tail 100
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/api/health
```

## Verification checklist

- [ ] `bq ls` shows `raw`, `staging`, `analytics`, `snapshots` in `asia-southeast2`.
- [ ] Raw counts are 17,499 / 14,111 / 410,284.
- [ ] `dbt build` is `PASS=126 ... TOTAL=131`.
- [ ] `dbt test` is `PASS=107`.
- [ ] `validate_bigquery.ps1` prints every check as `PASS`.
- [ ] `fct_reviews` has 410,283 rows and no duplicate `review_id`.
- [ ] Snapshots have 14,111 and 17,499 rows and do not duplicate on rebuild.
- [ ] Dagster loads 22 assets and the daily schedule is stopped.
- [ ] Metabase health returns 200.
- [ ] `Airbnb Analytics` shows 12 tables and 150 fields from `analytics` only.
- [ ] The service account can list `analytics` tables but is denied on `raw`, `staging`, and `snapshots`.
- [ ] 5 dashboards and 66 cards exist; every card executes.
- [ ] Filter mappings match their expected card counts.
- [ ] A real Field Filter returns `9,890` listings for `Entire home/apt`.
- [ ] Export manifest reports 6 collections / 66 cards / 5 dashboards.
- [ ] A backup restores and Metabase remains healthy.
- [ ] No secrets or dumps are tracked by git.
