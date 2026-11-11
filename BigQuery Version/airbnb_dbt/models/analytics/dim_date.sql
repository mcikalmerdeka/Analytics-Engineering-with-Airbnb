{{ config(materialized='table') }}

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2009-01-01' as date)",
        end_date="cast('2022-01-01' as date)"
    ) }}
)
SELECT
    date_day::date AS date_day,
    CAST(TO_CHAR(date_day, 'YYYYMMDD') AS INTEGER) AS date_key,
    CAST(EXTRACT(YEAR FROM date_day) AS INTEGER) AS year,
    CAST(EXTRACT(QUARTER FROM date_day) AS INTEGER) AS quarter,
    CAST(EXTRACT(MONTH FROM date_day) AS INTEGER) AS month,
    TRIM(TO_CHAR(date_day, 'Month')) AS month_name,
    TRIM(TO_CHAR(date_day, 'Mon')) AS month_short,
    DATE_TRUNC('month', date_day)::date AS year_month,
    CAST(EXTRACT(WEEK FROM date_day) AS INTEGER) AS week_of_year,
    CAST(EXTRACT(ISODOW FROM date_day) AS INTEGER) AS day_of_week,
    TRIM(TO_CHAR(date_day, 'Day')) AS day_name,
    EXTRACT(ISODOW FROM date_day) IN (6, 7) AS is_weekend
FROM date_spine
WHERE date_day < DATE '2022-01-01'
