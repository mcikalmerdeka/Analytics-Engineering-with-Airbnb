# Analytics Engineering with Airbnb

![Project Header](assets/Project%20Header.jpg)

**Update 16/02/2025**:

> - Previously I made this using Snowflake as the data warehouse and Preset as the BI tools. Since I was using the free-tier of Snowflake that only lasted for 1 month, all of the created pipelines has been suspended.

> - So I decided to recreate the project using the open source tools such as PostgreSQL and Metabase (running local through Docker).

**Update 03/11/2026**:

> - Revamped the `Postgres Version` project to use `uv` (Python 3.13, managed by uv), a Dockerized PostgreSQL 17 instance on port `5433`, dbt v1.12, and Dagster 1.13. The local PostgreSQL 18 service is not used by this project.
> - dbt v2 (Fusion) is not yet supported for Postgres, so the project stays on dbt v1 until the Postgres adapter is available.

This project demonstrates a modern data stack implementation using Airbnb data. It includes data transformation pipelines using dbt (data build tool), workflow orchestration with Dagster, and visualization with Metabase.

## Project Overview

This project showcases the end-to-end process of building a data analytics pipeline:

1. **Data Ingestion**: Loading raw Airbnb data into PostgreSQL
2. **Data Transformation**: Using dbt to transform the raw data into analytical models
3. **Workflow Orchestration**: Using Dagster to orchestrate the data pipeline
4. **Data Visualization**: Creating dashboards with Metabase

## Technology Stack

- **Database**: PostgreSQL (running locally through Docker)
- **Transformation**: dbt (data build tool)
- **Orchestration**: Dagster
- **Visualization**: Metabase
- **Infrastructure**: Docker for containerization

## Project Structure

```
Postgres Version/
├── pyproject.toml                # uv workspace + dbt dependencies
├── uv.lock                       # Locked Python dependencies
├── compose.yaml                  # Dockerized PostgreSQL (host port 5433)
├── docker/init/                  # Schema, raw CSV bootstrap, reporting grants
├── docker/pgadmin/               # pgAdmin server configuration
├── scripts/                      # Local helper scripts (live row-count watcher)
├── profiles.yml                  # Local dbt connection (gitignored)
├── airbnb_dbt/                   # dbt project for data transformations
│   ├── models/                   # Data models organized in layers
│   │   ├── staging/              # Source-aligned raw data models
│   │   ├── dimension/            # Dimension tables (hosts, listings)
│   │   ├── fact/                 # Fact tables (reviews)
│   │   └── mart/                 # Business-specific aggregations
│   ├── dbt_project.yml           # dbt project configuration
│   └── packages.yml              # dbt dependencies
├── airbnb_dagster_project/       # Dagster project for workflow orchestration
├── sql/                          # Ad-hoc SQL data checks
├── docs/                         # Historical setup notes
└── data/raw/                     # Raw CSVs (gitignored; see data/raw/README.md)
```

## Data Models

The data models are organized into the following layers:

### Source Layer (Staging)

- `src_listings`: Raw listings data from Airbnb
- `src_hosts`: Raw hosts data from Airbnb
- `src_reviews`: Raw reviews data from Airbnb

### Dimensions Layer

- `dim_listings_cleansed`: Cleaned listings data with proper data types
- `dim_hosts_cleansed`: Cleaned hosts data with proper data types
- `dim_listings_w_hosts`: Joint dimension table with listings and hosts data

### Fact Layer

- `fct_reviews`: Fact table containing reviews data with incremental loading capability

### Mart Layer

- `full_moon_reviews`: Analysis of reviews that occurred during full moon periods

## Getting Started

For the full command reference, setup order, database browsing, and troubleshooting, see [`Postgres Version/docs/RUNBOOK.md`](Postgres%20Version/docs/RUNBOOK.md).

### Prerequisites

- [uv](https://docs.astral.sh/uv/)
- Docker Desktop
- Metabase (optional, for visualization)

### Installation

1. Clone the repository and enter the Postgres project:

   ```powershell
   git clone https://github.com/mcikalmerdeka/Analytics-Engineering-with-Airbnb.git
   cd "Analytics-Engineering-with-Airbnb/Postgres Version"
   ```

2. Install the Python environment. `uv` reads `.python-version` and uses its own managed Python 3.13:

   ```powershell
   uv sync
   ```

3. Start the Dockerized PostgreSQL. The first start loads the raw CSVs into the `raw` schema:

   ```powershell
   docker compose up -d
   docker compose exec postgres psql -U postgres -d airbnb -c "select count(*) from raw.raw_listings;"
   ```

4. Install dbt packages and build/test the models:

   ```powershell
   cd airbnb_dbt
   uv run dbt deps
   uv run dbt build --profiles-dir ..
   ```

5. Start Dagster (UI on port `3001`):

   ```powershell
   cd ../airbnb_dagster_project
   uv run dagster dev -p 3001
   ```

6. (Optional) Browse the database with pgAdmin at `http://localhost:5050`:

   - Login: `admin@example.com` / `admin123`
   - Server: `Airbnb Postgres` (pre-configured)
   - Database: `airbnb`
   - User: `postgres`
   - Password: `cikalmerdeka`

   To watch row counts from the terminal while Dagster runs:

   ```powershell
   .\scripts\watch_db.ps1
   ```

7. (Optional) Start Metabase and connect it to the local database:

   ```powershell
   docker run -d -p 3000:3000 --name airbnb-metabase metabase/metabase
   ```

   - Host: `host.docker.internal` (or `localhost` if Metabase runs on the host)
   - Port: `5433`
   - Database: `airbnb`
   - User: `metabase`
   - Password: `metabasePassword123`

### Reset the local database

The Docker init scripts only run when the database volume is empty. To reload the raw data from scratch:

```powershell
docker compose down -v
docker compose up -d
```

> **dbt v2 note:** dbt v2 (formerly Fusion) does not yet support Postgres. This project therefore uses dbt v1 (`dbt-core` 1.12 + `dbt-postgres` 1.11). Once the Postgres adapter ships for dbt v2, the switch is `dagster-dbt[dbt]` + the `dbt` package, with the `dbt-core`/`dbt-postgres` dependencies removed.

## Workflow Orchestration

The project uses Dagster to orchestrate the dbt transformations. The Dagster pipeline:

1. Loads raw data into PostgreSQL
2. Triggers dbt transformations
3. Schedules regular updates

## Data Visualization

![Airbnb Executive Dashboard](https://raw.githubusercontent.com/mcikalmerdeka/Analytics-Engineering-with-Airbnb/refs/heads/main/assets/Metabase%20Dashboard.png)

The project uses Metabase to create an interactive executive dashboard that includes:

- **KPI Metrics**:

  - Number of Hosts (290)
  - New Listings (331)
- **Interactive Filters**:

  - Room Type (Entire home, Private room, Other)
  - Superhost Indicator (True/False)
  - Price Range
  - Review Sentiment
  - Fullmoon Indicator
  - Month and Year selection
- **Data Visualizations**:

  - Superhosts Distribution (pie chart showing percentage of superhosts)
  - Room Type Distribution (breakdown of listing types)
  - Sentiment vs Full Moon Analysis (comparing review sentiment during full moon periods)
  - Price Distribution (histogram of listing prices)

## Project Workflow

1. Raw Airbnb data is loaded into PostgreSQL
2. dbt transforms the data into dimensional models
3. Dagster orchestrates the regular updates of the data
4. Metabase provides interactive dashboards for analysis

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the [MIT License](LICENSE).
