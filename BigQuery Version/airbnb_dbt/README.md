# Airbnb dbt project (BigQuery)

This dbt project transforms the raw Airbnb CSVs in BigQuery into the
`analytics` dataset consumed by Metabase.

## Layout

| Path | Materialization | Dataset |
| --- | --- | --- |
| `models/staging` | ephemeral | - |
| `models/intermediate` | view | `staging` |
| `models/analytics` | table | `analytics` |
| `snapshots` | snapshot | `snapshots` |
| `seeds` | table | `staging` |

Sources are declared in `models/sources.yml` and point at
`orbital-scene-422012-h0.raw` (`raw_listings`, `raw_hosts`, `raw_reviews`).

## Commands

Run from `BigQuery Version/airbnb_dbt/`:

```powershell
uv run dbt deps --profiles-dir ..
uv run dbt parse --profiles-dir ..
uv run dbt debug --profiles-dir ..
uv run dbt build --profiles-dir ..
uv run dbt test --profiles-dir ..
uv run dbt docs generate --profiles-dir ..
```

Expected full build: `PASS=126 WARN=0 ERROR=0 SKIP=0 NO-OP=5 TOTAL=131`.
Expected tests: `PASS=107`.

## Connection

`profiles.yml` lives one directory up and is gitignored. It uses gcloud
Application Default Credentials (`method: oauth`), project
`orbital-scene-422012-h0`, dataset `staging`, location `asia-southeast2`, and a
1 GiB per-query cap (`maximum_bytes_billed: 1000000000`).

## Notes

- Review dates are normalized to `DATE` in `src_reviews`; all source times are
  midnight.
- `dim_date` casts the dbt_utils date spine to `DATE` so month keys stay DATE.
- Native Metabase cards alias every table (`FROM analytics.x AS x`) so BigQuery
  Field Filters can qualify columns as `x.column`.
- Seeds: `seed_review_topics` uses Unicode-aware word boundaries
  (`(?:^|[^\p{L}\p{N}_])...`) to match Postgres `\y` semantics.
