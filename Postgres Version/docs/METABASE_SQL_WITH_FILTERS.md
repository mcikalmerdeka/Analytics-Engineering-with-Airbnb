# Metabase SQL with Field Filters

This is the native-SQL companion to
[`METABASE_DASHBOARDS.md`](METABASE_DASHBOARDS.md). Use it when you build the
five dashboards as **native SQL questions** instead of query-builder cards.

Every SQL block below is written for Metabase v0.64.x and PostgreSQL 17. The
values and filter columns match the `analytics` schema in this project.

The matching question descriptions are in
[`METABASE_DASHBOARDS.md`](METABASE_DASHBOARDS.md). Use those in the
**Description** field when saving each native SQL question.

## How to use this file

1. Create the question as **New → SQL query** on the `Airbnb Analytics`
   database.
2. Paste the SQL block exactly as written.
3. Open the **Variables** panel. Metabase creates one variable for every
   `{{variable}}` it finds.
4. For every variable marked **Field Filter**, change its type from Text to
   **Field Filter**, choose the field shown in the dashboard's variable table,
   and choose the widget type.
5. Turn **Always require a value** off for optional filters.
6. Save the question, then add it to the dashboard.
7. Add the dashboard filters and map each one to the matching card variable.

### Field Filter rules

- Use `AND {{variable}}`, **not** `AND column = {{variable}}`. A Field Filter
  inserts the column, operator, and value handling.
- Do not wrap a Field Filter in quotes: `'{{variable}}'` is wrong.
- A Field Filter only works when the mapped field's table is in the query's
  `FROM`/`JOIN`. For cards built on marts, map to the mart's own column.
- If the SQL aliases the table, fill in **Table and field alias** with the alias
  and column, for example `l.room_type`.
- Boolean filters are dashboard **Boolean** filters and Field Filters mapped to
  boolean columns.
- Date filters are dashboard **Date** filters and Field Filters mapped to date
  columns.
- Number filters are dashboard **Number** filters and Field Filters mapped to
  numeric columns.

### Text search variables

`listing_name` and `host_name` are plain **Text** variables, not Field Filters.
They use optional `[[ ... ]]` blocks so the SQL still runs when the search box
is empty. The dashboard filter type is **Text** with the **Contains** operator.

### Optional filter blocks

Field Filters in this project are optional. If your Metabase build insists on a
value, use the `[[AND {{variable}}]]` form around the filter. The SQL blocks
already use that form for Text variables; convert the Field Filter lines the
same way if needed.

---

## Dashboard 1 — Executive Overview

### Variables

| Variable | Type | Field to map to | Widget |
| --- | --- | --- | --- |
| `month_start` | Field Filter | `analytics.mart_executive_kpis.month_start` on cards 1.6–1.8, 1.11, 1.12; `analytics.mart_market_monthly.month_start` on card 1.13 | Date |

The Executive dashboard has one dashboard filter: `Month range` (Date range).
Map it to `month_start`. KPI cards and all-time mix cards have no variables and
do not respond to it.

### 1.1 KPI - Total Listings

Expected: `17,499`. No variables.

```sql
SELECT COUNT(*) AS total_listings
FROM analytics.dim_listings;
```

### 1.2 KPI - Total Hosts

Expected: `14,111`. No variables.

```sql
SELECT COUNT(*) AS total_hosts
FROM analytics.dim_hosts;
```

### 1.3 KPI - Total Reviews

Expected: `410,283`. No variables.

```sql
SELECT COUNT(*) AS total_reviews
FROM analytics.fct_reviews;
```

### 1.4 KPI - Active Listings (12m)

Expected: `6,050`. No variables.

```sql
SELECT COUNT(*) AS active_listings
FROM analytics.mart_listing_performance
WHERE is_active_last_12m = TRUE;
```

### 1.5 KPI - Avg Nightly Price

Expected: `70.41`. No variables.

```sql
SELECT AVG(price) AS avg_nightly_price
FROM analytics.dim_listings
WHERE NOT is_price_outlier;
```

### 1.6 Chart - Supply and Host Growth

Expected at 2021-10: listings `15,429`, hosts `12,568`. Visualization: Line,
X = `month_start`, Y = `value`, series = `metric`.

```sql
SELECT
    month_start,
    'Cumulative listings' AS metric,
    cumulative_listings::numeric AS value
FROM analytics.mart_executive_kpis
WHERE 1 = 1
  AND {{month_start}}

UNION ALL

SELECT
    month_start,
    'Cumulative hosts' AS metric,
    cumulative_hosts::numeric AS value
FROM analytics.mart_executive_kpis
WHERE 1 = 1
  AND {{month_start}}

ORDER BY month_start, metric;
```

### 1.7 Chart - New Listings per Month

Expected 2021-10: `1,246`. Visualization: Bar.

```sql
SELECT
    month_start,
    new_listings
FROM analytics.mart_executive_kpis
WHERE month_start <= DATE '2021-10-01'
  AND {{month_start}}
ORDER BY month_start;
```

### 1.8 Chart - Monthly Reviews

