# BigQuery Version — Full Port of the Airbnb Analytics Project

- **Date:** 2026-11-11
- **Status:** Approved design, pending written-spec review
- **Source project:** `Postgres Version/`
- **Target project:** `BigQuery Version/`
- **Google Cloud project:** `airbnb-analytics` / `orbital-scene-422012-h0` / `959272142489`
- **Billing account:** `My Billing Account` / `01D852-BA4F4C-1BCBD1` (billing enabled)

## 1. Context

`Postgres Version/` is a complete local analytics stack: Dockerized PostgreSQL 17,
dbt 1.12, Dagster 1.13, Metabase 0.64, raw Airbnb CSVs, five dashboards, and a
runbook. The goal is to reproduce that project feature-for-feature in
`BigQuery Version/` with **one intentional difference**: the analytics warehouse
is Google BigQuery instead of local PostgreSQL.

Everything else must remain equivalent: project layout, dbt models, tests,
snapshots, seeds, layer names, Dagster orchestration, data, Metabase collections,
cards, dashboards, filters, exports, backups, scripts, and documentation.

The local PostgreSQL container remains only because Metabase needs an
application database. It is no longer an analytics warehouse.

## 2. Goals

1. Create four BigQuery datasets that mirror the Postgres schemas: `raw`,
   `staging`, `analytics`, `snapshots`.
2. Provision all BigQuery resources with the installed `gcloud` / `bq` CLI.
3. Load the three raw CSVs into `raw` with the same row counts and column
   semantics.
4. Port the dbt project to GoogleSQL while preserving every model name, grain,
   column name, test, seed, snapshot, exposure, and expected result.
5. Keep Dagster as the orchestration layer with no change in behavior.
6. Recreate all five Metabase dashboards and 66 cards against BigQuery.
7. Keep the Metabase application database in local PostgreSQL, with working
   export, seed, backup, and restore workflows.
8. Keep expected BigQuery cost at zero through the free tier plus explicit
   guardrails.
9. Produce a runbook that lets the project be rebuilt from a fresh clone.

## 3. Non-goals

- Rewriting the analytics logic or changing model grains.
- Migrating the Metabase application database to Cloud SQL or another service.
- Creating Cloud Storage buckets, Dataproc clusters, BI Engine reservations, or
  BigQuery reservations.
- Streaming ingestion, Data Transfer Service, or scheduled BigQuery queries.
- Production deployment to Cloud Run, GKE, or any cloud compute.
- Changing the Metabase visual design or dashboard content.

## 4. Approved decisions

| Decision | Choice |
|---|---|
| BigQuery dataset location | `asia-southeast2` (Jakarta) |
| dbt authentication | gcloud Application Default Credentials (`method: oauth`) |
| Metabase authentication | Dedicated service account JSON key |
| Metabase scope | Full port: 5 dashboards, 66 cards, filters, layout |
| Local Docker | PostgreSQL for Metabase app DB + Metabase + pgAdmin |
| Sandbox vs billing | Billing enabled on `My Billing Account`; stay within free tier |
| Cost guardrails | $1 budget alert, dbt 1 GiB per-query cap, 30 GiB/day query quota |

## 5. Architecture

```text
data/raw/raw_listings.csv ─┐
data/raw/raw_hosts.csv    ─┼─ bq load ──> raw.raw_listings
data/raw/raw_reviews.csv  ─┘              raw.raw_hosts
                                          raw.raw_reviews
                                                │
                                                ▼
                                     dbt staging (ephemeral src_*)
                                                │
                                                ▼
                                  dbt intermediate (views in staging)
                                                │
                                                ▼
                         analytics.dim_* / fct_reviews / mart_*
                         snapshots.scd_raw_hosts / scd_raw_listings
                                                │
                         ┌──────────────────────┴──────────────────────┐
                         ▼                                             ▼
                  Dagster (dbt CLI)                          Metabase (BigQuery)
```

- **dbt** owns all transformation logic and writes only to BigQuery.
- **Dagster** invokes the dbt CLI and exposes the dbt graph as assets/checks.
- **Metabase** reads only the `analytics` dataset.
- **PostgreSQL in Docker** stores only Metabase application data.

## 6. Repository layout

