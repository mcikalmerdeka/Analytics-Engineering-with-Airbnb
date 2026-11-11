# Postgres Analytics Revamp — Phase A Design

**Date:** 2026-11-05
**Scope:** `Postgres Version/airbnb_dbt`
**Status:** Approved design; implementation plan written
**Author:** AXIOM (AI agent) with Muhammad Cikal Merdeka

## 1. Context

The Postgres project is a local Berlin Airbnb analytics stack:

- PostgreSQL 17 in Docker on host port `5433`
- dbt Core 1.12.6 + dbt-postgres 1.11.0
- Dagster 1.13 for orchestration
- Metabase for visualization (optional)

The raw data is the dbtlearn Berlin snapshot:

| Table | Rows | Date range |
|---|---:|---|
| `raw.raw_listings` | 17,499 | created 2009-06-05 → 2021-11-19 |
| `raw.raw_hosts` | 14,111 | created 2009-06-05 → 2021-11-19 |
| `raw.raw_reviews` | 410,284 | 2009-06-20 → 2021-10-22 |

The row count is not the problem. The schema is narrow: listings have only nine columns and reviews have five. There is no neighbourhood, latitude/longitude, capacity, property type, amenities, availability, review score, booking, or calendar data. The current dbt project also stops at staging plus one wide dimension, one review fact, and a full-moon mart. There is no analytics layer for BI.

The result is that Metabase must join 410k reviews to dimensions for every chart, and the available slices are limited to room type, price, minimum nights, superhost status, listing age, review date, and sentiment.

## 2. Goals

1. Create a clean, BI-facing `analytics` schema containing only dimensions, one fact, and dashboard marts.
2. Add derived dimensions that multiply the useful slices without changing raw data:
   - price bands
   - minimum-night bands
   - listing age cohorts
   - host portfolio segments
   - review recency / activity
   - review topic mentions
3. Add marts at the correct grain for the intended dashboards:
   - one row per listing
   - one row per host
   - one row per month × room type
   - one row per price band × room type
   - one row per month × review topic
   - one row per month for KPI cards
4. Fix correctness issues in the existing review fact:
   - deterministic review key
   - safe incremental loading
   - keep null-comment reviews
   - deduplicate only exact duplicates
5. Make the reporting contract explicit through dbt exposures and tests.
6. Keep the existing Dagster integration working. No Dagster code changes are required because it reads the dbt manifest.

## 3. Non-goals

- No raw CSV replacement or enrichment in Phase A.
- No neighbourhood maps, occupancy, revenue, capacity, amenities, or review-score analysis. Those require richer raw data and are Phase B.
- No Metabase service changes in `compose.yaml`. Metabase setup remains optional and manual.
- No machine-learning sentiment model. The source `sentiment` column is treated as precomputed input.
- No changes to the Docker raw loader or the raw table schemas.
- No compatibility views for old model names. The database can be reset with `docker compose down -v`, and Metabase questions will be rebuilt against `analytics`.

## 4. Verified current-state facts

These numbers are the acceptance baseline.

| Fact | Value |
|---|---:|
| Listings | 17,499 |
| Hosts | 14,111 |
| Raw reviews | 410,284 |
| Distinct reviews after exact dedupe | 410,283 |
| Listings with at least one review | 14,245 |
| Listings with zero reviews | 3,254 |
| Listings active in trailing 12 months as of 2021-11-19 | 6,050 (34.6%) |
| Superhost hosts | 1,920 (13.6%) |
| Superhost listings | 2,738 |
| Median listing price | $55 |
| 2021 average sentiment score | 0.366 |
| 2019 average sentiment score | 0.533 |

Sentiment score is defined as `positive = 1`, `neutral = 0`, `negative = -1`.

## 5. Target architecture

### 5.1 Schema contract

| Schema | Purpose | Visible to Metabase |
|---|---|---|
| `staging` | Ephemeral models and internal views | No |
| `analytics` | Dimensions, fact, and dashboard marts | Yes |
| `snapshots` | SCD snapshot tables | No |