Expected 2021-10: `5,110`. Visualization: Line.

```sql
SELECT
    month_start,
    reviews
FROM analytics.mart_executive_kpis
WHERE month_start <= DATE '2021-10-01'
  AND {{month_start}}
ORDER BY month_start;
```

### 1.9 Chart - Room Type Mix

Expected: Entire home/apt `9,890`; Private room `7,233`; Shared room `211`;
Hotel room `165`. Visualization: Pie.

```sql
SELECT
    room_type,
    COUNT(*) AS listings
FROM analytics.dim_listings
GROUP BY room_type
ORDER BY listings DESC;
```

### 1.10 Chart - Sentiment Mix

Expected: Positive `232,554`; Neutral `147,255`; Negative `30,090`;
Unknown `384`. Visualization: Pie.

```sql
SELECT
    review_sentiment,
    COUNT(*) AS reviews
FROM analytics.fct_reviews
GROUP BY review_sentiment
ORDER BY reviews DESC;
```

### 1.11 Chart - Avg Sentiment Trend

Expected 2021-10: `0.43`. Visualization: Line.

```sql
SELECT
    month_start,
    avg_sentiment
FROM analytics.mart_executive_kpis
WHERE month_start <= DATE '2021-10-01'
  AND {{month_start}}
ORDER BY month_start;
```

### 1.12 Chart - Superhost Share Trend

Expected 2021-10: `0.174` (17.4%). Visualization: Line. Format as percentage.

```sql
SELECT
    month_start,
    superhost_share
FROM analytics.mart_executive_kpis
WHERE month_start <= DATE '2021-10-01'
  AND {{month_start}}
ORDER BY month_start;
```

### 1.13 Chart - Review Volume by Room Type

Expected 2021-10: Entire home/apt `3,478`; Private room `1,458`; Hotel room
`93`; Shared room `81`. Visualization: Line, breakout = `room_type`.

```sql
SELECT
    month_start,
    room_type,
    reviews
FROM analytics.mart_market_monthly
WHERE month_start <= DATE '2021-10-01'
  AND {{month_start}}
ORDER BY month_start, room_type;
```

### 1.14 Chart - Listing Age Cohorts

Expected: 3–5 years `6,135`; < 1 year `4,819`; 1–2 years `4,158`;
6+ years `2,387`. Visualization: Bar.

```sql
SELECT
    listing_age_cohort,
    COUNT(*) AS listings
FROM analytics.dim_listings
GROUP BY listing_age_cohort
ORDER BY listings DESC;
```

### Executive filter mapping

| Filter | Cards |
| --- | --- |
| `Month range` | 1.6, 1.7, 1.8, 1.11, 1.12, 1.13 |

---

## Dashboard 2 — Supply and Pricing

### Variables

| Variable | Type | Field to map to | Widget |
| --- | --- | --- | --- |
| `room_type` | Field Filter | `dim_listings.room_type`, `mart_price_bands.room_type`, or `mart_room_type_benchmark.room_type` — whichever table the card uses | Category |
| `price_band` | Field Filter | `dim_listings.price_band` or `mart_price_bands.price_band` | Category |
| `minimum_nights_band` | Field Filter | `dim_listings.minimum_nights_band` | Category |
| `is_superhost` | Field Filter | `dim_listings.is_superhost` | Boolean |
| `price` | Field Filter | `dim_listings.price` | Number |

### Per-card filter availability

| Card | room_type | price_band | minimum_nights_band | is_superhost | price |
| --- | :---: | :---: | :---: | :---: | :---: |
| 2.1 Total Listings | Yes | Yes | Yes | Yes | Yes |
| 2.2 Median Price | — | — | — | — | — |
| 2.3 Avg Price | Yes | Yes | Yes | Yes | Yes |
| 2.4 Outlier Listings | Yes | Yes | Yes | Yes | Yes |
| 2.5 Superhost Listings | Yes | Yes | Yes | — | Yes |
| 2.6 Price Band Distribution | Yes | Yes | Yes | Yes | Yes |
| 2.7 Price Band × Room Type | Yes | Yes | — | — | — |
| 2.8 Room Type Benchmark | Yes | — | — | — | — |
| 2.9 Supply Share | Yes | — | — | — | — |
| 2.10 Minimum Nights | Yes | Yes | Yes | Yes | Yes |
| 2.11 Active Share by Band | Yes | Yes | — | — | — |
| 2.12 Superhost Share by Band | Yes | Yes | — | — | — |
| 2.13 Room Type Table | Yes | — | — | — | — |

### 2.1 KPI - Total Listings

Expected: `17,499`.

```sql
SELECT COUNT(*) AS total_listings
FROM analytics.dim_listings
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{price}};
```

### 2.2 KPI - Median Nightly Price

Expected: `55`. Fixed card: no variables.

```sql
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM analytics.dim_listings
WHERE NOT is_price_outlier;
```

### 2.3 KPI - Avg Nightly Price (excl. outliers)

Expected: `70.41`.

