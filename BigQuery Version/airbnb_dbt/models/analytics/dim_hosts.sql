{{ config(materialized='table') }}

WITH src_hosts AS (
    SELECT *
    FROM {{ ref('src_hosts') }}
),
typed_hosts AS (
    SELECT
        *,
        CASE is_superhost
            WHEN 't' THEN TRUE
            WHEN 'f' THEN FALSE
            ELSE NULL
        END AS is_superhost_bool
    FROM src_hosts
),
host_attributes AS (
    SELECT
        host_id,
        MAX(host_listing_count) AS host_listing_count,
        MAX(host_segment) AS host_segment
    FROM {{ ref('int_listings_enriched') }}
    GROUP BY host_id
)
SELECT
    h.host_id,
    COALESCE(h.host_name, 'Anonymous') AS host_name,
    h.is_superhost_bool AS is_superhost,
    h.is_superhost_bool IS NOT NULL AS is_superhost_known,
    h.created_at AS host_created_at,
    DATE_DIFF(DATE '2021-11-19', DATE(h.created_at), DAY) AS host_age_days,
    COALESCE(a.host_listing_count, 0) AS host_listing_count,
    a.host_segment
FROM typed_hosts h
LEFT JOIN host_attributes a ON h.host_id = a.host_id
