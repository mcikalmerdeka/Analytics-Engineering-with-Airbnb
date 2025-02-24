WITH raw_listings AS (
    SELECT *
    FROM {{ source('airbnb_source', 'listings') }}
    -- FROM airbnb.staging.raw_listings  -- Direct database reference
)

SELECT
    id AS listing_id,
    name AS listing_name,
    listing_url,
    room_type,
    minimum_nights,
    host_id,
    price AS price_str,
    created_at,
    updated_at

FROM raw_listings