```sql
SELECT AVG(price) AS avg_nightly_price
FROM analytics.dim_listings
WHERE NOT is_price_outlier
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{price}};
```

### 2.4 KPI - Outlier Listings

Expected: `97`.

```sql
SELECT COUNT(*) AS outlier_listings
FROM analytics.dim_listings
WHERE is_price_outlier = TRUE
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{price}};
```

### 2.5 KPI - Superhost Listings

Expected: `2,738` (15.6%). The `Superhost` filter is intentionally omitted:
this card is defined by superhost status.

```sql
SELECT COUNT(*) AS superhost_listings
FROM analytics.dim_listings
WHERE is_superhost = TRUE
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{price}};
```

### 2.6 Chart - Listings by Price Band

Expected: `<30` `2,509`; `30-49` `4,849`; `50-74` `4,319`; `75-99` `2,551`;
`100-149` `1,850`; `150-249` `1,036`; `250+` `385`. Visualization: Bar.

If the `Price band` dashboard filter is applied, this chart collapses to the
selected band. That is expected.

```sql
SELECT
    price_band,
    COUNT(*) AS listings
FROM analytics.dim_listings
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{price}}
GROUP BY price_band
ORDER BY CASE price_band
    WHEN '<30' THEN 1
    WHEN '30-49' THEN 2
    WHEN '50-74' THEN 3
    WHEN '75-99' THEN 4
    WHEN '100-149' THEN 5
    WHEN '150-249' THEN 6
    ELSE 7
END;
```

### 2.7 Chart - Price Band by Room Type

Expected total: `17,499`. Visualization: Bar, X = `price_band`,
Y = `listings`, breakout = `room_type`.

```sql
SELECT
    price_band,
    room_type,
    SUM(listing_count) AS listings
FROM analytics.mart_price_bands
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
GROUP BY price_band, room_type
ORDER BY CASE price_band
    WHEN '<30' THEN 1
    WHEN '30-49' THEN 2
    WHEN '50-74' THEN 3
    WHEN '75-99' THEN 4
    WHEN '100-149' THEN 5
    WHEN '150-249' THEN 6
    ELSE 7
END, room_type;
```

### 2.8 Chart - Room Type Price Benchmark

Expected medians: Entire home/apt `75`; Private room `35`; Shared room `30`;
Hotel room `155`. P90: `156`, `70`, `98`, `326.4`. Visualization: Bar,
X = `room_type`, Y = `value`, series = `metric`.

```sql
SELECT
    room_type,
    'Median price' AS metric,
    median_price::numeric AS value
FROM analytics.mart_room_type_benchmark
WHERE 1 = 1
  AND {{room_type}}

UNION ALL

SELECT
    room_type,
    'P90 price' AS metric,
    p90_price::numeric AS value
FROM analytics.mart_room_type_benchmark
WHERE 1 = 1
  AND {{room_type}}

ORDER BY room_type, metric;
```

### 2.9 Chart - Supply Share by Room Type

Expected: Entire home/apt `56.5%`; Private room `41.3%`; Shared room `1.2%`;
Hotel room `0.9%`. Visualization: Pie.

```sql
SELECT
    room_type,
    listing_count
FROM analytics.mart_room_type_benchmark
WHERE 1 = 1
  AND {{room_type}}
ORDER BY listing_count DESC;
```

### 2.10 Chart - Minimum Nights Distribution

Expected: `1` `4,045`; `2-6` `10,027`; `7-29` `2,078`; `30+` `1,349`.
Visualization: Bar.

```sql
SELECT
    minimum_nights_band,
    COUNT(*) AS listings
FROM analytics.dim_listings
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{price}}
GROUP BY minimum_nights_band
ORDER BY CASE minimum_nights_band
    WHEN '1' THEN 1
    WHEN '2-6' THEN 2
    WHEN '7-29' THEN 3
    ELSE 4
END;
```

### 2.11 Chart - Active Share by Price Band

Expected: `19.7%`, `49.0%`, `43.8%`, `39.7%`, `44.8%`, `30.6%`, `22.5%`.
Visualization: Bar.

```sql
SELECT
    price_band,
    AVG(pct_active) AS active_share
FROM analytics.mart_price_bands
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
GROUP BY price_band
ORDER BY CASE price_band
    WHEN '<30' THEN 1
    WHEN '30-49' THEN 2
    WHEN '50-74' THEN 3
    WHEN '75-99' THEN 4
    WHEN '100-149' THEN 5
    WHEN '150-249' THEN 6
    ELSE 7
END;
```

### 2.12 Chart - Superhost Share by Price Band

Expected: `7.9%`, `6.8%`, `23.6%`, `12.6%`, `11.6%`, `13.0%`, `21.4%`.
Visualization: Bar.

```sql
SELECT
    price_band,
    AVG(pct_superhost) AS superhost_share
FROM analytics.mart_price_bands
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
GROUP BY price_band
ORDER BY CASE price_band
    WHEN '<30' THEN 1
    WHEN '30-49' THEN 2
    WHEN '50-74' THEN 3
    WHEN '75-99' THEN 4
    WHEN '100-149' THEN 5
    WHEN '150-249' THEN 6
    ELSE 7
END;
```

