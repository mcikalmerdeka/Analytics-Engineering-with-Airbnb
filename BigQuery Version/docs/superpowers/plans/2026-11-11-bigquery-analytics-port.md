# BigQuery Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `BigQuery Version/` as a complete, working clone of `Postgres Version/` with Google BigQuery as the analytics warehouse and local PostgreSQL retained only as the Metabase application database.

**Architecture:** Raw CSVs are loaded into four BigQuery datasets (`raw`, `staging`, `analytics`, `snapshots`) with the `gcloud`/`bq` CLI. dbt transforms raw data with GoogleSQL models that preserve every name, grain, test, seed, snapshot, and expected result. Dagster orchestrates dbt through the same asset graph. Metabase reads only `analytics`, with cards and dashboards converted from Postgres SQL to BigQuery SQL.

**Tech Stack:** Python 3.13 + `uv`, dbt-core 1.12 + dbt-bigquery 1.12, Dagster 1.13, Metabase 0.64, Docker Compose, Google BigQuery, PowerShell helper scripts.

**Spec:** `BigQuery Version/docs/superpowers/specs/2026-11-11-bigquery-analytics-port-design.md`

## Global Constraints

- Google Cloud project: `orbital-scene-422012-h0` (project number `959272142489`, display name `airbnb-analytics`).
- Billing account: `01D852-BA4F4C-1BCBD1` (`My Billing Account`), billing enabled.
- BigQuery dataset location: `asia-southeast2` (Jakarta). This cannot be changed later.
- Datasets: `raw`, `staging`, `analytics`, `snapshots`.
- Python: `>=3.13,<3.14`; use `uv init`, `uv add`, `uv sync`, and `uv run`.
- dbt: `dbt-core>=1.12,<2`, `dbt-bigquery>=1.12,<2`; profile name `airbnb_dbt`; target `dev`.
- Dagster: `>=1.13.28,<1.14`; `dagster-dbt>=0.29.28,<0.30`; `dagster-webserver>=1.13.28,<1.14`.
- Metabase image: `metabase/metabase:v0.64.3.5`; host port `3000`.
- Local Postgres image: `postgres:17-alpine`; host port `5433`; application database `metabase`; container `airbnb-postgres`.
- pgAdmin: `dpage/pgadmin4:latest`; host port `5050`; preconfigured to the `metabase` database.
- BigQuery service account: `airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com`.
- Service account roles: `roles/bigquery.dataViewer` on the `analytics` dataset, `roles/bigquery.metadataViewer` and `roles/bigquery.jobUser` on the project.
- Service account key path: `.secrets/metabase-bigquery-key.json`; never commit it.
- Cost guardrails: $1 monthly budget with 50/100/200% alerts; 30 GiB/day `QueryUsagePerDay` quota (`32212254720` bytes); dbt `maximum_bytes_billed: 1000000000`.
- Raw row counts: `raw_listings` 17,499; `raw_hosts` 14,111; `raw_reviews` 410,284.
- Analytics row counts: `dim_date` 4,748; `dim_listings` 17,499; `dim_hosts` 14,111; `fct_reviews` 410,283; `mart_listing_performance` 17,499; `mart_host_performance` 14,111; `mart_market_monthly` 620; `mart_price_bands` 28; `mart_room_type_benchmark` 4; `mart_review_topics` 1,573; `mart_executive_kpis` 155; `mart_full_moon_reviews` 8.
- Snapshot row counts on first build: `scd_raw_hosts` 14,111; `scd_raw_listings` 17,499.
- Seed row counts: `seed_full_moon_dates` 272; `seed_review_topics` 11.
- `dbt build` target: `PASS=126 WARN=0 ERROR=0 SKIP=0 NO-OP=5 TOTAL=131`; `dbt test` target: `PASS=107`.
- KPI targets: listings 17,499; hosts 14,111; reviews 410,283; active listings 6,050; zero-review listings 3,254; avg nightly price 70.41; median nightly price 55; positive share 56.68%; negative share 7.33%; avg sentiment 0.494.
- Metabase: 5 dashboards, 66 cards, all cards execute, all filters mapped to expected card counts.
- Commit style: one logical change per commit; imperative, descriptive messages, for example `Add BigQuery datasets and service account`. Do not commit `.env`, `.secrets/`, `metabase/backups/*.dump`, `.venv/`, `target/`, or `logs/`.
- Use branch `feat/bigquery-version` unless the owner says otherwise.

## Review Focus

These are the failure modes the spec implies but that a normal happy-path build may not exercise. Each has a test in the owning task.

1. **CSV edge cases:** quoted newlines in `raw_reviews.comments`, German umlauts, Cyrillic text, `$`-prefixed prices, and timestamps with `.000` milliseconds must load without truncation or row loss. Tested in Task 3.
2. **Silent numeric drift:** BigQuery `PERCENTILE_CONT`, ISO week/day extraction, `COUNTIF`, and RE2 topic regexes must reproduce the Postgres row counts and KPI values. Tested in Tasks 8 and 9.
3. **Metabase Field Filters:** the converted cards must still filter correctly after the Postgres field IDs are replaced by BigQuery field IDs. Tested in Task 15 with a real filtered query.
4. **Least-privilege access:** the Metabase service account must see `analytics` and must not see `raw`, `staging`, or `snapshots`. Tested in Task 12.
5. **Idempotency and cost:** re-running provisioning, raw loads, dbt builds, and Metabase seeding must not create duplicates or exceed the guardrails. Tested in Tasks 2, 3, 9, and 14.

---

### Task 1: Scaffold `BigQuery Version` and the uv workspace

**Files:**
- Create: `BigQuery Version/.python-version`
- Create: `BigQuery Version/pyproject.toml`
- Create: `BigQuery Version/.env` (local, gitignored)
- Create: `BigQuery Version/profiles.yml` (local, gitignored)
- Create: `BigQuery Version/README.md`
- Modify: `.gitignore`
- Copy: `Postgres Version/data`, `Postgres Version/airbnb_dbt`, `Postgres Version/airbnb_dagster_project`, `Postgres Version/metabase`, `Postgres Version/scripts`, `Postgres Version/sql`, `Postgres Version/docs`, `Postgres Version/docker`, `Postgres Version/.vscode`
- Do not copy: `target/`, `dbt_packages/`, `logs/`, `.venv/`, `__pycache__/`, `*.egg-info/`, `.tmp_dagster_home_*`, `metabase/backups/*.dump`

**Interfaces:**
- Consumes: nothing.
- Produces: a `BigQuery Version/` directory with the same source tree as the Postgres version, a working `uv` workspace, and a root `.gitignore` that ignores secrets and build artifacts.

- [ ] **Step 1: Create the feature branch**

```powershell
cd "E:\Personal Projects\Analytics Engineering with Airbnb"
git checkout -b feat/bigquery-version
```

Expected: `Switched to a new branch 'feat/bigquery-version'`.

- [ ] **Step 2: Initialize the uv project**

```powershell
cd "BigQuery Version"
uv init --bare --python 3.13 --name airbnb-bigquery-analytics
```

Expected: `pyproject.toml` and `.python-version` are created; no sample `main.py`.

- [ ] **Step 3: Write the root `pyproject.toml`**

Use this exact content:

```toml
[project]
name = "airbnb-bigquery-analytics"
version = "0.1.0"
description = "Airbnb analytics stack on Google BigQuery: dbt, Dagster, and Metabase."
requires-python = ">=3.13,<3.14"
dependencies = [
    "airbnb-dagster-project",
    "dbt-core>=1.12,<2",
    "dbt-bigquery>=1.12,<2",
]

[tool.uv.workspace]
members = ["airbnb_dagster_project"]

[tool.uv.sources]
airbnb-dagster-project = { workspace = true }
```

- [ ] **Step 4: Copy the static project tree**

Use PowerShell `Copy-Item` with `-Recurse` for the listed directories, then delete build artifacts and `.venv` from the copies. Keep `metabase/definitions.json`, `metabase/dashboard_filters.json`, `metabase/export/`, `metabase/README.md`, and `metabase/.gitignore`; do not copy `metabase/backups/*.dump`.

- [ ] **Step 5: Create the local `.env`**

