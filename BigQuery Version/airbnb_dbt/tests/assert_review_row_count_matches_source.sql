WITH source_reviews AS (
    SELECT DISTINCT
        listing_id,
        date AS review_date,
        reviewer_name,
        comments AS review_text
    FROM {{ source('airbnb_source', 'reviews') }}
),
expected AS (
    SELECT COUNT(*) AS expected_count
    FROM source_reviews
),
actual AS (
    SELECT COUNT(*) AS actual_count
    FROM {{ ref('fct_reviews') }}
)
SELECT
    actual.actual_count,
    expected.expected_count
FROM actual
CROSS JOIN expected
WHERE actual.actual_count <> expected.expected_count