```text
BigQuery Version/
├── .env                          # local config, gitignored
├── .gitignore
├── .python-version               # 3.13
├── .secrets/                     # service account key, gitignored
├── .vscode/settings.json
├── pyproject.toml                # uv workspace + dbt-bigquery
├── uv.lock
├── profiles.yml                  # dbt-bigquery profile, gitignored
├── compose.yaml                  # Postgres app DB + Metabase + pgAdmin
├── README.md
├── docker/
│   ├── init/01_create_metabase_db.sql
│   └── pgadmin/servers.json
├── data/raw/                     # same three CSVs + README
├── airbnb_dbt/
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── package-lock.yml
│   ├── analyses/
│   ├── macros/
│   ├── models/
│   │   ├── sources.yml
│   │   ├── schema.yml
│   │   ├── dashboards.yml
│   │   ├── docs.md
│   │   ├── overview.md
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── analytics/
│   ├── seeds/
│   ├── snapshots/
│   └── tests/
├── airbnb_dagster_project/
│   ├── pyproject.toml
│   └── airbnb_dagster_project/
│       ├── assets.py
│       ├── definitions.py
│       ├── project.py
│       ├── schedules.py
│       └── test_path.py
├── metabase/
│   ├── definitions.json
│   ├── dashboard_filters.json
│   ├── export/
│   ├── backups/
│   ├── README.md
│   └── .gitignore
├── scripts/
│   ├── provision_bigquery.ps1
│   ├── set_bigquery_guardrails.ps1
│   ├── load_raw_data.ps1
│   ├── validate_bigquery.ps1
│   ├── watch_db.ps1
│   ├── setup_metabase.py
│   ├── convert_metabase_sql.py
│   ├── seed_metabase.py
│   ├── add_dashboard_filters.py
│   ├── export_metabase.py
│   ├── backup_metabase.ps1
│   └── restore_metabase.ps1
├── sql/
│   ├── _profile_data.sql
│   ├── check_data_information.sql
│   └── check_raw_data.sql
└── docs/
    ├── RUNBOOK.md
    ├── METABASE_DASHBOARDS.md
    ├── METABASE_FILTER_AUTOMATION.md
    ├── METABASE_SQL_WITH_FILTERS.md
    ├── legacy/                   # copied as-is
    └── superpowers/
        ├── specs/
        └── plans/
```

## 7. BigQuery provisioning

### 7.1 Project and datasets

| Item | Value |
|---|---|
| Project ID | `orbital-scene-422012-h0` |
| Project number | `959272142489` |
| Location | `asia-southeast2` |
| Datasets | `raw`, `staging`, `analytics`, `snapshots` |

`scripts/provision_bigquery.ps1` is idempotent and performs:

1. `gcloud config set project orbital-scene-422012-h0`.
2. Verify billing is enabled and the active account can create datasets.
3. Enable `bigquery.googleapis.com` if it is not already enabled.
4. Create each dataset with `bq mk --location=asia-southeast2 --dataset` if it
   does not exist.
5. Set `default_table_expiration_ms=0` on every dataset so tables do not expire.
6. Set dataset labels:
   `project=airbnb-analytics`, `layer=<raw|staging|analytics|snapshots>`.
7. Print the dataset list and location for verification.

### 7.2 Service account and IAM

Create service account:

```text
airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com
```

Roles:

| Role | Scope | Reason |
|---|---|---|
| `roles/bigquery.dataViewer` | `analytics` dataset | Read analytics tables |
| `roles/bigquery.metadataViewer` | project | Sync dataset/table metadata |
| `roles/bigquery.jobUser` | project | Run SELECT jobs |

The service account must not have access to `raw`, `staging`, or `snapshots`.
The dataset-level read grant is applied through the official BigQuery Python
client because this `bq` CLI cannot set dataset IAM policies. The result is the
same dataset ACL (`READER` for `userByEmail`). The key is written to
`.secrets/metabase-bigquery-key.json` and never committed.

### 7.3 Raw data loading

`scripts/load_raw_data.ps1` runs one `bq load` per table with
`WRITE_TRUNCATE`, so it can be rerun safely.

| Table | Schema | Expected rows |
|---|---|---:|
| `raw.raw_listings` | `id INT64, listing_url STRING, name STRING, room_type STRING, minimum_nights INT64, host_id INT64, price STRING, created_at TIMESTAMP, updated_at TIMESTAMP` | 17,499 |
| `raw.raw_hosts` | `id INT64, name STRING, is_superhost STRING, created_at TIMESTAMP, updated_at TIMESTAMP` | 14,111 |
| `raw.raw_reviews` | `listing_id INT64, date TIMESTAMP, reviewer_name STRING, comments STRING, sentiment STRING` | 410,284 |