```dotenv
# Google Cloud
GCP_PROJECT_ID=orbital-scene-422012-h0
GCP_PROJECT_NUMBER=959272142489
BQ_LOCATION=asia-southeast2
BQ_RAW_DATASET=raw
BQ_STAGING_DATASET=staging
BQ_ANALYTICS_DATASET=analytics
BQ_SNAPSHOTS_DATASET=snapshots
BQ_METABASE_KEY_PATH=.secrets/metabase-bigquery-key.json

# Local Docker / Metabase application database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=cikalmerdeka
POSTGRES_DB=airbnb
POSTGRES_PORT=5433
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=admin123
PGADMIN_PORT=5050
METABASE_PORT=3000
METABASE_URL=http://127.0.0.1:3000
METABASE_ADMIN_EMAIL=admin@example.com
METABASE_ADMIN_PASSWORD=admin123
METABASE_ADMIN_FIRST_NAME=Airbnb
METABASE_ADMIN_LAST_NAME=Admin
MB_SITE_URL=http://localhost:3000
TZ=Asia/Jakarta
```

Do not add `METABASE_API_KEY` yet; Task 12 writes it.

- [ ] **Step 6: Create the dbt profile**

`profiles.yml`:

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

- [ ] **Step 7: Update the root `.gitignore`**

Add these entries while preserving the existing Postgres and Snowflake rules:

```gitignore
# BigQuery Version patterns
BigQuery Version/.venv/
BigQuery Version/logs/
BigQuery Version/airbnb_dagster_project/.tmp_dagster_home_*
BigQuery Version/.secrets/
!BigQuery Version/airbnb_dbt/seeds/seed_full_moon_dates.csv
!BigQuery Version/airbnb_dbt/seeds/seed_review_topics.csv
```

Also ensure `**/profiles.yml`, `**/.env`, `**/.user.yml`, and `*.csv` remain ignored, with the two seed exceptions above.

- [ ] **Step 8: Sync the environment and verify**

```powershell
cd "BigQuery Version"
uv sync
uv run python --version
uv run dbt --version
uv tree --depth 1
```

Expected:
- Python `3.13.x`
- `dbt-core` 1.12.x and `dbt-bigquery` 1.12.x are installed.
- `airbnb-dagster-project` is installed in editable mode.
- `uv tree --depth 1` lists the three top-level dependencies.

- [ ] **Step 9: Commit the scaffold**

```powershell
git add "BigQuery Version" .gitignore
git commit -m "Scaffold BigQuery Version uv workspace and project skeleton"
```

Do not stage `.env`, `profiles.yml`, or `.secrets/`.

---

### Task 2: Provision BigQuery datasets, service account, and cost guardrails

**Files:**
- Create: `BigQuery Version/scripts/provision_bigquery.ps1`
- Create: `BigQuery Version/scripts/set_bigquery_guardrails.ps1`
- Test: run both scripts and inspect BigQuery, IAM, billing, and quota state.

**Interfaces:**
- Consumes: `GCP_PROJECT_ID`, `GCP_PROJECT_NUMBER`, `BQ_LOCATION`, `BQ_*_DATASET` from `.env`.
- Produces: datasets `raw`, `staging`, `analytics`, `snapshots`; service account `airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com`; key file `.secrets/metabase-bigquery-key.json`; budget `Airbnb Analytics BigQuery Guardrail`; quota preference `bigquery-query-usage-daily-cap`.

- [ ] **Step 1: Write `provision_bigquery.ps1`**

The script must be idempotent and stop on the first error (`$ErrorActionPreference = "Stop"`). It must:

1. Load `.env` into process environment without overwriting existing variables.
2. Set the active project: `gcloud config set project orbital-scene-422012-h0`.
3. Fail if `gcloud billing projects describe` does not return `billingEnabled: true`.
4. Enable the BigQuery API if needed:
   `gcloud services enable bigquery.googleapis.com --project=orbital-scene-422012-h0`.
5. Create each dataset only if missing:
   `bq --project_id=orbital-scene-422012-h0 mk --location=asia-southeast2 --dataset --default_table_expiration=0 --description="<layer> layer" <dataset>`.
6. Update every existing dataset with `bq update --dataset --default_table_expiration=0`.
7. Add dataset labels `project=airbnb-analytics` and `layer=<layer>`.
8. Create the service account if missing:
   `gcloud iam service-accounts create airbnb-metabase --display-name="Airbnb Metabase BigQuery Reader"`.
9. Grant project roles:
   `roles/bigquery.metadataViewer` and `roles/bigquery.jobUser`.
10. Grant dataset role:
    `bq add-iam-policy-binding --member="serviceAccount:airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com" --role="roles/bigquery.dataViewer" --project_id=orbital-scene-422012-h0 analytics`.
    If this CLI build rejects a dataset identifier, fall back to
    `bq get-iam-policy --format=json analytics`, add the binding, and apply it
    with `bq set-iam-policy analytics <file>`.
11. Create the key only if `.secrets/metabase-bigquery-key.json` does not exist:
    `gcloud iam service-accounts keys create .secrets/metabase-bigquery-key.json --iam-account=airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com`.
12. Print a summary of datasets, roles, and key path.

- [ ] **Step 2: Write `set_bigquery_guardrails.ps1`**

The script must be idempotent and must:

1. Enable `billingbudgets.googleapis.com` on the project.
2. Create a $1 budget only if `Airbnb Analytics BigQuery Guardrail` does not already exist:

```powershell
gcloud billing budgets create `
  --billing-account=01D852-BA4F4C-1BCBD1 `
  --display-name="Airbnb Analytics BigQuery Guardrail" `
  --budget-amount=1USD `
  --filter-projects=projects/orbital-scene-422012-h0 `
  --filter-services=services/bigquery.googleapis.com `
  --threshold-rule=percent=0.5 `
  --threshold-rule=percent=1.0 `
  --threshold-rule=percent=2.0
```

3. Create the daily query quota only if it does not exist:

```powershell
gcloud quotas preferences create `
  --service=bigquery.googleapis.com `
  --project=orbital-scene-422012-h0 `
  --quota-id=QueryUsagePerDay `
  --preferred-value=32212254720 `
  --preference-id=bigquery-query-usage-daily-cap `
  --allow-high-percentage-quota-decrease `
  --allow-quota-decrease-below-usage
```

4. Print the current budget and quota preference.

- [ ] **Step 3: Run provisioning and guardrails**

```powershell
cd "BigQuery Version"
.\scripts\provision_bigquery.ps1
.\scripts\set_bigquery_guardrails.ps1
```

Expected: both scripts exit `0` and print the resource summary.

- [ ] **Step 4: Verify datasets**

```powershell
bq ls --project_id=orbital-scene-422012-h0
bq show --format=json orbital-scene-422012-h0:analytics
```

Expected: four datasets, all with location `asia-southeast2` and `defaultTableExpirationMs` absent or `0`.

- [ ] **Step 5: Verify IAM and key**

```powershell
gcloud projects get-iam-policy orbital-scene-422012-h0 `
  --flatten="bindings[].members" `
  --filter="bindings.members:airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com" `
  --format="value(bindings.role)"

bq get-iam-policy --project_id=orbital-scene-422012-h0 analytics
Test-Path .secrets\metabase-bigquery-key.json
```

Expected: `roles/bigquery.metadataViewer`, `roles/bigquery.jobUser`, a dataset binding for `roles/bigquery.dataViewer`, and `True`.

- [ ] **Step 6: Verify guardrails**

```powershell
gcloud billing budgets list --billing-account=01D852-BA4F4C-1BCBD1 --format="table(displayName,budget.amount)"
gcloud quotas preferences list --project=orbital-scene-422012-h0 --service=bigquery.googleapis.com --format="table(name,quotaId,preferredValue)"
```

Expected: the budget and `bigquery-query-usage-daily-cap` are present.

- [ ] **Step 7: Rerun both scripts to prove idempotency**

Run the two scripts again. Expected: no duplicate datasets, no duplicate service account, no duplicate key, no duplicate budget, no duplicate quota preference. The scripts print "already exists" or equivalent.

- [ ] **Step 8: Commit**

```powershell
git add "BigQuery Version/scripts/provision_bigquery.ps1" "BigQuery Version/scripts/set_bigquery_guardrails.ps1"
git commit -m "Provision BigQuery datasets, service account, and cost guardrails"
```

---

### Task 3: Load raw CSVs into BigQuery and validate

**Files:**
- Create: `BigQuery Version/scripts/load_raw_data.ps1`
- Create: `BigQuery Version/scripts/validate_bigquery.ps1` (raw section)
- Test: raw row counts, multiline comments, Unicode, price strings.

**Interfaces:**
- Consumes: datasets from Task 2; `data/raw/raw_listings.csv`, `raw_hosts.csv`, `raw_reviews.csv`.
- Produces: `raw.raw_listings` 17,499 rows; `raw.raw_hosts` 14,111 rows; `raw.raw_reviews` 410,284 rows.

- [ ] **Step 1: Write `load_raw_data.ps1`**

For each table, run:

