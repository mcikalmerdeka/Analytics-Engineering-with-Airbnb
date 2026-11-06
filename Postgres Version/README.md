# Postgres Version

Local Airbnb analytics stack:

- **PostgreSQL 17** in Docker (host port `5433`; the local PostgreSQL 18 service is left untouched)
- **dbt v1** (`dbt-core` 1.12 + `dbt-postgres` 1.11)
- **Dagster** 1.13 for orchestration
- **Metabase** in Docker (host port `3000`), with its application data stored in Postgres

Full command reference and troubleshooting: [`docs/RUNBOOK.md`](docs/RUNBOOK.md). The older setup notes are in `docs/` as well.

## Prerequisites

- [uv](https://docs.astral.sh/uv/)
- Docker Desktop

## First-time setup

```powershell
cd "Postgres Version"

# 1. Create/use the uv-managed Python 3.13 environment
uv sync

# 2. Start Postgres, Metabase, and pgAdmin, and load the raw CSVs into the raw schema
docker compose up -d
docker compose exec postgres psql -U postgres -d airbnb -c "select count(*) from raw.raw_listings;"

# 3. Install dbt packages, then build and test the project
cd airbnb_dbt
uv run dbt deps
uv run dbt build --profiles-dir ..

# 4. Start Dagster on port 3001
cd ../airbnb_dagster_project
uv run dagster dev -p 3001
```

The raw CSVs must exist in `data/raw/` (the CSV files are gitignored; see `data/raw/README.md`). The Docker init scripts load `raw_listings.csv`, `raw_hosts.csv`, and `raw_reviews.csv` into the `raw` schema and create the `metabase` application database on the first container start.

## Daily commands

| Task | Command |
| --- | --- |
| Sync Python environment | `uv sync` |
| Start stack | `docker compose up -d` |
| Stop stack | `docker compose stop` |
| dbt build + test | `cd airbnb_dbt; uv run dbt build --profiles-dir ..` |
| dbt docs | `cd airbnb_dbt; uv run dbt docs generate --profiles-dir ..` |
| Dagster UI | `cd airbnb_dagster_project; uv run dagster dev -p 3001` |
| Metabase | http://localhost:3000 |
| Export Metabase definitions | `uv run python scripts\export_metabase.py` |
| Backup Metabase app DB | `.\scripts\backup_metabase.ps1` |
| pgAdmin | http://localhost:5050 |
| Live row counts | `.\scripts\watch_db.ps1` |
| Run a dbt command directly | `cd airbnb_dbt; uv run dbt <command> --profiles-dir ..` |

## Viewing the database with pgAdmin

pgAdmin runs in the same Compose stack and is pre-configured with the `Airbnb Postgres` server:

- URL: http://localhost:5050
- Login email: `admin@example.com`
- Login password: `admin123`
- Server host: `postgres` (inside Docker)
- Database: `airbnb`
- Database user: `postgres`
- Database password: `cikalmerdeka`

On first connection, pgAdmin may ask for the database password (`cikalmerdeka`). If the pre-configured server does not appear, add it manually with the values above. pgAdmin can take up to a minute to initialize on its first start.

## Live row counts

To watch table counts change while Dagster or dbt runs:

```powershell
.\scripts\watch_db.ps1
```

The script shows exact row counts for the raw tables and lists staging views plus analytics and snapshot tables as they appear (non-raw counts are PostgreSQL estimates). It works even before the first `dbt build`. Press `Ctrl+C` to stop. If PowerShell blocks the script, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\watch_db.ps1
```

## Connecting Metabase

Metabase runs in the Compose stack at http://localhost:3000. Its application
data (users, questions, dashboards) lives in the separate `metabase` database
inside the same Postgres container, not in the container filesystem.

On the first start, complete the setup wizard and create the admin account.
Then add the analytics database with these values:

- Display name: `Airbnb Analytics`
- Host: `postgres` (the Compose service name; `localhost` only works from the host)
- Port: `5432` (inside the Docker network; `5433` is the host mapping)
- Database: `airbnb`
- User: `metabase`
- Password: `metabasePassword123`
- SSL: off (local Docker network)

Query the `analytics` schema. `staging` is internal and the `reporter` role has
no access to it. The full dashboard build guide is in
[`docs/METABASE_DASHBOARDS.md`](docs/METABASE_DASHBOARDS.md). If you build the
questions as native SQL, use the matching
[`docs/METABASE_SQL_WITH_FILTERS.md`](docs/METABASE_SQL_WITH_FILTERS.md).

## Saving and publishing Metabase content

Metabase stores everything in the `metabase` application database, so it
survives container restarts. To keep a reviewable copy in Git and a private
restore point, use the `metabase/` folder:

```powershell
# Export collections, questions/models, and dashboards to JSON
uv run python scripts\export_metabase.py

# Create the documented collections/questions/dashboards (idempotent)
uv run python scripts\seed_metabase.py

# Full application-database backup (keep private; gitignored)
.\scripts\backup_metabase.ps1
```

- Commit `metabase/export/` — it contains the dashboard definitions, SQL,
  visualization settings, and filter mappings.
- Do **not** commit `.env` or `metabase/backups/*.dump`; both are gitignored.
- Restore a dump with `.\scripts\restore_metabase.ps1 -DumpFile <path>`.
- Full details, sizes, and security notes: [`metabase/README.md`](metabase/README.md).

Metabase's native YAML serialization is a Pro/Enterprise feature. The OSS image
uses the JSON export above for versioning; the `.dump` is the exact restore
path.

## Reset the local database

The init scripts run only when the Docker volume is empty. To reload the raw data:

```powershell
docker compose down -v
docker compose up -d
```

`down -v` also removes the Metabase application database and its volume, so
saved questions and dashboards are lost. Re-run the Metabase setup wizard after
the reset. This is the supported full reset; dropping only the `airbnb`
database keeps Metabase settings but requires re-running the init scripts and a
full `dbt build` manually.

## Notes

- The local `profiles.yml` and `.env` are development-only and gitignored.
- The uv-managed Python 3.13 lives under uv's own Python directory; the system Python 3.14 is not used.
- dbt v2 (Fusion) is not yet supported for Postgres. The project stays on dbt v1 until the Postgres adapter ships.