Flags:

```text
--source_format=CSV
--skip_leading_rows=1
--allow_quoted_newlines
--encoding=UTF-8
--write_disposition=WRITE_TRUNCATE
--location=asia-southeast2
```

After loading, the script runs exact `COUNT(*)` checks and fails if a count does
not match.

### 7.4 Cost guardrails

The project is expected to stay inside BigQuery's free tier:

- **1 TiB of queries per month** per billing account.
- **10 GiB of storage per month** per billing account.
- Batch loads are free.
- Query result reads from the API are free.

Guardrails:

1. `scripts/set_bigquery_guardrails.ps1` enables
   `billingbudgets.googleapis.com`.
2. It creates a **16,000 IDR monthly budget** (approximately USD 1; the billing
   account currency is IDR) named `Airbnb Analytics BigQuery Guardrail`,
   filtered to `projects/orbital-scene-422012-h0`, with email thresholds at 50%
   and 100%. Cloud Billing rejects thresholds above 100%.
3. It creates a project-level Cloud Quota preference:
   - quota ID: `QueryUsagePerDay`
   - service: `bigquery.googleapis.com`
   - preferred value: `32212254720` bytes (30 GiB/day)
   - preference ID: `bigquery-query-usage-daily-cap`
   - contact email: the active `gcloud` account, required by the Quotas API
4. `profiles.yml` sets `maximum_bytes_billed: 1000000000` (1 GiB) per dbt query.
5. Helper scripts pass `--maximum_bytes_billed` to `bq query`.
6. The Dagster schedule stays stopped until explicitly started.
7. No streaming inserts, reservations, BI Engine, Cloud Storage, or Data
   Transfer Service are created.

Expected monthly cost at normal usage: **$0.00**. The guardrails exist to make
abnormal usage visible and to hard-cap daily query volume.

## 8. dbt project

### 8.1 Environment and dependencies

`BigQuery Version/` is initialized with `uv init --python 3.13`. The root
`pyproject.toml` declares:

```toml
dependencies = [
    "airbnb-dagster-project",
    "dbt-core>=1.12,<2",
    "dbt-bigquery>=1.12,<2",
]
```

The uv workspace includes `airbnb_dagster_project`. `uv sync` creates `.venv/`
and installs the local Dagster package in editable mode.

### 8.2 `profiles.yml`

```yaml
airbnb_dbt:
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: orbital-scene-422012-h0
      dataset: staging
      location: asia-southeast2
      threads: 4
      priority: interactive
      maximum_bytes_billed: 1000000000
  target: dev
```

`profiles.yml` is gitignored; the README and runbook document how to recreate it.

### 8.3 `dbt_project.yml`

Unchanged from the Postgres version except for comments:

- `name: airbnb_dbt`
- `profile: airbnb_dbt`
- `staging`: `+materialized: ephemeral`, `+schema: staging`
- `intermediate`: `+materialized: view`, `+schema: staging`
- `analytics`: `+materialized: table`, `+schema: analytics`
- `snapshots`: `+target_schema: snapshots`
- `vars.user_name: default_user_name_for_this_project`

`generate_schema_name` keeps the custom schema name unchanged, so `schema` maps
directly to a BigQuery dataset.

### 8.4 Sources

`models/sources.yml`:

- `database: orbital-scene-422012-h0`
- `schema: raw`
- tables `listings`, `hosts`, `reviews` with identifiers `raw_listings`,
  `raw_hosts`, `raw_reviews`
- column `data_type` values updated to BigQuery types (`int64`, `string`,
  `timestamp`, `datetime`)
- existing `dbt_expectations` tests retained
- `date` column quoted as `` `date` `` where it appears in SQL

### 8.5 SQL dialect conversion rules

