{{ config(materialized='table') }}

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2009-01-01' as date)",
        end_date="cast('2022-01-01' as date)"
    ) }}
)
SELECT
    date_day,
    CAST(FORMAT_DATE('%Y%m%d', date_day) AS INT64) AS date_key,
    CAST(EXTRACT(YEAR FROM date_day) AS INT64) AS year,
    CAST(EXTRACT(QUARTER FROM date_day) AS INT64) AS quarter,
    CAST(EXTRACT(MONTH FROM date_day) AS INT64) AS month,
    FORMAT_DATE('%B', date_day) AS month_name,
    FORMAT_DATE('%b', date_day) AS month_short,
    DATE_TRUNC(date_day, MONTH) AS year_month,
    CAST(EXTRACT(ISOWEEK FROM date_day) AS INT64) AS week_of_year,
    CAST(FORMAT_DATE('%u', date_day) AS INT64) AS day_of_week,
    FORMAT_DATE('%A', date_day) AS day_name,
    EXTRACT(DAYOFWEEK FROM date_day) IN (1, 7) AS is_weekend
FROM date_spine
WHERE date_day < DATE '2022-01-01'
