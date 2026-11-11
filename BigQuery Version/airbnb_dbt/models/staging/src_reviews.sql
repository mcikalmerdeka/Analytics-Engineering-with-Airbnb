WITH raw_reviews AS (
    SELECT *
    FROM {{ source('airbnb_source', 'reviews') }}
    -- FROM airbnb.staging.raw_reviews  -- Direct database reference
)
SELECT
    listing_id,
    date AS review_date,
    reviewer_name,
    comments AS review_text,
    sentiment AS review_sentiment
    
FROM raw_reviews