| Postgres | BigQuery |
|---|---|
| `COUNT(*) FILTER (WHERE cond)` | `COUNTIF(cond)` |
| `AVG(x) FILTER (WHERE cond)` | `AVG(IF(cond, x, NULL))` |
| `x::type` | `CAST(x AS type)` |
| `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)` | exact `PERCENTILE_CONT(x, p) OVER (PARTITION BY …)` followed by `MAX`/`GROUP BY` |
| `DATE '2021-11-19' - ts::date` | `DATE_DIFF(DATE '2021-11-19', DATE(ts), DAY)` |
| `date + INTERVAL '1 month - 1 day'` | `LAST_DAY(date)` |
| `date + INTERVAL '1 month'` | `DATE_ADD(date, INTERVAL 1 MONTH)` |
| `date - INTERVAL '12 months'` | `DATE_SUB(date, INTERVAL 12 MONTH)` |
| `TO_CHAR(d, 'Month')` | `FORMAT_DATE('%B', d)` |
| `TO_CHAR(d, 'Mon')` | `FORMAT_DATE('%b', d)` |
| `TO_CHAR(d, 'Day')` | `FORMAT_DATE('%A', d)` |
| `TO_CHAR(d, 'YYYYMMDD')` | `FORMAT_DATE('%Y%m%d', d)` |
| `EXTRACT(WEEK FROM d)` | `EXTRACT(ISOWEEK FROM d)` |
| `EXTRACT(ISODOW FROM d)` | `CAST(FORMAT_DATE('%u', d) AS INT64)` |
| `EXTRACT(ISODOW FROM d) IN (6, 7)` | `EXTRACT(DAYOFWEEK FROM d) IN (1, 7)` |
| `DATE_TRUNC('month', d)::date` | `DATE_TRUNC(d, MONTH)` |
| `a / NULLIF(b, 0)` | `SAFE_DIVIDE(a, b)` |
| `x ~* regex` | `REGEXP_CONTAINS(LOWER(x), LOWER(regex))` |
| `\y` word boundary in seed regex | RE2-compatible `\b` |
| `incremental_strategy='delete+insert'` | `incremental_strategy='merge'` |
| `NULL::bigint` in UNION | `CAST(NULL AS INT64)` |
| `host_id::text` | `CAST(host_id AS STRING)` |

All timestamps remain UTC. `DATE(timestamp)` is used where the Postgres version
used `timestamp::date`.

### 8.6 Model-by-model notes

- `src_hosts`, `src_listings`, `src_reviews`: unchanged except quoted `date`
  and source resolution.
- `int_listings_enriched`: price parsing unchanged; exact p99.5 threshold via
  a window-function CTE; age via `DATE_DIFF`; bands and host segments unchanged.
- `int_reviews_deduped`: `generate_surrogate_key` unchanged; `DATE_TRUNC` and
  `LENGTH` adapted; dedupe unchanged.
- `int_review_topics`: `REGEXP_CONTAINS` with RE2 patterns; same seed topics.
- `fct_reviews`: incremental with `merge`, `unique_key='review_id'`, 3-day
  lookback via `DATE_SUB(COALESCE(MAX(review_date), DATE '1900-01-01'), INTERVAL 3 DAY)`.
- `dim_date`: dbt_utils date spine; `FORMAT_DATE` names; ISO week and ISO
  weekday; 4,748 rows.
- `dim_hosts`: host age via `DATE_DIFF`; same grain and columns.
- `dim_listings`: pass-through of `int_listings_enriched`.
- `mart_listing_performance`: `COUNTIF`, `IF`, `SAFE_DIVIDE`, `DATE_DIFF`.
- `mart_host_performance`: exact median via window CTE; `COUNTIF`; same grain.
- `mart_market_monthly`: `LAST_DAY`; `COUNTIF`; exact median via window CTE;
  zero-filled month spine.
- `mart_price_bands`: `SAFE_DIVIDE`; exact median via window CTE; zero-filled
  band spine.
- `mart_room_type_benchmark`: exact median and p90 via window CTEs;
  `SAFE_DIVIDE(COUNT(*), 17499)`.
- `mart_executive_kpis`: `COUNTIF`; `LAST_DAY`; `SAFE_DIVIDE`; exact median;
  same 155 months.
- `mart_review_topics`: `COUNTIF`; `SAFE_DIVIDE`; same month × topic grain.
- `mart_full_moon_reviews`: `DATE_ADD(full_moon_date, INTERVAL 1 DAY)`;
  `SAFE_DIVIDE`.
- `scd_raw_hosts`, `scd_raw_listings`: same snapshot config; dbt-bigquery
  `merge` strategy; `invalidate_hard_deletes=True`.
