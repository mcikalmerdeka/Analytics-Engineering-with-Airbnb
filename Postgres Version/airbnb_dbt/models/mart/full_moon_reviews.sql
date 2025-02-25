{{ config(
    materialized='table',
    on_schema_change='fail',
) }}

WITH fct_reviews AS (
    SELECT * FROM {{ ref('fct_reviews') }}
),
full_moon_dates AS (
    SELECT * FROM {{ ref('seed_full_moon_dates') }}
)

SELECT
    r.*,
    CASE
        WHEN fm.full_moon_date IS NULL THEN 'not_full_moon'
        ELSE 'full_moon'
    END AS is_full_moon
FROM fct_reviews AS r
LEFT JOIN full_moon_dates AS fm
    ON CAST(r.review_date AS DATE) = fm.full_moon_date + INTERVAL '1 day'