The `metabase` database user inherits the `reporter` role. `reporter` receives `USAGE` on `analytics` and `SELECT` on its tables. Access to `staging` is removed from the reporting contract.

### 5.2 DAG

```text
raw.raw_listings ─┐
raw.raw_hosts ────┼──> staging.src_* (ephemeral)
raw.raw_reviews ──┘
                         │
                         ▼
        intermediate.int_listings_enriched (view)
        intermediate.int_reviews_deduped (view)
        intermediate.int_review_topics (view)
                         │
                         ▼
        analytics.dim_date
        analytics.dim_hosts
        analytics.dim_listings
        analytics.fct_reviews
                         │
                         ├── analytics.mart_executive_kpis
                         ├── analytics.mart_listing_performance
                         ├── analytics.mart_host_performance
                         ├── analytics.mart_market_monthly
                         ├── analytics.mart_price_bands
                         ├── analytics.mart_room_type_benchmark
                         ├── analytics.mart_review_topics
                         └── analytics.mart_full_moon_reviews
```

### 5.3 Materializations

| Layer | Materialization | Schema |
|---|---|---|
| `staging` | `ephemeral` | `staging` |
| `intermediate` | `view` | `staging` |
| `analytics.dim_*` | `table` | `analytics` |
| `analytics.fct_reviews` | `incremental` (`delete+insert` on `review_id`) | `analytics` |
| `analytics.mart_*` | `table` | `analytics` |
| Snapshots | `snapshot` | `snapshots` |

The dimensions and marts are small (14k–17k rows), so tables are cheap and faster for Metabase. `fct_reviews` stays incremental to preserve the project's incremental-loading example. Because the raw data is static, `dbt build --full-refresh` is always safe.

## 6. Model specifications

### 6.1 `staging.src_listings`, `src_hosts`, `src_reviews`

Keep the existing source-aligned models. Changes:

- `src_reviews` keeps `review_text` nullable.
- `src_listings` keeps `price_str` for lineage.
- No business logic beyond renaming and casting.

### 6.2 `intermediate.int_listings_enriched`

**Grain:** one row per listing.
**Materialization:** view in `staging`.

Joins `src_listings` to `src_hosts` on `host_id`.

Columns:

| Column | Logic |
|---|---|
| `listing_id` | `src_listings.listing_id` |
| `listing_name` | source name |
| `listing_url` | source URL |
| `room_type` | source room type |
| `price` | `CAST(REPLACE(REPLACE(price_str, '$', ''), ',', '') AS NUMERIC)` |
| `price_band` | `<30`, `30-49`, `50-74`, `75-99`, `100-149`, `150-249`, `250+` |
| `is_price_outlier` | `price = 0 OR price > p99.5(price) within room_type` |
| `minimum_nights` | `CASE WHEN minimum_nights = 0 THEN 1 ELSE minimum_nights END` |
| `minimum_nights_band` | `1`, `2-6`, `7-29`, `30+` |
| `host_id` | source host id |
| `host_name` | `COALESCE(host_name, 'Anonymous')` |
| `is_superhost` | `CASE is_superhost WHEN 't' THEN TRUE WHEN 'f' THEN FALSE ELSE NULL END` |
| `is_superhost_known` | `is_superhost IS NOT NULL` |
| `host_created_at` | source host created timestamp |
| `listing_created_at` | source listing created timestamp |
| `listing_updated_at` | source listing updated timestamp |
| `listing_age_days` | `DATE '2021-11-19' - listing_created_at::date` |
| `listing_age_cohort` | `< 1 year`, `1-2 years`, `3-5 years`, `6+ years` |
| `host_listing_count` | count of listings per `host_id` |
| `host_segment` | `Single listing` (1), `Small portfolio` (2–4), `Professional` (5–9), `Large professional` (10–19), `Enterprise` (20+) |

`p99.5` is computed per `room_type` in a grouped CTE and joined back to the listing rows. PostgreSQL does not allow `percentile_cont` with `OVER`, so the CTE pattern is required:

