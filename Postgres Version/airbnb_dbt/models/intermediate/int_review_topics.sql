{{ config(materialized='view') }}

SELECT
    r.review_id,
    r.review_month,
    t.topic,
    r.review_sentiment,
    r.sentiment_score
FROM {{ ref('fct_reviews') }} AS r
INNER JOIN {{ ref('seed_review_topics') }} AS t
    ON r.review_text ~* t.keywords_regex
WHERE r.has_comment = TRUE
