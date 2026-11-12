-- Inspect the analytics review fact in BigQuery.
SELECT column_name, data_type, is_nullable
FROM `orbital-scene-422012-h0.analytics.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'fct_reviews'
ORDER BY ordinal_position;

-- Sample rows.
SELECT *
FROM `orbital-scene-422012-h0.analytics.fct_reviews`
LIMIT 10;

-- Table inventory for the analytics dataset.
SELECT table_name, table_type
FROM `orbital-scene-422012-h0.analytics.INFORMATION_SCHEMA.TABLES`
ORDER BY table_name;

-- Row counts for the BI-facing tables.
SELECT 'dim_date' AS table_name, COUNT(*) AS row_count
FROM `orbital-scene-422012-h0.analytics.dim_date`
UNION ALL
SELECT 'dim_listings', COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_listings`
UNION ALL
SELECT 'dim_hosts', COUNT(*) FROM `orbital-scene-422012-h0.analytics.dim_hosts`
UNION ALL
SELECT 'fct_reviews', COUNT(*) FROM `orbital-scene-422012-h0.analytics.fct_reviews`
UNION ALL
SELECT 'mart_listing_performance', COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_listing_performance`
UNION ALL
SELECT 'mart_executive_kpis', COUNT(*) FROM `orbital-scene-422012-h0.analytics.mart_executive_kpis`
ORDER BY table_name;