```sql
SELECT room_type,
       percentile_cont(0.995) WITHIN GROUP (ORDER BY price) AS p99_5
FROM parsed_listings
GROUP BY room_type
```

The outlier flag is used to exclude extreme prices from distribution charts; it does not remove rows.

### 6.3 `intermediate.int_reviews_deduped`

**Grain:** one row per distinct review.
**Materialization:** view in `staging`.

Columns:

| Column | Logic |
|---|---|
| `review_id` | `dbt_utils.generate_surrogate_key(['listing_id', 'review_date', 'reviewer_name', 'review_text'])` |
| `listing_id` | source listing id |
| `review_date` | source review date |
| `reviewer_name` | source reviewer name (kept for lineage, not exposed in marts) |
| `review_text` | source comment, nullable |
| `review_sentiment` | `COALESCE(sentiment, 'unknown')` |
| `sentiment_score` | `positive = 1`, `neutral = 0`, `negative = -1`, `unknown = NULL` |
| `has_comment` | `review_text IS NOT NULL` |
| `review_length` | `LENGTH(review_text)` |
| `review_year` | `EXTRACT(YEAR FROM review_date)` |
| `review_month` | `DATE_TRUNC('month', review_date)::date` |

Deduplication uses `ROW_NUMBER() OVER (PARTITION BY listing_id, review_date, reviewer_name, review_text ORDER BY review_date) = 1`. This removes the one exact duplicate row and keeps the 31 legitimate same-day/same-reviewer reviews that have different comments. Expected row count: **410,283**.

### 6.4 `analytics.dim_date`

**Grain:** one row per day.
**Range:** 2009-01-01 → 2021-12-31.

Generated with `dbt_utils.date_spine`.

Columns: `date_day`, `date_key` (`YYYYMMDD` integer), `year`, `quarter`, `month`, `month_name`, `month_short`, `year_month` (first day of month), `week_of_year`, `day_of_week`, `day_name`, `is_weekend`.

### 6.5 `analytics.dim_listings`

**Grain:** one row per listing.
**Materialization:** table.

Selects attributes from `int_listings_enriched`:

`listing_id`, `listing_name`, `listing_url`, `room_type`, `price`, `price_band`, `is_price_outlier`, `minimum_nights`, `minimum_nights_band`, `host_id`, `host_name`, `is_superhost`, `is_superhost_known`, `host_listing_count`, `host_segment`, `listing_created_at`, `listing_age_days`, `listing_age_cohort`, `listing_updated_at`.

Review metrics are deliberately excluded. They live in `mart_listing_performance`.

### 6.6 `analytics.dim_hosts`

**Grain:** one row per host.
**Materialization:** table.

Columns: `host_id`, `host_name`, `is_superhost`, `is_superhost_known`, `host_created_at`, `host_age_days` (as of 2021-11-19), `host_listing_count`, `host_segment`.

### 6.7 `analytics.fct_reviews`

**Grain:** one row per review.
**Materialization:** incremental, `unique_key = 'review_id'`, `incremental_strategy = 'delete+insert'`, `on_schema_change = 'append_new_columns'`.

Columns: `review_id`, `listing_id`, `review_date`, `reviewer_name`, `review_text`, `review_sentiment`, `sentiment_score`, `has_comment`, `review_length`, `review_year`, `review_month`.

Incremental filter:

```sql
{% if is_incremental() %}
WHERE review_date >= (
    SELECT COALESCE(MAX(review_date), DATE '1900-01-01') - INTERVAL '3 days'
    FROM {{ this }}
)
{% endif %}
```

The three-day lookback captures late-arriving or corrected reviews; `delete+insert` prevents duplicate `review_id`s.

`reviewer_name` stays in the fact for lineage but is not exposed in any mart.

### 6.8 `analytics.mart_listing_performance`

**Grain:** one row per listing.
**Materialization:** table.

Built from `dim_listings` left joined to `fct_reviews` aggregated by `listing_id`.

Columns:

