{{ config(materialized='table') }}

WITH month_spine AS (
    SELECT DISTINCT year_month AS month_start
    FROM {{ ref('dim_date') }}
    WHERE date_day < DATE '2021-12-01'
),
room_types AS (
    SELECT DISTINCT room_type
    FROM {{ ref('dim_listings') }}
),
listing_monthly AS (
    SELECT
        m.month_start,
        rt.room_type,
        COUNTIF(
            DATE(l.listing_created_at) >= m.month_start
            AND DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
        ) AS new_listings,
        COUNT(l.listing_id) AS cumulative_listings,
        AVG(IF(NOT l.is_price_outlier, l.price, NULL)) AS avg_price
    FROM month_spine AS m
    CROSS JOIN room_types AS rt
    LEFT JOIN {{ ref('dim_listings') }} AS l
        ON l.room_type = rt.room_type
       AND DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    GROUP BY m.month_start, rt.room_type
),
listing_median AS (
    SELECT
        month_start,
        room_type,
        MAX(median_price) AS median_price
    FROM (
        SELECT
            m.month_start,
            rt.room_type,
            PERCENTILE_CONT(IF(NOT l.is_price_outlier, l.price, NULL), 0.5)
                OVER (PARTITION BY m.month_start, rt.room_type) AS median_price
        FROM month_spine AS m
        CROSS JOIN room_types AS rt
        LEFT JOIN {{ ref('dim_listings') }} AS l
            ON l.room_type = rt.room_type
           AND DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    )
    GROUP BY month_start, room_type
),
review_rollup AS (
    SELECT
        r.review_month AS month_start,
        l.room_type,
        COUNT(*) AS reviews,
        COUNT(DISTINCT r.listing_id) AS reviewing_listings,
        AVG(r.sentiment_score) AS avg_sentiment,
        COUNTIF(r.review_sentiment = 'positive') AS positive_reviews,
        COUNTIF(r.review_sentiment = 'negative') AS negative_reviews
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l ON r.listing_id = l.listing_id
    GROUP BY r.review_month, l.room_type
)
SELECT
    m.month_start,
    rt.room_type,
    COALESCE(lm.new_listings, 0) AS new_listings,
    COALESCE(lm.cumulative_listings, 0) AS cumulative_listings,
    COALESCE(rr.reviewing_listings, 0) AS reviewing_listings,
    COALESCE(rr.reviews, 0) AS reviews,
    SAFE_DIVIDE(
        COALESCE(rr.reviewing_listings, 0),
        lm.cumulative_listings
    ) AS review_coverage,
    rr.avg_sentiment,
    SAFE_DIVIDE(rr.positive_reviews, rr.reviews) AS pct_positive,
    SAFE_DIVIDE(rr.negative_reviews, rr.reviews) AS pct_negative,
    lm.avg_price,
    md.median_price
FROM month_spine AS m
CROSS JOIN room_types AS rt
LEFT JOIN listing_monthly AS lm
    ON m.month_start = lm.month_start
   AND rt.room_type = lm.room_type
LEFT JOIN listing_median AS md
    ON m.month_start = md.month_start
   AND rt.room_type = md.room_type
LEFT JOIN review_rollup AS rr
    ON m.month_start = rr.month_start
   AND rt.room_type = rr.room_type
