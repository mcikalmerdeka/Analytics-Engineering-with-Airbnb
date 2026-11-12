{{ config(materialized='view') }}

WITH src_reviews AS (
    SELECT *
    FROM {{ ref('src_reviews') }}
),
deduped AS (
    SELECT
        listing_id,
        review_date,
        reviewer_name,
        review_text,
        review_sentiment,
        ROW_NUMBER() OVER (
            PARTITION BY listing_id, review_date, reviewer_name, review_text
            ORDER BY review_date
        ) AS duplicate_rank
    FROM src_reviews
)
SELECT
    {{ dbt_utils.generate_surrogate_key(['listing_id', 'review_date', 'reviewer_name', 'review_text']) }} AS review_id,
    listing_id,
    review_date,
    reviewer_name,
    review_text,
    COALESCE(review_sentiment, 'unknown') AS review_sentiment,
    CASE review_sentiment
        WHEN 'positive' THEN 1
        WHEN 'neutral' THEN 0
        WHEN 'negative' THEN -1
        ELSE NULL
    END AS sentiment_score,
    review_text IS NOT NULL AS has_comment,
    LENGTH(review_text) AS review_length,
    EXTRACT(YEAR FROM review_date) AS review_year,
    DATE_TRUNC(DATE(review_date), MONTH) AS review_month
FROM deduped
WHERE duplicate_rank = 1
