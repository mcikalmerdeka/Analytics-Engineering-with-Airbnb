# Postgres Analytics Revamp — Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a BI-facing `analytics` layer that turns the static 2021 Berlin Airbnb snapshot into five dashboard-ready marts without changing the raw data.

**Architecture:** Keep `src_*` ephemeral models, add two intermediate views and a date spine, then expose clean dimensions, one review fact, and eight marts in an `analytics` schema. Metabase reads only `analytics`; `staging` stays internal and `snapshots` holds the unchanged SCD examples.

**Tech Stack:** dbt Core 1.12.6, dbt-postgres 1.11.0, PostgreSQL 17 (Docker, host port 5433), dbt_utils, dbt_expectations, Dagster 1.13 (no code change required).

**Spec:** `Postgres Version/docs/superpowers/specs/2026-11-05-postgres-analytics-revamp-design.md`

## Global Constraints

- dbt Core is **1.12.6** and dbt-postgres is **1.11.0**. Do not upgrade them.
- Raw data is a static Berlin snapshot. Do not modify `data/raw/*` or `docker/init/02_raw_tables.sql`.
- Raw row counts: **17,499 listings / 14,111 hosts / 410,284 reviews**.
- Reference dates: listing snapshot **2021-11-19**; latest review **2021-10-22**.
- Expected fact row count after exact dedupe: **410,283**.
- `analytics` is the only BI-facing schema. `staging` is internal. `snapshots` is for SCD examples.
- All BI models are tables except `fct_reviews`, which is incremental with `delete+insert` on `review_id`.
- Reviewer names stay in `fct_reviews` for lineage and must not appear in any mart.
- Price is the source price string parsed from `$` values. Label it “source price”; do not claim EUR or USD conversion.
- Run dbt from `Postgres Version/airbnb_dbt` with `--profiles-dir ..`.
- Run database checks from `Postgres Version` with `docker compose exec -T postgres psql -U postgres -d airbnb`.
- **Owner commits.** Stage changed files with `git add`; do not run `git commit`.

## Review Focus

1. **Null review sentiment (385 rows).** Keeping null-comment reviews introduces `unknown` sentiment; a missed `COALESCE` breaks accepted-values tests and sentiment percentages. Test: `fct_reviews` accepted values include `unknown`; `count(*) filter (where review_sentiment = 'unknown') = 385` (Task 3).
2. **Legitimate same-day/same-reviewer reviews (31 pairs).** Deduping by natural key would drop real reviews; only exact duplicates may go. Test: `fct_reviews` count = 410,283, `review_id` unique (Task 3).
3. **Listings with zero reviews (3,254).** Left joins must produce `has_reviews = false`, null dates, and null percentages rather than dropping listings. Test: row count 17,499, no-review count 3,254 (Task 5).
4. **Price outliers and zero prices (8 zero, max $8,000).** Naive averages and histograms distort the story. Test: `is_price_outlier` flags them; median price remains $55 (Task 2 and Task 5).
5. **Incremental re-runs.** A second build must not duplicate reviews. Test: run `dbt build --select +fct_reviews` twice; count stays 410,283 (Task 3).

## File Structure

**Create**
- `airbnb_dbt/macros/generate_schema_name.sql`
- `airbnb_dbt/models/intermediate/int_listings_enriched.sql`
- `airbnb_dbt/models/intermediate/int_reviews_deduped.sql`
- `airbnb_dbt/models/intermediate/int_review_topics.sql`
- `airbnb_dbt/models/analytics/dim_date.sql`
- `airbnb_dbt/models/analytics/dim_listings.sql`
- `airbnb_dbt/models/analytics/dim_hosts.sql`
- `airbnb_dbt/models/analytics/fct_reviews.sql`
- `airbnb_dbt/models/analytics/mart_listing_performance.sql`
- `airbnb_dbt/models/analytics/mart_host_performance.sql`
- `airbnb_dbt/models/analytics/mart_market_monthly.sql`
- `airbnb_dbt/models/analytics/mart_price_bands.sql`
- `airbnb_dbt/models/analytics/mart_room_type_benchmark.sql`
- `airbnb_dbt/models/analytics/mart_review_topics.sql`
- `airbnb_dbt/models/analytics/mart_executive_kpis.sql`
- `airbnb_dbt/models/analytics/mart_full_moon_reviews.sql`
- `airbnb_dbt/seeds/seed_review_topics.csv`
- `airbnb_dbt/tests/assert_no_future_reviews.sql`
- `airbnb_dbt/tests/assert_price_positive.sql`

**Modify**
- `airbnb_dbt/dbt_project.yml`
- `airbnb_dbt/models/sources.yml`
- `airbnb_dbt/models/schema.yml`
- `airbnb_dbt/models/dashboards.yml`
- `airbnb_dbt/snapshots/scd_raw_listings.sql`
- `airbnb_dbt/snapshots/scd_raw_hosts.sql`
- `airbnb_dbt/tests/consistent_created_at.sql`
- `airbnb_dbt/tests/dim_listings_minimum_nights.sql`
- `docker/init/01_schema_roles.sql`
- `docker/init/03_reporting.sql`
- `Postgres Version/docs/RUNBOOK.md`
- `README.md` (model list only)

