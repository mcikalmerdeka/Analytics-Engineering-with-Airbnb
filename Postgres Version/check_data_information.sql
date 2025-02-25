-- Check columns data type
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'fct_reviews';

select *
from airbnb.staging.full_moon_reviews;

-- ======================================================================================================================================

-- Create index in the listing_id column
CREATE INDEX
ON airbnb.staging.fct_reviews (listing_id); 

-- ======================================================================================================================================

-- Check currently running query
SELECT pid, state, query
FROM pg_stat_activity
WHERE state = 'active' AND query NOT LIKE '%pg_stat_activity%';

-- ======================================================================================================================================

-- Table data profiling query (version 1)
WITH column_info AS (
    SELECT 
        column_name AS "Feature",
        data_type AS "Data Type"
    FROM information_schema.columns
    WHERE table_name = 'fct_reviews'
    AND table_schema = 'staging'
),
-- We need dynamic SQL to count nulls for each column
-- This is a placeholder - the actual implementation would require dynamic SQL
null_counts AS (
    SELECT 
        'listing_id' AS "Feature",
        SUM(CASE WHEN listing_id IS NULL THEN 1 ELSE 0 END) AS "Null Values",
        ROUND(100.0 * SUM(CASE WHEN listing_id IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS "Null Percentage"
    FROM airbnb.staging.fct_reviews
    UNION ALL
    SELECT 
        'listing_id' AS "Feature",
        SUM(CASE WHEN listing_id IS NULL THEN 1 ELSE 0 END) AS "Null Values",
        ROUND(100.0 * SUM(CASE WHEN listing_id IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS "Null Percentage"
    FROM airbnb.staging.fct_reviews
    -- Repeat for each column in your table
),
-- For duplicates, we need to define what constitutes a duplicate (which columns)
duplicates AS (
    SELECT COUNT(*) - COUNT(DISTINCT listing_id) AS "Duplicated Values"
    FROM airbnb.staging.fct_reviews
),
-- For unique counts, we need a similar approach to null counts
unique_counts AS (
    SELECT 
        'listing_id' AS "Feature",
        COUNT(DISTINCT listing_id) AS "Unique Values"
    FROM airbnb.staging.fct_reviews
    UNION ALL
    SELECT 
        'listing_id' AS "Feature",
        COUNT(DISTINCT listing_id) AS "Unique Values"
    FROM airbnb.staging.fct_reviews
    -- Repeat for each column in your table
)
SELECT 
    c."Feature",
    c."Data Type",
    n."Null Values",
    n."Null Percentage",
    d."Duplicated Values",
    u."Unique Values"
FROM column_info c
LEFT JOIN null_counts n ON c."Feature" = n."Feature"
CROSS JOIN duplicates d
LEFT JOIN unique_counts u ON c."Feature" = u."Feature";

-- ======================================================================================================================================

-- Table data profiling query (version 2)
WITH column_info AS (
    SELECT 
        column_name AS "Feature",
        data_type AS "Data Type"
    FROM information_schema.columns
    WHERE table_name = 'fct_reviews'
	AND table_schema = 'staging'
),
null_counts AS (
    SELECT 
        column_name AS "Feature",
        COUNT(*) FILTER (WHERE column_name IS NULL) AS "Null Values",
        ROUND(100.0 * COUNT(*) FILTER (WHERE column_name IS NULL) / COUNT(*), 2) AS "Null Percentage"
    FROM information_schema.columns
    JOIN airbnb.staging.fct_reviews ON true
    GROUP BY column_name
),
duplicates AS (
    SELECT COUNT(*) - COUNT(DISTINCT *) AS "Duplicated Values"
    FROM your_table_name
),
unique_counts AS (
    SELECT 
        column_name AS "Feature",
        COUNT(DISTINCT column_name) AS "Unique Values"
    FROM information_schema.columns
    JOIN your_table_name ON true
    GROUP BY column_name
)
SELECT 
    c."Feature",
    c."Data Type",
    n."Null Values",
    n."Null Percentage",
    d."Duplicated Values",
    u."Unique Values"
FROM column_info c
LEFT JOIN null_counts n ON c."Feature" = n."Feature"
LEFT JOIN duplicates d ON true
LEFT JOIN unique_counts u ON c."Feature" = u."Feature";

-- ======================================================================================================================================

-- Table data profiling query (version 3)

-- Dynamic SQL procedure to analyze table structure and data quality
CREATE OR REPLACE PROCEDURE analyze_table_data(schema_name VARCHAR, table_name VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
// Get all columns for the table
var get_columns_sql = `
    SELECT column_name, data_type 
    FROM information_schema.columns
    WHERE table_schema = UPPER('${SCHEMA_NAME}')
    AND table_name = UPPER('${TABLE_NAME}')
    ORDER BY ordinal_position
`;

var columns_result = snowflake.execute({sqlText: get_columns_sql});
var columns = [];
var column_types = {};

// Store column names and types
while (columns_result.next()) {
    var col_name = columns_result.getColumnValue(1);
    var data_type = columns_result.getColumnValue(2);
    columns.push(col_name);
    column_types[col_name] = data_type;
}

if (columns.length === 0) {
    return `Table ${SCHEMA_NAME}.${TABLE_NAME} not found or has no columns.`;
}

// Build the dynamic query
var full_table_name = `${SCHEMA_NAME}.${TABLE_NAME}`;
var row_count_sql = `SELECT COUNT(*) FROM ${full_table_name}`;
var row_count_result = snowflake.execute({sqlText: row_count_sql});
row_count_result.next();
var total_rows = row_count_result.getColumnValue(1);

// Duplicate check - we'll use all columns for this check
var duplicate_sql = `
    SELECT COUNT(*) - COUNT(DISTINCT ${columns.join(', ')}) AS duplicate_count
    FROM ${full_table_name}
`;

// Generate the null counts and unique value counts for each column
var null_count_cases = [];
var unique_count_selects = [];

columns.forEach(function(col) {
    // Null count case
    null_count_cases.push(`SUM(CASE WHEN ${col} IS NULL THEN 1 ELSE 0 END) AS "${col}_null_count"`);
    
    // Unique values count
    unique_count_selects.push(`
        SELECT 
            '${col}' AS column_name,
            COUNT(DISTINCT ${col}) AS unique_count
        FROM ${full_table_name}
    `);
});

var null_counts_sql = `
    SELECT 
        ${null_count_cases.join(', ')}
    FROM ${full_table_name}
`;

var unique_counts_sql = unique_count_selects.join(' UNION ALL ');

// Execute all the queries
var duplicate_result = snowflake.execute({sqlText: duplicate_sql});
duplicate_result.next();
var duplicate_count = duplicate_result.getColumnValue(1);

var null_counts_result = snowflake.execute({sqlText: null_counts_sql});
null_counts_result.next();

var unique_counts_result = snowflake.execute({sqlText: unique_counts_sql});
var unique_counts = {};
while (unique_counts_result.next()) {
    var col = unique_counts_result.getColumnValue(1);
    var count = unique_counts_result.getColumnValue(2);
    unique_counts[col] = count;
}

// Format results into a final query that will return the analysis as a table
var final_sql_parts = [];
columns.forEach(function(col, i) {
    var null_count = null_counts_result.getColumnValue(`${col}_null_count`);
    var null_percentage = (null_count / total_rows * 100).toFixed(2);
    var unique_count = unique_counts[col] || 0;
    
    final_sql_parts.push(`
        SELECT 
            '${col}' AS "Feature",
            '${column_types[col]}' AS "Data Type",
            ${null_count} AS "Null Values",
            ${null_percentage} AS "Null Percentage",
            ${duplicate_count} AS "Duplicated Values",
            ${unique_count} AS "Unique Values"
    `);
});

var final_sql = final_sql_parts.join(' UNION ALL ') + ' ORDER BY "Feature"';

// Execute and return the formatted analysis
return final_sql;
$$;

-- Example usage:
CALL analyze_table_data('airbnb', 'staging.fct_reviews');

-- Alternatively, for a single-query approach without stored procedures
-- (this is less flexible but doesn't require creating a procedure):

-- First, create a query that generates our analysis query
SELECT 
    'WITH table_stats AS (SELECT COUNT(*) AS row_count FROM airbnb.staging.fct_reviews), ' ||
    'duplicate_check AS (SELECT COUNT(*) - COUNT(DISTINCT ' || 
        LISTAGG(column_name, ', ') WITHIN GROUP (ORDER BY ordinal_position) || 
        ') AS duplicate_count FROM airbnb.staging.fct_reviews) ' ||
    'SELECT ' ||
        LISTAGG(
            'column_name AS "Feature", ' ||
            'data_type AS "Data Type", ' ||
            'null_count AS "Null Values", ' ||
            'ROUND(100.0 * null_count / t.row_count, 2) AS "Null Percentage", ' ||
            'd.duplicate_count AS "Duplicated Values", ' ||
            'unique_count AS "Unique Values"', 
            ' UNION ALL '
        ) WITHIN GROUP (ORDER BY ordinal_position) || 
    ' FROM (' ||
        LISTAGG(
            'SELECT ''' || column_name || ''' AS column_name, ' ||
            '''' || data_type || ''' AS data_type, ' ||
            'SUM(CASE WHEN ' || column_name || ' IS NULL THEN 1 ELSE 0 END) AS null_count, ' ||
            'COUNT(DISTINCT ' || column_name || ') AS unique_count ' ||
            'FROM airbnb.staging.fct_reviews',
            ' UNION ALL '
        ) WITHIN GROUP (ORDER BY ordinal_position) ||
    ') v, table_stats t, duplicate_check d'
FROM information_schema.columns
WHERE table_schema = 'STAGING'
AND table_name = 'FCT_REVIEWS';

-- The query above generates a single dynamic SQL statement that you can copy and execute

-- Call the procedure
CALL analyze_table_data('airbnb', 'staging.fct_reviews');