SELECT
    *
FROM
    {{ ref('dim_listings') }}
WHERE minimum_nights < 1
LIMIT 10