**Delete**
- `airbnb_dbt/models/dimension/dim_listings_cleansed.sql`
- `airbnb_dbt/models/dimension/dim_hosts_cleansed.sql`
- `airbnb_dbt/models/dimension/dim_listings_w_hosts.sql`
- `airbnb_dbt/models/fact/fct_reviews.sql`
- `airbnb_dbt/models/mart/full_moon_reviews.sql`
- `airbnb_dbt/tests/no_nulls_in_dim_listings.sql`

---

### Task 1: Schema Contract and Scaffolding

**Files:**
- Modify: `airbnb_dbt/dbt_project.yml`
- Create: `airbnb_dbt/macros/generate_schema_name.sql`
- Modify: `docker/init/01_schema_roles.sql`
- Modify: `docker/init/03_reporting.sql`
- Modify: `airbnb_dbt/models/sources.yml`
- Modify: `airbnb_dbt/snapshots/scd_raw_listings.sql`
- Modify: `airbnb_dbt/snapshots/scd_raw_hosts.sql`
- Create directories: `airbnb_dbt/models/intermediate/`, `airbnb_dbt/models/analytics/`

**Interfaces:**
- Produces: exact schema routing (`staging`, `analytics`, `snapshots`) and `reporter` grants.
- Later tasks rely on `analytics` existing and `generate_schema_name` returning the custom schema verbatim.

- [ ] **Step 1: Replace the `models` block in `dbt_project.yml`**

Use this exact structure; keep the existing `vars` block:

```yaml
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
```

- [ ] **Step 2: Create `macros/generate_schema_name.sql`**

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
```

- [ ] **Step 3: Create the new schemas in `docker/init/01_schema_roles.sql`**

Add below the existing `CREATE SCHEMA` statements:

```sql
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS snapshots;
```

- [ ] **Step 4: Replace `docker/init/03_reporting.sql`**

```sql
-- Give the Metabase reporting user read access to the analytics output only.
CREATE SCHEMA IF NOT EXISTS analytics;

GRANT USAGE ON SCHEMA analytics TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO reporter;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA analytics
    GRANT SELECT ON TABLES TO reporter;

REVOKE USAGE ON SCHEMA staging FROM reporter;
```

- [ ] **Step 5: Remove the misleading freshness block from `models/sources.yml`**

Delete `loaded_at_field: date` and the `freshness:` block on the reviews source. Add a comment:

```yaml
# Freshness is not applicable: the raw CSV is a static 2021 snapshot.
```

- [ ] **Step 6: Update both snapshot files**

In `snapshots/scd_raw_listings.sql` and `snapshots/scd_raw_hosts.sql`, change:

```sql
target_schema = 'staging',
```

to:

```sql
target_schema = 'snapshots',
```

- [ ] **Step 7: Parse the project**

Run: `uv run dbt parse --profiles-dir ..`

Expected: parse succeeds with no duplicate model names and no YAML errors.

- [ ] **Step 8: Build the snapshots into the new schema**

Run: `uv run dbt build --select scd_raw_hosts scd_raw_listings --profiles-dir ..`

Expected: both snapshots pass.

- [ ] **Step 9: Apply the reporting grants to the running database**

From `Postgres Version/`:

```powershell
Get-Content -Raw .\docker\init\03_reporting.sql | docker compose exec -T postgres psql -U postgres -d airbnb
```

- [ ] **Step 10: Verify the schema contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select nspname from pg_namespace where nspname in ('staging','analytics','snapshots') order by 1;"
```

Expected: `analytics`, `snapshots`, `staging`.

- [ ] **Step 11: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 2: Listing Dimensions

**Files:**
- Create: `airbnb_dbt/models/intermediate/int_listings_enriched.sql`
- Create: `airbnb_dbt/models/analytics/dim_listings.sql`
- Create: `airbnb_dbt/models/analytics/dim_hosts.sql`
- Modify: `airbnb_dbt/models/schema.yml`
- Modify: `airbnb_dbt/tests/dim_listings_minimum_nights.sql`
- Create: `airbnb_dbt/tests/assert_price_positive.sql`
- Delete: the three old files in `airbnb_dbt/models/dimension/`
- Delete: `airbnb_dbt/tests/no_nulls_in_dim_listings.sql`

**Interfaces:**
- Consumes: `src_listings`, `src_hosts`.
- Produces:
  - `analytics.dim_listings(listing_id PK, listing_name, listing_url, room_type, price, price_band, is_price_outlier, minimum_nights, minimum_nights_band, host_id, host_name, is_superhost, is_superhost_known, host_listing_count, host_segment, listing_created_at, listing_age_days, listing_age_cohort, listing_updated_at)`
  - `analytics.dim_hosts(host_id PK, host_name, is_superhost, is_superhost_known, host_created_at, host_age_days, host_listing_count, host_segment)`

- [ ] **Step 1: Add the failing model tests to `models/schema.yml`**

Remove every entry for `dim_listings_cleansed`, `dim_hosts_cleansed`, and `dim_listings_w_hosts`. Add:

- `dim_listings`: `unique` and `not_null` on `listing_id`; `not_null` on `host_id`, `room_type`, `price`, `minimum_nights`; `relationships` from `host_id` to `dim_hosts.host_id`; `accepted_values` for `room_type`; `positive_value` (existing macro) for `minimum_nights`.
- `dim_hosts`: `unique` and `not_null` on `host_id`; `not_null` on `host_name` and `is_superhost_known`; `accepted_values` for `host_segment`.

