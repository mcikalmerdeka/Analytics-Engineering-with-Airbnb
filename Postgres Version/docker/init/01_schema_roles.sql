-- Create the schemas used by the project.
-- Raw CSVs are loaded into `raw`; dbt builds internal models into `staging`,
-- BI-facing models into `analytics`, and SCD snapshots into `snapshots`.
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS snapshots;

-- Local reporting user for Metabase. This is a development-only password.
CREATE ROLE reporter NOLOGIN;
CREATE ROLE metabase WITH LOGIN PASSWORD 'metabasePassword123';
GRANT reporter TO metabase;

DO $$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO metabase', current_database());
END
$$;