### 2.13 Table - Room Type Benchmark

Expected: `4` rows.

```sql
SELECT
    room_type,
    listing_count,
    share_of_supply,
    avg_price,
    median_price,
    p90_price,
    avg_reviews,
    median_reviews,
    avg_sentiment,
    pct_superhost,
    pct_active
FROM analytics.mart_room_type_benchmark
WHERE 1 = 1
  AND {{room_type}}
ORDER BY listing_count DESC;
```

### Supply filter mapping

| Filter | Cards |
| --- | --- |
| `Room type` | 2.1, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13 |
| `Price band` | 2.1, 2.3, 2.4, 2.5, 2.6, 2.7, 2.10, 2.11, 2.12 |
| `Minimum nights band` | 2.1, 2.3, 2.4, 2.5, 2.6, 2.10 |
| `Superhost` | 2.1, 2.3, 2.4, 2.6, 2.10 |
| `Price range` | 2.1, 2.3, 2.4, 2.5, 2.6, 2.10 |

---

## Dashboard 3 — Guest Experience

### Variables

| Variable | Type | Field to map to | Widget |
| --- | --- | --- | --- |
| `review_date` | Field Filter | `analytics.fct_reviews.review_date` (alias `r.review_date` on card 3.9) | Date |
| `review_month` | Field Filter | `analytics.mart_review_topics.month_start` | Date |
| `review_sentiment` | Field Filter | `analytics.fct_reviews.review_sentiment` (alias `r.review_sentiment` on card 3.9) | Category |
| `has_comment` | Field Filter | `analytics.fct_reviews.has_comment` (alias `r.has_comment` on card 3.9) | Boolean |
| `room_type` | Field Filter | `analytics.dim_listings.room_type` (alias `l.room_type` on card 3.9) | Category |
| `topic` | Field Filter | `analytics.mart_review_topics.topic` | Category |

### 3.1 KPI - Total Reviews

Expected: `410,283`.

```sql
SELECT COUNT(*) AS total_reviews
FROM analytics.fct_reviews
WHERE 1 = 1
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}};
```

### 3.2 KPI - Positive Review Share

Expected: `0.5668` (56.7%). Fixed card: no variables.

```sql
SELECT
    COUNT(*) FILTER (WHERE review_sentiment = 'positive')::numeric
        / NULLIF(COUNT(*), 0) AS positive_share
FROM analytics.fct_reviews;
```

### 3.3 KPI - Negative Review Share

Expected: `0.0733` (7.3%). Fixed card: no variables.

```sql
SELECT
    COUNT(*) FILTER (WHERE review_sentiment = 'negative')::numeric
        / NULLIF(COUNT(*), 0) AS negative_share
FROM analytics.fct_reviews;
```

### 3.4 KPI - Avg Sentiment Score

Expected: `0.494`.

```sql
SELECT AVG(sentiment_score) AS avg_sentiment_score
FROM analytics.fct_reviews
WHERE 1 = 1
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}};
```

### 3.5 KPI - Reviews in 2021

Expected: `47,356`.

```sql
SELECT COUNT(*) AS reviews_2021
FROM analytics.fct_reviews
WHERE review_year = 2021
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}};
```

### 3.6 Chart - Review Volume by Month

Expected 2021-10: `5,110`. Visualization: Line.

```sql
SELECT
    review_month,
    COUNT(*) AS reviews
FROM analytics.fct_reviews
WHERE review_month <= DATE '2021-10-01'
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}}
GROUP BY review_month
ORDER BY review_month;
```

### 3.7 Chart - Sentiment Mix

Expected: Positive `232,554`; Neutral `147,255`; Negative `30,090`;
Unknown `384`. Visualization: Pie.

```sql
SELECT
    review_sentiment,
    COUNT(*) AS reviews
FROM analytics.fct_reviews
WHERE 1 = 1
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}}
GROUP BY review_sentiment
ORDER BY reviews DESC;
```

### 3.8 Chart - Sentiment by Month

Visualization: Bar, X = `review_month`, Y = `reviews`,
breakout = `review_sentiment`.

```sql
SELECT
    review_month,
    review_sentiment,
    COUNT(*) AS reviews
FROM analytics.fct_reviews
WHERE review_month <= DATE '2021-10-01'
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}}
GROUP BY review_month, review_sentiment
ORDER BY review_month, review_sentiment;
```

### 3.9 Chart - Reviews by Room Type

Expected: Entire home/apt `261,438`; Private room `138,356`; Shared room
`6,078`; Hotel room `4,411`. Visualization: Bar.

**Alias settings for this card:** set `review_date` → `r.review_date`,
`review_sentiment` → `r.review_sentiment`, `has_comment` → `r.has_comment`,
and `room_type` → `l.room_type`.

