-- Set search path (similar to USE SCHEMA)
SET search_path TO raw;

-- Create listings table
DROP TABLE IF EXISTS raw_listings;
CREATE TABLE raw_listings (
    id integer,
    listing_url varchar,
    name varchar,
    room_type varchar,
    minimum_nights integer,
    host_id integer,
    price varchar,
    created_at timestamp,
    updated_at timestamp
);

COPY raw_listings(id, listing_url, name, room_type, minimum_nights, 
                 host_id, price, created_at, updated_at)
FROM 'E:/Personal Projects/Analytics Engineering with Airbnb/Analytics-Engineering-with-Airbnb/Postgres Version/raw_csv_snowflake/raw_listings.csv'
WITH (FORMAT CSV, HEADER true, QUOTE '"');

-- Create reviews table
DROP TABLE IF EXISTS raw_reviews;
CREATE TABLE raw_reviews (
    listing_id integer,
    date timestamp,
    reviewer_name varchar,
    comments text,
    sentiment varchar
);

COPY raw_reviews(listing_id, date, reviewer_name, comments, sentiment)
FROM 'E:/Personal Projects/Analytics Engineering with Airbnb/Analytics-Engineering-with-Airbnb/Postgres Version/raw_csv_snowflake/raw_reviews.csv'
WITH (FORMAT CSV, HEADER true, QUOTE '"');

-- Create hosts table
DROP TABLE IF EXISTS raw_hosts;
CREATE TABLE raw_hosts (
    id integer,
    name varchar,
    is_superhost varchar,
    created_at timestamp,
    updated_at timestamp
);

COPY raw_hosts(id, name, is_superhost, created_at, updated_at)
FROM 'E:/Personal Projects/Analytics Engineering with Airbnb/Analytics-Engineering-with-Airbnb/Postgres Version/raw_csv_snowflake/raw_hosts.csv'
WITH (FORMAT CSV, HEADER true, QUOTE '"');