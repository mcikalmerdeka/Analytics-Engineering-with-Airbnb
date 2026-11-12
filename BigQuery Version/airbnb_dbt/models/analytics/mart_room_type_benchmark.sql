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
        SAFE_DIVIDE(COUNT(*), 17499) AS share_of_supply,
        AVG(IF(NOT is_price_outlier, price, NULL)) AS avg_price,
        AVG(review_count) AS avg_reviews,
        SAFE_DIVIDE(COUNTIF(is_superhost), COUNT(*)) AS pct_superhost,
        SAFE_DIVIDE(COUNTIF(is_active_last_12m), COUNT(*)) AS pct_active
    FROM {{ ref('mart_listing_performance') }}
    GROUP BY room_type
),
price_median AS (
    SELECT
        room_type,
        MAX(median_price) AS median_price,
        MAX(p90_price) AS p90_price
    FROM (
        SELECT
            room_type,
            PERCENTILE_CONT(IF(NOT is_price_outlier, price, NULL), 0.5)
                OVER (PARTITION BY room_type) AS median_price,
            PERCENTILE_CONT(IF(NOT is_price_outlier, price, NULL), 0.9)
                OVER (PARTITION BY room_type) AS p90_price
        FROM {{ ref('mart_listing_performance') }}
    )
    GROUP BY room_type
),
review_median AS (
    SELECT
        room_type,
        MAX(median_reviews) AS median_reviews
    FROM (
        SELECT
            room_type,
            PERCENTILE_CONT(review_count, 0.5)
                OVER (PARTITION BY room_type) AS median_reviews
        FROM {{ ref('mart_listing_performance') }}
    )
    GROUP BY room_type
)
SELECT
    b.room_type,
    b.listing_count,
    b.share_of_supply,
    b.avg_price,
    pm.median_price,
    pm.p90_price,
    b.avg_reviews,
    rm.median_reviews,
    rs.avg_sentiment,
    b.pct_superhost,
    b.pct_active
FROM benchmark AS b
LEFT JOIN price_median AS pm ON b.room_type = pm.room_type
LEFT JOIN review_median AS rm ON b.room_type = rm.room_type
LEFT JOIN review_sentiment AS rs ON b.room_type = rs.room_type