```sql
SELECT
    l.room_type,
    COUNT(*) AS reviews
FROM analytics.fct_reviews AS r
INNER JOIN analytics.dim_listings AS l
    ON r.listing_id = l.listing_id
WHERE 1 = 1
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}}
  AND {{room_type}}
GROUP BY l.room_type
ORDER BY reviews DESC;
```

### 3.10 Chart - Review Length

Expected: `409,697` comments (99.9%). Visualization: Histogram on
`review_length`.

```sql
SELECT review_length
FROM analytics.fct_reviews
WHERE has_comment = TRUE
  AND {{review_date}}
  AND {{review_sentiment}}
  AND {{has_comment}};
```

### 3.11 Chart - Topic Mentions

Expected: Location `150,557`; Host `109,692`; Cleanliness `100,973`;
Transport `66,742`; Check-in `43,206`; Noise `43,035`; Kitchen `21,356`;
Bed `19,276`; Bathroom `17,805`; WiFi `8,810`; Breakfast `6,585`.

```sql
SELECT
    topic,
    SUM(mentions) AS mentions
FROM analytics.mart_review_topics
WHERE 1 = 1
  AND {{review_month}}
  AND {{topic}}
GROUP BY topic
ORDER BY mentions DESC;
```

### 3.12 Chart - Topic Mention Rate Trend

Visualization: Line, X = `month_start`, Y = `avg_mention_rate`,
breakout = `topic`. The fixed range prevents the partial 2021-11 month from
appearing.

```sql
SELECT
    month_start,
    topic,
    AVG(mention_rate) AS avg_mention_rate
FROM analytics.mart_review_topics
WHERE month_start BETWEEN DATE '2019-11-01' AND DATE '2021-10-01'
  AND {{review_month}}
  AND {{topic}}
GROUP BY month_start, topic
ORDER BY month_start, topic;
```

### 3.13 Chart - Negative Mentions by Topic

Expected average negative share: Check-in `7.8%`; Cleanliness `7.4%`;
Host `7.2%`; Noise `7.2%`; Kitchen `6.9%`; Location `5.5%`; Bed `5.4%`;
Breakfast `5.4%`; Transport `4.5%`; WiFi `3.9%`; Bathroom `3.2%`.

```sql
SELECT
    topic,
    AVG(pct_negative) AS avg_pct_negative
FROM analytics.mart_review_topics
WHERE 1 = 1
  AND {{review_month}}
  AND {{topic}}
GROUP BY topic
ORDER BY avg_pct_negative DESC;
```

### 3.14 Table - Topic Detail

Expected: `1,573` rows unfiltered; the fixed 12-month window returns `132`.

```sql
SELECT
    month_start,
    topic,
    mentions,
    mention_rate,
    avg_sentiment,
    pct_negative
FROM analytics.mart_review_topics
WHERE month_start BETWEEN DATE '2020-11-01' AND DATE '2021-10-01'
  AND {{review_month}}
  AND {{topic}}
ORDER BY mentions DESC
LIMIT 1000;
```

### Guest filter mapping

| Filter | Cards |
| --- | --- |
| `Review date` | 3.1, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10 |
| `Review month` | 3.11, 3.12, 3.13, 3.14 |
| `Room type` | 3.9 |
| `Sentiment` | 3.1, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10 |
| `Has comment` | 3.1, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10 |
| `Topic` | 3.11, 3.12, 3.13, 3.14 |

Topic cards cannot accept room type or sentiment filters:
`mart_review_topics` is aggregated at month × topic grain.

---

## Dashboard 4 — Host Portfolio

### Variables

| Variable | Type | Field to map to | Widget |
| --- | --- | --- | --- |
| `host_segment` | Field Filter | `analytics.mart_host_performance.host_segment` (cards 4.1, 4.5–4.8, 4.10–4.13); `analytics.dim_hosts.host_segment` is not needed | Category |
| `is_superhost` | Field Filter | `analytics.mart_host_performance.is_superhost` | Boolean |
| `listing_count` | Field Filter | `analytics.mart_host_performance.listing_count` | Number |
| `host_created_at` | Field Filter | `analytics.dim_hosts.host_created_at` | Date |
| `host_name` | **Text** | Plain Text variable; no field mapping | Text (Contains) |

### Per-card filter availability

| Card | host_segment | is_superhost | listing_count | host_created_at | host_name |
| --- | :---: | :---: | :---: | :---: | :---: |
| 4.1 Total Hosts | Yes | Yes | Yes | — | — |
| 4.2 Superhosts | Yes | — | Yes | — | — |
| 4.3 Single-listing Hosts | — | Yes | Yes | — | — |
| 4.4 Professional+ Hosts | — | Yes | Yes | — | — |
| 4.5 Avg Reviews per Host | Yes | Yes | Yes | — | — |
| 4.6 Hosts by Segment | Yes | Yes | Yes | — | — |
| 4.7 Avg Listings by Segment | Yes | Yes | Yes | — | — |
| 4.8 Avg Reviews by Segment | Yes | Yes | Yes | — | — |
| 4.9 New Hosts per Month | — | — | — | Yes | — |
| 4.10 Superhost Performance | Yes | — | Yes | — | — |
| 4.11 Segment × Superhost | Yes | — | Yes | — | — |
| 4.12 Portfolio Size | Yes | Yes | Yes | — | — |
| 4.13 Top Hosts | Yes | Yes | Yes | — | Yes |