Use the existing dbt 1.12 `arguments:` syntax already present in `schema.yml`.

Create `tests/assert_price_positive.sql`:

```sql
SELECT *
FROM {{ ref('dim_listings') }}
WHERE price < 0
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run dbt test --select dim_listings dim_hosts --profiles-dir ..`

Expected: FAIL because neither model exists yet.

- [ ] **Step 3: Implement `int_listings_enriched.sql`**

Follow spec §6.2 exactly. Required logic:

- Parse price with `CAST(REPLACE(REPLACE(price_str, '$', ''), ',', '') AS NUMERIC)`.
- `price_band`: `<30`, `30-49`, `50-74`, `75-99`, `100-149`, `150-249`, `250+`.
- `minimum_nights`: `CASE WHEN minimum_nights = 0 THEN 1 ELSE minimum_nights END`.
- `minimum_nights_band`: `1`, `2-6`, `7-29`, `30+`.
- `is_superhost`: `t` → `TRUE`, `f` → `FALSE`, else `NULL`; `is_superhost_known = is_superhost IS NOT NULL`.
- `host_listing_count`: count of listings per `host_id`.
- `host_segment`: `Single listing` (1), `Small portfolio` (2–4), `Professional` (5–9), `Large professional` (10–19), `Enterprise` (20+).
- `listing_age_days`: `DATE '2021-11-19' - listing_created_at::date`.
- `listing_age_cohort`: `< 1 year`, `1-2 years`, `3-5 years`, `6+ years`.
- `is_price_outlier`: `price = 0 OR price > p99.5(price) within room_type`. Compute the p99.5 threshold in a grouped CTE with `percentile_cont(0.995) WITHIN GROUP (ORDER BY price) GROUP BY room_type` and join it back; PostgreSQL does not allow `percentile_cont` with `OVER`.

- [ ] **Step 4: Implement `dim_listings.sql` and `dim_hosts.sql`**

`dim_listings` selects the listing and host attributes from `int_listings_enriched`; it contains no review metrics. `dim_hosts` starts from `src_hosts` and left joins listing aggregates by `host_id`, so hosts with zero listings are retained; use `host_created_at`, `host_age_days` as of 2021-11-19, `host_listing_count`, and `host_segment`.

- [ ] **Step 5: Delete the old dimension models and the all-null test**

Delete `models/dimension/dim_listings_cleansed.sql`, `models/dimension/dim_hosts_cleansed.sql`, `models/dimension/dim_listings_w_hosts.sql`, and `tests/no_nulls_in_dim_listings.sql`.

Update `tests/dim_listings_minimum_nights.sql` to use `ref('dim_listings')` and `WHERE minimum_nights < 1`.

- [ ] **Step 6: Build the dimensions**

Run: `uv run dbt build --select +dim_listings +dim_hosts --profiles-dir ..`

Expected: PASS, including relationships tests.

- [ ] **Step 7: Verify the listing and host contracts**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select (select count(*) from analytics.dim_listings) as listings, (select count(*) from analytics.dim_hosts) as hosts, (select count(*) from analytics.dim_hosts where not is_superhost_known) as unknown_superhosts, (select count(*) from analytics.dim_listings where is_price_outlier) as price_outliers;"
```

Expected: `17499`, `14111`, `15`, and a non-zero outlier count (8 zero prices plus extreme highs).

Verify host segments:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select host_segment, count(*) from analytics.dim_listings group by 1 order by 1;"
```

Expected counts: `Single listing` 12,666; `Small portfolio` 2,884; `Professional` 887; `Large professional` 579; `Enterprise` 483.

Run the singular price test:

Run: `uv run dbt test --select assert_price_positive --profiles-dir ..`

Expected: PASS.

- [ ] **Step 8: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 3: Review Fact

**Files:**
- Create: `airbnb_dbt/models/intermediate/int_reviews_deduped.sql`
- Create: `airbnb_dbt/models/analytics/fct_reviews.sql`
- Modify: `airbnb_dbt/models/schema.yml`
- Modify: `airbnb_dbt/tests/consistent_created_at.sql`
- Create: `airbnb_dbt/tests/assert_no_future_reviews.sql`
- Delete: `airbnb_dbt/models/fact/fct_reviews.sql`

**Interfaces:**
- Consumes: `src_reviews`.
- Produces: `analytics.fct_reviews(review_id PK, listing_id, review_date, reviewer_name, review_text, review_sentiment, sentiment_score, has_comment, review_length, review_year, review_month)`.
- Later tasks use `review_id`, `listing_id`, `review_date`, `review_sentiment`, `sentiment_score`, `has_comment`, `review_length`, and `review_month`.

- [ ] **Step 1: Delete the old fact model**

Delete `models/fact/fct_reviews.sql` so the new model can use the same name.

- [ ] **Step 2: Add the failing model tests to `models/schema.yml`**

Add for `fct_reviews`:

- `unique` and `not_null` on `review_id`
- `not_null` on `listing_id`, `review_date`, `review_sentiment`
- `relationships` from `listing_id` to `dim_listings.listing_id`
- `accepted_values` for `review_sentiment`: `positive`, `neutral`, `negative`, `unknown`

Create `tests/assert_no_future_reviews.sql`:

```sql
SELECT *
FROM {{ ref('fct_reviews') }}
WHERE review_date > DATE '2021-11-19'
```

Update `tests/consistent_created_at.sql`:

