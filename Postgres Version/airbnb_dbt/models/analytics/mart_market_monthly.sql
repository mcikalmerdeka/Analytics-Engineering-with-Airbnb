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
        COUNT(*) FILTER (
            WHERE l.listing_created_at >= m.month_start
              AND l.listing_created_at < m.month_start + INTERVAL '1 month'
        ) AS new_listings,
        COUNT(l.listing_id) AS cumulative_listings,
        AVG(CASE WHEN NOT l.is_price_outlier THEN l.price END) AS avg_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY CASE WHEN NOT l.is_price_outlier THEN l.price END
        )::numeric AS median_price
    FROM month_spine AS m
    CROSS JOIN room_types AS rt
    LEFT JOIN {{ ref('dim_listings') }} AS l
        ON l.room_type = rt.room_type
       AND l.listing_created_at < m.month_start + INTERVAL '1 month'
    GROUP BY m.month_start, rt.room_type
),
review_rollup AS (
    SELECT
        r.review_month AS month_start,
        l.room_type,
        COUNT(*) AS reviews,
        COUNT(DISTINCT r.listing_id) AS reviewing_listings,
        AVG(r.sentiment_score) AS avg_sentiment,
        COUNT(*) FILTER (WHERE r.review_sentiment = 'positive') AS positive_reviews,
        COUNT(*) FILTER (WHERE r.review_sentiment = 'negative') AS negative_reviews
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
    COALESCE(rr.reviewing_listings, 0)::numeric
        / NULLIF(lm.cumulative_listings, 0) AS review_coverage,
    rr.avg_sentiment,
    rr.positive_reviews::numeric / NULLIF(rr.reviews, 0) AS pct_positive,
    rr.negative_reviews::numeric / NULLIF(rr.reviews, 0) AS pct_negative,
    lm.avg_price,
    lm.median_price
FROM month_spine AS m
CROSS JOIN room_types AS rt
LEFT JOIN listing_monthly AS lm
    ON m.month_start = lm.month_start
   AND rt.room_type = lm.room_type
LEFT JOIN review_rollup AS rr
    ON m.month_start = rr.month_start
   AND rt.room_type = rr.room_type
