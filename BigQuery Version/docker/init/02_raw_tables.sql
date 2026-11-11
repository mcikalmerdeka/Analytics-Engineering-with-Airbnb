-- Load the Airbnb raw CSVs into the `raw` schema.
-- The CSVs are mounted read-only at /data by compose.yaml.

SET search_path TO raw;

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
FROM '/data/raw/raw_listings.csv'
WITH (FORMAT CSV, HEADER true, QUOTE '"');

DROP TABLE IF EXISTS raw_reviews;
CREATE TABLE raw_reviews (
    listing_id integer,
    date timestamp,
    reviewer_name varchar,
    comments text,
    sentiment varchar
);

COPY raw_reviews(listing_id, date, reviewer_name, comments, sentiment)
FROM '/data/raw/raw_reviews.csv'
WITH (FORMAT CSV, HEADER true, QUOTE '"');

DROP TABLE IF EXISTS raw_hosts;
CREATE TABLE raw_hosts (
    id integer,
    name varchar,
    is_superhost varchar,
    created_at timestamp,
    updated_at timestamp
);

COPY raw_hosts(id, name, is_superhost, created_at, updated_at)
FROM '/data/raw/raw_hosts.csv'
WITH (FORMAT CSV, HEADER true, QUOTE '"');

ANALYZE raw_listings;
ANALYZE raw_reviews;
ANALYZE raw_hosts;
