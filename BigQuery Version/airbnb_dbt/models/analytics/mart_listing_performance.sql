{{ config(materialized='table') }}

WITH review_aggregates AS (
    SELECT
        listing_id,
        COUNT(*) AS review_count,
        COUNTIF(
            review_date > DATE_SUB(DATE '2021-11-19', INTERVAL 12 MONTH)
        ) AS review_count_12m,
        MIN(review_date) AS first_review_date,
        MAX(review_date) AS last_review_date,
        AVG(sentiment_score) AS avg_sentiment,
        COUNTIF(review_sentiment = 'positive') AS positive_reviews,
        COUNTIF(review_sentiment = 'neutral') AS neutral_reviews,
        COUNTIF(review_sentiment = 'negative') AS negative_reviews,
        AVG(IF(has_comment, review_length, NULL)) AS avg_review_length
    FROM {{ ref('fct_reviews') }}
    GROUP BY listing_id
)
SELECT
    l.listing_id,
    l.listing_name,
    l.room_type,
    l.price,
    l.price_band,
    l.is_price_outlier,
    l.minimum_nights,
    l.minimum_nights_band,
    l.host_id,
    l.host_name,
    l.is_superhost,
    l.host_segment,
    l.listing_age_days,
    COALESCE(r.review_count, 0) > 0 AS has_reviews,
    COALESCE(
        r.last_review_date > DATE_SUB(DATE '2021-11-19', INTERVAL 12 MONTH),
        FALSE
    ) AS is_active_last_12m,
    COALESCE(r.review_count, 0) AS review_count,
    COALESCE(r.review_count_12m, 0) AS review_count_12m,
    r.first_review_date,
    r.last_review_date,
    CASE
        WHEN r.last_review_date IS NOT NULL
            THEN DATE_DIFF(DATE '2021-11-19', r.last_review_date, DAY)
    END AS days_since_last_review,
    COALESCE(r.review_count, 0) / GREATEST(l.listing_age_days / 365.25, 1) AS reviews_per_year,
    r.avg_sentiment,
    SAFE_DIVIDE(r.positive_reviews, r.review_count) AS pct_positive,
    SAFE_DIVIDE(r.neutral_reviews, r.review_count) AS pct_neutral,
    SAFE_DIVIDE(r.negative_reviews, r.review_count) AS pct_negative,
    r.avg_review_length
FROM {{ ref('dim_listings') }} AS l
LEFT JOIN review_aggregates AS r ON l.listing_id = r.listing_id
