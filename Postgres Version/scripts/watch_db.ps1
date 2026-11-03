param(
    [int]$Seconds = 5
)

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot

$query = @"
SELECT
    now() AS observed_at,
    object_name,
    row_count,
    kind
FROM (
    SELECT 'raw.raw_listings' AS object_name, count(*)::bigint AS row_count, 'table' AS kind
    FROM raw.raw_listings
    UNION ALL
    SELECT 'raw.raw_hosts', count(*)::bigint, 'table'
    FROM raw.raw_hosts
    UNION ALL
    SELECT 'raw.raw_reviews', count(*)::bigint, 'table'
    FROM raw.raw_reviews
    UNION ALL
    SELECT 'staging.' || relname, n_live_tup, 'table'
    FROM pg_stat_user_tables
    WHERE schemaname = 'staging'
    UNION ALL
    SELECT 'staging.' || c.relname, NULL::bigint, 'view'
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'staging' AND c.relkind = 'v'
) AS objects
ORDER BY kind, object_name
\watch $Seconds
"@

$query | docker compose exec -T postgres psql -U postgres -d airbnb
