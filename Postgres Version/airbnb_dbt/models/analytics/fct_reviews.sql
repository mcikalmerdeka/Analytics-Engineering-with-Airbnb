{{ config(
    materialized='incremental',
    unique_key='review_id',
    incremental_strategy='delete+insert',
    on_schema_change='append_new_columns'
) }}

SELECT
    review_id,
    listing_id,
    review_date,
    reviewer_name,
    review_text,
    review_sentiment,
    sentiment_score,
    has_comment,
    review_length,
    review_year,
    review_month
FROM {{ ref('int_reviews_deduped') }}

{% if is_incremental() %}
WHERE review_date >= (
    SELECT COALESCE(MAX(review_date), DATE '1900-01-01') - INTERVAL '3 days'
    FROM {{ this }}
)
{% endif %}
