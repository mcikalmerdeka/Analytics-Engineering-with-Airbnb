{{ config(materialized='table') }}

WITH month_spine AS (
    SELECT DISTINCT
        year_month AS month_start,
        (year_month + INTERVAL '1 month - 1 day')::date AS month_end
    FROM {{ ref('dim_date') }}
    WHERE date_day < DATE '2021-12-01'
),
listing_monthly AS (
    SELECT
        m.month_start,
        COUNT(l.listing_id) AS cumulative_listings,
        COUNT(*) FILTER (
            WHERE l.listing_created_at >= m.month_start
              AND l.listing_created_at < m.month_start + INTERVAL '1 month'
        ) AS new_listings,
        COUNT(*) FILTER (WHERE l.is_superhost) AS superhost_listings,
        COUNT(*) FILTER (WHERE p.first_review_date <= m.month_end) AS reviewed_listings,
        AVG(CASE WHEN NOT l.is_price_outlier THEN l.price END) AS avg_price,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY CASE WHEN NOT l.is_price_outlier THEN l.price END
        )::numeric AS median_price
    FROM month_spine AS m
    LEFT JOIN {{ ref('dim_listings') }} AS l
        ON l.listing_created_at < m.month_start + INTERVAL '1 month'
    LEFT JOIN {{ ref('mart_listing_performance') }} AS p
        ON l.listing_id = p.listing_id
    GROUP BY m.month_start
),
host_monthly AS (
    SELECT
        m.month_start,
        COUNT(h.host_id) AS cumulative_hosts,
        COUNT(*) FILTER (
            WHERE h.host_created_at >= m.month_start
              AND h.host_created_at < m.month_start + INTERVAL '1 month'
        ) AS new_hosts
    FROM month_spine AS m
    LEFT JOIN {{ ref('dim_hosts') }} AS h
        ON h.host_created_at < m.month_start + INTERVAL '1 month'
    GROUP BY m.month_start
),
review_monthly AS (
    SELECT
        review_month AS month_start,
        COUNT(*) AS reviews,
        COUNT(DISTINCT listing_id) AS reviewing_listings,
        AVG(sentiment_score) AS avg_sentiment,
        COUNT(*) FILTER (WHERE review_sentiment = 'positive') AS positive_reviews,
        COUNT(*) FILTER (WHERE review_sentiment = 'negative') AS negative_reviews
    FROM {{ ref('fct_reviews') }}
    GROUP BY review_month
),
active_12m AS (
    SELECT
        m.month_start,
        COUNT(DISTINCT r.listing_id) AS active_listings
    FROM month_spine AS m
    INNER JOIN {{ ref('fct_reviews') }} AS r
        ON r.review_date::date > (m.month_end - INTERVAL '12 months')::date
       AND r.review_date::date <= m.month_end
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
    COALESCE(lm.reviewed_listings, 0)::numeric
        / NULLIF(lm.cumulative_listings, 0) AS pct_listings_reviewed,
    COALESCE(am.active_listings, 0)::numeric
        / NULLIF(lm.cumulative_listings, 0) AS pct_active_12m,
    lm.avg_price,
    lm.median_price,
    COALESCE(lm.superhost_listings, 0)::numeric
        / NULLIF(lm.cumulative_listings, 0) AS superhost_share,
    rm.avg_sentiment,
    rm.positive_reviews::numeric / NULLIF(rm.reviews, 0) AS pct_positive,
    rm.negative_reviews::numeric / NULLIF(rm.reviews, 0) AS pct_negative,
    (m.month_start = DATE '2021-10-01') AS is_latest_review_month
FROM month_spine AS m
LEFT JOIN listing_monthly AS lm ON m.month_start = lm.month_start
LEFT JOIN host_monthly AS hm ON m.month_start = hm.month_start
LEFT JOIN review_monthly AS rm ON m.month_start = rm.month_start
LEFT JOIN active_12m AS am ON m.month_start = am.month_start