- Tests: `assert_sentiment_is_review_weighted` uses `IS DISTINCT FROM` and
  explicit `CAST(NULL AS STRING)` in UNIONs; other tests are dialect-neutral
  or need only cast changes.

### 8.7 Seeds

- `seed_full_moon_dates.csv` copied byte-for-byte.
- `seed_review_topics.csv` copied with the same topics, but `\y` boundaries
  converted to `\b` for RE2.
- Seeds materialize in `staging` because no custom `+schema` is set and
  `target.schema` is `staging`.

### 8.8 Expected outputs

| Object | Rows |
|---|---:|
| `dim_date` | 4,748 |
| `dim_listings` | 17,499 |
| `dim_hosts` | 14,111 |
| `fct_reviews` | 410,283 |
| `mart_listing_performance` | 17,499 |
| `mart_host_performance` | 14,111 |
| `mart_market_monthly` | 620 |
| `mart_price_bands` | 28 |
| `mart_room_type_benchmark` | 4 |
| `mart_review_topics` | 1,573 |
| `mart_executive_kpis` | 155 |
| `mart_full_moon_reviews` | 8 |
| `scd_raw_hosts` | 14,111 |
| `scd_raw_listings` | 17,499 |
| `seed_full_moon_dates` | 272 |
| `seed_review_topics` | 11 |

`dbt build` target: `PASS=126 WARN=0 ERROR=0 SKIP=0 NO-OP=5 TOTAL=131`.
`dbt test` target: `PASS=107`.

KPI parity targets:

| KPI | Expected |
|---|---:|
| Total listings | 17,499 |
| Total hosts | 14,111 |
| Total reviews | 410,283 |
| Active listings (12m) | 6,050 |
| Zero-review listings | 3,254 |
| Avg nightly price | 70.41 |
| Median nightly price | 55 |
| Positive review share | 56.68% |
| Negative review share | 7.33% |
| Avg sentiment score | 0.494 |

## 9. Dagster

The Dagster package is copied without behavioral changes:

- `assets.py`: `@dbt_assets` with `dbt.cli(["build"])`.
- `definitions.py`: registers assets, dbt resource, schedules.
- `project.py`: `DbtProject(project_dir=project_root / "airbnb_dbt",
  profiles_dir=project_root)` and `prepare_if_dev()`.
- `schedules.py`: daily `0 0 * * *` schedule, stopped by default.
- `pyproject.toml`: same Dagster 1.13 dependencies and
  `[tool.dagster] module_name`.

Only path comments and documentation change.

## 10. Local Docker stack

`compose.yaml` keeps the same shape:

- `postgres:17-alpine`, container `airbnb-postgres`, host port `5433`.
  - `POSTGRES_DB=airbnb` remains the default database.
  - `docker/init/01_create_metabase_db.sql` creates the `metabase` application
    database idempotently.
  - No raw, staging, analytics, or snapshots schemas are created.
- `metabase/metabase:v0.64.3.5`, container `airbnb-metabase`, host port `3000`,
  app DB `metabase`.
- `dpage/pgadmin4:latest`, container `airbnb-pgadmin`, host port `5050`,
  preconfigured to the `metabase` application database.
- Named volumes same as before.

The `airbnb` database is intentionally empty. The runbook states that it is the
container default and not used for analytics.

## 11. Metabase

### 11.1 Application setup

`scripts/setup_metabase.py`:

1. Polls `http://127.0.0.1:3000/api/health`.
2. Reads the setup token from `/api/session/properties`.
3. Posts `/api/setup` with the admin user from `.env`:
   - `METABASE_ADMIN_EMAIL`
   - `METABASE_ADMIN_PASSWORD`
   - `METABASE_ADMIN_FIRST_NAME`
   - `METABASE_ADMIN_LAST_NAME`
   - site name `Airbnb Analytics`
4. Creates an API key and writes it to `.env` as `METABASE_API_KEY`.
5. Creates the BigQuery database connection:

```json
{
  "name": "Airbnb Analytics",
  "engine": "bigquery",
  "details": {
    "project-id": "orbital-scene-422012-h0",
    "service-account-json": "<contents of .secrets/metabase-bigquery-key.json>",
    "dataset-filters-type": "inclusion",
    "dataset-filters-patterns": "analytics"
  }
}
```

6. Triggers schema sync and waits until `analytics` tables and fields are
   visible.
