-- Give the Metabase reporting user read access to the analytics output only.
CREATE SCHEMA IF NOT EXISTS analytics;

GRANT USAGE ON SCHEMA analytics TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO reporter;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA analytics
    GRANT SELECT ON TABLES TO reporter;

REVOKE USAGE ON SCHEMA staging FROM reporter;
