{{ config(materialized='table') }}

WITH price_band_values AS (
    SELECT '<30' AS price_band
    UNION ALL SELECT '30-49'
    UNION ALL SELECT '50-74'
    UNION ALL SELECT '75-99'
    UNION ALL SELECT '100-149'
    UNION ALL SELECT '150-249'
    UNION ALL SELECT '250+'
),
room_types AS (
    SELECT DISTINCT room_type
    FROM {{ ref('mart_listing_performance') }}
),
band_spine AS (
    SELECT
        b.price_band,
        r.room_type
    FROM price_band_values AS b
    CROSS JOIN room_types AS r
),
band_rollup AS (
    SELECT
        price_band,
        room_type,
        COUNT(*) AS listing_count,
        AVG(review_count) AS avg_reviews,
        SAFE_DIVIDE(COUNTIF(is_superhost), COUNT(*)) AS pct_superhost,
        SAFE_DIVIDE(COUNTIF(is_active_last_12m), COUNT(*)) AS pct_active
    FROM {{ ref('mart_listing_performance') }}
    GROUP BY price_band, room_type
),
band_median AS (
    SELECT
        price_band,
        room_type,
        MAX(median_reviews) AS median_reviews
    FROM (
        SELECT
            price_band,
            room_type,
            PERCENTILE_CONT(review_count, 0.5)
                OVER (PARTITION BY price_band, room_type) AS median_reviews
        FROM {{ ref('mart_listing_performance') }}
    )
    GROUP BY price_band, room_type
),
review_sentiment AS (
    SELECT
        l.price_band,
        l.room_type,
        AVG(r.sentiment_score) AS avg_sentiment
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l
        ON r.listing_id = l.listing_id
    GROUP BY l.price_band, l.room_type
)
SELECT
    s.price_band,
    s.room_type,
    COALESCE(r.listing_count, 0) AS listing_count,
    SAFE_DIVIDE(
        COALESCE(r.listing_count, 0),
        SUM(COALESCE(r.listing_count, 0)) OVER (PARTITION BY s.room_type)
    ) AS share_of_room_type,
    r.avg_reviews,
    bm.median_reviews,
    rs.avg_sentiment,
    COALESCE(r.pct_superhost, 0) AS pct_superhost,
    COALESCE(r.pct_active, 0) AS pct_active
FROM band_spine AS s
LEFT JOIN band_rollup AS r
    ON s.price_band = r.price_band
   AND s.room_type = r.room_type
LEFT JOIN band_median AS bm
    ON s.price_band = bm.price_band
   AND s.room_type = bm.room_type
LEFT JOIN review_sentiment AS rs
    ON s.price_band = rs.price_band
   AND s.room_type = rs.room_type
