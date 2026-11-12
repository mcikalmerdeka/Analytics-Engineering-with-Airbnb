{{ config(materialized='table') }}

WITH listing_rollup AS (
    SELECT
        host_id,
        COUNT(*) AS listing_count,
        COUNTIF(is_active_last_12m) AS active_listing_count,
        SUM(review_count) AS total_reviews,
        AVG(IF(NOT is_price_outlier, price, NULL)) AS avg_price,
        MIN(first_review_date) AS first_review_date,
        MAX(last_review_date) AS last_review_date
    FROM {{ ref('mart_listing_performance') }}
    GROUP BY host_id
),
host_median AS (
    SELECT
        host_id,
        MAX(median_price) AS median_price
    FROM (
        SELECT
            host_id,
            PERCENTILE_CONT(IF(NOT is_price_outlier, price, NULL), 0.5)
                OVER (PARTITION BY host_id) AS median_price
        FROM {{ ref('mart_listing_performance') }}
    )
    GROUP BY host_id
),
host_review_sentiment AS (
    SELECT
        l.host_id,
        AVG(r.sentiment_score) AS avg_sentiment
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l
        ON r.listing_id = l.listing_id
    GROUP BY l.host_id
)
SELECT
    h.host_id,
    h.host_name,
    h.is_superhost,
    h.host_created_at,
    h.host_age_days,
    h.host_segment,
    COALESCE(r.listing_count, 0) AS listing_count,
    COALESCE(r.active_listing_count, 0) AS active_listing_count,
    SAFE_DIVIDE(
        COALESCE(r.active_listing_count, 0),
        COALESCE(r.listing_count, 0)
    ) AS pct_active_listings,
    COALESCE(r.total_reviews, 0) AS total_reviews,
    SAFE_DIVIDE(
        COALESCE(r.total_reviews, 0),
        COALESCE(r.listing_count, 0)
    ) AS avg_reviews_per_listing,
    r.avg_price,
    m.median_price,
    hrs.avg_sentiment,
    r.first_review_date,
    r.last_review_date
FROM {{ ref('dim_hosts') }} AS h
LEFT JOIN listing_rollup AS r ON h.host_id = r.host_id
LEFT JOIN host_median AS m ON h.host_id = m.host_id
LEFT JOIN host_review_sentiment AS hrs ON h.host_id = hrs.host_id
