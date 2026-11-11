{{ config(materialized='view') }}

WITH src_listings AS (
    SELECT *
    FROM {{ ref('src_listings') }}
),
src_hosts AS (
    SELECT *
    FROM {{ ref('src_hosts') }}
),
parsed_listings AS (
    SELECT
        l.listing_id,
        l.listing_name,
        l.listing_url,
        l.room_type,
        CAST(REPLACE(REPLACE(l.price_str, '$', ''), ',', '') AS NUMERIC) AS price,
        CASE
            WHEN l.minimum_nights = 0 THEN 1
            ELSE l.minimum_nights
        END AS minimum_nights,
        l.host_id,
        h.host_name AS host_name_raw,
        h.is_superhost AS is_superhost_raw,
        h.created_at AS host_created_at,
        l.created_at AS listing_created_at,
        l.updated_at AS listing_updated_at
    FROM src_listings l
    LEFT JOIN src_hosts h ON l.host_id = h.host_id
),
typed_listings AS (
    SELECT
        *,
        CASE is_superhost_raw
            WHEN 't' THEN TRUE
            WHEN 'f' THEN FALSE
            ELSE NULL
        END AS is_superhost
    FROM parsed_listings
),
aged_listings AS (
    SELECT
        *,
        DATE '2021-11-19' - listing_created_at::date AS listing_age_days
    FROM typed_listings
),
price_thresholds AS (
    SELECT
        room_type,
        percentile_cont(0.995) WITHIN GROUP (ORDER BY price) AS p99_5_price
    FROM parsed_listings
    GROUP BY room_type
),
host_listing_counts AS (
    SELECT
        host_id,
        COUNT(*) AS host_listing_count
    FROM parsed_listings
    GROUP BY host_id
)
SELECT
    a.listing_id,
    a.listing_name,
    a.listing_url,
    a.room_type,
    a.price,
    CASE
        WHEN a.price < 30 THEN '<30'
        WHEN a.price < 50 THEN '30-49'
        WHEN a.price < 75 THEN '50-74'
        WHEN a.price < 100 THEN '75-99'
        WHEN a.price < 150 THEN '100-149'
        WHEN a.price < 250 THEN '150-249'
        ELSE '250+'
    END AS price_band,
    (a.price = 0 OR a.price > p.p99_5_price) AS is_price_outlier,
    a.minimum_nights,
    CASE
        WHEN a.minimum_nights = 1 THEN '1'
        WHEN a.minimum_nights <= 6 THEN '2-6'
        WHEN a.minimum_nights <= 29 THEN '7-29'
        ELSE '30+'
    END AS minimum_nights_band,
    a.host_id,
    COALESCE(a.host_name_raw, 'Anonymous') AS host_name,
    a.is_superhost,
    a.is_superhost IS NOT NULL AS is_superhost_known,
    a.host_created_at,
    a.listing_created_at,
    a.listing_updated_at,
    a.listing_age_days,
    CASE
        WHEN a.listing_age_days < 365 THEN '< 1 year'
        WHEN a.listing_age_days < 1095 THEN '1-2 years'
        WHEN a.listing_age_days < 2190 THEN '3-5 years'
        ELSE '6+ years'
    END AS listing_age_cohort,
    c.host_listing_count,
    CASE
        WHEN c.host_listing_count = 1 THEN 'Single listing'
        WHEN c.host_listing_count BETWEEN 2 AND 4 THEN 'Small portfolio'
        WHEN c.host_listing_count BETWEEN 5 AND 9 THEN 'Professional'
        WHEN c.host_listing_count BETWEEN 10 AND 19 THEN 'Large professional'
        ELSE 'Enterprise'
    END AS host_segment
FROM aged_listings a
LEFT JOIN price_thresholds p ON a.room_type = p.room_type
LEFT JOIN host_listing_counts c ON a.host_id = c.host_id
