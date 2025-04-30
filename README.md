# Analytics Engineering with Airbnb

**Update 16/02/2025**: 
> - Previously I made this using Snowflake as the data warehouse and Preset as the BI tools. Since I was using the free-tier of Snowflake that only lasted for 1 month, all of the created pipelines has been suspended.

> - So I decided to recreate the project using the open source tools such as PostgreSQL and Metabase (running local through Docker).

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
├── airbnb_dbt/                    # dbt project for data transformations
│   ├── models/                    # Data models organized in layers
│   │   ├── staging/               # Source-aligned raw data models
│   │   ├── dimension/             # Dimension tables (hosts, listings)
│   │   ├── fact/                  # Fact tables (reviews)
│   │   └── mart/                  # Business-specific aggregations
│   ├── dbt_project.yml            # dbt project configuration
│   └── packages.yml               # dbt dependencies
├── airbnb_dagster_project/        # Dagster project for workflow orchestration
├── setup_database.sql             # SQL scripts to set up the database
├── setup_metabase_dashboard.sql   # SQL scripts for Metabase setup
└── requirements.txt               # Python dependencies
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

### Prerequisites

- Docker and Docker Compose
- Python 3.9+
- PostgreSQL client (optional, for direct database access)

### Installation

1. Clone the repository:

   ```
   git clone https://github.com/yourusername/Analytics-Engineering-with-Airbnb.git
   cd Analytics-Engineering-with-Airbnb/Postgres\ Version/
   ```
2. Set up the Python environment:

   ```
   python -m venv dbt-env
   source dbt-env/bin/activate  # On Windows: dbt-env\Scripts\activate
   pip install -r requirements.txt
   ```
3. Set up the database:

   ```
   psql -U postgres -f setup_database.sql
   ```
4. Initialize dbt:

   ```
   cd airbnb_dbt
   dbt deps
   dbt seed
   ```
5. Run the dbt models:

   ```
   dbt run
   ```
6. Set up Dagster for orchestration:

   ```
   cd ../airbnb_dagster_project
   pip install -e .
   dagster dev
   ```
7. Set up Metabase for visualization:

   ```
   docker run -d -p 3000:3000 --name metabase metabase/metabase
   ```

## Workflow Orchestration

The project uses Dagster to orchestrate the dbt transformations. The Dagster pipeline:

1. Loads raw data into PostgreSQL
2. Triggers dbt transformations
3. Schedules regular updates

## Data Visualization

Metabase is used to create interactive dashboards for analyzing:

- Listing prices by neighborhood
- Host performance metrics
- Review sentiment analysis
- Seasonal booking trends

## Project Workflow

1. Raw Airbnb data is loaded into PostgreSQL
2. dbt transforms the data into dimensional models
3. Dagster orchestrates the regular updates of the data
4. Metabase provides interactive dashboards for analysis

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the [MIT License](LICENSE).