```powershell
bq load `
  --project_id=orbital-scene-422012-h0 `
  --location=asia-southeast2 `
  --source_format=CSV `
  --skip_leading_rows=1 `
  --allow_quoted_newlines `
  --encoding=UTF-8 `
  --write_disposition=WRITE_TRUNCATE `
  --schema="id:INT64,listing_url:STRING,name:STRING,room_type:STRING,minimum_nights:INT64,host_id:INT64,price:STRING,created_at:TIMESTAMP,updated_at:TIMESTAMP" `
  "orbital-scene-422012-h0:raw.raw_listings" `
  "data/raw/raw_listings.csv"
```

Use the same pattern with these schemas:

- `raw_hosts`: `id:INT64,name:STRING,is_superhost:STRING,created_at:TIMESTAMP,updated_at:TIMESTAMP`
- `raw_reviews`: `listing_id:INT64,date:TIMESTAMP,reviewer_name:STRING,comments:STRING,sentiment:STRING`

After each load, run an exact count and throw if it differs from the expected value.

- [ ] **Step 2: Write the raw validation section of `validate_bigquery.ps1`**

Add a `Invoke-BqScalar` helper that runs `bq query --use_legacy_sql=false --format=csv --quiet "<sql>"` and returns the second CSV line (the first line is the header). Use it to check three separate scalars:

```powershell
$listings = Invoke-BqScalar "SELECT COUNT(*) FROM \`orbital-scene-422012-h0.raw.raw_listings\`"
$hosts    = Invoke-BqScalar "SELECT COUNT(*) FROM \`orbital-scene-422012-h0.raw.raw_hosts\`"
$reviews  = Invoke-BqScalar "SELECT COUNT(*) FROM \`orbital-scene-422012-h0.raw.raw_reviews\`"
```

Expected: `17499`, `14111`, `410284`.

- [ ] **Step 3: Add edge-case checks**

```sql
-- A multiline review must be preserved, not truncated at the first newline.
SELECT COUNT(*) AS multiline_reviews
FROM `orbital-scene-422012-h0.raw.raw_reviews`
WHERE STRPOS(comments, '\n') > 0;

-- German umlauts and non-ASCII text must survive the UTF-8 load.
SELECT COUNT(*) AS unicode_reviews
FROM `orbital-scene-422012-h0.raw.raw_reviews`
WHERE REGEXP_CONTAINS(comments, r'[üöäÜÖÄß]');

-- Prices must remain the original dollar strings.
SELECT COUNT(*) AS dollar_prices
FROM `orbital-scene-422012-h0.raw.raw_listings`
WHERE STARTS_WITH(price, '$');

-- Timestamps must parse.
SELECT MIN(created_at) AS min_created, MAX(created_at) AS max_created
FROM `orbital-scene-422012-h0.raw.raw_listings`;
```

Expected: `multiline_reviews > 0`, `unicode_reviews > 0`, `dollar_prices = 17499`, and non-null timestamp range from 2009 to 2021.

- [ ] **Step 4: Run the loader and validator**

```powershell
cd "BigQuery Version"
.\scripts\load_raw_data.ps1
.\scripts\validate_bigquery.ps1 -RawOnly
```

Expected: three successful load jobs and the raw checks pass.

- [ ] **Step 5: Rerun the loader to prove idempotency**

