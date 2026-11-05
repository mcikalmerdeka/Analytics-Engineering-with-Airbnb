{{ config(materialized='table') }}

WITH review_sentiment AS (
    SELECT
        l.room_type,
        AVG(r.sentiment_score) AS avg_sentiment
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l
        ON r.listing_id = l.listing_id
    GROUP BY l.room_type
),
benchmark AS (
    SELECT
        room_type,
        COUNT(*) AS listing_count,
        COUNT(*)::numeric / 17499 AS share_of_supply,
        AVG(CASE WHEN NOT is_price_outlier THEN price END) AS avg_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY CASE WHEN NOT is_price_outlier THEN price END
        )::numeric AS median_price,
        PERCENTILE_CONT(0.9) WITHIN GROUP (
            ORDER BY CASE WHEN NOT is_price_outlier THEN price END
        )::numeric AS p90_price,
        AVG(review_count) AS avg_reviews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY review_count
        )::numeric AS median_reviews,
        COUNT(*) FILTER (WHERE is_superhost)::numeric / COUNT(*) AS pct_superhost,
        COUNT(*) FILTER (WHERE is_active_last_12m)::numeric / COUNT(*) AS pct_active
    FROM {{ ref('mart_listing_performance') }}
    GROUP BY room_type
)
SELECT
    b.room_type,
    b.listing_count,
    b.share_of_supply,
    b.avg_price,
    b.median_price,
    b.p90_price,
    b.avg_reviews,
    b.median_reviews,
    rs.avg_sentiment,
    b.pct_superhost,
    b.pct_active
FROM benchmark AS b
LEFT JOIN review_sentiment AS rs ON b.room_type = rs.room_type
