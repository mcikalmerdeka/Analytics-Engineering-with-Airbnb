# Raw data

The raw Airbnb CSVs are not committed to git (see the root `.gitignore`). Download them from the dbtlearn S3 bucket and keep the local filenames shown below:

| Local file | Source |
| --- | --- |
| `raw_listings.csv` | https://dbtlearn.s3.us-east-2.amazonaws.com/listings.csv |
| `raw_reviews.csv` | https://dbtlearn.s3.us-east-2.amazonaws.com/reviews.csv |
| `raw_hosts.csv` | https://dbtlearn.s3.us-east-2.amazonaws.com/hosts.csv |

The `seed_full_moon_dates.csv` file used by dbt is tracked separately in `airbnb_dbt/seeds/` (source: https://dbtlearn.s3.us-east-2.amazonaws.com/seed_full_moon_dates.csv).

These files are mounted read-only into the Postgres container at `/data` and loaded by `docker/init/02_raw_tables.sql` on the first `docker compose up`. To reload after changing the files, run `docker compose down -v` and `docker compose up -d`.
