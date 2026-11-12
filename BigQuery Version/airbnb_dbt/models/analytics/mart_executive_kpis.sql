{{ config(materialized='table') }}

WITH month_spine AS (
    SELECT DISTINCT
        year_month AS month_start,
        LAST_DAY(year_month) AS month_end
    FROM {{ ref('dim_date') }}
    WHERE date_day < DATE '2021-12-01'
),
listing_monthly AS (
    SELECT
        m.month_start,
        COUNT(l.listing_id) AS cumulative_listings,
        COUNTIF(
            DATE(l.listing_created_at) >= m.month_start
            AND DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
        ) AS new_listings,
        COUNTIF(l.is_superhost) AS superhost_listings,
        COUNTIF(p.first_review_date <= m.month_end) AS reviewed_listings,
        AVG(IF(NOT l.is_price_outlier, l.price, NULL)) AS avg_price
    FROM month_spine AS m
    LEFT JOIN {{ ref('dim_listings') }} AS l
        ON DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    LEFT JOIN {{ ref('mart_listing_performance') }} AS p
        ON l.listing_id = p.listing_id
    GROUP BY m.month_start
),
listing_median AS (
    SELECT
        month_start,
        MAX(median_price) AS median_price
    FROM (
        SELECT
            m.month_start,
            PERCENTILE_CONT(IF(NOT l.is_price_outlier, l.price, NULL), 0.5)
                OVER (PARTITION BY m.month_start) AS median_price
        FROM month_spine AS m
        LEFT JOIN {{ ref('dim_listings') }} AS l
            ON DATE(l.listing_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    )
    GROUP BY month_start
),
host_monthly AS (
    SELECT
        m.month_start,
        COUNT(h.host_id) AS cumulative_hosts,
        COUNTIF(
            DATE(h.host_created_at) >= m.month_start
            AND DATE(h.host_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
        ) AS new_hosts
    FROM month_spine AS m
    LEFT JOIN {{ ref('dim_hosts') }} AS h
        ON DATE(h.host_created_at) < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    GROUP BY m.month_start
),
review_monthly AS (
    SELECT
        review_month AS month_start,
        COUNT(*) AS reviews,
        COUNT(DISTINCT listing_id) AS reviewing_listings,
        AVG(sentiment_score) AS avg_sentiment,
        COUNTIF(review_sentiment = 'positive') AS positive_reviews,
        COUNTIF(review_sentiment = 'negative') AS negative_reviews
    FROM {{ ref('fct_reviews') }}
    GROUP BY review_month
),
active_12m AS (
    SELECT
        m.month_start,
        COUNT(DISTINCT r.listing_id) AS active_listings
    FROM month_spine AS m
    INNER JOIN {{ ref('fct_reviews') }} AS r
        ON r.review_date > DATE_SUB(m.month_end, INTERVAL 12 MONTH)
       AND r.review_date <= m.month_end
    GROUP BY m.month_start
)
SELECT
    m.month_start,
    COALESCE(lm.cumulative_listings, 0) AS cumulative_listings,
    COALESCE(hm.cumulative_hosts, 0) AS cumulative_hosts,
    COALESCE(lm.new_listings, 0) AS new_listings,
    COALESCE(hm.new_hosts, 0) AS new_hosts,
    COALESCE(rm.reviews, 0) AS reviews,
    COALESCE(rm.reviewing_listings, 0) AS reviewing_listings,
    SAFE_DIVIDE(
        COALESCE(lm.reviewed_listings, 0),
        lm.cumulative_listings
    ) AS pct_listings_reviewed,
    SAFE_DIVIDE(
        COALESCE(am.active_listings, 0),
        lm.cumulative_listings
    ) AS pct_active_12m,
    lm.avg_price,
    md.median_price,
    SAFE_DIVIDE(
        COALESCE(lm.superhost_listings, 0),
        lm.cumulative_listings
    ) AS superhost_share,
    rm.avg_sentiment,
    SAFE_DIVIDE(rm.positive_reviews, rm.reviews) AS pct_positive,
    SAFE_DIVIDE(rm.negative_reviews, rm.reviews) AS pct_negative,
    (m.month_start = DATE '2021-10-01') AS is_latest_review_month
FROM month_spine AS m
LEFT JOIN listing_monthly AS lm ON m.month_start = lm.month_start
LEFT JOIN listing_median AS md ON m.month_start = md.month_start
LEFT JOIN host_monthly AS hm ON m.month_start = hm.month_start
LEFT JOIN review_monthly AS rm ON m.month_start = rm.month_start
LEFT JOIN active_12m AS am ON m.month_start = am.month_start
