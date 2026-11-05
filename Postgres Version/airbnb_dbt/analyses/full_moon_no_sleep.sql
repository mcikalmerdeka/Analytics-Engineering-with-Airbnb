SELECT
    is_full_moon,
    review_sentiment,
    reviews
FROM {{ ref('mart_full_moon_reviews') }}
ORDER BY
    is_full_moon,
    review_sentiment
