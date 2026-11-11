-- Metabase stores its application data (users, questions, dashboards) in its
-- own database. Keeping it separate from `airbnb` means a database reset for
-- analytics work does not delete the Metabase configuration.
--
-- This script runs only when the Postgres volume is empty. On an existing
-- volume, create the database once manually:
--   docker compose exec postgres psql -U postgres -d airbnb -c "CREATE DATABASE metabase;"
CREATE DATABASE metabase;