Cards 4.2–4.4 are defined by superhost or segment status: card 4.2 omits the
`Superhost` filter, and cards 4.3–4.4 omit the `Host segment` filter. All three
still accept the other filters shown above.

### 4.1 KPI - Total Hosts

Expected: `14,111`.

```sql
SELECT COUNT(*) AS total_hosts
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}};
```

### 4.2 KPI - Superhosts

Expected: `1,920` (13.6%).

```sql
SELECT COUNT(*) AS superhosts
FROM analytics.mart_host_performance
WHERE is_superhost = TRUE
  AND {{host_segment}}
  AND {{listing_count}};
```

### 4.3 KPI - Single-listing Hosts

Expected: `12,666`.

```sql
SELECT COUNT(*) AS single_listing_hosts
FROM analytics.mart_host_performance
WHERE host_segment = 'Single listing'
  AND {{is_superhost}}
  AND {{listing_count}};
```

### 4.4 KPI - Professional+ Hosts

Expected: `204` (Professional `144` + Large professional `46` + Enterprise
`14`).

```sql
SELECT COUNT(*) AS professional_plus_hosts
FROM analytics.mart_host_performance
WHERE host_segment IN ('Professional', 'Large professional', 'Enterprise')
  AND {{is_superhost}}
  AND {{listing_count}};
```

### 4.5 KPI - Avg Reviews per Host

Expected: `29.08`.

```sql
SELECT AVG(total_reviews) AS avg_reviews_per_host
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}};
```

### 4.6 Chart - Hosts by Segment

Expected: Single listing `12,666`; Small portfolio `1,241`; Professional `144`;
Large professional `46`; Enterprise `14`.

```sql
SELECT
    host_segment,
    COUNT(*) AS hosts
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}}
GROUP BY host_segment
ORDER BY hosts DESC;
```

### 4.7 Chart - Avg Listings per Host by Segment

Expected: `1.00`, `2.32`, `6.16`, `12.59`, `34.50`.

```sql
SELECT
    host_segment,
    AVG(listing_count) AS avg_listings
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}}
GROUP BY host_segment
ORDER BY avg_listings DESC;
```

### 4.8 Chart - Avg Reviews per Host by Segment

Expected: `18.7`, `81.0`, `267.3`, `508.6`, `800.1`.

```sql
SELECT
    host_segment,
    AVG(total_reviews) AS avg_reviews
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}}
GROUP BY host_segment
ORDER BY avg_reviews DESC;
```

### 4.9 Chart - New Hosts per Month

Visualization: Line. The fixed start date keeps the chart readable; the
dashboard filter can narrow it further.

```sql
SELECT
    DATE_TRUNC('month', host_created_at)::date AS month_start,
    COUNT(*) AS new_hosts
FROM analytics.dim_hosts
WHERE host_created_at >= DATE '2015-01-01'
  AND {{host_created_at}}
GROUP BY 1
ORDER BY 1;
```

### 4.10 Chart - Superhost Performance

Expected average reviews: superhost `96.7`; non-superhost `18.4`.

```sql
SELECT
    is_superhost,
    AVG(total_reviews) AS avg_reviews
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{listing_count}}
GROUP BY is_superhost
ORDER BY is_superhost NULLS LAST;
```

### 4.11 Chart - Hosts by Segment and Superhost

Visualization: Stacked bar, X = `host_segment`, Y = `hosts`,
breakout = `is_superhost`.

```sql
SELECT
    host_segment,
    is_superhost,
    COUNT(*) AS hosts
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{listing_count}}
GROUP BY host_segment, is_superhost
ORDER BY host_segment, is_superhost NULLS LAST;
```

### 4.12 Chart - Portfolio Size

Visualization: Histogram on `listing_count`.

```sql
SELECT listing_count
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}};
```

### 4.13 Table - Top Hosts

Expected: `100` rows (limit).

```sql
SELECT
    host_name,
    host_segment,
    is_superhost,
    listing_count,
    active_listing_count,
    total_reviews,
    avg_reviews_per_listing,
    avg_sentiment
FROM analytics.mart_host_performance
WHERE 1 = 1
  AND {{host_segment}}
  AND {{is_superhost}}
  AND {{listing_count}}
  [[AND LOWER(host_name) LIKE '%' || LOWER({{host_name}}) || '%']]
ORDER BY total_reviews DESC
LIMIT 100;
```

### Host filter mapping

| Filter | Cards |
| --- | --- |
| `Host segment` | 4.1, 4.2, 4.5, 4.6, 4.7, 4.8, 4.10, 4.11, 4.12, 4.13 |
| `Superhost` | 4.1, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.12, 4.13 |
| `Minimum listings` | 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.10, 4.11, 4.12, 4.13 |
| `Host created date` | 4.9 |
| `Host name` | 4.13 |

---