```sql
SELECT
    *
FROM {{ ref('dim_listings') }} l
INNER JOIN {{ ref('fct_reviews') }} r
    ON l.listing_id = r.listing_id
WHERE l.listing_created_at >= r.review_date
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `uv run dbt test --select fct_reviews --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 4: Implement `int_reviews_deduped.sql`**

Follow spec §6.3 exactly:

- `review_id`: `dbt_utils.generate_surrogate_key(['listing_id', 'review_date', 'reviewer_name', 'review_text'])`.
- `review_sentiment`: `COALESCE(sentiment, 'unknown')`.
- `sentiment_score`: positive 1, neutral 0, negative -1, unknown `NULL`.
- `has_comment`: `review_text IS NOT NULL`.
- `review_length`: `LENGTH(review_text)`.
- `review_year`: `EXTRACT(YEAR FROM review_date)`.
- `review_month`: `DATE_TRUNC('month', review_date)::date`.
- Deduplicate with `ROW_NUMBER() OVER (PARTITION BY listing_id, review_date, reviewer_name, review_text ORDER BY review_date) = 1`.

- [ ] **Step 5: Implement `fct_reviews.sql`**

Use incremental materialization:

```sql
{{ config(
    materialized='incremental',
    unique_key='review_id',
    incremental_strategy='delete+insert',
    on_schema_change='append_new_columns'
) }}
```

Incremental filter:

```sql
{% if is_incremental() %}
WHERE review_date >= (
    SELECT COALESCE(MAX(review_date), DATE '1900-01-01') - INTERVAL '3 days'
    FROM {{ this }}
)
{% endif %}
```

- [ ] **Step 6: Build the fact**

Run: `uv run dbt build --select +fct_reviews --profiles-dir ..`

Expected: PASS.

Run the singular review tests:

Run: `uv run dbt test --select assert_no_future_reviews consistent_created_at --profiles-dir ..`

Expected: PASS.

- [ ] **Step 7: Verify the review contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(*) as rows, count(distinct review_id) as distinct_ids, count(*) filter (where review_sentiment = 'unknown') as unknown_sentiment, count(*) filter (where not has_comment) as no_comment, min(review_date) as min_date, max(review_date) as max_date from analytics.fct_reviews;"
```

Expected: `410283`, `410283`, `385`, `587`, `2009-06-20`, `2021-10-22`.

- [ ] **Step 8: Verify incremental idempotence**

Run `uv run dbt build --select +fct_reviews --profiles-dir ..` a second time, then repeat the count query.

Expected: row count remains `410283`; `review_id` remains unique.

- [ ] **Step 9: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 4: Date Dimension

**Files:**
- Create: `airbnb_dbt/models/analytics/dim_date.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Produces: `analytics.dim_date(date_day PK, date_key, year, quarter, month, month_name, month_short, year_month, week_of_year, day_of_week, day_name, is_weekend)`.
- Later tasks use `date_day`, `year_month`, `year`, `month`, and `is_weekend`.

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `unique` and `not_null` on `date_day`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run dbt test --select dim_date --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 3: Implement `dim_date.sql`**

Use `dbt_utils.date_spine` with `datepart='day'`, `start_date=cast('2009-01-01' as date)`, and `end_date=cast('2022-01-01' as date)`; filter to `< '2022-01-01'`. Derive the calendar columns from `date_day`.

- [ ] **Step 4: Build the date dimension**

Run: `uv run dbt build --select dim_date --profiles-dir ..`

Expected: PASS.

- [ ] **Step 5: Verify the date range**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(*) as days, min(date_day) as min_day, max(date_day) as max_day, count(*) filter (where is_weekend) as weekend_days from analytics.dim_date;"
```

Expected: `4748` days, `2009-01-01` to `2021-12-31`, `1356` weekend days.

- [ ] **Step 6: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 5: Listing Performance Mart

**Files:**
- Create: `airbnb_dbt/models/analytics/mart_listing_performance.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Consumes: `dim_listings`, `fct_reviews`.
- Produces: `analytics.mart_listing_performance(listing_id PK, listing_name, room_type, price, price_band, is_price_outlier, minimum_nights, host_id, host_name, is_superhost, host_segment, listing_age_days, has_reviews, is_active_last_12m, review_count, review_count_12m, first_review_date, last_review_date, days_since_last_review, reviews_per_year, avg_sentiment, pct_positive, pct_neutral, pct_negative, avg_review_length)`.

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `unique` and `not_null` on `listing_id`; `not_null` on `review_count`, `has_reviews`, `is_active_last_12m`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run dbt test --select mart_listing_performance --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 3: Implement `mart_listing_performance.sql`**

Follow spec §6.8. Use `dim_listings` left joined to a `fct_reviews` aggregate by `listing_id`.

Rules:

- `as_of_date = DATE '2021-11-19'`.
- `has_reviews = review_count > 0`.
- `is_active_last_12m = COALESCE(last_review_date > as_of_date - INTERVAL '12 months', FALSE)`.
- `review_count_12m` counts reviews in the trailing 12 months.
- `days_since_last_review = as_of_date - last_review_date`.
- `reviews_per_year = review_count / GREATEST(listing_age_days / 365.25, 1)`.
- Percentages are `count(*) FILTER (...)` divided by `NULLIF(review_count, 0)`.
- `avg_review_length` uses only `has_comment = TRUE`.
- Keep every listing; no inner join.

