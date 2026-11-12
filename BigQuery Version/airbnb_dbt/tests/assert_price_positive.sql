SELECT *
FROM {{ ref('dim_listings') }}
WHERE price < 0