## Dashboard 5 — Listing Explorer

### Variables

| Variable | Type | Field to map to | Widget |
| --- | --- | --- | --- |
| `room_type` | Field Filter | `analytics.mart_listing_performance.room_type` | Category |
| `price_band` | Field Filter | `analytics.mart_listing_performance.price_band` | Category |
| `minimum_nights_band` | Field Filter | `analytics.mart_listing_performance.minimum_nights_band` | Category |
| `is_superhost` | Field Filter | `analytics.mart_listing_performance.is_superhost` | Boolean |
| `host_segment` | Field Filter | `analytics.mart_listing_performance.host_segment` | Category |
| `is_active_last_12m` | Field Filter | `analytics.mart_listing_performance.is_active_last_12m` | Boolean |
| `price` | Field Filter | `analytics.mart_listing_performance.price` | Number |
| `listing_name` | **Text** | Plain Text variable; no field mapping | Text (Contains) |

### 5.1 KPI - Listings in View

Expected: `17,499` unfiltered.

```sql
SELECT COUNT(*) AS listings
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.2 KPI - Avg Price in View

Expected: `70.41` unfiltered.

```sql
SELECT AVG(price) AS avg_price
FROM analytics.mart_listing_performance
WHERE NOT is_price_outlier
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.3 KPI - Avg Reviews in View

Expected: `23.45` unfiltered.

```sql
SELECT AVG(review_count) AS avg_reviews
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.4 KPI - Active Listings in View

Expected: `6,050` unfiltered. The `Active last 12m` filter is intentionally
omitted: this card is defined by active status.

```sql
SELECT COUNT(*) AS active_listings
FROM analytics.mart_listing_performance
WHERE is_active_last_12m = TRUE
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.5 KPI - Zero-review Listings

Expected: `3,254` unfiltered.

```sql
SELECT COUNT(*) AS zero_review_listings
FROM analytics.mart_listing_performance
WHERE review_count = 0
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.6 Chart - Price vs Review Count

Visualization: Scatter, X = `price`, Y = `review_count`. The active filter is
fixed to keep the point count around `6,050`.

```sql
SELECT
    price,
    review_count
FROM analytics.mart_listing_performance
WHERE NOT is_price_outlier
  AND is_active_last_12m = TRUE
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.7 Chart - Listings by Room Type

Expected: Entire home/apt `9,890`; Private room `7,233`; Shared room `211`;
Hotel room `165`.

```sql
SELECT
    room_type,
    COUNT(*) AS listings
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']]
GROUP BY room_type
ORDER BY listings DESC;
```

### 5.8 Chart - Listings by Price Band

Expected: `<30` `2,509`; `30-49` `4,849`; `50-74` `4,319`; `75-99` `2,551`;
`100-149` `1,850`; `150-249` `1,036`; `250+` `385`.

```sql
SELECT
    price_band,
    COUNT(*) AS listings
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']]
GROUP BY price_band
ORDER BY CASE price_band
    WHEN '<30' THEN 1
    WHEN '30-49' THEN 2
    WHEN '50-74' THEN 3
    WHEN '75-99' THEN 4
    WHEN '100-149' THEN 5
    WHEN '150-249' THEN 6
    ELSE 7
END;
```

### 5.9 Chart - Review Count Distribution

Visualization: Histogram on `review_count`.

```sql
SELECT review_count
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']];
```

### 5.10 Chart - Active Listings by Host Segment

Expected: Single listing `3,453`; Small portfolio `1,349`; Professional `591`;
Large professional `396`; Enterprise `261`.

```sql
SELECT
    host_segment,
    COUNT(*) AS active_listings
FROM analytics.mart_listing_performance
WHERE is_active_last_12m = TRUE
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']]
GROUP BY host_segment
ORDER BY active_listings DESC;
```

### 5.11 Chart - Listings by Minimum Nights

Expected: `1` `4,045`; `2-6` `10,027`; `7-29` `2,078`; `30+` `1,349`.

```sql
SELECT
    minimum_nights_band,
    COUNT(*) AS listings
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']]
GROUP BY minimum_nights_band
ORDER BY CASE minimum_nights_band
    WHEN '1' THEN 1
    WHEN '2-6' THEN 2
    WHEN '7-29' THEN 3
    ELSE 4
END;
```

### 5.12 Table - Listing Detail

Expected: `200` rows (limit).

```sql
SELECT
    listing_id,
    listing_name,
    room_type,
    price,
    price_band,
    minimum_nights,
    host_name,
    host_segment,
    is_superhost,
    review_count,
    review_count_12m,
    avg_sentiment,
    pct_positive,
    last_review_date,
    is_active_last_12m,
    days_since_last_review
FROM analytics.mart_listing_performance
WHERE 1 = 1
  AND {{room_type}}
  AND {{price_band}}
  AND {{minimum_nights_band}}
  AND {{is_superhost}}
  AND {{host_segment}}
  AND {{is_active_last_12m}}
  AND {{price}}
  [[AND LOWER(listing_name) LIKE '%' || LOWER({{listing_name}}) || '%']]
ORDER BY review_count DESC
LIMIT 200;
```

