{{ config(materialized='table') }}

WITH months_with_comments AS (
    SELECT DISTINCT review_month AS month_start
    FROM {{ ref('fct_reviews') }}
    WHERE has_comment = TRUE
),
topics AS (
    SELECT DISTINCT topic
    FROM {{ ref('seed_review_topics') }}
),
grid AS (
    SELECT
        m.month_start,
        t.topic
    FROM months_with_comments AS m
    CROSS JOIN topics AS t
),
comment_counts AS (
    SELECT
        review_month AS month_start,
        COUNT(DISTINCT review_id) AS reviews_with_comments
    FROM {{ ref('fct_reviews') }}
    WHERE has_comment = TRUE
    GROUP BY review_month
),
topic_rollup AS (
    SELECT
        review_month AS month_start,
        topic,
        COUNT(DISTINCT review_id) AS mentions,
        AVG(sentiment_score) AS avg_sentiment,
        COUNT(*) FILTER (WHERE review_sentiment = 'negative') AS negative_mentions
    FROM {{ ref('int_review_topics') }}
    GROUP BY review_month, topic
)
SELECT
    g.month_start,
    g.topic,
    COALESCE(r.mentions, 0) AS mentions,
    COALESCE(r.mentions, 0)::numeric
        / NULLIF(c.reviews_with_comments, 0) AS mention_rate,
    r.avg_sentiment,
    COALESCE(r.negative_mentions, 0)::numeric
        / NULLIF(r.mentions, 0) AS pct_negative
FROM grid AS g
LEFT JOIN topic_rollup AS r
    ON g.month_start = r.month_start
   AND g.topic = r.topic
LEFT JOIN comment_counts AS c ON g.month_start = c.month_start
