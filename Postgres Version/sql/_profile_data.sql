\pset pager off
\echo '=== 01 ROW COUNTS ==='
SELECT 'raw_listings' AS tbl, count(*) FROM raw.raw_listings
UNION ALL SELECT 'raw_hosts', count(*) FROM raw.raw_hosts
UNION ALL SELECT 'raw_reviews', count(*) FROM raw.raw_reviews
UNION ALL SELECT 'staging.dim_listings_w_hosts', count(*) FROM staging.dim_listings_w_hosts
UNION ALL SELECT 'staging.fct_reviews', count(*) FROM staging.fct_reviews
UNION ALL SELECT 'staging.full_moon_reviews', count(*) FROM staging.full_moon_reviews;

\echo '=== 02 LISTINGS NULLS / CARDINALITY ==='
SELECT
    count(*) AS rows,
    count(DISTINCT id) AS distinct_ids,
    count(*) - count(DISTINCT id) AS duplicate_ids,
    count(*) FILTER (WHERE listing_url IS NULL) AS null_url,
    count(*) FILTER (WHERE name IS NULL) AS null_name,
    count(*) FILTER (WHERE room_type IS NULL) AS null_room_type,
    count(*) FILTER (WHERE minimum_nights IS NULL) AS null_min_nights,
    count(*) FILTER (WHERE host_id IS NULL) AS null_host_id,
    count(*) FILTER (WHERE price IS NULL) AS null_price,
    count(*) FILTER (WHERE created_at IS NULL) AS null_created,
    count(*) FILTER (WHERE updated_at IS NULL) AS null_updated,
    min(created_at) AS min_created,
    max(created_at) AS max_created,
    min(updated_at) AS min_updated,
    max(updated_at) AS max_updated
FROM raw.raw_listings;

\echo '=== 03 LISTINGS ROOM TYPE / PRICE STRING ==='
SELECT room_type, count(*) AS listings,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM raw.raw_listings GROUP BY room_type ORDER BY listings DESC;

SELECT
    count(*) FILTER (WHERE price ~ '^\$[0-9,]+(\.[0-9]+)?$') AS dollar_comma_ok,
    count(*) FILTER (WHERE price ~ '^\$[0-9]+(\.[0-9]+)?$') AS dollar_ok,
    count(*) FILTER (WHERE price ~ '^[0-9]+(\.[0-9]+)?$') AS bare_number,
    count(*) FILTER (WHERE price !~ '^\$?[0-9,]+(\.[0-9]+)?$') AS other_format,
    min(price) AS min_price_str, max(price) AS max_price_str
FROM raw.raw_listings;

SELECT price, count(*) AS n FROM raw.raw_listings
GROUP BY price ORDER BY n DESC LIMIT 10;

\echo '=== 04 LISTING CREATED_AT BY YEAR ==='
SELECT EXTRACT(YEAR FROM created_at)::int AS year, count(*) AS listings
FROM raw.raw_listings GROUP BY 1 ORDER BY 1;

\echo '=== 05 HOSTS NULLS / CARDINALITY ==='
SELECT
    count(*) AS rows,
    count(DISTINCT id) AS distinct_ids,
    count(*) - count(DISTINCT id) AS duplicate_ids,
    count(*) FILTER (WHERE name IS NULL) AS null_name,
    count(*) FILTER (WHERE is_superhost IS NULL) AS null_superhost,
    count(*) FILTER (WHERE created_at IS NULL) AS null_created,
    count(*) FILTER (WHERE updated_at IS NULL) AS null_updated,
    min(created_at) AS min_created, max(created_at) AS max_created,
    min(updated_at) AS min_updated, max(updated_at) AS max_updated
FROM raw.raw_hosts;

\echo '=== 06 HOST SUPERHOST DIST ==='
SELECT is_superhost, count(*) AS hosts,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM raw.raw_hosts GROUP BY is_superhost ORDER BY hosts DESC;

\echo '=== 07 HOST CREATED_AT BY YEAR ==='
SELECT EXTRACT(YEAR FROM created_at)::int AS year, count(*) AS hosts
FROM raw.raw_hosts GROUP BY 1 ORDER BY 1;

\echo '=== 08 REVIEWS NULLS / RANGE ==='
SELECT
    count(*) AS rows,
    count(*) FILTER (WHERE listing_id IS NULL) AS null_listing_id,
    count(*) FILTER (WHERE date IS NULL) AS null_date,
    count(*) FILTER (WHERE reviewer_name IS NULL) AS null_reviewer,
    count(*) FILTER (WHERE comments IS NULL) AS null_comments,
    count(*) FILTER (WHERE comments = '') AS empty_comments,
    count(*) FILTER (WHERE sentiment IS NULL) AS null_sentiment,
    min(date) AS min_date, max(date) AS max_date,
    count(DISTINCT listing_id) AS distinct_listings_reviewed
FROM raw.raw_reviews;

\echo '=== 09 REVIEWS PER YEAR ==='
SELECT EXTRACT(YEAR FROM date)::int AS year, count(*) AS reviews
FROM raw.raw_reviews GROUP BY 1 ORDER BY 1;