- `listing_id`, `listing_name`, `room_type`, `price`, `price_band`, `is_price_outlier`, `minimum_nights`
- `host_id`, `host_name`, `is_superhost`, `host_segment`
- `listing_age_days`, `has_reviews`, `is_active_last_12m`
- `review_count`, `review_count_12m`
- `first_review_date`, `last_review_date`, `days_since_last_review`
- `reviews_per_year`
- `avg_sentiment`, `pct_positive`, `pct_neutral`, `pct_negative`
- `avg_review_length`

Rules:

- `as_of_date = DATE '2021-11-19'`.
- `is_active_last_12m = last_review_date > as_of_date - INTERVAL '12 months'`.
- `review_count_12m` counts reviews in the trailing 12 months.
- `reviews_per_year = review_count / GREATEST(listing_age_days / 365.25, 1)`.
- Percentages are `NULL` when `has_reviews = FALSE`; `has_reviews` makes the null meaning explicit.
- `avg_review_length` uses only reviews with comments.

### 6.9 `analytics.mart_host_performance`

**Grain:** one row per host.
**Materialization:** table.

Built from `dim_hosts` left joined to `mart_listing_performance` aggregated by `host_id`.

Columns:

- `host_id`, `host_name`, `is_superhost`, `host_created_at`, `host_age_days`, `host_segment`
- `listing_count`, `active_listing_count`, `pct_active_listings`
- `total_reviews`, `avg_reviews_per_listing`

`pct_active_listings = active_listing_count / listing_count`. `avg_sentiment` is weighted by each listing's `review_count`. Price aggregates (`avg_price`, `median_price`) exclude listings flagged as price outliers.
- `avg_price`, `median_price`
- `avg_sentiment`
- `first_review_date`, `last_review_date`

### 6.10 `analytics.mart_market_monthly`

**Grain:** one row per month × room type.
**Materialization:** table.

Month spine: distinct `year_month` from `dim_date` between 2009-01-01 and 2021-11-01, cross joined to the four room types. This ensures zero-filled months.

Columns:

- `month_start`, `room_type`
- `new_listings` — listings created in the month
- `cumulative_listings` — listings created on or before month end
- `reviewing_listings` — distinct listings with a review in the month
- `reviews` — reviews in the month
- `review_coverage` — `reviewing_listings / cumulative_listings`
- `avg_sentiment`, `pct_positive`, `pct_negative`
- `avg_price`, `median_price` — among listings created on or before month end

Price is static, so it represents the listed price of supply, not a transaction price. Price aggregates (`avg_price`, `median_price`) exclude listings flagged as price outliers.

### 6.11 `analytics.mart_price_bands`

**Grain:** one row per price band × room type.
**Materialization:** table.

Built from `mart_listing_performance`.

Columns: `price_band`, `room_type`, `listing_count`, `share_of_room_type`, `avg_reviews`, `median_reviews`, `avg_sentiment`, `pct_superhost`, `pct_active`.

`share_of_room_type = listing_count / total listings in that room type`; `pct_superhost` is the share of listings in the band whose host is a superhost; `pct_active` is the share of listings in the band active in the trailing 12 months.

### 6.12 `analytics.mart_room_type_benchmark`

**Grain:** one row per room type.
**Materialization:** table.

Columns: `room_type`, `listing_count`, `share_of_supply`, `avg_price`, `median_price`, `p90_price`, `avg_reviews`, `median_reviews`, `avg_sentiment`, `pct_superhost`, `pct_active`.

`share_of_supply = listing_count / 17,499`; `pct_active` is the share of listings of that room type active in the trailing 12 months. Price aggregates (`avg_price`, `median_price`, `p90_price`) exclude listings flagged as price outliers.

### 6.13 `analytics.mart_review_topics`

**Grain:** one row per month × topic.
**Materialization:** table.

Uses a new seed `seeds/seed_review_topics.csv` with two columns: `topic`, `keywords_regex`.

Seed rows (bilingual German/English, case-insensitive):