7. Prints the database ID and field counts.

### 11.2 Definitions conversion

`scripts/convert_metabase_sql.py` converts the Postgres definitions to
BigQuery SQL using the same mapping as dbt, with these specifics:

- `PERCENTILE_CONT ... WITHIN GROUP` → `SELECT MAX(median_price) FROM
  (SELECT PERCENTILE_CONT(price, 0.5) OVER () AS median_price ...)`.
- `COUNT(*) FILTER` → `COUNTIF`.
- `::numeric` → `CAST(... AS FLOAT64)` for chart values and `NUMERIC` where
  exact decimals matter.
- `DATE_TRUNC('month', ts)::date` → `DATE_TRUNC(DATE(ts), MONTH)`.
- `NULLS LAST` retained only if BigQuery accepts it; otherwise rewritten as
  `ORDER BY col IS NULL, col`.
- `LOWER(...) LIKE '%' || LOWER({{var}}) || '%'` retained; BigQuery supports
  `||`.
- All table references remain `analytics.<table>`.

Each template tag in `definitions.json` gains a stable field reference:

```json
{
  "name": "room_type",
  "field": "analytics.dim_listings.room_type",
  "widget_type": "string/=",
  "display_name": "Room Type"
}
```

The converter writes the converted definitions back to
`metabase/definitions.json` and is safe to rerun.

### 11.3 Dynamic field resolution and seeding

`scripts/seed_metabase.py`:

1. Loads the BigQuery database metadata from
   `/api/database/{id}/metadata`.
2. Builds a lookup from `dataset.table.column` to Metabase field ID.
3. Resolves each template tag's `field` reference to the current BigQuery
   field ID.
4. Creates missing collections, cards, and dashboards by name.
5. Seeds all five dashboards, including Executive Overview.
6. Applies the exact card layout from
   `metabase/export/dashboards/*.json`, matched by card name.
7. Preserves existing cards when rerun; creates only missing items.

### 11.4 Dashboard filters

`metabase/dashboard_filters.json` is extended with the Executive filter:

- `Month range`, slug `month_start`, tag `month_start`,
  type `date/all-options`, mapped to the six Executive cards that expose it.

`scripts/add_dashboard_filters.py` creates and maps filters for all five
dashboards. It remains idempotent by slug and preserves unrelated parameters,
mappings, layout, and tabs. The `expected_cards` counts must match.

### 11.5 Validation and export

- All 66 cards are executed through `POST /api/card/{id}/query`.
- Any card error fails validation.
- Unfiltered KPI cards must match the expected values in section 8.8.
- `scripts/export_metabase.py` regenerates `metabase/export/` with the BigQuery
  SQL and new IDs.
- `scripts/backup_metabase.ps1` and `restore_metabase.ps1` continue to operate
  on the `metabase` application database.

## 12. Scripts and documentation

### 12.1 Scripts

| Script | Responsibility |
|---|---|
| `provision_bigquery.ps1` | Datasets, service account, IAM, key |
| `set_bigquery_guardrails.ps1` | Budget alert and 30 GiB/day query quota |
| `load_raw_data.ps1` | `bq load` three raw tables and verify counts |
| `validate_bigquery.ps1` | Dataset inventory, row counts, KPI assertions |
| `watch_db.ps1` | BigQuery table inventory and live row counts |
| `setup_metabase.py` | Metabase setup, API key, BigQuery connection, sync |
| `convert_metabase_sql.py` | Postgres-to-BigQuery definitions conversion |
| `seed_metabase.py` | Dynamic field IDs, cards, dashboards, layout |
| `add_dashboard_filters.py` | Create and map all dashboard filters |
| `export_metabase.py` | Read-only JSON export |
| `backup_metabase.ps1` | `pg_dump` the Metabase app DB |
| `restore_metabase.ps1` | Restore the Metabase app DB |

### 12.2 Documentation

- `README.md`: BigQuery stack, prerequisites, first-time setup, daily commands,
  cost guardrails, and reset procedures.
- `docs/RUNBOOK.md`: full command reference, data flow, schema map, Dagster,
  Metabase, troubleshooting, and verification checklist.
- `docs/METABASE_DASHBOARDS.md`: same dashboard guide, BigQuery SQL.
- `docs/METABASE_SQL_WITH_FILTERS.md`: same 66-card SQL reference with BigQuery
  syntax and the same expected values.
