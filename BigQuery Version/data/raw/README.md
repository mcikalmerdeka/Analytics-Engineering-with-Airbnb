# Raw data

The raw Airbnb CSVs are not committed to git (see the root `.gitignore`). Download them from the dbtlearn S3 bucket and keep the local filenames shown below:

| Local file | Source |
| --- | --- |
| `raw_listings.csv` | https://dbtlearn.s3.us-east-2.amazonaws.com/listings.csv |
| `raw_reviews.csv` | https://dbtlearn.s3.us-east-2.amazonaws.com/reviews.csv |
| `raw_hosts.csv` | https://dbtlearn.s3.us-east-2.amazonaws.com/hosts.csv |

The `seed_full_moon_dates.csv` file used by dbt is tracked separately in `airbnb_dbt/seeds/` (source: https://dbtlearn.s3.us-east-2.amazonaws.com/seed_full_moon_dates.csv).

These files are loaded into BigQuery by `scripts/load_raw_data.ps1`. The loader
runs one `bq load --replace` job per file, so rerunning it truncates and reloads
`raw_listings`, `raw_hosts`, and `raw_reviews` in the `raw` dataset. The local Docker
Postgres container is not used for analytics data; it stores only the Metabase
application database.

```powershell
cd "BigQuery Version"
.\scripts\load_raw_data.ps1
.\scripts\validate_bigquery.ps1 -RawOnly
```
