SELECT
    *
FROM
    {{ ref('dim_listings') }} l
INNER JOIN
    {{ ref('fct_reviews') }} r
    ON l.listing_id = r.listing_id
WHERE DATE(l.listing_created_at) >= r.review_date