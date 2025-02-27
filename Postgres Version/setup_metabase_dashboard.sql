-- Create a role for reporting
CREATE ROLE reporter;

-- Create a user for Metabase with appropriate permissions
CREATE USER metabase WITH 
  PASSWORD 'metabasePassword123'
  LOGIN;

-- Grant the reporter role to metabase user
GRANT reporter TO metabase;

-- Grant the reporter role to postgres (superuser)
GRANT reporter TO postgres;

-- Make sure we're in the right database
\c airbnb

-- Grant necessary privileges to the reporter role
GRANT USAGE ON SCHEMA staging TO reporter;
GRANT USAGE ON SCHEMA dev TO reporter;

-- Grant SELECT privileges on all tables in the schemas
GRANT SELECT ON ALL TABLES IN SCHEMA staging TO reporter;
GRANT SELECT ON ALL TABLES IN SCHEMA dev TO reporter;

-- Grant SELECT privileges on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT SELECT ON TABLES TO reporter;
ALTER DEFAULT PRIVILEGES IN SCHEMA dev GRANT SELECT ON TABLES TO reporter;