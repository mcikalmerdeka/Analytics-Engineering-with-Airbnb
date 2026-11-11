{{ config(materialized='table') }}

WITH listing_rollup AS (
    SELECT
        host_id,
        COUNT(*) AS listing_count,
        COUNT(*) FILTER (WHERE is_active_last_12m) AS active_listing_count,
        SUM(review_count) AS total_reviews,
        AVG(CASE WHEN NOT is_price_outlier THEN price END) AS avg_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY CASE WHEN NOT is_price_outlier THEN price END
        )::numeric AS median_price,
        MIN(first_review_date) AS first_review_date,
        MAX(last_review_date) AS last_review_date
    FROM {{ ref('mart_listing_performance') }}
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
    COALESCE(r.active_listing_count, 0)::numeric
        / NULLIF(COALESCE(r.listing_count, 0), 0) AS pct_active_listings,
    COALESCE(r.total_reviews, 0) AS total_reviews,
    COALESCE(r.total_reviews, 0)::numeric
        / NULLIF(COALESCE(r.listing_count, 0), 0) AS avg_reviews_per_listing,
    r.avg_price,
    r.median_price,
    hrs.avg_sentiment,
    r.first_review_date,
    r.last_review_date
FROM {{ ref('dim_hosts') }} AS h
LEFT JOIN listing_rollup AS r ON h.host_id = r.host_id
LEFT JOIN host_review_sentiment AS hrs ON h.host_id = hrs.host_id
