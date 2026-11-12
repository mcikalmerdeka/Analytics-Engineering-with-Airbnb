-- Profile the raw Airbnb CSVs and the analytics layer in BigQuery.
-- Run in the BigQuery console or with:
--   bq query --use_legacy_sql=false < sql/_profile_data.sql
--
-- Exact medians use PERCENTILE_CONT as a window function; profiling uses
-- APPROX_QUANTILES where an approximate distribution is acceptable.

-- === 01 ROW COUNTS ===
SELECT 'raw.raw_listings' AS object_name, COUNT(*) AS row_count
FROM `orbital-scene-422012-h0.raw.raw_listings`
UNION ALL
SELECT 'raw.raw_hosts', COUNT(*)
FROM `orbital-scene-422012-h0.raw.raw_hosts`
UNION ALL
SELECT 'raw.raw_reviews', COUNT(*)
FROM `orbital-scene-422012-h0.raw.raw_reviews`
UNION ALL
SELECT 'analytics.dim_listings', COUNT(*)
FROM `orbital-scene-422012-h0.analytics.dim_listings`
UNION ALL
SELECT 'analytics.fct_reviews', COUNT(*)
FROM `orbital-scene-422012-h0.analytics.fct_reviews`
ORDER BY object_name;

-- === 02 LISTINGS NULLS / CARDINALITY ===
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT id) AS distinct_ids,
    COUNT(*) - COUNT(DISTINCT id) AS duplicate_ids,
    COUNTIF(listing_url IS NULL) AS null_url,
    COUNTIF(name IS NULL) AS null_name,
    COUNTIF(room_type IS NULL) AS null_room_type,
    COUNTIF(minimum_nights IS NULL) AS null_min_nights,
    COUNTIF(host_id IS NULL) AS null_host_id,
    COUNTIF(price IS NULL) AS null_price,
    COUNTIF(created_at IS NULL) AS null_created,
    COUNTIF(updated_at IS NULL) AS null_updated,
    MIN(created_at) AS min_created,
    MAX(created_at) AS max_created
FROM `orbital-scene-422012-h0.raw.raw_listings`;

-- === 03 LISTINGS ROOM TYPE / PRICE STRING ===
SELECT
    room_type,
    COUNT(*) AS listings,
    ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS pct
FROM `orbital-scene-422012-h0.raw.raw_listings`
GROUP BY room_type
ORDER BY listings DESC;

SELECT
    COUNTIF(REGEXP_CONTAINS(price, r'^\$[0-9,]+(\.[0-9]+)?$')) AS dollar_comma_ok,
    COUNTIF(REGEXP_CONTAINS(price, r'^\$[0-9]+(\.[0-9]+)?$')) AS dollar_ok,
    COUNTIF(REGEXP_CONTAINS(price, r'^[0-9]+(\.[0-9]+)?$')) AS bare_number,
    COUNTIF(NOT REGEXP_CONTAINS(price, r'^\$?[0-9,]+(\.[0-9]+)?$')) AS other_format
FROM `orbital-scene-422012-h0.raw.raw_listings`;

-- === 04 LISTING CREATED_AT BY YEAR ===
SELECT EXTRACT(YEAR FROM created_at) AS year, COUNT(*) AS listings
FROM `orbital-scene-422012-h0.raw.raw_listings`
GROUP BY year
ORDER BY year;

-- === 05 HOSTS NULLS / CARDINALITY ===
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT id) AS distinct_ids,
    COUNT(*) - COUNT(DISTINCT id) AS duplicate_ids,
    COUNTIF(name IS NULL) AS null_name,
    COUNTIF(is_superhost IS NULL) AS null_superhost,
    COUNTIF(created_at IS NULL) AS null_created,
    COUNTIF(updated_at IS NULL) AS null_updated
FROM `orbital-scene-422012-h0.raw.raw_hosts`;

-- === 06 HOST SUPERHOST DISTRIBUTION ===
SELECT
    is_superhost,
    COUNT(*) AS hosts,
    ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS pct
FROM `orbital-scene-422012-h0.raw.raw_hosts`
GROUP BY is_superhost
ORDER BY hosts DESC;

-- === 07 REVIEWS NULLS / RANGE ===
SELECT
    COUNT(*) AS row_count,
    COUNTIF(listing_id IS NULL) AS null_listing_id,
    COUNTIF(`date` IS NULL) AS null_date,
    COUNTIF(reviewer_name IS NULL) AS null_reviewer,
    COUNTIF(comments IS NULL) AS null_comments,
    COUNTIF(comments = '') AS empty_comments,
    COUNTIF(sentiment IS NULL) AS null_sentiment,
    MIN(`date`) AS min_date,
    MAX(`date`) AS max_date,
    COUNT(DISTINCT listing_id) AS distinct_listings_reviewed
FROM `orbital-scene-422012-h0.raw.raw_reviews`;

-- === 08 REVIEWS PER YEAR / SENTIMENT ===
SELECT EXTRACT(YEAR FROM `date`) AS year, COUNT(*) AS reviews
FROM `orbital-scene-422012-h0.raw.raw_reviews`
GROUP BY year
ORDER BY year;

SELECT
    sentiment,
    COUNT(*) AS reviews,
    ROUND(100 * SAFE_DIVIDE(COUNT(*), SUM(COUNT(*)) OVER ()), 2) AS pct