- `docs/METABASE_FILTER_AUTOMATION.md`: same filter automation explanation.
- `metabase/README.md`: export/seed/backup/restore instructions for BigQuery.
- `data/raw/README.md`: same CSV sources and `bq load` instructions.
- `airbnb_dbt/README.md`: BigQuery dbt commands.
- `docs/legacy/*`: copied unchanged.
- Root `README.md`: add a BigQuery Version section and update the stack table.

## 13. Security

- `.env` and `.secrets/` are gitignored. The service account key is never
  written to logs or committed.
- Metabase uses a least-privilege service account: read-only on `analytics`,
  metadata viewer, job user. It cannot read `raw`, `staging`, or `snapshots`.
- The dbt user uses the developer's ADC; no long-lived dbt key is stored.
- The Metabase app DB backup contains user and application secrets and remains
  gitignored.
- No authentication, authorization, or encryption changes are made to the
  existing application logic.

## 14. Cost model

| Resource | Expected usage | Free tier | Expected charge |
|---|---|---:|---:|
| Storage | < 1 GiB | 10 GiB/month | $0 |
| Queries | 30–60 GiB/month at daily builds | 1 TiB/month | $0 |
| Batch loads | 3 files per refresh | Free | $0 |
| Streaming | None | — | $0 |
| Cloud Storage / Dataproc / BI Engine | None | — | $0 |
| Query result reads | Small API result sets | Free | $0 |

Guardrails cap the downside:

- `maximum_bytes_billed=1 GiB` per dbt query.
- 30 GiB/day project query quota.
- 16,000 IDR (~$1) budget alert at 50% and 100%.
- No automatic schedule by default.

## 15. Acceptance criteria

### BigQuery

- `bq ls` shows the four datasets in `asia-southeast2`.
- Dataset `default_table_expiration_ms` is `0`.
- Raw counts: 17,499 / 14,111 / 410,284.
- `dbt build`: `PASS=126 WARN=0 ERROR=0 SKIP=0 NO-OP=5 TOTAL=131`.
- `dbt test`: `PASS=107`.
- All analytics row counts and KPI values match section 8.8.
- `fct_reviews` is incremental and reruns without duplicating review IDs.
- Both snapshots exist and contain the expected row counts.

### Dagster

- `dagster dev -p 3001` starts and loads the full asset graph.
- A materialization runs `dbt build` successfully against BigQuery.

### Metabase

- `http://localhost:3000/api/health` returns healthy.
- `Airbnb Analytics` connects to BigQuery and syncs `analytics`.
- Five dashboards and 66 cards exist.
- All 66 cards execute without error.
- All dashboard filters map to the expected number of cards.
- Export and backup scripts succeed.

### Cost and security

- Budget and quota guardrails are configured.
- `maximum_bytes_billed` is active in dbt.
- No secrets are tracked by git.
- No BigQuery resources exist outside the four datasets and the service account.

## 16. Risks and mitigations

| Risk | Mitigation |
|---|---|
| BigQuery SQL differences change results | Exact dialect mapping, row-count and KPI validation, documented expected values |
| Exact median implementation differs | Window-function `PERCENTILE_CONT` per group, then aggregate; compare to Postgres values |
| ISO week/day mismatch | Use `ISOWEEK` and `FORMAT_DATE('%u')`; verify `dim_date` |
| Regex topic counts differ | Convert `\y` to `\b`; compare `mart_review_topics` to 1,573 rows and expected mention totals |
| BigQuery CSV loader rejects multiline comments | `--allow_quoted_newlines`; verify 410,284 rows and checksums |
| Metabase Field Filters fail on BigQuery | Resolve field IDs dynamically; validate every card; fallback to typed variables with explicit predicates |
| Service account key creation blocked | Fail loudly; use a user-created key or mounted ADC as fallback |
| Cost overrun | Budget alert, daily query quota, per-query cap, no schedule by default |
| Metabase app DB lost | Existing backup/restore scripts remain and are tested |

## 17. Out of scope

- Cloud deployment of Dagster or Metabase.
- BigQuery partitioning/clustering optimization.
- Streaming ingestion.
- Additional dashboards or analytics models.
- Migrating the Metabase app DB to a managed service.
- Changing the Metabase visual design or card names.

## 18. Open items

None. All design decisions are resolved. Implementation planning can begin after
this spec is reviewed.
