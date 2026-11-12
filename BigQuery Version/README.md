# BigQuery Version

Airbnb analytics stack with Google BigQuery as the warehouse:

- **BigQuery** datasets `raw`, `staging`, `analytics`, and `snapshots` in `orbital-scene-422012-h0` (`asia-southeast2`)
- **dbt** 1.12 (`dbt-core` + `dbt-bigquery`) for transformations
- **Dagster** 1.13 for orchestration
- **Metabase** 0.64 for dashboards, with its application database in local Dockerized PostgreSQL

The local PostgreSQL container is only the Metabase application database. It is
not the analytics warehouse.

## Prerequisites

- [uv](https://docs.astral.sh/uv/)
- Docker Desktop
- Google Cloud SDK (`gcloud` and `bq`) authenticated as a user with access to
  project `orbital-scene-422012-h0`

## First-time setup

```powershell
cd "BigQuery Version"

# 0. Create local configuration from the committed examples
Copy-Item .env.example .env
Copy-Item profiles.yml.example profiles.yml
# Edit .env: set a strong METABASE_ADMIN_PASSWORD and keep the GCP values.

# 1. Create/use the uv-managed Python 3.13 environment
uv sync

# 2. Create BigQuery datasets, the Metabase reader service account, and guardrails
.\scripts\provision_bigquery.ps1
.\scripts\set_bigquery_guardrails.ps1

# 3. Load the raw CSVs into BigQuery
.\scripts\load_raw_data.ps1

# 4. Install dbt packages, then build and test
cd airbnb_dbt
uv run dbt deps --profiles-dir ..
uv run dbt build --profiles-dir ..
cd ..

# 5. Start the Metabase application database stack
docker compose up -d

# 6. Provision the Metabase connection, cards, dashboards, and filters
uv run python scripts\setup_metabase.py
uv run python scripts\seed_metabase.py
uv run python scripts\add_dashboard_filters.py

# 7. Start Dagster on port 3001
cd airbnb_dagster_project
uv run dagster dev -p 3001
```

The raw CSVs must exist in `data/raw/` (see `data/raw/README.md`).

## Daily commands

| Task | Command |
| --- | --- |
| Sync Python environment | `uv sync` |
| Reload raw CSVs into BigQuery | `.\scripts\load_raw_data.ps1` |
| Validate BigQuery counts and KPIs | `.\scripts\validate_bigquery.ps1` |
| dbt build + test | `cd airbnb_dbt; uv run dbt build --profiles-dir ..` |
| dbt docs | `cd airbnb_dbt; uv run dbt docs generate --profiles-dir ..` |
| Dagster UI | `cd airbnb_dagster_project; uv run dagster dev -p 3001` |
| Live row counts | `.\scripts\watch_db.ps1` |
| Metabase | http://localhost:3000 |
| pgAdmin (Metabase app DB only) | http://localhost:5050 |

## Cost guardrails

This project is designed to stay inside the BigQuery free tier:

- **1 TiB of queries per month** free
- **10 GiB of storage per month** free
- Batch loads are free

Additional guardrails:

- `maximum_bytes_billed: 1000000000` (1 GiB) per dbt query
- 30 GiB/day project query quota
- 16,000 IDR (~$1) monthly budget alert at 50% and 100%
- Dagster schedule stopped by default

Expected monthly BigQuery cost at normal usage: **$0.00**.

## Local Metabase application database

PostgreSQL runs in Docker on host port `5433` and stores only Metabase
application data in the `metabase` database. Start it with:

```powershell
docker compose up -d
```

The analytics warehouse remains BigQuery.

## Documentation

Full setup, architecture, Dagster, Metabase, troubleshooting, and verification
details are in [`docs/RUNBOOK.md`](docs/RUNBOOK.md).
