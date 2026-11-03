-- Give the Metabase reporting user read access to the dbt output schema.
GRANT USAGE ON SCHEMA staging TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA staging TO reporter;

-- Apply the same permissions to tables dbt creates in the future.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA staging
    GRANT SELECT ON TABLES TO reporter;