- [ ] **Step 4: Build the mart**

Run: `uv run dbt build --select +mart_listing_performance --profiles-dir ..`

Expected: PASS.

- [ ] **Step 5: Verify the listing performance contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(*) as rows, count(*) filter (where has_reviews) as reviewed, count(*) filter (where not has_reviews) as no_reviews, count(*) filter (where is_active_last_12m) as active_12m, sum(review_count) as total_reviews, round(percentile_cont(0.5) within group (order by price)::numeric, 0) as median_price from analytics.mart_listing_performance;"
```

Expected: `17499`, `14245`, `3254`, `6050`, `410283`, `55`.

- [ ] **Step 6: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 6: Host Performance Mart

**Files:**
- Create: `airbnb_dbt/models/analytics/mart_host_performance.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Consumes: `dim_hosts`, `mart_listing_performance`.
- Produces: `analytics.mart_host_performance(host_id PK, host_name, is_superhost, host_created_at, host_age_days, host_segment, listing_count, active_listing_count, pct_active_listings, total_reviews, avg_reviews_per_listing, avg_price, median_price, avg_sentiment, first_review_date, last_review_date)`.

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `unique` and `not_null` on `host_id`; `not_null` on `listing_count`, `total_reviews`, `pct_active_listings`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run dbt test --select mart_host_performance --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 3: Implement `mart_host_performance.sql`**

Follow spec §6.9. Roll up `mart_listing_performance` by `host_id`, then join `dim_hosts`.

Rules:

- `active_listing_count = count(*) FILTER (WHERE is_active_last_12m)`.
- `pct_active_listings = active_listing_count / NULLIF(listing_count, 0)`.
- `total_reviews = sum(review_count)`.
- `avg_reviews_per_listing = total_reviews / NULLIF(listing_count, 0)`.
- `avg_price` and `median_price` exclude `is_price_outlier = TRUE`.
- `avg_sentiment` is the weighted mean of listing sentiment, weighted by `review_count`; if all weights are zero, return `NULL`.

- [ ] **Step 4: Build the mart**

Run: `uv run dbt build --select +mart_host_performance --profiles-dir ..`

Expected: PASS.

- [ ] **Step 5: Verify the host performance contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(*) as hosts, count(*) filter (where is_superhost) as superhosts, count(*) filter (where listing_count = 1) as single_listing_hosts, sum(total_reviews) as total_reviews from analytics.mart_host_performance;"
```

Expected: `14111`, `1920`, `12666`, `410283`.

- [ ] **Step 6: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 7: Market Monthly Mart

**Files:**
- Create: `airbnb_dbt/models/analytics/mart_market_monthly.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Consumes: `dim_date`, `dim_listings`, `fct_reviews`.
- Produces: `analytics.mart_market_monthly(month_start, room_type, new_listings, cumulative_listings, reviewing_listings, reviews, review_coverage, avg_sentiment, pct_positive, pct_negative, avg_price, median_price)`.

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `dbt_utils.unique_combination_of_columns` for `(month_start, room_type)`; `not_null` on both.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run dbt test --select mart_market_monthly --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 3: Implement `mart_market_monthly.sql`**

Follow spec §6.10.

- Build a month spine from `dim_date` where `date_day < '2021-12-01'`, using `year_month`.
- Cross join the four room types from `dim_listings`.
- `new_listings`: listings created in the month.
- `cumulative_listings`: listings created on or before month end.
- `reviewing_listings`: distinct listings with a review in the month.
- `reviews`: review count in the month.
- `review_coverage = reviewing_listings / NULLIF(cumulative_listings, 0)`.
- `avg_sentiment`, `pct_positive`, `pct_negative` from reviews in the month.
- `avg_price`, `median_price` among listings created by month end, excluding `is_price_outlier`.
- Use left joins so months with zero reviews/listings remain.

- [ ] **Step 4: Build the mart**

Run: `uv run dbt build --select +mart_market_monthly --profiles-dir ..`

Expected: PASS.

- [ ] **Step 5: Verify the monthly contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(*) as rows, min(month_start) as min_month, max(month_start) as max_month, sum(reviews) as total_reviews, sum(new_listings) as total_new_listings from analytics.mart_market_monthly;"
```

Expected: `620` rows (155 months × 4 room types), `2009-01-01` to `2021-11-01`, `410283`, `17499`.

- [ ] **Step 6: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 8: Price Bands and Room-Type Benchmark

**Files:**
- Create: `airbnb_dbt/models/analytics/mart_price_bands.sql`
- Create: `airbnb_dbt/models/analytics/mart_room_type_benchmark.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Consumes: `mart_listing_performance`.
- Produces:
  - `analytics.mart_price_bands(price_band, room_type, listing_count, share_of_room_type, avg_reviews, median_reviews, avg_sentiment, pct_superhost, pct_active)`
  - `analytics.mart_room_type_benchmark(room_type PK, listing_count, share_of_supply, avg_price, median_price, p90_price, avg_reviews, median_reviews, avg_sentiment, pct_superhost, pct_active)`

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `dbt_utils.unique_combination_of_columns` for `(price_band, room_type)` and `unique` on `room_type`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run dbt test --select mart_price_bands mart_room_type_benchmark --profiles-dir ..`

Expected: FAIL because the models do not exist yet.

- [ ] **Step 3: Implement `mart_price_bands.sql`**

Follow spec §6.11.

- Create a band spine with the seven bands and cross join the four room types; left join the aggregate so every combination exists.
- `share_of_room_type = listing_count / SUM(listing_count) OVER (PARTITION BY room_type)`.
- `pct_superhost` and `pct_active` are shares of listings in the band.
- `avg_reviews`, `median_reviews`, `avg_sentiment` are not price aggregates, so they may include outlier listings.

- [ ] **Step 4: Implement `mart_room_type_benchmark.sql`**

Follow spec §6.12.

- Aggregate from `mart_listing_performance` by `room_type`.
- `share_of_supply = listing_count / 17499`.
- `avg_price`, `median_price`, `p90_price` exclude `is_price_outlier = TRUE`.
- `pct_superhost`, `pct_active` are listing shares.

- [ ] **Step 5: Build the marts**

Run: `uv run dbt build --select +mart_price_bands +mart_room_type_benchmark --profiles-dir ..`

Expected: PASS.

- [ ] **Step 6: Verify the price contracts**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select (select count(*) from analytics.mart_price_bands) as band_rows, (select count(*) from analytics.mart_room_type_benchmark) as room_type_rows, (select sum(listing_count) from analytics.mart_room_type_benchmark) as total_listings;"
```