Run `load_raw_data.ps1` again. Expected: counts unchanged; no duplicate rows.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/scripts/load_raw_data.ps1" "BigQuery Version/scripts/validate_bigquery.ps1"
git commit -m "Load raw Airbnb CSVs into BigQuery with validation"
```

---

### Task 4: Configure dbt and port metadata

**Files:**
- Modify: `BigQuery Version/airbnb_dbt/dbt_project.yml`
- Modify: `BigQuery Version/airbnb_dbt/models/sources.yml`
- Copy/verify: `airbnb_dbt/macros/*.sql`, `analyses/*.sql`, `packages.yml`, `package-lock.yml`, `seeds/*.csv`, `snapshots/*.sql`, `tests/*.sql`
- Create: `BigQuery Version/airbnb_dbt/README.md`

**Interfaces:**
- Consumes: `profiles.yml`, raw tables from Task 3.
- Produces: a parsed dbt project connected to BigQuery.

- [ ] **Step 1: Verify the dbt project config**

`dbt_project.yml` must keep the Postgres values:

```yaml
name: "airbnb_dbt"
version: "1.0.0"
profile: "airbnb_dbt"
model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]
models:
  airbnb_dbt:
    staging:
      +materialized: ephemeral
      +schema: staging
    intermediate:
      +materialized: view
      +schema: staging
    analytics:
      +materialized: table
      +schema: analytics
snapshots:
  airbnb_dbt:
    +target_schema: snapshots
vars:
  user_name: default_user_name_for_this_project
```

- [ ] **Step 2: Update `sources.yml`**

Set:

```yaml
database: orbital-scene-422012-h0
schema: raw
tables:
  - name: listings
    identifier: raw_listings
  - name: hosts
    identifier: raw_hosts
  - name: reviews
    identifier: raw_reviews
```

Change `data_type` values to BigQuery types: `int64`, `string`, `timestamp`, `datetime`. Keep all descriptions and `dbt_expectations` tests.

- [ ] **Step 3: Update the regex seed for RE2**

In `seeds/seed_review_topics.csv`, replace every `\y` word boundary with `\b`. Do not change topic names or any other pattern. The resulting first row must be:

```csv
topic,keywords_regex
cleanliness,sauber|\bclean\b|hygien|schmutz|\bdirty\b
```

- [ ] **Step 4: Install packages and parse**

```powershell
cd "BigQuery Version/airbnb_dbt"
uv run dbt deps --profiles-dir ..
uv run dbt parse --profiles-dir ..
```

Expected: packages install, parse succeeds, no unsupported macro errors.

- [ ] **Step 5: Check the connection**

```powershell
uv run dbt debug --profiles-dir ..
```

Expected: `All checks passed!` with project `orbital-scene-422012-h0`, dataset `staging`, location `asia-southeast2`.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/airbnb_dbt/dbt_project.yml" "BigQuery Version/airbnb_dbt/models/sources.yml" "BigQuery Version/airbnb_dbt/seeds/seed_review_topics.csv"
git commit -m "Configure dbt BigQuery profile, sources, and RE2 topic seed"
```

---

### Task 5: Port staging and intermediate models

**Files:**
- Modify: `BigQuery Version/airbnb_dbt/models/staging/src_hosts.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/staging/src_listings.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/staging/src_reviews.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/intermediate/int_listings_enriched.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/intermediate/int_reviews_deduped.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/intermediate/int_review_topics.sql`
- Test: query the intermediate views and compare counts.

**Interfaces:**
- Consumes: `source('airbnb_source', ...)`, `dbt_utils.generate_surrogate_key`, `seed_review_topics`.
- Produces: `staging.int_listings_enriched` view (17,499 rows), `staging.int_reviews_deduped` view (410,283 rows), `staging.int_review_topics` view (one row per review × matched topic).

- [ ] **Step 1: Port the three staging models**

Keep the same selected columns. Quote the source review date column as `` `date` AS review_date ``.

- [ ] **Step 2: Port `int_listings_enriched`**

Required conversions:

- Price parse: `CAST(REPLACE(REPLACE(l.price_str, '$', ''), ',', '') AS NUMERIC)`.
- Age: `DATE_DIFF(DATE '2021-11-19', DATE(l.listing_created_at), DAY)`.
- Exact p99.5 by room type:

```sql
price_thresholds AS (
    SELECT room_type, MAX(p99_5_price) AS p99_5_price
    FROM (
        SELECT
            room_type,
            PERCENTILE_CONT(price, 0.995) OVER (PARTITION BY room_type) AS p99_5_price
        FROM parsed_listings
    )
    GROUP BY room_type
)
```

- `host_listing_count`, price bands, minimum-night bands, listing-age cohorts, and host segments must be identical to the Postgres model.

- [ ] **Step 3: Port `int_reviews_deduped`**

Required conversions:

- Keep `dbt_utils.generate_surrogate_key(['listing_id', 'review_date', 'reviewer_name', 'review_text'])`.
- `LENGTH(review_text)` is valid in BigQuery.
- `DATE_TRUNC(review_date, MONTH)` instead of `DATE_TRUNC('month', review_date)::date`.
- Keep `ROW_NUMBER()` dedupe and the `duplicate_rank = 1` filter.

- [ ] **Step 4: Port `int_review_topics`**

Use:

```sql
INNER JOIN {{ ref('seed_review_topics') }} AS t
    ON REGEXP_CONTAINS(LOWER(r.review_text), LOWER(t.keywords_regex))
WHERE r.has_comment = TRUE
```

- [ ] **Step 5: Build and validate the intermediate layer**

```powershell
cd "BigQuery Version/airbnb_dbt"
uv run dbt build --select +int_listings_enriched +int_reviews_deduped --profiles-dir ..
```

Then query:

```sql
SELECT COUNT(*) FROM `orbital-scene-422012-h0.staging.int_listings_enriched`; -- 17499
SELECT COUNT(*) FROM `orbital-scene-422012-h0.staging.int_reviews_deduped`; -- 410283
```

Expected: both counts match.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/airbnb_dbt/models/staging" "BigQuery Version/airbnb_dbt/models/intermediate"
git commit -m "Port staging and intermediate dbt models to BigQuery SQL"
```

---

### Task 6: Port dimensions and the incremental review fact

**Files:**
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/dim_date.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/dim_hosts.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/dim_listings.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/fct_reviews.sql`
- Test: row counts, ISO date attributes, incremental rerun.

**Interfaces:**
- Consumes: `int_listings_enriched`, `int_reviews_deduped`, `src_hosts`.
- Produces: `analytics.dim_date` 4,748 rows; `analytics.dim_hosts` 14,111; `analytics.dim_listings` 17,499; `analytics.fct_reviews` 410,283.

- [ ] **Step 1: Port `dim_date`**

Use `dbt_utils.date_spine` unchanged. Convert:

- `CAST(FORMAT_DATE('%Y%m%d', date_day) AS INT64) AS date_key`
- `EXTRACT(YEAR FROM date_day)`, `EXTRACT(QUARTER FROM date_day)`, `EXTRACT(MONTH FROM date_day)`
- `FORMAT_DATE('%B', date_day) AS month_name`
- `FORMAT_DATE('%b', date_day) AS month_short`
- `DATE_TRUNC(date_day, MONTH) AS year_month`
- `EXTRACT(ISOWEEK FROM date_day) AS week_of_year`
- `CAST(FORMAT_DATE('%u', date_day) AS INT64) AS day_of_week`
- `FORMAT_DATE('%A', date_day) AS day_name`
- `EXTRACT(DAYOFWEEK FROM date_day) IN (1, 7) AS is_weekend`
- Keep `WHERE date_day < DATE '2022-01-01'`.

- [ ] **Step 2: Port `dim_hosts`**

Use `DATE_DIFF(DATE '2021-11-19', DATE(h.created_at), DAY) AS host_age_days`. Keep the same `is_superhost` mapping, host attributes, and grain.

- [ ] **Step 3: Port `dim_listings`**

This model is a pass-through of `int_listings_enriched`; keep the same columns and order.

- [ ] **Step 4: Port `fct_reviews`**

Use:

```sql
{{ config(
    materialized='incremental',
    unique_key='review_id',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}
```

The incremental filter must be:

```sql
{% if is_incremental() %}
WHERE review_date >= (
    SELECT DATE_SUB(COALESCE(MAX(review_date), DATE '1900-01-01'), INTERVAL 3 DAY)
    FROM {{ this }}
)
{% endif %}
```

- [ ] **Step 5: Build and validate**

```powershell
uv run dbt build --select +dim_date +dim_hosts +dim_listings +fct_reviews --profiles-dir ..
```

Expected: all nodes pass. Then query:

```sql
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_date`;        -- 4748
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_hosts`;       -- 14111
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_listings`;    -- 17499
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.fct_reviews`;     -- 410283
SELECT COUNT(*) - COUNT(DISTINCT review_id) FROM `orbital-scene-422012-h0.analytics.fct_reviews`; -- 0
```

- [ ] **Step 6: Verify ISO date attributes**

```sql
SELECT day_of_week, day_name, week_of_year, is_weekend
FROM `orbital-scene-422012-h0.analytics.dim_date`
WHERE date_day = DATE '2021-01-01';
```

Expected: `day_of_week = 5`, `day_name = 'Friday'`, `week_of_year = 53`, `is_weekend = FALSE`.

- [ ] **Step 7: Test incremental behavior**

Run `uv run dbt build --select fct_reviews --profiles-dir ..` again. Then recheck `COUNT(*)` and duplicate count. Expected: 410,283 rows and 0 duplicates.

- [ ] **Step 8: Commit**

```powershell
git add "BigQuery Version/airbnb_dbt/models/analytics/dim_date.sql" "BigQuery Version/airbnb_dbt/models/analytics/dim_hosts.sql" "BigQuery Version/airbnb_dbt/models/analytics/dim_listings.sql" "BigQuery Version/airbnb_dbt/models/analytics/fct_reviews.sql"
git commit -m "Port dimensions and incremental review fact to BigQuery"
```

---

### Task 7: Port the core marts

**Files:**
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_listing_performance.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_host_performance.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_market_monthly.sql`
- Test: counts and KPI values.

**Interfaces:**
- Consumes: `dim_listings`, `dim_hosts`, `fct_reviews`, `mart_listing_performance`.
- Produces: `mart_listing_performance` 17,499; `mart_host_performance` 14,111; `mart_market_monthly` 620.

- [ ] **Step 1: Port `mart_listing_performance`**

Replace `FILTER` with `COUNTIF`/`IF`, use `DATE_SUB(DATE '2021-11-19', INTERVAL 12 MONTH)`, `DATE_DIFF(DATE '2021-11-19', r.last_review_date, DAY)`, and `SAFE_DIVIDE` for the percentage columns. Keep all columns and order.

- [ ] **Step 2: Port `mart_host_performance`**

Use `COUNTIF(is_active_last_12m)` and `SAFE_DIVIDE`. Exact median:

```sql
host_median AS (
    SELECT host_id, MAX(median_price) AS median_price
    FROM (
        SELECT
            host_id,
            PERCENTILE_CONT(IF(NOT is_price_outlier, price, NULL), 0.5)
                OVER (PARTITION BY host_id) AS median_price
        FROM {{ ref('mart_listing_performance') }}
    )
    GROUP BY host_id
)
```

Join it into the final select.

- [ ] **Step 3: Port `mart_market_monthly`**

Use `LAST_DAY(year_month) AS month_end`, `COUNTIF`, `SAFE_DIVIDE`, and an exact median CTE:

```sql
listing_median AS (
    SELECT month_start, MAX(median_price) AS median_price
    FROM (
        SELECT
            m.month_start,
            PERCENTILE_CONT(IF(NOT l.is_price_outlier, l.price, NULL), 0.5)
                OVER (PARTITION BY m.month_start) AS median_price
        FROM month_spine AS m
        LEFT JOIN {{ ref('dim_listings') }} AS l
            ON DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    )
    GROUP BY month_start
)
```

Also use `DATE(l.listing_created_at) >= m.month_start` in the `listing_monthly`
CTE; do not compare a `TIMESTAMP` column directly to a `DATE`.

- [ ] **Step 4: Build and validate**

```powershell
uv run dbt build --select +mart_listing_performance +mart_host_performance +mart_market_monthly --profiles-dir ..
```

Then query:

```sql
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_listing_performance`; -- 17499
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_host_performance`;    -- 14111
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_market_monthly`;      -- 620
SELECT ROUND(AVG(price), 2) FROM `orbital-scene-422012-h0.analytics.dim_listings` WHERE NOT is_price_outlier; -- 70.41
```

- [ ] **Step 5: Commit**

```powershell
git add "BigQuery Version/airbnb_dbt/models/analytics/mart_listing_performance.sql" "BigQuery Version/airbnb_dbt/models/analytics/mart_host_performance.sql" "BigQuery Version/airbnb_dbt/models/analytics/mart_market_monthly.sql"
git commit -m "Port listing, host, and market marts to BigQuery"
```

---

### Task 8: Port the remaining marts and topic matching

**Files:**
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_price_bands.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_room_type_benchmark.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_review_topics.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_executive_kpis.sql`
- Modify: `BigQuery Version/airbnb_dbt/models/analytics/mart_full_moon_reviews.sql`
- Build: `BigQuery Version/airbnb_dbt/models/intermediate/int_review_topics.sql`
- Test: counts, topic totals, full-moon counts.

**Interfaces:**
- Consumes: `mart_listing_performance`, `dim_listings`, `fct_reviews`, `seed_review_topics`, `seed_full_moon_dates`.
- Produces: `mart_price_bands` 28; `mart_room_type_benchmark` 4; `mart_review_topics` 1,573; `mart_executive_kpis` 155; `mart_full_moon_reviews` 8.

- [ ] **Step 1: Port `mart_price_bands`**

Use `SAFE_DIVIDE(COUNTIF(is_superhost), COUNT(*))`, `SAFE_DIVIDE(COUNTIF(is_active_last_12m), COUNT(*))`, and an exact median CTE over `review_count` partitioned by `price_band, room_type`.

- [ ] **Step 2: Port `mart_room_type_benchmark`**

Use `SAFE_DIVIDE(COUNT(*), 17499)` for `share_of_supply`, `SAFE_DIVIDE(COUNTIF(is_superhost), COUNT(*))`, and exact median/p90 CTEs partitioned by `room_type`.

- [ ] **Step 3: Port `mart_review_topics`**

Use `COUNTIF(review_sentiment = 'negative')` and `SAFE_DIVIDE`. Keep the month × topic grid and the `has_comment = TRUE` filter.

- [ ] **Step 4: Port `mart_executive_kpis`**

Use `LAST_DAY`, `COUNTIF`, `SAFE_DIVIDE`, and exact median. Replace timestamp comparisons with `DATE(l.listing_created_at)` and `DATE_ADD`. Keep the 155-month spine and the `is_latest_review_month = DATE '2021-10-01'` flag.

- [ ] **Step 5: Port `mart_full_moon_reviews`**

Use `DATE_ADD(fm.full_moon_date, INTERVAL 1 DAY)` and `SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER (PARTITION BY is_full_moon))`.

- [ ] **Step 6: Build and validate**

```powershell
uv run dbt build --select +mart_price_bands +mart_room_type_benchmark +mart_review_topics +mart_executive_kpis +mart_full_moon_reviews --profiles-dir ..
```

Then query:

```sql
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_price_bands`;             -- 28
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_room_type_benchmark`;    -- 4
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_review_topics`;          -- 1573
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_executive_kpis`;         -- 155
SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_full_moon_reviews`;      -- 8
```

- [ ] **Step 7: Verify topic and full-moon parity**

```sql
SELECT topic, SUM(mentions) AS mentions
FROM `orbital-scene-422012-h0.analytics.mart_review_topics`
GROUP BY topic
ORDER BY mentions DESC;
```

Expected: location 150,557; host 109,692; cleanliness 100,973; transport 66,742; check-in 43,206; noise 43,035; kitchen 21,356; bed 19,276; bathroom 17,805; wifi 8,810; breakfast 6,585.

```sql
SELECT is_full_moon, review_sentiment, reviews
FROM `orbital-scene-422012-h0.analytics.mart_full_moon_reviews`
ORDER BY is_full_moon, review_sentiment;
```

Expected: 8 rows; totals must match the Postgres run.

- [ ] **Step 8: Commit**

```powershell
git add "BigQuery Version/airbnb_dbt/models/analytics/mart_price_bands.sql" "BigQuery Version/airbnb_dbt/models/analytics/mart_room_type_benchmark.sql" "BigQuery Version/airbnb_dbt/models/analytics/mart_review_topics.sql" "BigQuery Version/airbnb_dbt/models/analytics/mart_executive_kpis.sql" "BigQuery Version/airbnb_dbt/models/analytics/mart_full_moon_reviews.sql" "BigQuery Version/airbnb_dbt/models/intermediate/int_review_topics.sql"
git commit -m "Port pricing, topic, executive, and full-moon marts to BigQuery"
```

---

### Task 9: Port tests and snapshots, then pass the full build

**Files:**
- Modify: `BigQuery Version/airbnb_dbt/models/schema.yml`
- Modify: `BigQuery Version/airbnb_dbt/tests/*.sql`
- Modify: `BigQuery Version/airbnb_dbt/snapshots/scd_raw_hosts.sql`
- Modify: `BigQuery Version/airbnb_dbt/snapshots/scd_raw_listings.sql`
- Modify: `BigQuery Version/scripts/validate_bigquery.ps1` (analytics and KPI section)

**Interfaces:**
- Consumes: all models, seeds, and raw tables.
- Produces: a full green `dbt build`, a green `dbt test`, and a validated acceptance script.

- [ ] **Step 1: Port schema tests**

Keep every model name, column name, and test. Update only BigQuery-specific expressions:

- `accepted_values` values remain the same.
- `relationships` tests remain the same.
- `dbt_expectations` tests remain the same.
- `positive_value` remains the same.
- Any `data_type` in descriptions or source columns uses BigQuery types.

- [ ] **Step 2: Port custom tests**

- `assert_no_future_reviews.sql`: unchanged.
- `assert_price_positive.sql`: unchanged.
- `assert_review_row_count_matches_source.sql`: unchanged.
- `assert_sentiment_is_review_weighted.sql`:
  - keep `IS DISTINCT FROM`;
  - replace `a.host_id::text` with `CAST(a.host_id AS STRING)`;
  - replace `NULL AS dimension_2` with `CAST(NULL AS STRING)` in every UNION branch.
- `consistent_created_at.sql`: unchanged.
- `dim_listings_minimum_nights.sql`: unchanged.
- `no_nulls_in_dim_listings.sql`: unchanged; the `no_nulls_in_columns` macro uses `adapter.get_columns_in_relation`, which works on BigQuery.

- [ ] **Step 3: Port snapshots**

Keep the same snapshot names, `unique_key`, `timestamp` strategy, `updated_at`, and `invalidate_hard_deletes = True`. The only change is that dbt-bigquery uses its `merge` strategy automatically.

- [ ] **Step 4: Extend `validate_bigquery.ps1`**

Add checks for:

- all analytics row counts in the Global Constraints;
- KPI values in the Global Constraints;
- `fct_reviews` duplicate count = 0;
- `dim_date` has 4,748 rows and no null `date_day`;
- `mart_market_monthly` has 620 rows and `month_start` between 2009-01-01 and 2021-11-01;
- `mart_review_topics` has 1,573 rows;
- snapshots have the expected first-build counts.

The script must print `PASS` or `FAIL <check>` for each check and exit `1` if any fail.

- [ ] **Step 5: Run the full build**

```powershell
cd "BigQuery Version/airbnb_dbt"
uv run dbt build --profiles-dir ..
```

Expected: `Completed successfully` and `PASS=126 WARN=0 ERROR=0 SKIP=0 NO-OP=5 TOTAL=131`. If the node count differs, verify that no tests or exposures were accidentally dropped; the node inventory must match the Postgres project.

- [ ] **Step 6: Run tests separately**

```powershell
uv run dbt test --profiles-dir ..
```

Expected: `PASS=107`.

- [ ] **Step 7: Run the acceptance validator**

```powershell
cd ..
.\scripts\validate_bigquery.ps1
```

Expected: every check prints `PASS`, exit code `0`.

- [ ] **Step 8: Rerun the full build to prove idempotency**

```powershell
cd airbnb_dbt
uv run dbt build --profiles-dir ..
```

Expected: still green; `fct_reviews` remains 410,283 rows; snapshots do not duplicate unchanged rows.

- [ ] **Step 9: Commit**

```powershell
git add "BigQuery Version/airbnb_dbt/models/schema.yml" "BigQuery Version/airbnb_dbt/tests" "BigQuery Version/airbnb_dbt/snapshots" "BigQuery Version/scripts/validate_bigquery.ps1"
git commit -m "Port dbt tests and snapshots and pass the full BigQuery build"
```

---

### Task 10: Wire Dagster to the BigQuery dbt project

**Files:**
- Modify: `BigQuery Version/airbnb_dagster_project/airbnb_dagster_project/project.py` (path comments only)
- Modify: `BigQuery Version/airbnb_dagster_project/airbnb_dagster_project/assets.py` (if needed)
- Modify: `BigQuery Version/airbnb_dagster_project/airbnb_dagster_project/definitions.py` (if needed)
- Modify: `BigQuery Version/airbnb_dagster_project/airbnb_dagster_project/schedules.py` (if needed)
- Modify: `BigQuery Version/airbnb_dagster_project/pyproject.toml` (unchanged dependencies)

**Interfaces:**
- Consumes: `airbnb_dbt` project and root `profiles.yml`.
- Produces: a Dagster definitions object with all dbt assets and the daily schedule.

- [ ] **Step 1: Verify the copied Dagster files**

`project.py` must resolve `project_root` as `Path(__file__).resolve().parents[2]` and create:

```python
airbnb_dbt_project = DbtProject(
    project_dir=project_root / "airbnb_dbt",
    profiles_dir=project_root,
)
airbnb_dbt_project.prepare_if_dev()
```

`assets.py` must keep `@dbt_assets(manifest=airbnb_dbt_project.manifest_path)` and `dbt.cli(["build"])`.

`definitions.py` must register the assets, the `DbtCliResource`, and the schedules.

`schedules.py` must keep the daily `0 0 * * *` schedule with `dbt_select="fqn:*"`.

- [ ] **Step 2: Validate the definitions import**

```powershell
cd "BigQuery Version/airbnb_dagster_project"
uv run python -c "from airbnb_dagster_project.definitions import defs; print(len(defs.assets or []))"
```

Expected: import succeeds and prints a positive asset count.

- [ ] **Step 3: Validate the Dagster definitions**

```powershell
uv run dagster definitions validate -m airbnb_dagster_project.definitions
```

Expected: no validation errors.

- [ ] **Step 4: Start Dagster and check the UI**

```powershell
uv run dagster dev -p 3001
```

Open `http://localhost:3001`. Expected: the asset graph lists the dbt models, seeds, snapshots, and asset checks; the `materialize_dbt_models_schedule` exists and is stopped.

- [ ] **Step 5: Materialize one asset**

With Dagster running, use the UI to materialize `dim_date`, or run the CLI equivalent supported by Dagster 1.13:

```powershell
uv run dagster asset materialize --select dim_date -m airbnb_dagster_project.definitions
```

Expected: run succeeds and the dbt log shows a BigQuery materialization.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/airbnb_dagster_project"
git commit -m "Wire Dagster assets to the BigQuery dbt project"
```

---

### Task 11: Add the local Docker stack for Metabase application data

**Files:**
- Create: `BigQuery Version/compose.yaml`
- Create: `BigQuery Version/docker/init/01_create_metabase_db.sql`
- Create: `BigQuery Version/docker/pgadmin/servers.json`
- Modify: `BigQuery Version/.env`

**Interfaces:**
- Consumes: `.env` values.
- Produces: healthy `airbnb-postgres`, `airbnb-metabase`, and `airbnb-pgadmin` containers; a `metabase` application database.

- [ ] **Step 1: Write `01_create_metabase_db.sql`**

```sql
-- Create the Metabase application database if it does not already exist.
SELECT 'CREATE DATABASE metabase'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metabase')\gexec
```

- [ ] **Step 2: Write `compose.yaml`**

Use the Postgres service from the Postgres version with the same volume mount, but only the Metabase DB init script. Keep the Metabase service and its app DB settings. Keep pgAdmin, but point its `servers.json` at the `metabase` database.

Required Metabase environment:

```yaml
MB_DB_TYPE: postgres
MB_DB_DBNAME: metabase
MB_DB_PORT: 5432
MB_DB_USER: ${POSTGRES_USER:-postgres}
MB_DB_PASS: ${POSTGRES_PASSWORD:-cikalmerdeka}
MB_DB_HOST: postgres
MB_SITE_URL: ${MB_SITE_URL:-http://localhost:3000}
TZ: ${TZ:-Asia/Jakarta}
JAVA_TIMEZONE: ${TZ:-Asia/Jakarta}
```

- [ ] **Step 3: Write `servers.json`**

Point the preconfigured server at:

```json
{
  "Name": "Airbnb Metabase App DB",
  "Host": "postgres",
  "Port": 5432,
  "MaintenanceDB": "metabase",
  "Username": "postgres",
  "SSLMode": "prefer"
}
```

- [ ] **Step 4: Validate and start the stack**

```powershell
cd "BigQuery Version"
docker compose config
docker compose up -d
docker compose ps
```

Expected: Postgres healthy, Metabase healthy after initialization, pgAdmin running.

- [ ] **Step 5: Verify the app database**

```powershell
docker compose exec postgres psql -U postgres -d airbnb -c "\l"
docker compose exec postgres psql -U postgres -d metabase -c "SELECT current_database();"
```

Expected: `metabase` exists and is reachable.

- [ ] **Step 6: Verify Metabase health**

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:3000/api/health
```

Expected: HTTP 200.

- [ ] **Step 7: Commit**

```powershell
git add "BigQuery Version/compose.yaml" "BigQuery Version/docker"
git commit -m "Add Docker stack for the Metabase application database"
```

---

### Task 12: Provision Metabase and connect it to BigQuery

**Files:**
- Create: `BigQuery Version/scripts/setup_metabase.py`
- Modify: `BigQuery Version/.env` (adds `METABASE_API_KEY`)

**Interfaces:**
- Consumes: Metabase health, `.secrets/metabase-bigquery-key.json`, `.env` admin values.
- Produces: a Metabase admin account, an API key, and a BigQuery database connection with `analytics` metadata synced.

- [ ] **Step 1: Write `setup_metabase.py`**

Use only the Python standard library (`urllib`, `json`, `base64`, `pathlib`). Implement:

1. `load_dotenv(PROJECT_ROOT / ".env")`.
2. `wait_for_health()` polling `/api/health` for up to 180 seconds.
3. `get_setup_token()` from `/api/session/properties` (`setup-token`).
4. If a setup token exists, `POST /api/setup`:

```json
{
  "token": "<setup-token>",
  "user": {
    "email": "<METABASE_ADMIN_EMAIL>",
    "password": "<METABASE_ADMIN_PASSWORD>",
    "first_name": "<METABASE_ADMIN_FIRST_NAME>",
    "last_name": "<METABASE_ADMIN_LAST_NAME>"
  },
  "prefs": {
    "site_name": "Airbnb Analytics",
    "site_locale": "en"
  }
}
```

5. Log in with `POST /api/session` using `username` and `password`; keep the `id` session key.
6. Find the `Administrators` group via `GET /api/permissions/group`.
7. Create an API key via `POST /api/api-key` with `{"group_id": <admin-group-id>, "name": "git-export"}`. If an API key with that name exists, reuse it.
8. Write `METABASE_API_KEY=<unmasked_key>` to `.env`, replacing any existing line.
9. Create the BigQuery database if it does not exist:

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

10. Trigger `POST /api/database/{id}/sync_schema` and poll
    `GET /api/database/{id}/metadata` until a table named `dim_listings`
    appears in schema `analytics` or until 300 seconds elapse.
11. Print the database ID and the number of analytics tables/fields.

- [ ] **Step 2: Run setup**

```powershell
cd "BigQuery Version"
uv run python scripts\setup_metabase.py
```

Expected: setup completes, API key is written to `.env`, database ID is printed, and `dim_listings` is visible.

- [ ] **Step 3: Verify the database connection**

```powershell
$env:METABASE_API_KEY = (Select-String -Path .env -Pattern '^METABASE_API_KEY=' | ForEach-Object { $_.Line.Split('=',2)[1] })
Invoke-RestMethod -Uri http://127.0.0.1:3000/api/database -Headers @{ "X-API-Key" = $env:METABASE_API_KEY } | ConvertTo-Json -Depth 4
```

Expected: one database named `Airbnb Analytics` with engine `bigquery`.

- [ ] **Step 4: Verify least-privilege visibility**

Use the Metabase metadata response to confirm:

- schema `analytics` is present;
- schemas `raw`, `staging`, and `snapshots` are absent;
- `dim_listings`, `fct_reviews`, and the `mart_*` tables are present.

- [ ] **Step 5: Rerun setup to prove idempotency**

Run `uv run python scripts\setup_metabase.py` again. Expected: no duplicate database, no duplicate API key, no setup error.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/scripts/setup_metabase.py"
git commit -m "Provision Metabase and connect it to BigQuery"
```

Do not commit `.env` or `.secrets/`.

---

### Task 13: Convert Metabase definitions to BigQuery SQL

**Files:**
- Create: `BigQuery Version/scripts/convert_metabase_sql.py`
- Modify: `BigQuery Version/metabase/definitions.json`

**Interfaces:**
- Consumes: `metabase/definitions.json` with 66 Postgres-native cards.
- Produces: the same 66 cards with BigQuery SQL and stable `field` references; every SQL dry-runs in BigQuery.

- [ ] **Step 1: Write the converter**

The converter must:

1. Load `definitions.json` and iterate every dashboard/card.
2. Apply the SQL mapping table from the spec.
3. Replace `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY x)` with a scalar-compatible exact median:

```sql
SELECT MAX(median_price) AS median_price
FROM (
    SELECT PERCENTILE_CONT(x, 0.5) OVER () AS median_price
    FROM ...
)
```

4. Replace `COUNT(*) FILTER (WHERE cond)::numeric / NULLIF(COUNT(*), 0)` with `SAFE_DIVIDE(COUNTIF(cond), COUNT(*))`.
5. Replace `::numeric` with `CAST(... AS FLOAT64)`.
6. Replace `DATE_TRUNC('month', ts)::date` with `DATE_TRUNC(DATE(ts), MONTH)`.
7. Ensure `ORDER BY ... NULLS LAST` is compatible; if BigQuery rejects it, rewrite as `ORDER BY col IS NULL, col`.
8. Add a `field` key to every template tag and remove the Postgres `field_id`:
   - default: `analytics.<card.source>.<tag.name>`;
   - override `review_month` on `mart_review_topics` to
     `analytics.mart_review_topics.month_start`;
   - for `Chart - Reviews by Room Type`, map `room_type` to
     `analytics.dim_listings.room_type` and the review fields to
     `analytics.fct_reviews.*`;
   - `host_name` and `listing_name` appear only as selected columns, not as
     template tags; do not invent tags for them.
9. Remove the hardcoded `database_id` use from the definitions; the seeder resolves the live database ID.
10. Write the converted JSON back with stable key order and 2-space indentation.

- [ ] **Step 2: Run the converter**

```powershell
cd "BigQuery Version"
uv run python scripts\convert_metabase_sql.py
```

Expected: valid JSON, 66 cards, 5 dashboards.

- [ ] **Step 3: Check for Postgres-only syntax**

```powershell
Select-String -Path metabase\definitions.json -Pattern "PERCENTILE_CONT.*WITHIN GROUP|::numeric|COUNT\(\*\) FILTER|::date|::text|ISODOW|TO_CHAR"
```

Expected: no matches.

- [ ] **Step 4: Dry-run every SQL statement**

Add a `--dry-run-bigquery` mode to the converter that:

1. Extracts each card SQL.
2. Replaces every `{{tag}}` with `TRUE` and removes `[[ ... ]]` blocks.
3. Runs `bq query --use_legacy_sql=false --dry_run --format=none "<sql>"`.
4. Fails on the first invalid query and prints the card name.

Run:

```powershell
uv run python scripts\convert_metabase_sql.py --dry-run-bigquery
```

Expected: 66/66 SQL statements valid.

- [ ] **Step 5: Commit**

```powershell
git add "BigQuery Version/scripts/convert_metabase_sql.py" "BigQuery Version/metabase/definitions.json"
git commit -m "Convert Metabase definitions to BigQuery SQL"
```

---

### Task 14: Seed Metabase cards, dashboards, and layout

**Files:**
- Modify: `BigQuery Version/scripts/seed_metabase.py`
- Modify: `BigQuery Version/metabase/definitions.json` (only if the seeder needs a `skip` change)

**Interfaces:**
- Consumes: Metabase BigQuery database from Task 12; converted definitions from Task 13.
- Produces: 5 collections, 66 cards, 5 dashboards, exact card layout.

- [ ] **Step 1: Update the seeder's database and root collection handling**

- Replace `DATABASE_ID = 2` with a lookup by database name `Airbnb Analytics` from `GET /api/database`.
- Replace `root_collection_id = 5` with a lookup/create of the `Airbnb Analytics` root collection under `parent_id: null`.
- Keep `FULL_WIDTH` and `ALIASES` behavior.
- Remove the Executive Overview skip; seed all five dashboards.

- [ ] **Step 2: Resolve field IDs dynamically**

`GET /api/database/{id}/metadata` returns tables with `schema`, `name`, and `fields` (`id`, `name`). Build:

```python
field_ids[(schema, table, field_name)] = field_id
```

For each card template tag with a `field` key like `analytics.dim_listings.room_type`, split it and resolve:

```python
["field", {"lib/uuid": str(uuid.uuid4())}, field_ids[(schema, table, column)]]
```

Use the resolved field in the `dimension` array of the template tag, matching
the MBQL shape already used by the Postgres seeder. If a field is missing, fail
with the card name, tag name, and requested `table.column`; do not silently skip.

- [ ] **Step 3: Apply exact dashboard layout**

Read `metabase/export/dashboards/*.json`. For each dashboard, map `dashcard.card_name` to the created card ID and apply `row`, `col`, `size_x`, `size_y`, `dashboard_tab_id`, and `visualization_settings`. Do **not** copy `parameter_mappings` from the export: those IDs belong to the Postgres instance and are replaced by Task 15. Leave mappings empty or preserve the ones created by the seeder. If a card name is missing, fail with the dashboard name and card name.

- [ ] **Step 4: Run the dry run**

```powershell
uv run python scripts\seed_metabase.py --dry-run
```

Expected: prints 6 collections (1 root + 5 dashboard collections), 66 cards, 5 dashboards, and no errors.

- [ ] **Step 5: Seed**

```powershell
uv run python scripts\seed_metabase.py
```

Expected: all collections, cards, and dashboards created; no duplicate names.

- [ ] **Step 6: Validate counts and card execution**

Use the Metabase API to check:

- `GET /api/collection/{root}/items` returns 5 dashboards.
- The total card count is 66.
- `POST /api/card/{id}/query` for every card returns HTTP 200 with at least one row or a valid scalar.

Expected: 66/66 cards execute.

- [ ] **Step 7: Rerun the seeder to prove idempotency**

Run `uv run python scripts\seed_metabase.py` again. Expected: no duplicate collections, cards, or dashboards; layout unchanged.

- [ ] **Step 8: Commit**

```powershell
git add "BigQuery Version/scripts/seed_metabase.py" "BigQuery Version/metabase/definitions.json"
git commit -m "Seed Metabase cards and dashboards against BigQuery"
```

---

### Task 15: Add dashboard filters and validate filtered queries

**Files:**
- Modify: `BigQuery Version/metabase/dashboard_filters.json`
- Modify: `BigQuery Version/scripts/add_dashboard_filters.py`

**Interfaces:**
- Consumes: seeded dashboards and cards from Task 14.
- Produces: all five dashboards have the documented filters, mapped to the expected card counts, and at least one filtered query returns the expected value.

- [ ] **Step 1: Add the Executive filter spec**

Add to `dashboard_filters.json`:

```json
{
  "key": "executive",
  "collection": "Executive Overview Collection",
  "dashboard": "Executive Overview Dashboard",
  "filters": [
    {
      "name": "Month range",
      "slug": "month_start",
      "tag": "month_start",
      "type": "date/all-options",
      "section_id": "date",
      "values_query_type": "none",
      "is_multi": false,
      "expected_cards": 6
    }
  ]
}
```

- [ ] **Step 2: Run the filter dry run**

```powershell
uv run python scripts\add_dashboard_filters.py --dry-run
```

Expected: every filter maps to its `expected_cards` count; no `MISMATCH`.

- [ ] **Step 3: Apply the filters**

```powershell
uv run python scripts\add_dashboard_filters.py
```

Expected: all five dashboards updated.

- [ ] **Step 4: Verify a real Field Filter**

Use the Metabase API to run the Supply `KPI - Total Listings` card with `room_type = Entire home/apt`:

```json
{
  "parameters": [
    {
      "type": "string/=",
      "target": ["dimension", ["template-tag", "room_type"]],
      "value": ["Entire home/apt"]
    }
  ]
}
```

Expected: one row with `total_listings = 9890`.

- [ ] **Step 5: Verify all cards again**

Run every card through `POST /api/card/{id}/query` and confirm 66/66 succeed. Also confirm all five dashboards load via `GET /api/dashboard/{id}` and contain the expected dashcards.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/metabase/dashboard_filters.json" "BigQuery Version/scripts/add_dashboard_filters.py"
git commit -m "Add and validate Metabase dashboard filters for BigQuery"
```

---

### Task 16: Export, back up, and restore Metabase content

**Files:**
- Modify: `BigQuery Version/scripts/export_metabase.py`
- Modify: `BigQuery Version/scripts/backup_metabase.ps1`
- Modify: `BigQuery Version/scripts/restore_metabase.ps1`
- Modify: `BigQuery Version/metabase/README.md`

**Interfaces:**
- Consumes: running Metabase with seeded content and API key.
- Produces: regenerated `metabase/export/`, a working `.dump`, and a successful restore.

- [ ] **Step 1: Verify the exporter**

The exporter already reads `METABASE_URL` and `METABASE_API_KEY` from `.env`. Update the default root collection lookup to find `Airbnb Analytics` by name instead of hardcoded ID `5`. Keep the cleaning rules.

- [ ] **Step 2: Run the exporter**

```powershell
uv run python scripts\export_metabase.py
```

Expected: `metabase/export/manifest.json` reports 6 collections (root + 5 dashboard collections), 66 cards, 5 dashboards.

- [ ] **Step 3: Back up the application database**

```powershell
.\scripts\backup_metabase.ps1
```

Expected: a new `.dump` under `metabase/backups/`.

- [ ] **Step 4: Restore the same backup**

```powershell
.\scripts\restore_metabase.ps1 -DumpFile .\metabase\backups\<timestamp>.dump -Force
```

Expected: Metabase stops, the app DB is recreated, the dump restores, `/api/health` returns 200, and the dashboard/card counts are unchanged.

- [ ] **Step 5: Update `metabase/README.md`**

Change all Postgres-specific instructions to BigQuery, including:

- the database connection fields;
- the service account key path;
- the `bq` dataset names;
- the app DB restore wording (the analytics warehouse is BigQuery and is not touched by the restore).

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/scripts/export_metabase.py" "BigQuery Version/scripts/backup_metabase.ps1" "BigQuery Version/scripts/restore_metabase.ps1" "BigQuery Version/metabase/README.md" "BigQuery Version/metabase/export"
git commit -m "Export and validate Metabase content for BigQuery"
```

Do not commit `metabase/backups/*.dump`.

---

### Task 17: Port operational scripts, SQL checks, and documentation

**Files:**
- Modify: `BigQuery Version/scripts/watch_db.ps1`
- Modify: `BigQuery Version/sql/_profile_data.sql`
- Modify: `BigQuery Version/sql/check_data_information.sql`
- Modify: `BigQuery Version/sql/check_raw_data.sql`
- Modify: `BigQuery Version/README.md`
- Modify: `BigQuery Version/docs/RUNBOOK.md`
- Modify: `BigQuery Version/docs/METABASE_DASHBOARDS.md`
- Modify: `BigQuery Version/docs/METABASE_SQL_WITH_FILTERS.md`
- Modify: `BigQuery Version/docs/METABASE_FILTER_AUTOMATION.md`
- Modify: `BigQuery Version/data/raw/README.md`
- Modify: `BigQuery Version/airbnb_dbt/README.md`
- Modify: root `README.md`

**Interfaces:**
- Consumes: all previous tasks.
- Produces: a complete, accurate runbook and operational tooling.

- [ ] **Step 1: Rewrite `watch_db.ps1`**

Use `bq query` to show:

- exact counts for `raw.raw_listings`, `raw.raw_hosts`, `raw.raw_reviews`;
- table inventory and approximate row counts for `staging`, `analytics`, and
  `snapshots` from
  `` `orbital-scene-422012-h0.region-asia-southeast2.INFORMATION_SCHEMA.TABLES` ``.

Add a `-Once` switch for a single refresh; the default loops every `-Seconds` seconds.

- [ ] **Step 2: Rewrite `sql/*.sql`**

- `_profile_data.sql`: BigQuery profiling queries using `COUNTIF`, `SAFE_DIVIDE`, `APPROX_QUANTILES` (or exact window medians), and `INFORMATION_SCHEMA`.
- `check_data_information.sql`: BigQuery `INFORMATION_SCHEMA.COLUMNS` for `analytics.fct_reviews`, and a sample query.
- `check_raw_data.sql`: `SELECT * FROM raw.raw_* LIMIT 10`.

- [ ] **Step 3: Rewrite the README files**

Each README must reflect:

- BigQuery project/datasets/location;
- `gcloud`/`bq` setup;
- `uv sync`, `dbt deps`, `dbt build`, `dbt test`;
- Dagster on port 3001;
- Metabase on port 3000, connected to BigQuery;
- Postgres container is only the Metabase app DB;
- cost guardrails and expected $0;
- reset/reload commands (`load_raw_data.ps1`, not `docker compose down -v` for analytics);
- no references to `raw.raw_*` in Postgres or `analytics` schema in Postgres.

- [ ] **Step 4: Validate the docs**

```powershell
Select-String -Path README.md,docs\*.md,data\raw\README.md,airbnb_dbt\README.md -Pattern "localhost:5433|psql -U postgres -d airbnb|raw\.raw_|dbt-postgres|dbname: airbnb" | Select-Object -First 40
```

Expected: remaining matches are only in historical/legacy docs or clearly marked as the Metabase app DB. Current-runbook commands must use BigQuery. Do not flag `analytics.<table>` by itself; that is the correct BigQuery dataset reference.

- [ ] **Step 5: Run the operational scripts**

```powershell
.\scripts\watch_db.ps1 -Once
.\scripts\validate_bigquery.ps1
cd airbnb_dbt
uv run dbt docs generate --profiles-dir ..
```

Expected: the watcher prints the inventory, validation passes, and dbt docs generate with five exposures.

- [ ] **Step 6: Commit**

```powershell
git add "BigQuery Version/scripts/watch_db.ps1" "BigQuery Version/sql" "BigQuery Version/README.md" "BigQuery Version/docs" "BigQuery Version/data/raw/README.md" "BigQuery Version/airbnb_dbt/README.md" "README.md"
git commit -m "Document and validate the BigQuery Version workflow"
```

---

### Task 18: Run end-to-end acceptance and publish

**Files:**
- Modify: any files needed to fix acceptance failures.
- Test: full clean workflow and git state.

**Interfaces:**
- Consumes: all tasks.
- Produces: a complete `BigQuery Version/` in git, pushed to the remote branch.

- [ ] **Step 1: Run the full workflow from the project root**

```powershell
cd "BigQuery Version"
uv sync
.\scripts\provision_bigquery.ps1
.\scripts\set_bigquery_guardrails.ps1
.\scripts\load_raw_data.ps1
cd airbnb_dbt
uv run dbt deps --profiles-dir ..
uv run dbt build --profiles-dir ..
uv run dbt test --profiles-dir ..
cd ..
.\scripts\validate_bigquery.ps1
```

Expected: every command exits `0`; `dbt build` is `PASS=126 ... TOTAL=131`; `dbt test` is `PASS=107`; all KPI checks pass.

- [ ] **Step 2: Run the full Metabase workflow**

```powershell
docker compose up -d
uv run python scripts\setup_metabase.py
uv run python scripts\seed_metabase.py
uv run python scripts\add_dashboard_filters.py
uv run python scripts\export_metabase.py
.\scripts\backup_metabase.ps1
```

Expected: 5 dashboards, 66 cards, all filters mapped, export manifest correct, backup file created.

- [ ] **Step 3: Run Dagster**

```powershell
cd airbnb_dagster_project
uv run dagster dev -p 3001
```

Expected: UI loads at `http://localhost:3001`; asset graph is complete; materializing `dim_date` succeeds.

- [ ] **Step 4: Verify cost guardrails**

```powershell
gcloud billing budgets list --billing-account=01D852-BA4F4C-1BCBD1 --format="table(displayName,budget.amount)"
gcloud quotas preferences list --project=orbital-scene-422012-h0 --service=bigquery.googleapis.com --format="table(name,quotaId,preferredValue)"
```

Expected: budget and quota preference are present and unchanged.

- [ ] **Step 5: Verify no secrets or artifacts are staged**

```powershell
git status --short
git check-ignore -v ".env" "profiles.yml" ".secrets/metabase-bigquery-key.json" "metabase/backups/test.dump"
```

Expected: `.env`, `profiles.yml`, `.secrets/...`, and dumps are ignored. `git status` shows only intended source files.

- [ ] **Step 6: Commit the final acceptance fixes**

If any source files changed during acceptance:

```powershell
git add "BigQuery Version" "README.md" ".gitignore"
git commit -m "Complete BigQuery Version end-to-end verification"
```

If nothing changed, skip this commit.

- [ ] **Step 7: Push the branch**

```powershell
git push -u origin feat/bigquery-version
```

Expected: branch pushed, remote tracking set.

---

## Plan Self-Review

- **Spec coverage:** every spec section has a task: repository layout (Task 1), BigQuery provisioning and guardrails (Task 2), raw loading (Task 3), dbt config/sources (Task 4), staging/intermediate (Task 5), dimensions/fact (Task 6), core marts (Task 7), remaining marts (Task 8), tests/snapshots/full build (Task 9), Dagster (Task 10), Docker (Task 11), Metabase setup (Task 12), definitions conversion (Task 13), seeding/layout (Task 14), filters/validation (Task 15), export/backup/restore (Task 16), scripts/docs (Task 17), end-to-end/push (Task 18).
- **Step scan:** every step names a file, command, or exact value. No `TBD`, no "handle edge cases", no unspecified tests.
- **Type consistency:** `validate_bigquery.ps1` uses `Invoke-BqScalar` throughout; `seed_metabase.py` uses `field_ids[(schema, table, column)]`; `setup_metabase.py` uses `METABASE_API_KEY`; all task interfaces match these names.
- **Review Focus:** the five risk areas have explicit tests in Tasks 3, 8, 9, 12, 14, and 15.
- **Proportion:** the plan is larger than a typical feature plan because it ports an entire multi-tool project, but each task produces a testable deliverable and no task is a transcript of a full file.
