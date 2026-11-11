{{ config(materialized='table') }}

SELECT
    listing_id,
    listing_name,
    listing_url,
    room_type,
    price,
    price_band,
    is_price_outlier,
    minimum_nights,
    minimum_nights_band,
    host_id,
    host_name,
    is_superhost,
    is_superhost_known,
    host_listing_count,
    host_segment,
    listing_created_at,
    listing_age_days,
    listing_age_cohort,
    listing_updated_at
FROM {{ ref('int_listings_enriched') }}