### Listing filter mapping

All eight filters apply to cards 5.1–5.3, 5.5, 5.9, and 5.12. The exceptions:

| Filter | Exception |
| --- | --- |
| `Active last 12m` | Not on 5.4, 5.6, 5.10 — those cards already fix `is_active_last_12m = TRUE` |
| `Room type` | On 5.7 it collapses the chart to one bar |
| `Price band` | On 5.8 it collapses the chart to one bar |
| `Minimum nights band` | On 5.11 it collapses the chart to one bar |
| `Host segment` | Not on 5.10 — it is the grouping column |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `A text variable in this card can only be connected to a text filter with Is operator` | The card has no mappable variable, or the variable is still Text | Change it to **Field Filter**, map the field, save the question |
| `Cannot run the query: missing required parameters` | A variable is Text, or **Always require a value** is on | Change to **Field Filter** and turn **Always require a value** off |
| `argument of AND must be type boolean, not type character varying` | A Text variable was used where a Field Filter was needed; a value was substituted as `AND 'Female'` | Change the variable to **Field Filter** and map it |
| `operator does not exist: boolean = character varying` | A Text/Category dashboard filter is connected to a boolean column | Change the dashboard filter to **Boolean** |
| Field Filter does not appear in the dashboard mapping panel | Question not saved, or the dashboard editor is stale | Save the question, reload the dashboard editor |
| Filter changes one card but not another | The other card lacks the matching variable or mapping | Add the variable and map the filter |
| `column ... does not exist` | Field Filter mapped to the wrong field, or alias missing | Correct the field mapping or **Table and field alias** |
| `missing FROM-clause entry for table ...` | A Field Filter maps to a field from a table not present in the query | Map to the table actually used by that card, or join it |
| Filter works in the question but not on the dashboard | The dashboard filter is not connected to the card | Map the dashboard filter to the card variable |

### Alias settings for joined cards

Only card **3.9** uses table aliases. Set these in the variable panel:

| Variable | Table and field alias |
| --- | --- |
| `review_date` | `r.review_date` |
| `review_sentiment` | `r.review_sentiment` |
| `has_comment` | `r.has_comment` |
| `room_type` | `l.room_type` |

If you add joins to other cards, apply the same rule: alias + column.

---

## Verification

Run these checks after creating the questions. Each one should match the value
in the card section.

### Unfiltered totals

| Check | Expected |
| --- | --- |
| Listings | `17,499` |
| Hosts | `14,111` |
| Reviews | `410,283` |
| Active listings | `6,050` |
| Zero-review listings | `3,254` |
| Avg nightly price | `70.41` |
| Median nightly price | `55` |
| Positive review share | `56.68%` |
| Negative review share | `7.33%` |
| Avg sentiment score | `0.494` |

### Filter checks

| Check | Expected |
| --- | --- |
| `Room type = Entire home/apt` | listings `9,890`; reviews `261,438` |
| `Price band = 50-74` | listings `4,319` |
| `Superhost = true` | listings `2,738`; hosts `1,920` |
| `Host segment = Enterprise` | hosts `14` |
| `Sentiment = positive` | reviews `232,554` |
| `Topic = cleanliness` | mentions `100,973` |
| `Active last 12m = true` | listings `6,050` |

### SQL sanity checks

Run the same queries directly in psql by removing the `{{...}}` and `[[...]]`
filter lines. For example:

```powershell
docker compose exec postgres psql -U postgres -d airbnb -c "SELECT COUNT(*) FROM analytics.mart_listing_performance;"
```

Expected: `17499`.

For a filtered check:

```powershell
docker compose exec postgres psql -U postgres -d airbnb -c "SELECT COUNT(*) FROM analytics.dim_listings WHERE room_type = 'Entire home/apt';"
```

Expected: `9890`.

---

## Notes and limits

1. **Native SQL cards do not inherit dashboard filters automatically.** Every
   filter needs a template tag and a mapping. Query-builder cards are still the
   better choice for simple counts and averages.
2. **Fixed KPI cards** (median price, positive/negative share) have no
   variables and will not respond to dashboard filters. That is intentional.
3. **Aggregated marts are narrower than the base tables.** `mart_price_bands`
   and `mart_room_type_benchmark` do not expose minimum nights, superhost, or
   price range. Do not map filters those cards cannot answer.
4. **`mart_review_topics` is month × topic.** It cannot answer room type or
   sentiment filters. Use `fct_reviews` or the joined review model for those.
5. **The price band and minimum-night `CASE` sorts** keep the bars in logical
   order. Do not remove them; alphabetical sorting puts `100-149` before
   `30-49`.
6. **The 2021-11 month is partial.** Supply marts include it; review data ends
   in 2021-10. The fixed `<= DATE '2021-10-01'` clauses protect review trends.
7. **Relative date filters are evaluated against today.** Always use absolute
   date ranges in this project. The data ends in 2021, and "Past 12 months" in
   2026 returns nothing.