Expected: `28`, `4`, `17499`.

Verify median prices:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select room_type, listing_count, median_price from analytics.mart_room_type_benchmark order by room_type;"
```

Expected medians: Entire home/apt `75`, Hotel room `145`, Private room `35`, Shared room `30`.

- [ ] **Step 7: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 9: Executive KPIs

**Files:**
- Create: `airbnb_dbt/models/analytics/mart_executive_kpis.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Consumes: `dim_date`, `dim_listings`, `dim_hosts`, `fct_reviews`.
- Produces: `analytics.mart_executive_kpis(month_start PK, cumulative_listings, cumulative_hosts, new_listings, new_hosts, reviews, reviewing_listings, pct_listings_reviewed, pct_active_12m, avg_price, median_price, superhost_share, avg_sentiment, pct_positive, pct_negative, is_latest_review_month)`.

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `unique` and `not_null` on `month_start`; `not_null` on `is_latest_review_month`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run dbt test --select mart_executive_kpis --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 3: Implement `mart_executive_kpis.sql`**

Follow spec §6.14.

- Month spine from `dim_date` where `date_day < '2021-12-01'`.
- `cumulative_listings`: listings created on or before month end.
- `cumulative_hosts`: hosts created on or before month end.
- `new_listings`, `new_hosts`: created in the month.
- `reviews`, `reviewing_listings`: reviews and distinct reviewing listings in the month.
- `pct_listings_reviewed`: cumulative listings with at least one review / cumulative listings.
- `pct_active_12m`: listings with a review in the trailing 12 months / cumulative listings.
- `avg_price`, `median_price`: listings created by month end, excluding `is_price_outlier`.
- `superhost_share`: listings whose host is a superhost / cumulative listings.
- `avg_sentiment`, `pct_positive`, `pct_negative`: reviews in the month.
- `is_latest_review_month = (month_start = DATE '2021-10-01')`.

- [ ] **Step 4: Build the mart**

Run: `uv run dbt build --select +mart_executive_kpis --profiles-dir ..`

Expected: PASS.

- [ ] **Step 5: Verify the KPI contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(*) as rows, sum(reviews) as total_reviews, max(cumulative_listings) as latest_listings, max(cumulative_hosts) as latest_hosts, count(*) filter (where is_latest_review_month) as latest_review_months from analytics.mart_executive_kpis;"
```

Expected: `155` rows, `410283` total reviews, `17499` latest listings, `14111` latest hosts, `1` latest-review month.

Verify 2021 annual sentiment from the fact:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select round(avg(sentiment_score), 3) as sentiment_2021 from analytics.fct_reviews where review_year = 2021;"
```

Expected: `0.366`.

- [ ] **Step 6: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 10: Review Topics

**Files:**
- Create: `airbnb_dbt/seeds/seed_review_topics.csv`
- Create: `airbnb_dbt/models/intermediate/int_review_topics.sql`
- Create: `airbnb_dbt/models/analytics/mart_review_topics.sql`
- Modify: `airbnb_dbt/models/schema.yml`

**Interfaces:**
- Consumes: `fct_reviews`, `seed_review_topics`.
- Produces:
  - `intermediate.int_review_topics(review_id, review_month, topic, review_sentiment, sentiment_score)`
  - `analytics.mart_review_topics(month_start, topic, mentions, mention_rate, avg_sentiment, pct_negative)`

- [ ] **Step 1: Create `seeds/seed_review_topics.csv`**

Save the file as UTF-8.

```csv
topic,keywords_regex
cleanliness,sauber|\bclean\b|hygien|schmutz|\bdirty\b
location,\blage\b|\blocation\b|\bzentral\b|\bcentral\b|\bnahe\b|close to|\bnear\b
host,gastgeber|\bhost\b|\bkommunikation\b|\bcommunication\b
check-in,check.?in|check.?out|ankunft|arrival|schlüssel|\bkey\b
noise,\bruhig\b|\bquiet\b|\blaut\b|\bnoisy\b|\blärm\b|\bnoise\b
bed,\bbett\b|\bbed\b|\bmatratze\b|\bmattress\b
bathroom,badezimmer|\bbathroom\b|\bdusche\b|\bshower\b|\bwc\b
kitchen,küche|\bkitchen\b
wifi,wlan|\bwifi\b|\binternet\b
transport,u.?bahn|s.?bahn|\bbahn\b|\bmetro\b|\bsubway\b|\bbus\b|\btransport\b
breakfast,frühstück|\bbreakfast\b
```