| Topic | Regex examples |
|---|---|
| `cleanliness` | `sauber\|\bclean\b\|hygien\|schmutz\|\bdirty\b` |
| `location` | `\blage\b\|\blocation\b\|\bzentral\b\|\bcentral\b\|\bnahe\b\|close to\|\bnear\b` |
| `host` | `gastgeber\|\bhost\b\|\bkommunikation\b\|\bcommunication\b` |
| `check-in` | `check.?in\|check.?out\|ankunft\|arrival\|schlüssel\|\bkey\b` |
| `noise` | `\bruhig\b\|\bquiet\b\|\blaut\b\|\bnoisy\b\|\blärm\b\|\bnoise\b` |
| `bed` | `\bbett\b\|\bbed\b\|\bmatratze\b\|\bmattress\b` |
| `bathroom` | `badezimmer\|\bbathroom\b\|\bdusche\b\|\bshower\b\|\bwc\b` |
| `kitchen` | `küche\|\bkitchen\b` |
| `wifi` | `wlan\|\bwifi\b\|\binternet\b` |
| `transport` | `u.?bahn\|s.?bahn\|\bbahn\b\|\bmetro\b\|\bsubway\b\|\bbus\b\|\btransport\b` |
| `breakfast` | `frühstück\|\bbreakfast\b` |

`intermediate.int_review_topics` produces one row per review × matched topic. A review can match multiple topics and contributes once per topic.

`mart_review_topics` aggregates:

- `month_start`, `topic`
- `mentions`
- `mention_rate` — mentions divided by reviews with comments in the month
- `avg_sentiment`
- `pct_negative`

Topic matching is directional, not a semantic classifier. The dashboard should label it “keyword mentions,” not “topic sentiment” in a definitive sense. The pipes in the table are escaped for Markdown; the seed stores plain `|` alternation.

### 6.14 `analytics.mart_executive_kpis`

**Grain:** one row per month.
**Materialization:** table.

Columns:

- `month_start`
- `cumulative_listings`, `cumulative_hosts`
- `new_listings`, `new_hosts`
- `reviews`, `reviewing_listings`
- `pct_listings_reviewed`
- `pct_active_12m`
- `avg_price`, `median_price`
- `superhost_share`
- `avg_sentiment`, `pct_positive`, `pct_negative`
- `is_latest_review_month`

Rules:

- `cumulative_hosts` = hosts created on or before month end.
- `pct_listings_reviewed` = cumulative distinct listings with at least one review / cumulative listings.
- `pct_active_12m` = distinct listings with a review in the trailing 12 months / cumulative listings.
- `superhost_share` = listings whose host is a superhost / cumulative listings.
- `is_latest_review_month = TRUE` for 2021-10, the last month with review data. October is partial (reviews through 2021-10-22), so the dashboard should label it as partial.
- Price aggregates (`avg_price`, `median_price`) exclude listings flagged as price outliers.

### 6.15 `analytics.mart_full_moon_reviews`

**Grain:** one row per `is_full_moon` × `review_sentiment`.
**Materialization:** table.

Built from `fct_reviews` joined to `seed_full_moon_dates` on `review_date = full_moon_date + 1 day`.

Columns: `is_full_moon`, `review_sentiment`, `reviews`, `share_of_group`.

`share_of_group = reviews / all reviews in that full-moon group`. This remains a novelty mart and is not part of the core executive dashboard.

## 7. Data quality rules

### 7.1 Source freshness

Remove the `freshness` block from `sources.yml`. The review source is a static 2021 snapshot; a 1-hour/24-hour freshness threshold can never pass. Add a comment explaining that freshness belongs to a future ingestion layer.

### 7.2 Price

- `price = 0` is flagged as an outlier.
- `price > p99.5` within room type is flagged as an outlier.
- Outliers remain in the data; dashboards filter them for distribution charts.
- KPI cards use median price.

### 7.3 Hosts

- 15 hosts have null names and null superhost values.
- `host_name` becomes `Anonymous`.
- `is_superhost` is nullable boolean; `is_superhost_known` makes the gap explicit.
- Do not coerce unknown superhosts to `FALSE`.

### 7.4 Reviews