\echo '=== 10 SENTIMENT DIST ==='
SELECT sentiment, count(*) AS reviews,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM raw.raw_reviews GROUP BY sentiment ORDER BY reviews DESC;

\echo '=== 11 REVIEWS PER LISTING DIST ==='
WITH r AS (SELECT listing_id, count(*) n FROM raw.raw_reviews GROUP BY 1)
SELECT
    count(*) AS listings_with_reviews,
    round(avg(n), 2) AS avg_reviews,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY n) AS median_reviews,
    max(n) AS max_reviews,
    count(*) FILTER (WHERE n = 1) AS one_review,
    count(*) FILTER (WHERE n >= 10) AS ten_plus,
    count(*) FILTER (WHERE n >= 50) AS fifty_plus
FROM r;

\echo '=== 12 COVERAGE LISTINGS vs REVIEWS ==='
SELECT
    (SELECT count(*) FROM raw.raw_listings) AS listings_total,
    (SELECT count(DISTINCT listing_id) FROM raw.raw_reviews) AS listings_reviewed,
    (SELECT count(*) FROM raw.raw_listings l WHERE NOT EXISTS
        (SELECT 1 FROM raw.raw_reviews r WHERE r.listing_id = l.id)) AS listings_no_reviews,
    (SELECT count(*) FROM raw.raw_reviews r WHERE NOT EXISTS
        (SELECT 1 FROM raw.raw_listings l WHERE l.id = r.listing_id)) AS reviews_orphaned;

\echo '=== 13 REVIEW DUPLICATES ==='
SELECT
    count(*) - count(DISTINCT (listing_id, date, reviewer_name, comments)) AS duplicate_full_rows,
    count(*) - count(DISTINCT (listing_id, date, reviewer_name)) AS duplicate_key_rows
FROM raw.raw_reviews;

\echo '=== 14 COMMENT LENGTH ==='
SELECT
    count(*) FILTER (WHERE length(comments) < 20) AS under_20,
    count(*) FILTER (WHERE length(comments) BETWEEN 20 AND 99) AS len_20_99,
    count(*) FILTER (WHERE length(comments) >= 100) AS len_100_plus,
    round(avg(length(comments)), 1) AS avg_len,
    max(length(comments)) AS max_len
FROM raw.raw_reviews WHERE comments IS NOT NULL;

\echo '=== 15 LISTINGS PRICE PARSE (cleansed logic) ==='
WITH parsed AS (
    SELECT CAST(REPLACE(REPLACE(price, '$', ''), ',', '') AS NUMERIC) AS price
    FROM raw.raw_listings
)
SELECT count(*) AS rows,
       count(price) AS parsed,
       round(min(price), 2) AS min_price,
       round(percentile_cont(0.25) WITHIN GROUP (ORDER BY price)::numeric, 2) AS p25,
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY price)::numeric, 2) AS median,
       round(percentile_cont(0.75) WITHIN GROUP (ORDER BY price)::numeric, 2) AS p75,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY price)::numeric, 2) AS p95,
       round(max(price), 2) AS max_price,
       count(*) FILTER (WHERE price = 0) AS zero_price
FROM parsed;

\echo '=== 16 MINIMUM_NIGHTS DIST ==='
SELECT
    count(*) FILTER (WHERE minimum_nights = 0) AS zero_nights,
    count(*) FILTER (WHERE minimum_nights BETWEEN 1 AND 6) AS one_to_six,
    count(*) FILTER (WHERE minimum_nights BETWEEN 7 AND 29) AS one_week_to_month,
    count(*) FILTER (WHERE minimum_nights >= 30) AS month_plus,
    max(minimum_nights) AS max_nights
FROM raw.raw_listings;

\echo '=== 17 HOSTS PER LISTING / LISTINGS PER HOST ==='
WITH h AS (SELECT host_id, count(*) n FROM raw.raw_listings GROUP BY 1)
SELECT count(*) AS hosts_with_listings,
       round(avg(n), 2) AS avg_listings_per_host,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY n) AS median,
       max(n) AS max_listings,
       count(*) FILTER (WHERE n = 1) AS single_listing_hosts,
       count(*) FILTER (WHERE n >= 10) AS ten_plus_listings
FROM h;

\echo '=== 18 STAGING FCT/REVIEWS QUALITY ==='
SELECT count(*) AS rows,
       count(*) FILTER (WHERE review_text IS NULL) AS null_text,
       min(review_date) AS min_date, max(review_date) AS max_date
FROM staging.fct_reviews;

SELECT is_full_moon, count(*) AS reviews
FROM staging.full_moon_reviews GROUP BY 1 ORDER BY 1;

\echo '=== 19 REVIEWS PER MONTH (last 24 months present) ==='
SELECT date_trunc('month', date)::date AS month, count(*) AS reviews
FROM raw.raw_reviews
GROUP BY 1 ORDER BY 1 DESC LIMIT 24;