- [ ] **Step 2: Add the failing tests to `models/schema.yml`**

For `int_review_topics`: `dbt_utils.unique_combination_of_columns` for `(review_id, topic)`; `relationships` from `review_id` to `fct_reviews.review_id`.

For `mart_review_topics`: `dbt_utils.unique_combination_of_columns` for `(month_start, topic)`; `mention_rate` between 0 and 1.

- [ ] **Step 3: Load the seed and run the tests to verify they fail**

Run: `uv run dbt seed --select seed_review_topics --profiles-dir ..`
Run: `uv run dbt test --select int_review_topics mart_review_topics --profiles-dir ..`

Expected: seed loads; tests FAIL because the models do not exist yet.

- [ ] **Step 4: Implement `int_review_topics.sql`**

Select from `fct_reviews` where `has_comment = TRUE`, join `seed_review_topics` on `review_text ~* keywords_regex`, and emit one row per matched review × topic with `review_id`, `review_month`, `topic`, `review_sentiment`, and `sentiment_score`.

- [ ] **Step 5: Implement `mart_review_topics.sql`**

Follow spec §6.13.

- Create a grid of months with at least one comment × all 11 topics; left join the topic counts.
- `mentions`: distinct `review_id` count for the month/topic.
- `mention_rate = mentions / reviews_with_comments_in_month`.
- `avg_sentiment`: average `sentiment_score` for matched reviews.
- `pct_negative`: negative matched reviews / mentions.

- [ ] **Step 6: Build the topic models**

Run: `uv run dbt build --select +mart_review_topics --profiles-dir ..`

Expected: PASS.

- [ ] **Step 7: Verify the topic contract**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select count(distinct topic) as topics, count(*) as rows, min(mention_rate) as min_rate, max(mention_rate) as max_rate from analytics.mart_review_topics;"
```

Expected: `11` topics; `min_rate >= 0`; `max_rate <= 1`.

Verify the top topic:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select topic, sum(mentions) as mentions from analytics.mart_review_topics group by 1 order by 2 desc limit 3;"
```

Expected: `location` is the top topic, with `transport` and `host` near the top.

- [ ] **Step 8: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 11: Full-Moon Mart, Exposures, and Docs

**Files:**
- Create: `airbnb_dbt/models/analytics/mart_full_moon_reviews.sql`
- Delete: `airbnb_dbt/models/mart/full_moon_reviews.sql`
- Modify: `airbnb_dbt/models/schema.yml`
- Replace: `airbnb_dbt/models/dashboards.yml`
- Modify: `Postgres Version/docs/RUNBOOK.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `fct_reviews`, `seed_full_moon_dates`.
- Produces: `analytics.mart_full_moon_reviews(is_full_moon, review_sentiment, reviews, share_of_group)` and five dbt exposures.

- [ ] **Step 1: Add the failing tests to `models/schema.yml`**

Add `accepted_values` for `is_full_moon`: `full_moon`, `not_full_moon`; `not_null` on `reviews`, `share_of_group`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `uv run dbt test --select mart_full_moon_reviews --profiles-dir ..`

Expected: FAIL because the model does not exist yet.

- [ ] **Step 3: Implement `mart_full_moon_reviews.sql`**

Follow spec §6.15. Delete the old `models/mart/full_moon_reviews.sql`.

- Join `fct_reviews` to `seed_full_moon_dates` on `review_date = full_moon_date + INTERVAL '1 day'`.
- `is_full_moon`: `full_moon` or `not_full_moon`.
- Aggregate by `is_full_moon`, `review_sentiment`.
- `share_of_group = reviews / SUM(reviews) OVER (PARTITION BY is_full_moon)`.

- [ ] **Step 4: Replace `models/dashboards.yml` with five exposures**

Use `type: dashboard`, `maturity: low`, `url: http://localhost:3000/dashboard/<id>`, and the existing owner block. Define:

| Exposure | `depends_on` |
|---|---|
| `executive_overview` | `mart_executive_kpis`, `mart_market_monthly`, `dim_listings` |
| `supply_pricing` | `mart_price_bands`, `mart_room_type_benchmark`, `dim_listings` |
| `guest_experience` | `mart_review_topics`, `mart_market_monthly`, `fct_reviews` |
| `host_portfolio` | `mart_host_performance`, `dim_hosts` |
| `listing_explorer` | `mart_listing_performance` |

- [ ] **Step 5: Build the full-moon mart**

Run: `uv run dbt build --select +mart_full_moon_reviews --profiles-dir ..`

Expected: PASS.

- [ ] **Step 6: Generate docs and verify the exposures**

Run: `uv run dbt docs generate --profiles-dir ..`
Run: `uv run dbt ls --resource-type exposure --profiles-dir ..`

Expected: docs generate succeeds; exactly five exposure names appear.

- [ ] **Step 7: Update `docs/RUNBOOK.md`**

Update these sections with the new model map:

