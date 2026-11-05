{{ config(materialized='table') }}

WITH review_full_moon AS (
    SELECT
        r.review_id,
        r.review_sentiment,
        CASE
            WHEN fm.full_moon_date IS NOT NULL THEN 'full_moon'
            ELSE 'not_full_moon'
        END AS is_full_moon
    FROM {{ ref('fct_reviews') }} AS r
    LEFT JOIN {{ ref('seed_full_moon_dates') }} AS fm
        ON r.review_date = fm.full_moon_date + INTERVAL '1 day'
)
SELECT
    is_full_moon,
    review_sentiment,
    COUNT(*) AS reviews,
    COUNT(*)::numeric
        / SUM(COUNT(*)) OVER (PARTITION BY is_full_moon) AS share_of_group
FROM review_full_moon
GROUP BY is_full_moon, review_sentiment