- Keep null-comment reviews.
- `review_sentiment` becomes `unknown` when the source is null.
- Deduplicate only exact duplicates.
- Do not deduplicate the 31 same-day/same-reviewer reviews with different comments.
- Do not expose `reviewer_name` in BI marts.

### 7.5 Snapshots

Keep `scd_raw_listings` and `scd_raw_hosts` for the course/SCD example, but move them to the `snapshots` schema. They contain one version per key and are not part of the analytics contract.

## 8. Tests

| Model | Tests |
|---|---|
| `dim_listings` | `unique` + `not_null` on `listing_id`; `relationships` to `dim_hosts`; `accepted_values` for `room_type`; `price >= 0`; `minimum_nights >= 1` |
| `dim_hosts` | `unique` + `not_null` on `host_id`; `not_null` on `is_superhost_known` |
| `fct_reviews` | `unique` + `not_null` on `review_id`; `relationships` to `dim_listings`; `accepted_values` for `review_sentiment` (`positive`, `neutral`, `negative`, `unknown`); `not_null` on `review_date`; custom test `review_date >= listing_created_at`; row-count reconciliation to the raw source minus the one exact duplicate |
| `mart_listing_performance` | `unique` + `not_null` on `listing_id`; row count equals `dim_listings`; `not_null` on `review_count` |
| `mart_host_performance` | `unique` + `not_null` on `host_id`; row count equals `dim_hosts` |
| `mart_market_monthly` | `unique_combination_of_columns` (`month_start`, `room_type`); `not_null` on both |
| `mart_price_bands` | `unique_combination_of_columns` (`price_band`, `room_type`) |
| `mart_room_type_benchmark` | `unique` on `room_type` |
| `mart_review_topics` | `unique_combination_of_columns` (`month_start`, `topic`); `mention_rate` between 0 and 1 |
| `mart_executive_kpis` | `unique` on `month_start`; percentage fields between 0 and 1 |

Custom tests:

- `assert_review_after_listing_created`: no review predates its listing.
- `assert_no_future_reviews`: `review_date <= DATE '2021-11-19'`.
- `assert_price_positive`: `price >= 0` on `dim_listings`.

## 9. Exposures and dashboards

Replace `models/dashboards.yml` with five exposures. Use `http://localhost:3000/dashboard/<id>` as the URL placeholder until the Metabase dashboards exist; replace each one when the dashboard is created.

| Exposure | Depends on | Purpose |
|---|---|---|
| `executive_overview` | `mart_executive_kpis`, `mart_market_monthly`, `dim_listings` | KPI cards, growth, review volume, room mix, sentiment trend |
| `supply_pricing` | `mart_price_bands`, `mart_room_type_benchmark`, `dim_listings` | Price distribution, room-type benchmark, minimum-night segments, superhost premium |
| `guest_experience` | `mart_review_topics`, `mart_market_monthly`, `fct_reviews` | Review volume/seasonality, sentiment, topic mentions |
| `host_portfolio` | `mart_host_performance`, `dim_hosts` | Portfolio concentration, professional hosts, superhost performance |
| `listing_explorer` | `mart_listing_performance` | One-row-per-listing drill-down table |

The existing `models/dashboards.yml` is replaced by these exposures. The owner remains Muhammad Cikal Merdeka.

## 10. Configuration changes

### 10.1 `dbt_project.yml`

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

Also update the per-snapshot `target_schema` config in `snapshots/scd_raw_listings.sql` and `snapshots/scd_raw_hosts.sql` from `staging` to `snapshots`, because the file-level config overrides the project-level default.

### 10.2 `macros/generate_schema_name.sql`

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
```

This produces `analytics`, not `staging_analytics`.

### 10.3 Reporting grants

In `docker/init/01_schema_roles.sql`:

```sql
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS snapshots;
```

In `docker/init/03_reporting.sql`:

```sql
CREATE SCHEMA IF NOT EXISTS analytics;
GRANT USAGE ON SCHEMA analytics TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO reporter;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA analytics
    GRANT SELECT ON TABLES TO reporter;

