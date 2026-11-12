-- Preview the three BigQuery raw tables.
SELECT * FROM `orbital-scene-422012-h0.raw.raw_listings` LIMIT 10;
SELECT * FROM `orbital-scene-422012-h0.raw.raw_hosts` LIMIT 10;
SELECT * FROM `orbital-scene-422012-h0.raw.raw_reviews` LIMIT 10;

-- Exact row counts.
SELECT 'raw_listings' AS table_name, COUNT(*) AS row_count
FROM `orbital-scene-422012-h0.raw.raw_listings`
UNION ALL
SELECT 'raw_hosts', COUNT(*) FROM `orbital-scene-422012-h0.raw.raw_hosts`
UNION ALL
SELECT 'raw_reviews', COUNT(*) FROM `orbital-scene-422012-h0.raw.raw_reviews`;