- Project map: `analytics` and `snapshots` schemas.
- Data flow: raw → staging → intermediate → analytics.
- Fresh restart materialization order: dimensions, fact, marts.
- Row-count table: `dim_listings` 17,499; `dim_hosts` 14,111; `fct_reviews` 410,283; mart row counts from this plan.
- Metabase connection: query `analytics`, not `staging`.
- Troubleshooting: run `docker/init/03_reporting.sql` if grants are missing.

- [ ] **Step 8: Update the root `README.md` model list**

Replace the old dimension/fact/mart list with the new `dim_listings`, `dim_hosts`, `fct_reviews`, and `mart_*` names. Keep the dashboard section but describe the five dashboards.

- [ ] **Step 9: Stage the files**

Stage only the files changed in this task. Owner commits.

---

### Task 12: Full Build and Reconciliation

**Files:**
- No new files. This task verifies the whole project.

**Interfaces:**
- Consumes: every model and test from Tasks 1–11.

- [ ] **Step 1: Run the full build**

Run: `uv run dbt build --profiles-dir ..`

Expected: PASS with zero errors and zero skipped nodes caused by failures.

- [ ] **Step 2: Run the full test suite explicitly**

Run: `uv run dbt test --profiles-dir ..`

Expected: PASS with zero errors.

- [ ] **Step 3: Reconcile row counts**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select 'dim_listings' as model, count(*) from analytics.dim_listings union all select 'dim_hosts', count(*) from analytics.dim_hosts union all select 'fct_reviews', count(*) from analytics.fct_reviews union all select 'mart_listing_performance', count(*) from analytics.mart_listing_performance union all select 'mart_host_performance', count(*) from analytics.mart_host_performance union all select 'mart_market_monthly', count(*) from analytics.mart_market_monthly union all select 'mart_price_bands', count(*) from analytics.mart_price_bands union all select 'mart_room_type_benchmark', count(*) from analytics.mart_room_type_benchmark union all select 'mart_review_topics', count(*) from analytics.mart_review_topics union all select 'mart_executive_kpis', count(*) from analytics.mart_executive_kpis;"
```

Expected:

| Model | Rows |
|---|---:|
| `dim_listings` | 17,499 |
| `dim_hosts` | 14,111 |
| `fct_reviews` | 410,283 |
| `mart_listing_performance` | 17,499 |
| `mart_host_performance` | 14,111 |
| `mart_market_monthly` | 620 |
| `mart_price_bands` | 28 |
| `mart_room_type_benchmark` | 4 |
| `mart_review_topics` | 143 months × 11 topics = 1,573 |
| `mart_executive_kpis` | 155 |

`mart_review_topics` uses only months with comments. If the count differs, verify the number of distinct comment months before treating it as a failure. The verified count is 143 distinct comment months (2009-06 → 2021-10).

- [ ] **Step 4: Reconcile the KPI baseline**

Run:

```powershell
docker compose exec -T postgres psql -U postgres -d airbnb -c "select (select count(*) from analytics.mart_listing_performance where is_active_last_12m) as active_12m, (select count(*) from analytics.mart_listing_performance where not has_reviews) as no_reviews, (select round(100.0 * count(*) filter (where is_superhost) / count(*), 1) from analytics.mart_host_performance) as superhost_pct, (select round(percentile_cont(0.5) within group (order by price)::numeric, 0) from analytics.mart_listing_performance) as median_price, (select round(avg(sentiment_score), 3) from analytics.fct_reviews where review_year = 2021) as sentiment_2021;"
```

Expected: `6050`, `3254`, `13.6`, `55`, `0.366`.

- [ ] **Step 5: Verify the reporting contract**

Run as the `metabase` user:

```powershell
docker compose exec -T -e PGPASSWORD=metabasePassword123 postgres psql -U metabase -d airbnb -c "select count(*) from analytics.dim_listings;"
```

Expected: `17499`.

Run a staging query as the same user:

```powershell
docker compose exec -T -e PGPASSWORD=metabasePassword123 postgres psql -U metabase -d airbnb -c "select count(*) from staging.int_listings_enriched;"
```

Expected: permission denied for schema `staging` (or relation does not exist if the view was not built; either way, no rows are returned).

- [ ] **Step 6: Generate docs once more**

Run: `uv run dbt docs generate --profiles-dir ..`

Expected: success, with the five exposures and the new lineage.

- [ ] **Step 7: Review the working tree and hand off**

Run: `git status --short`

Expected: the revamp files are the only new changes. Pre-existing untracked items (`Postgres Version/fix/` and `Postgres Version/sql/_profile_data.sql`) are outside this plan. Do not commit. Report the final row counts, test result, and any deviations from the accepted baseline.

---

## Self-Review Notes

- Spec coverage: Tasks 1–3 cover schema, dimensions, fact, and data-quality fixes. Task 4 covers the date spine. Tasks 5–9 cover every core mart. Task 10 covers review topics. Task 11 covers the full-moon mart, exposures, and docs. Task 12 covers the acceptance criteria.
- Type consistency: every later task consumes the exact model and column names listed in the earlier task’s **Interfaces** block.
- Review Focus tests are attached to the owning tasks: null sentiment and dedupe (Task 3), zero-review listings (Task 5), price outliers (Tasks 2 and 5), and incremental re-runs (Task 3).
- Deliberate scope control: no raw-data changes, no Metabase compose service, no Phase B enrichment.