REVOKE USAGE ON SCHEMA staging FROM reporter;
```

The user can reset the stack with `docker compose down -v` and `docker compose up -d`. Existing databases need the grant SQL run manually once.

## 11. Migration and rollout

1. No raw-data migration. The CSV loader and raw schema stay unchanged.
2. The user may reset the database at any time:
   ```powershell
   docker compose down -v
   docker compose up -d
   ```
3. Run:
   ```powershell
   cd airbnb_dbt
   uv run dbt deps --profiles-dir ..
   uv run dbt build --profiles-dir ..
   ```
4. Existing Metabase questions that reference `staging.*` will break. Rebuild them against `analytics.*`. This is intentional: the analytics schema is the reporting contract.
5. Dagster requires no code change. It reads `target/manifest.json` and will expose the new models automatically.

## 12. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Static 2021 data makes incremental loading cosmetic | Keep incremental for the example; document that `--full-refresh` is safe and that freshness checks are disabled |
| Sentiment is precomputed and may reflect COVID/cancellation effects | Treat it as source data; label 2020–2021 as a distinct period in dashboards |
| Price currency is ambiguous (`$` in source) | Label as “source price”; do not claim EUR or USD conversion |
| Keyword topics are directional, not semantic | Label as “keyword mentions”; use bilingual patterns; document coverage |
| Deduping changes review count by 1 | Document expected 410,283; test row-count reconciliation |
| Reviewer names are PII | Keep in the fact for lineage; exclude from all marts |
| Metabase questions break on schema change | User accepted a reset/rebuild; provide a model map in the runbook |
| `percentile_cont` cannot be used with `OVER` on Postgres | Compute the p99.5 threshold in a grouped CTE and join it back; verified against PostgreSQL 17 |

## 13. Acceptance criteria

- `uv run dbt build --profiles-dir ..` completes with zero errors.
- `uv run dbt test --profiles-dir ..` completes with zero errors.
- Row counts:
  - `dim_listings` = 17,499
  - `dim_hosts` = 14,111
  - `fct_reviews` = 410,283
  - `mart_listing_performance` = 17,499
  - `mart_host_performance` = 14,111
- KPI reconciliation:
  - active listings as of 2021-11-19 = 6,050
  - superhost host share = 13.6%
  - median price = $55
  - 2021 average sentiment = 0.366
- `analytics` schema contains only `dim_*`, `fct_reviews`, and `mart_*` objects.
- `reporter` can `SELECT` from `analytics` tables and cannot use `staging`.
- `dbt docs generate` shows the five exposures and the new lineage.
- `docs/RUNBOOK.md` documents the new schema and model map.

## 14. Implementation order

1. Add schema configuration, `generate_schema_name` macro, folder structure, and reporting grants.
2. Build `int_listings_enriched`, `dim_listings`, `dim_hosts`, and their tests.
3. Build `int_reviews_deduped`, `fct_reviews`, and review tests.
4. Build `dim_date`.
5. Build `mart_listing_performance` and `mart_host_performance`.
6. Build `mart_market_monthly`, `mart_price_bands`, `mart_room_type_benchmark`, and `mart_executive_kpis`.
7. Add `seed_review_topics.csv`, `int_review_topics`, and `mart_review_topics`.
8. Move and test `mart_full_moon_reviews`.
9. Add exposures, model/column descriptions, and the runbook update.
10. Run the full build, reconcile KPIs, and verify Metabase access.

## 15. Resolved decisions

- **Raw data:** unchanged in Phase A. Phase B can re-source to a full Inside Airbnb snapshot.
- **Model names:** use clean `dim_listings` and `dim_hosts`; no compatibility views. The database can be reset.
- **Review topics:** included in Phase A as a differentiator.
- **Metabase:** no compose change; setup remains manual.
- **Snapshots:** kept for the SCD example, moved out of the reporting path.
- **Reviewer names:** kept in `fct_reviews`, excluded from marts.
- **Fact materialization:** incremental with `delete+insert`; full refresh is safe for the static source.
