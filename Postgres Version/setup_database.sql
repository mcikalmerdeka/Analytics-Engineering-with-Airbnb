-- Check username priviledges
SELECT rolname, rolcanlogin, rolsuper FROM pg_roles;
SELECT * FROM pg_roles;
SELECT usename, passwd FROM pg_shadow;

-- Create transform role
CREATE ROLE transform;
ALTER ROLE transform WITH NOLOGIN;

-- Change role to transform
SET ROLE transform;
SET SESSION AUTHORIZATION transform;

-- Create database and schema
CREATE DATABASE IF NOT EXISTS airbnb;
\c airbnb  -- Connect to database
CREATE SCHEMA IF NOT EXISTS raw;

-- Grant privileges to transform role
GRANT CONNECT ON DATABASE airbnb TO transform;
GRANT USAGE ON SCHEMA raw TO transform;
GRANT CREATE ON SCHEMA raw TO transform;

-- Grant table permissions (PostgreSQL doesn't have FUTURE GRANTS)
ALTER DEFAULT PRIVILEGES IN SCHEMA raw 
  GRANT ALL ON TABLES TO transform;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER 
  ON ALL TABLES IN SCHEMA raw TO transform;