FROM `orbital-scene-422012-h0.raw.raw_reviews`
GROUP BY sentiment
ORDER BY reviews DESC;

-- === 09 REVIEWS PER LISTING DISTRIBUTION ===
WITH reviews_per_listing AS (
    SELECT listing_id, COUNT(*) AS n
    FROM `orbital-scene-422012-h0.raw.raw_reviews`
    GROUP BY listing_id
)
SELECT
    COUNT(*) AS listings_with_reviews,
    ROUND(AVG(n), 2) AS avg_reviews,
    APPROX_QUANTILES(n, 100)[OFFSET(50)] AS median_reviews,
    MAX(n) AS max_reviews,
    COUNTIF(n = 1) AS one_review,
    COUNTIF(n >= 10) AS ten_plus,
    COUNTIF(n >= 50) AS fifty_plus
FROM reviews_per_listing;

-- === 10 COVERAGE LISTINGS vs REVIEWS ===
SELECT
    (SELECT COUNT(*) FROM `orbital-scene-422012-h0.raw.raw_listings`) AS listings_total,
    (SELECT COUNT(DISTINCT listing_id) FROM `orbital-scene-422012-h0.raw.raw_reviews`) AS listings_reviewed,
    (SELECT COUNT(*) FROM `orbital-scene-422012-h0.raw.raw_listings` l
     WHERE NOT EXISTS (
         SELECT 1 FROM `orbital-scene-422012-h0.raw.raw_reviews` r
         WHERE r.listing_id = l.id
     )) AS listings_no_reviews,
    (SELECT COUNT(*) FROM `orbital-scene-422012-h0.raw.raw_reviews` r
     WHERE NOT EXISTS (
         SELECT 1 FROM `orbital-scene-422012-h0.raw.raw_listings` l
         WHERE l.id = r.listing_id
     )) AS reviews_orphaned;

-- === 11 REVIEW DUPLICATES ===
SELECT
    COUNT(*) - COUNT(DISTINCT TO_JSON_STRING(STRUCT(listing_id, `date`, reviewer_name, comments))) AS duplicate_full_rows
FROM `orbital-scene-422012-h0.raw.raw_reviews`;

-- === 12 COMMENT LENGTH ===
SELECT
    COUNTIF(LENGTH(comments) < 20) AS under_20,
    COUNTIF(LENGTH(comments) BETWEEN 20 AND 99) AS len_20_99,
    COUNTIF(LENGTH(comments) >= 100) AS len_100_plus,
    ROUND(AVG(LENGTH(comments)), 1) AS avg_len,
    MAX(LENGTH(comments)) AS max_len
FROM `orbital-scene-422012-h0.raw.raw_reviews`
WHERE comments IS NOT NULL;

-- === 13 LISTINGS PRICE PARSE ===
WITH parsed AS (
    SELECT CAST(REPLACE(REPLACE(price, '$', ''), ',', '') AS NUMERIC) AS price
    FROM `orbital-scene-422012-h0.raw.raw_listings`
)
SELECT
    COUNT(*) AS row_count,
    COUNT(price) AS parsed,
    ROUND(MIN(price), 2) AS min_price,
    ROUND(APPROX_QUANTILES(price, 100)[OFFSET(25)], 2) AS p25,
    ROUND(APPROX_QUANTILES(price, 100)[OFFSET(50)], 2) AS median,
    ROUND(APPROX_QUANTILES(price, 100)[OFFSET(75)], 2) AS p75,
    ROUND(APPROX_QUANTILES(price, 100)[OFFSET(95)], 2) AS p95,
    ROUND(MAX(price), 2) AS max_price,
    COUNTIF(price = 0) AS zero_price
FROM parsed;

-- === 14 ANALYTICS KPI SNAPSHOT ===
SELECT
    (SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_listings`) AS total_listings,
    (SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_hosts`) AS total_hosts,
    (SELECT COUNT(*) FROM `orbital-scene-422012-h0.analytics.fct_reviews`) AS total_reviews,
    (SELECT COUNTIF(is_active_last_12m) FROM `orbital-scene-422012-h0.analytics.mart_listing_performance`) AS active_listings,
    (SELECT ROUND(AVG(price), 2) FROM `orbital-scene-422012-h0.analytics.dim_listings` WHERE NOT is_price_outlier) AS avg_nightly_price,
    (SELECT ROUND(SAFE_DIVIDE(COUNTIF(review_sentiment = 'positive'), COUNT(*)) * 100, 2) FROM `orbital-scene-422012-h0.analytics.fct_reviews`) AS positive_share_pct;

-- === 15 TABLE INVENTORY ===
SELECT 'raw' AS dataset, table_name, table_type
FROM `orbital-scene-422012-h0.raw.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT 'staging', table_name, table_type
FROM `orbital-scene-422012-h0.staging.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT 'analytics', table_name, table_type
FROM `orbital-scene-422012-h0.analytics.INFORMATION_SCHEMA.TABLES`
UNION ALL
SELECT 'snapshots', table_name, table_type
FROM `orbital-scene-422012-h0.snapshots.INFORMATION_SCHEMA.TABLES`
ORDER BY dataset, table_name;
