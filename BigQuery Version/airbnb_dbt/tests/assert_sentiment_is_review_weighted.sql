WITH price_band_expected AS (
    SELECT
        l.price_band,
        l.room_type,
        AVG(r.sentiment_score) AS expected_avg_sentiment
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l
        ON r.listing_id = l.listing_id
    GROUP BY l.price_band, l.room_type
),
price_band_actual AS (
    SELECT
        price_band,
        room_type,
        avg_sentiment AS actual_avg_sentiment
    FROM {{ ref('mart_price_bands') }}
),
room_type_expected AS (
    SELECT
        l.room_type,
        AVG(r.sentiment_score) AS expected_avg_sentiment
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l
        ON r.listing_id = l.listing_id
    GROUP BY l.room_type
),
room_type_actual AS (
    SELECT
        room_type,
        avg_sentiment AS actual_avg_sentiment
    FROM {{ ref('mart_room_type_benchmark') }}
),
host_expected AS (
    SELECT
        l.host_id,
        AVG(r.sentiment_score) AS expected_avg_sentiment
    FROM {{ ref('fct_reviews') }} AS r
    INNER JOIN {{ ref('dim_listings') }} AS l
        ON r.listing_id = l.listing_id
    GROUP BY l.host_id
),
host_actual AS (
    SELECT
        host_id,
        avg_sentiment AS actual_avg_sentiment
    FROM {{ ref('mart_host_performance') }}
)
SELECT
    'price_band' AS check_name,
    a.price_band AS dimension_1,
    a.room_type AS dimension_2,
    a.actual_avg_sentiment,
    e.expected_avg_sentiment
FROM price_band_actual AS a
INNER JOIN price_band_expected AS e
    ON a.price_band = e.price_band
   AND a.room_type = e.room_type
WHERE ROUND(a.actual_avg_sentiment, 9)
    IS DISTINCT FROM ROUND(e.expected_avg_sentiment, 9)

UNION ALL

SELECT
    'room_type' AS check_name,
    a.room_type AS dimension_1,
    CAST(NULL AS STRING) AS dimension_2,
    a.actual_avg_sentiment,
    e.expected_avg_sentiment
FROM room_type_actual AS a
INNER JOIN room_type_expected AS e ON a.room_type = e.room_type
WHERE ROUND(a.actual_avg_sentiment, 9)
    IS DISTINCT FROM ROUND(e.expected_avg_sentiment, 9)

UNION ALL

SELECT
    'host' AS check_name,
    CAST(a.host_id AS STRING) AS dimension_1,
    CAST(NULL AS STRING) AS dimension_2,
    a.actual_avg_sentiment,
    e.expected_avg_sentiment
FROM host_actual AS a
INNER JOIN host_expected AS e ON a.host_id = e.host_id
WHERE ROUND(a.actual_avg_sentiment, 9)
    IS DISTINCT FROM ROUND(e.expected_avg_sentiment, 9)
