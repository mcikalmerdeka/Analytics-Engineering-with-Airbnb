# Metabase Dashboard Build Guide

This guide builds the five dashboards declared in
`airbnb_dbt/models/dashboards.yml` against the `analytics` schema:

1. Executive Overview
2. Supply and Pricing
3. Guest Experience
4. Host Portfolio
5. Listing Explorer

It assumes Metabase v0.64.x and the stack from `compose.yaml`. Every expected
value below was captured from the current dataset on 2026-11-05.

If you build the cards as native SQL instead of query-builder questions, use
[`METABASE_SQL_WITH_FILTERS.md`](METABASE_SQL_WITH_FILTERS.md). It contains a
Field Filter version of all 66 cards.

## Before you build

### 1. Connect the analytics database

Complete the Metabase setup wizard at `http://localhost:3000`, then add a
PostgreSQL database:

| Field | Value |
| --- | --- |
| Display name | `Airbnb Analytics` |
| Host | `postgres` |
| Port | `5432` |
| Database | `airbnb` |
| Username | `metabase` |
| Password | `metabasePassword123` |
| SSL | Off |

Metabase syncs only the schemas the `metabase` user can see. That is
`analytics`; `staging`, `raw`, and `snapshots` are intentionally inaccessible.

### 2. Create the collection

Create a collection named **Airbnb Analytics**. Put every model, question, and
dashboard in it. Use these name prefixes so the collection stays searchable:

- `Model - ...`
- `KPI - ...`
- `Chart - ...`
- `Table - ...`

Several question names repeat across dashboards (for example,
`KPI - Total Listings`). Metabase allows duplicate names in one collection, but
the **Description** field is what distinguishes them. If that becomes
confusing, save each dashboard's questions in its own subcollection or append
the dashboard name to the question name.

### 3. Create the reusable models

Models give every card a stable column set and make dashboard filters easier to
map. Create these four before any saved question.

| Model | Based on | Grain | Notes |
| --- | --- | --- | --- |
| `Model - Listings` | `analytics.mart_listing_performance` | One row per listing | Main listing explorer source; includes `minimum_nights_band` |
| `Model - Hosts` | `analytics.mart_host_performance` | One row per host | Host portfolio source |
| `Model - Reviews` | `analytics.fct_reviews` | One row per review | Review KPIs and trends |
| `Model - Reviews with listing attributes` | Query builder join: `fct_reviews` → `dim_listings` on `listing_id` | One row per review | Adds `room_type`, `price_band`, `host_segment`, `is_superhost` to reviews |

For `Model - Reviews with listing attributes`, use a **left join** from
`fct_reviews` to `dim_listings` on `listing_id = listing_id`. Keep these
columns: `review_id`, `review_date`, `review_month`, `review_sentiment`,
`sentiment_score`, `has_comment`, `review_length`, `listing_id`, `room_type`,
`price_band`, `is_price_outlier`, `host_segment`, `is_superhost`.

Add a one-line description to each model. Example: "One row per listing with
review volume, recency, sentiment, price, room type, host attributes, and
minimum-night band. Source: analytics.mart_listing_performance."

### 4. Understand the date boundary

- **Supply snapshot:** the listing and host data is a snapshot from
  2021-11-19. `mart_executive_kpis` and `mart_market_monthly` include a
  **2021-11** row, but that month is partial (listings created through the
  19th, no reviews).
- **Review data:** the last complete review month is **2021-10**. All review
  trend cards should filter `month_start <= 2021-10-01` or
  `review_month <= 2021-10-01`.
- Do not compare `pct_active_12m` across marts; each model computes its own
  trailing-12-month window.

---

## 1. Executive Overview

**Purpose:** market-level supply, host growth, review volume, room mix, and
sentiment for the Airbnb Berlin market.

**Sources:** `dim_listings`, `dim_hosts`, `fct_reviews`, `mart_executive_kpis`,
`mart_market_monthly`.

### Cards

| # | Saved question | Visualization | Source | Build |
| ---: | --- | --- | --- | --- |
| 1 | `KPI - Total Listings` | Number | `Model - Listings` | Summarize **Count**; no filter |
| 2 | `KPI - Total Hosts` | Number | `Model - Hosts` | Summarize **Count** |
| 3 | `KPI - Total Reviews` | Number | `Model - Reviews` | Summarize **Count** |
| 4 | `KPI - Active Listings (12m)` | Number | `Model - Listings` | Filter `is_active_last_12m` = true; Summarize **Count** |
| 5 | `KPI - Avg Nightly Price` | Number | `Model - Listings` | Filter `is_price_outlier` = false; Summarize **Average** of `price` |
| 6 | `Chart - Supply and Host Growth` | Line | `mart_executive_kpis` | X = `month_start`; Y = **Sum** of `cumulative_listings` and **Sum** of `cumulative_hosts` |
| 7 | `Chart - New Listings per Month` | Bar | `mart_executive_kpis` | X = `month_start`; Y = **Sum** of `new_listings`; filter `month_start <= 2021-10-01` |
| 8 | `Chart - Monthly Reviews` | Line | `mart_executive_kpis` | X = `month_start`; Y = **Sum** of `reviews`; filter `month_start <= 2021-10-01` |
| 9 | `Chart - Room Type Mix` | Pie | `Model - Listings` | Group by `room_type`; Summarize **Count** |
| 10 | `Chart - Sentiment Mix` | Pie | `Model - Reviews` | Group by `review_sentiment`; Summarize **Count** |
| 11 | `Chart - Avg Sentiment Trend` | Line | `mart_executive_kpis` | X = `month_start`; Y = **Average** of `avg_sentiment`; filter `month_start <= 2021-10-01` |
| 12 | `Chart - Superhost Share Trend` | Line | `mart_executive_kpis` | X = `month_start`; Y = **Average** of `superhost_share`; filter `month_start <= 2021-10-01` |
| 13 | `Chart - Review Volume by Room Type` | Line | `mart_market_monthly` | X = `month_start`; Y = **Sum** of `reviews`; breakout `room_type`; filter `month_start <= 2021-10-01` |
| 14 | `Chart - Listing Age Cohorts` | Bar | `dim_listings` | Group by `listing_age_cohort`; Summarize **Count** |

### Question descriptions

Use these in the **Description** field when saving each question.

| Question | Description |
| --- | --- |
| `KPI - Total Listings` | Count of listings in the 2021-11-19 Airbnb Berlin snapshot. One row per listing; use this as the denominator for listing-level shares. |
| `KPI - Total Hosts` | Count of host profiles in the snapshot. One row per host; hosts with no listings are retained. |
| `KPI - Total Reviews` | Count of distinct reviews in the review fact. One row per review; duplicate reviews are removed upstream. |
| `KPI - Active Listings (12m)` | Listings with at least one review in the trailing 12 months ending 2021-11-19. One row per listing; this is not a review count. |
| `KPI - Avg Nightly Price` | Average source nightly price across listings, excluding zero-price and p99.5 outliers. One row per listing; the source currency is not normalized. |
| `Chart - Supply and Host Growth` | Monthly cumulative listing and host counts from the dbt month spine. One row per month; values are cumulative, not new additions. |
| `Chart - New Listings per Month` | Listings created in each month, through 2021-10 to exclude the partial snapshot month. One row per month. |
| `Chart - Monthly Reviews` | Reviews submitted per month through 2021-10. One row per month; early months have few or zero reviews. |
| `Chart - Room Type Mix` | Listings by standardized room type in the current snapshot. One row per room type. |
| `Chart - Sentiment Mix` | Reviews by source sentiment category. One row per review; unknown means the source did not provide a sentiment. |
| `Chart - Avg Sentiment Trend` | Monthly mean sentiment score (positive=1, neutral=0, negative=-1) through 2021-10. One row per month; unknown reviews are excluded from the mean. |
| `Chart - Superhost Share Trend` | Share of cumulative listings whose host is a superhost, by month through 2021-10. One row per month. |
| `Chart - Review Volume by Room Type` | Monthly reviews by listing room type through 2021-10. One row per month and room type; each review belongs to one room type. |
| `Chart - Listing Age Cohorts` | Listings by age cohort as of 2021-11-19. One row per listing; cohorts are derived from listing creation date. |

### Expected unfiltered values

| Card | Expected |
| --- | --- |
| Total Listings | `17,499` |
| Total Hosts | `14,111` |
| Total Reviews | `410,283` |
| Active Listings (12m) | `6,050` |
| Avg Nightly Price | `70.41` (median `55`) |
| Room Type Mix | Entire home/apt `9,890`; Private room `7,233`; Shared room `211`; Hotel room `165` |
| Sentiment Mix | Positive `232,554`; Neutral `147,255`; Negative `30,090`; Unknown `384` |
| New Listings, 2021-10 | `1,246` |
| Reviews, 2021-10 | `5,110` |
| Avg Sentiment, 2021-10 | `0.43` |
| Superhost Share, 2021-10 | `17.4%` |
| Review Volume by Room Type, 2021-10 | Entire home/apt `3,478`; Private room `1,458`; Hotel room `93`; Shared room `81` |
| Listing Age Cohorts | 3–5 years `6,135`; < 1 year `4,819`; 1–2 years `4,158`; 6+ years `2,387` |

### Layout

```text
Row 1: KPI - Total Listings | KPI - Total Hosts | KPI - Total Reviews | KPI - Active Listings | KPI - Avg Nightly Price
Row 2: Chart - Supply and Host Growth (2/3) | Chart - Room Type Mix (1/3)
Row 3: Chart - New Listings per Month | Chart - Monthly Reviews | Chart - Avg Sentiment Trend
Row 4: Chart - Review Volume by Room Type (2/3) | Chart - Sentiment Mix (1/3)
Row 5: Chart - Superhost Share Trend (1/2) | Chart - Listing Age Cohorts (1/2)
```

**Dashboard filter:** `Month range` (Date filter, "Date range") mapped to
`month_start` on cards 6, 7, 8, 11, 12, and 13. Set the default range
explicitly to `2009-01-01` → `2021-11-01`; do not use a relative "past N years"
preset, because the data ends in 2021 and a relative preset evaluated in 2026
returns nothing. KPI cards 1–5 and the all-time mix cards 9, 10, and 14 do not
respond to this filter; label the KPI row "Current snapshot" so the behavior is
obvious.

---

## 2. Supply and Pricing

**Purpose:** price distribution, room-type benchmarks, minimum-night segments,
and superhost pricing comparisons.

**Sources:** `Model - Listings`, `mart_price_bands`,
`mart_room_type_benchmark`.

### Cards

| # | Saved question | Visualization | Source | Build |
| ---: | --- | --- | --- | --- |
| 1 | `KPI - Total Listings` | Number | `Model - Listings` | Summarize **Count** |
| 2 | `KPI - Median Nightly Price` | Number | Native SQL | Fixed KPI; see Appendix A |
| 3 | `KPI - Avg Nightly Price (excl. outliers)` | Number | `Model - Listings` | Filter `is_price_outlier` = false; **Average** of `price` |
| 4 | `KPI - Outlier Listings` | Number | `Model - Listings` | Filter `is_price_outlier` = true; **Count** |
| 5 | `KPI - Superhost Listings` | Number | `Model - Listings` | Filter `is_superhost` = true; **Count** |
| 6 | `Chart - Listings by Price Band` | Bar | `Model - Listings` | Group by `price_band`; **Count**. Order bands `<30`, `30-49`, `50-74`, `75-99`, `100-149`, `150-249`, `250+` |
| 7 | `Chart - Price Band by Room Type` | Bar (stacked) | `mart_price_bands` | X = `price_band`; Y = **Sum** of `listing_count`; breakout `room_type` |
| 8 | `Chart - Room Type Price Benchmark` | Bar | `mart_room_type_benchmark` | X = `room_type`; Y = **Average** of `median_price`; add **Average** of `p90_price` as a second series |
| 9 | `Chart - Supply Share by Room Type` | Pie | `mart_room_type_benchmark` | Group by `room_type`; **Sum** of `listing_count` |
| 10 | `Chart - Minimum Nights Distribution` | Bar | `Model - Listings` | Group by `minimum_nights_band`; **Count**. Order `1`, `2-6`, `7-29`, `30+` |
| 11 | `Chart - Active Share by Price Band` | Bar | `mart_price_bands` | Group by `price_band`; **Average** of `pct_active` |
| 12 | `Chart - Superhost Share by Price Band` | Bar | `mart_price_bands` | Group by `price_band`; **Average** of `pct_superhost` |
| 13 | `Table - Room Type Benchmark` | Table | `mart_room_type_benchmark` | All columns; one row per room type |

### Question descriptions

| Question | Description |
| --- | --- |
| `KPI - Total Listings` | Count of listings matching the selected Supply filters. One row per listing; use this as the denominator for supply shares on this dashboard. |
| `KPI - Median Nightly Price` | Median source nightly price across non-outlier listings. One row per listing; robust to extreme prices. Fixed card, not filtered by the dashboard. |
| `KPI - Avg Nightly Price (excl. outliers)` | Mean source nightly price across non-outlier listings matching the selected filters. One row per listing; sensitive to high prices. |
| `KPI - Outlier Listings` | Listings flagged as zero-price or above the p99.5 price for their room type. One row per listing; outliers stay in the data and are excluded from price averages. |
| `KPI - Superhost Listings` | Listings whose host is a superhost. One row per listing; 15 hosts have unknown superhost status and are excluded from the true-filter count. |
| `Chart - Listings by Price Band` | Listings by derived price band, in band order. One row per listing; the chart collapses to one bar when the Price band filter is applied. |
| `Chart - Price Band by Room Type` | Listings by price band and room type. One row per price band and room type; the spine is zero-filled, so all 28 combinations exist. |
| `Chart - Room Type Price Benchmark` | Median and p90 source nightly price by room type, excluding outliers. One row per room type; p90 shows the high-price tail. |
| `Chart - Supply Share by Room Type` | Share of the 17,499-listing snapshot by room type. One row per room type; shares sum to 100%. |
| `Chart - Minimum Nights Distribution` | Listings by minimum-night band. One row per listing; zero minimum nights are normalized to one upstream. |
| `Chart - Active Share by Price Band` | Unweighted average of room-type active shares within each price band. One row per price band; active means a review in the trailing 12 months. |
| `Chart - Superhost Share by Price Band` | Unweighted average of room-type superhost shares within each price band. One row per price band; not a listing-weighted share. |
| `Table - Room Type Benchmark` | One row per room type with supply share, price distribution, review volume, sentiment, superhost share, and active share. |

### Expected unfiltered values

| Card | Expected |
| --- | --- |
| Total Listings | `17,499` |
| Median Nightly Price | `55` |
| Avg Nightly Price | `70.41` |
| Outlier Listings | `97` |
| Superhost Listings | `2,738` (15.6%) |
| Listings by Price Band | `<30` `2,509`; `30-49` `4,849`; `50-74` `4,319`; `75-99` `2,551`; `100-149` `1,850`; `150-249` `1,036`; `250+` `385` |
| Room Type Benchmark | Entire home/apt: median `75`, p90 `156`; Private room: `35`, `70`; Shared room: `30`, `98`; Hotel room: `155`, `326.4` |
| Supply Share | Entire home/apt `56.5%`; Private room `41.3%`; Shared room `1.2%`; Hotel room `0.9%` |
| Minimum Nights | `1` `4,045`; `2-6` `10,027`; `7-29` `2,078`; `30+` `1,349` |
| Active Share by Price Band | `19.7%`, `49.0%`, `43.8%`, `39.7%`, `44.8%`, `30.6%`, `22.5%` |
| Superhost Share by Price Band | `7.9%`, `6.8%`, `23.6%`, `12.6%`, `11.6%`, `13.0%`, `21.4%` |

### Layout

```text
Row 1: 5 KPI cards
Row 2: Chart - Listings by Price Band (1/2) | Chart - Supply Share by Room Type (1/2)
Row 3: Chart - Price Band by Room Type (2/3) | Chart - Minimum Nights Distribution (1/3)
Row 4: Chart - Room Type Price Benchmark (1/2) | Chart - Active Share by Price Band (1/2)
Row 5: Chart - Superhost Share by Price Band (1/2) | Table - Room Type Benchmark (1/2)
```

### Filters

| Dashboard filter | Type | Maps to |
| --- | --- | --- |
| `Room type` | Text or Category | `room_type` on cards 1, 3, 4, 5, 6, 7, 8, 9, 10, 13 |
| `Price band` | Text or Category | `price_band` on cards 1, 3, 4, 5, 6, 7, 11, 12 |
| `Minimum nights band` | Text or Category | `minimum_nights_band` on cards 1, 3, 4, 5, 6, 10 |
| `Superhost` | Boolean | `is_superhost` on cards 1, 3, 4, 6, 10 |
| `Price range` | Number | `price` on cards 1, 3, 4, 5, 6, 10 |

The fixed median card (2) does not respond to dashboard filters, and card 5
(Superhost Listings) is defined by superhost status, so the `Superhost` filter
is intentionally omitted from it. Cards 8, 9, 11, 12, and 13 do not contain
every filter column; map only the filters each query actually exposes.

---

## 3. Guest Experience

**Purpose:** review volume and seasonality, sentiment, and keyword topic
mentions across guest comments.

**Sources:** `Model - Reviews`, `Model - Reviews with listing attributes`,
`mart_review_topics`.

### Cards

| # | Saved question | Visualization | Source | Build |
| ---: | --- | --- | --- | --- |
| 1 | `KPI - Total Reviews` | Number | `Model - Reviews` | **Count** |
| 2 | `KPI - Positive Review Share` | Number | Native SQL | Fixed KPI; see Appendix A |
| 3 | `KPI - Negative Review Share` | Number | Native SQL | Fixed KPI; see Appendix A |
| 4 | `KPI - Avg Sentiment Score` | Number | `Model - Reviews` | **Average** of `sentiment_score` |
| 5 | `KPI - Reviews in 2021` | Number | `Model - Reviews` | Filter `review_year` = 2021; **Count** |
| 6 | `Chart - Review Volume by Month` | Line | `Model - Reviews` | X = `review_month`; **Count**; filter `review_month <= 2021-10-01` |
| 7 | `Chart - Sentiment Mix` | Pie | `Model - Reviews` | Group by `review_sentiment`; **Count** |
| 8 | `Chart - Sentiment by Month` | Bar (stacked) | `Model - Reviews` | X = `review_month`; **Count**; breakout `review_sentiment`; filter `review_month <= 2021-10-01` |
| 9 | `Chart - Reviews by Room Type` | Bar | `Model - Reviews with listing attributes` | Group by `room_type`; **Count** |
| 10 | `Chart - Review Length` | Histogram | `Model - Reviews` | X = `review_length`; filter `has_comment` = true |
| 11 | `Chart - Topic Mentions` | Bar | `mart_review_topics` | Group by `topic`; **Sum** of `mentions`; sort descending |
| 12 | `Chart - Topic Mention Rate Trend` | Line | `mart_review_topics` | X = `month_start`; **Average** of `mention_rate`; breakout `topic`; filter `month_start` between `2019-11-01` and `2021-10-01` |
| 13 | `Chart - Negative Mentions by Topic` | Bar | `mart_review_topics` | Group by `topic`; **Average** of `pct_negative`; sort descending |
| 14 | `Table - Topic Detail` | Table | `mart_review_topics` | `month_start`, `topic`, `mentions`, `mention_rate`, `avg_sentiment`, `pct_negative`; filter `month_start` between `2020-11-01` and `2021-10-01`; sort `mentions` descending |

### Question descriptions

| Question | Description |
| --- | --- |
| `KPI - Total Reviews` | Count of distinct reviews matching the selected Guest filters. One row per review; duplicate reviews are removed upstream. |
| `KPI - Positive Review Share` | Positive reviews divided by all reviews. One row per review; the denominator includes neutral, negative, and unknown sentiment. Fixed card. |
| `KPI - Negative Review Share` | Negative reviews divided by all reviews. One row per review; the denominator includes positive, neutral, and unknown sentiment. Fixed card. |
| `KPI - Avg Sentiment Score` | Mean sentiment score (positive=1, neutral=0, negative=-1) for the filtered reviews. One row per review; unknown reviews are excluded. |
| `KPI - Reviews in 2021` | Reviews submitted in calendar year 2021 matching the selected filters. One row per review. |
| `Chart - Review Volume by Month` | Reviews submitted per month through 2021-10. One row per month; 2021-11 is excluded because review data ends in October. |
| `Chart - Sentiment Mix` | Reviews by source sentiment category. One row per review; unknown means no source sentiment. |
| `Chart - Sentiment by Month` | Reviews by month and sentiment category through 2021-10. One row per month and sentiment. |
| `Chart - Reviews by Room Type` | Reviews grouped by the room type of the reviewed listing. One row per review; each review belongs to one listing and one room type. |
| `Chart - Review Length` | Distribution of comment length in characters for reviews with comments. One row per review; reviews without comments are excluded. |
| `Chart - Topic Mentions` | Keyword-topic mentions across review comments. One row per month and topic in the source; totals exceed the review count because one review can mention multiple topics. |
| `Chart - Topic Mention Rate Trend` | Average monthly share of comment-bearing reviews that mention each topic, for the last 24 complete months. One row per month and topic; unweighted average of monthly rates. |
| `Chart - Negative Mentions by Topic` | Average share of topic mentions with negative sentiment, by topic. One row per month and topic rolled up; unweighted average across months. |
| `Table - Topic Detail` | Monthly topic mentions, mention rate, average sentiment, and negative share for the last 12 complete months. One row per month and topic. |

### Expected unfiltered values

| Card | Expected |
| --- | --- |
| Total Reviews | `410,283` |
| Positive Review Share | `56.68%` |
| Negative Review Share | `7.33%` |
| Avg Sentiment Score | `0.494` |
| Reviews in 2021 | `47,356` |
| Sentiment Mix | Positive `232,554`; Neutral `147,255`; Negative `30,090`; Unknown `384` |
| Reviews by Room Type | Entire home/apt `261,438`; Private room `138,356`; Shared room `6,078`; Hotel room `4,411` |
| Reviews with Comments | `409,697` (99.9%) |
| Topic Mentions | Location `150,557`; Host `109,692`; Cleanliness `100,973`; Transport `66,742`; Check-in `43,206`; Noise `43,035`; Kitchen `21,356`; Bed `19,276`; Bathroom `17,805`; WiFi `8,810`; Breakfast `6,585` |
| Total Topic Mentions | `588,037` (reviews can match more than one topic) |

### Layout

```text
Row 1: 5 KPI cards
Row 2: Chart - Review Volume by Month (2/3) | Chart - Sentiment Mix (1/3)
Row 3: Chart - Sentiment by Month | Chart - Reviews by Room Type | Chart - Review Length
Row 4: Chart - Topic Mentions (2/3) | Chart - Negative Mentions by Topic (1/3)
Row 5: Chart - Topic Mention Rate Trend (full width)
Row 6: Table - Topic Detail (full width)
```

### Filters

| Dashboard filter | Type | Maps to |
| --- | --- | --- |
| `Review date` | Date | `review_date` on cards 1, 4, 6, 7, 8, 9, 10 |
| `Review month` | Date | `month_start` on cards 11, 12, 13, 14 |
| `Room type` | Text or Category | `room_type` on card 9 |
| `Sentiment` | Text or Category | `review_sentiment` on cards 1, 6, 8, 9 |
| `Has comment` | Boolean | `has_comment` on cards 1, 6, 8, 9, 10 |
| `Topic` | Text or Category | `topic` on cards 11, 12, 13, 14 |

Topic cards cannot be filtered by room type or sentiment: `mart_review_topics`
is aggregated at month × topic grain. Do not force those filters onto them.

---

## 4. Host Portfolio

**Purpose:** portfolio concentration, professional host segments, and
superhost performance.

**Sources:** `Model - Hosts`, `dim_hosts`, `mart_host_performance`.

### Cards

| # | Saved question | Visualization | Source | Build |
| ---: | --- | --- | --- | --- |
| 1 | `KPI - Total Hosts` | Number | `Model - Hosts` | **Count** |
| 2 | `KPI - Superhosts` | Number | `Model - Hosts` | Filter `is_superhost` = true; **Count** |
| 3 | `KPI - Single-listing Hosts` | Number | `Model - Hosts` | Filter `host_segment` = `Single listing`; **Count** |
| 4 | `KPI - Professional+ Hosts` | Number | `Model - Hosts` | Filter `host_segment` is `Professional`, `Large professional`, or `Enterprise`; **Count** |
| 5 | `KPI - Avg Reviews per Host` | Number | `Model - Hosts` | **Average** of `total_reviews` |
| 6 | `Chart - Hosts by Segment` | Bar | `Model - Hosts` | Group by `host_segment`; **Count** |
| 7 | `Chart - Avg Listings per Host by Segment` | Bar | `Model - Hosts` | Group by `host_segment`; **Average** of `listing_count` |
| 8 | `Chart - Avg Reviews per Host by Segment` | Bar | `Model - Hosts` | Group by `host_segment`; **Average** of `total_reviews` |
| 9 | `Chart - New Hosts per Month` | Line | `dim_hosts` | X = `host_created_at` grouped by month; **Count**; filter `host_created_at >= 2015-01-01` |
| 10 | `Chart - Superhost Performance` | Bar | `Model - Hosts` | Group by `is_superhost`; **Average** of `total_reviews` |
| 11 | `Chart - Hosts by Segment and Superhost` | Bar (stacked) | `Model - Hosts` | Group by `host_segment`; **Count**; breakout `is_superhost` |
| 12 | `Chart - Portfolio Size` | Histogram | `Model - Hosts` | X = `listing_count` |
| 13 | `Table - Top Hosts` | Table | `Model - Hosts` | `host_name`, `host_segment`, `is_superhost`, `listing_count`, `active_listing_count`, `total_reviews`, `avg_reviews_per_listing`, `avg_sentiment`; sort `total_reviews` desc; limit 100 |

### Question descriptions

| Question | Description |
| --- | --- |
| `KPI - Total Hosts` | Count of host profiles matching the selected Host filters. One row per host; hosts with no listings are retained. |
| `KPI - Superhosts` | Hosts whose superhost flag is true. One row per host; 15 hosts with unknown status are excluded. |
| `KPI - Single-listing Hosts` | Hosts with exactly one listing in the snapshot. One row per host; this is a host count, not a listing count. |
| `KPI - Professional+ Hosts` | Hosts in the Professional, Large professional, or Enterprise segments. One row per host; segments are based on listing count. |
| `KPI - Avg Reviews per Host` | Mean total reviews per host across all of the host's listings. One row per host; not a per-listing average. |
| `Chart - Hosts by Segment` | Hosts by portfolio segment. One row per host; these are host-grain counts and will not match listing-grain segment counts. |
| `Chart - Avg Listings per Host by Segment` | Mean number of listings per host within each segment. One row per host; host-grain calculation. |
| `Chart - Avg Reviews per Host by Segment` | Mean total reviews per host within each segment. One row per host; host-grain calculation. |
| `Chart - New Hosts per Month` | Host profiles created per month from 2015 onward. One row per host; this is new hosts, not cumulative hosts. |
| `Chart - Superhost Performance` | Average total reviews per host for superhosts vs non-superhosts. One row per host; includes an unclassified group for 15 hosts with unknown status. |
| `Chart - Hosts by Segment and Superhost` | Host counts by segment and superhost status. One row per host; the stacked bars sum to the host total. |
| `Chart - Portfolio Size` | Distribution of hosts by number of listings. One row per host; most hosts have one listing and the maximum is 75. |
| `Table - Top Hosts` | Top 100 hosts by total reviews with portfolio size, active listings, and sentiment. One row per host. |

### Expected unfiltered values

| Card | Expected |
| --- | --- |
| Total Hosts | `14,111` |
| Superhosts | `1,920` (13.6%; 15 hosts have unknown status) |
| Single-listing Hosts | `12,666` |
| Professional+ Hosts | `204` (Professional `144` + Large professional `46` + Enterprise `14`) |
| Avg Reviews per Host | `29.08` |
| Hosts by Segment | Single listing `12,666`; Small portfolio `1,241`; Professional `144`; Large professional `46`; Enterprise `14` |
| Avg Listings by Segment | `1.00`, `2.32`, `6.16`, `12.59`, `34.50` |
| Avg Reviews by Segment | `18.7`, `81.0`, `267.3`, `508.6`, `800.1` |
| Superhost vs Non-superhost Avg Reviews | `96.7` vs `18.4` |
| Portfolio Size | Most hosts have `1` listing; the maximum is `75` |

> Host-grain segment counts (cards 1–8, 10–13) are not the same as
> listing-grain segment counts in the Listing Explorer. A host in the
> `Enterprise` segment can own many listings, so the listing count by segment
> is larger than the host count by segment.

### Layout

```text
Row 1: 5 KPI cards
Row 2: Chart - Hosts by Segment (1/2) | Chart - Superhost Performance (1/2)
Row 3: Chart - Avg Listings per Host by Segment | Chart - Avg Reviews per Host by Segment | Chart - Portfolio Size
Row 4: Chart - New Hosts per Month (2/3) | Chart - Hosts by Segment and Superhost (1/3)
Row 5: Table - Top Hosts (full width)
```

### Filters

| Dashboard filter | Type | Maps to |
| --- | --- | --- |
| `Host segment` | Text or Category | `host_segment` on cards 1, 2, 5–8, 10–13 |
| `Superhost` | Boolean | `is_superhost` on cards 1, 3–8, 10–13 |
| `Minimum listings` | Number | `listing_count` on cards 1–8, 10–13 |
| `Host created date` | Date | `host_created_at` on card 9 (default `2015-01-01` → `2021-11-19`) |
| `Host name` | Text | `host_name` on card 13 |

Card 2 is **defined by** superhost status, so do not map the `Superhost` filter
to it. Cards 3 and 4 are **defined by** segment status, so do not map the
`Host segment` filter to them. Card 9 uses `dim_hosts.host_created_at`, not the
`mart_host_performance` model, so only the date filter applies there.

---

## 5. Listing Explorer

**Purpose:** one-row-per-listing drill-down for price, activity, review
volume, and sentiment.

**Source:** `Model - Listings` (all columns from
`analytics.mart_listing_performance`).

### Cards

| # | Saved question | Visualization | Build |
| ---: | --- | --- | --- |
| 1 | `KPI - Listings in View` | Number | **Count** of rows (responds to every dashboard filter) |
| 2 | `KPI - Avg Price in View` | Number | Filter `is_price_outlier` = false; **Average** of `price` |
| 3 | `KPI - Avg Reviews in View` | Number | **Average** of `review_count` |
| 4 | `KPI - Active Listings in View` | Number | Filter `is_active_last_12m` = true; **Count** |
| 5 | `KPI - Zero-review Listings` | Number | Filter `review_count` = 0; **Count** |
| 6 | `Chart - Price vs Review Count` | Scatter | X = `price`; Y = `review_count`; filter `is_price_outlier` = false and `is_active_last_12m` = true |
| 7 | `Chart - Listings by Room Type` | Bar | Group by `room_type`; **Count** |
| 8 | `Chart - Listings by Price Band` | Bar | Group by `price_band`; **Count** |
| 9 | `Chart - Review Count Distribution` | Histogram | X = `review_count` |
| 10 | `Chart - Active Listings by Host Segment` | Bar | Filter `is_active_last_12m` = true; group by `host_segment`; **Count** |
| 11 | `Chart - Listings by Minimum Nights` | Bar | Group by `minimum_nights_band`; **Count** |
| 12 | `Table - Listing Detail` | Table | `listing_id`, `listing_name`, `room_type`, `price`, `price_band`, `minimum_nights`, `host_name`, `host_segment`, `is_superhost`, `review_count`, `review_count_12m`, `avg_sentiment`, `pct_positive`, `last_review_date`, `is_active_last_12m`, `days_since_last_review`; sort `review_count` desc; limit 200; enable download |

### Question descriptions

| Question | Description |
| --- | --- |
| `KPI - Listings in View` | Count of listings matching the selected Listing Explorer filters. One row per listing; responds to every dashboard filter and is the denominator for listing-level shares. |
| `KPI - Avg Price in View` | Mean source nightly price of filtered listings, excluding outliers. One row per listing; currency is not normalized. |
| `KPI - Avg Reviews in View` | Mean lifetime review count per filtered listing. One row per listing; this is not a monthly review rate. |
| `KPI - Active Listings in View` | Filtered listings with at least one review in the trailing 12 months. One row per listing; the Active last 12m filter is fixed to true. |
| `KPI - Zero-review Listings` | Filtered listings with no reviews. One row per listing; includes new and inactive listings. |
| `Chart - Price vs Review Count` | Scatter of active, non-outlier listings: nightly price versus lifetime review count. One point per listing; not a time series. |
| `Chart - Listings by Room Type` | Filtered listings by room type. One row per listing; the chart collapses to one bar when the Room type filter is applied. |
| `Chart - Listings by Price Band` | Filtered listings by price band. One row per listing; the chart collapses to one bar when the Price band filter is applied. |
| `Chart - Review Count Distribution` | Distribution of lifetime review counts across filtered listings. One row per listing; helpful for spotting the long tail of highly reviewed listings. |
| `Chart - Active Listings by Host Segment` | Active filtered listings by host portfolio segment. One row per listing; this is listing-grain, not host-grain. |
| `Chart - Listings by Minimum Nights` | Filtered listings by minimum-night band. One row per listing; zero minimum nights are normalized to one upstream. |
| `Table - Listing Detail` | One row per listing with price, host, portfolio segment, activity, lifetime and 12-month reviews, sentiment, and recency for drill-down and verification. |

### Expected unfiltered values

| Card | Expected |
| --- | --- |
| Listings in View | `17,499` |
| Avg Price in View | `70.41` |
| Avg Reviews in View | `23.45` |
| Active Listings in View | `6,050` |
| Zero-review Listings | `3,254` |
| Listings by Room Type | Entire home/apt `9,890`; Private room `7,233`; Shared room `211`; Hotel room `165` |
| Active Listings by Host Segment | Single listing `3,453`; Small portfolio `1,349`; Professional `591`; Large professional `396`; Enterprise `261` |

### Layout

```text
Row 1: 5 KPI cards
Row 2: Chart - Price vs Review Count (2/3) | Chart - Listings by Room Type (1/3)
Row 3: Chart - Listings by Price Band | Chart - Review Count Distribution | Chart - Listings by Minimum Nights
Row 4: Chart - Active Listings by Host Segment (1/2) | [reserved for a second breakdown] (1/2)
Row 5: Table - Listing Detail (full width)
```

### Filters

This is the dashboard where every filter should work. Map each one to every
card that exposes the column:

| Dashboard filter | Type | Maps to |
| --- | --- | --- |
| `Room type` | Text or Category | `room_type` |
| `Price band` | Text or Category | `price_band` |
| `Minimum nights band` | Text or Category | `minimum_nights_band` |
| `Superhost` | Boolean | `is_superhost` |
| `Host segment` | Text or Category | `host_segment` |
| `Active last 12m` | Boolean | `is_active_last_12m` |
| `Price range` | Number | `price` |
| `Listing search` | Text | `listing_name` (contains) |

KPI cards 1–3 should respond to every filter. Card 4 (Active Listings) and
cards 6 and 10 already hard-filter `is_active_last_12m = true`; mapping the
`Active last 12m` dashboard filter to them is harmless but redundant. Cards 7,
8, and 11 group by the dimension they filter on, so selecting that filter
collapses the chart to one bar. Card 10 groups by `host_segment`, so the
`Host segment` filter collapses it to one bar. The detail table should respond
to all filters.

---

## Filter mapping matrix

Use this during dashboard QA. A filter only affects a card when the card's
query includes the mapped column.

| Filter | Executive | Supply | Guest | Host | Listing |
| --- | :---: | :---: | :---: | :---: | :---: |
| Date / month range | Yes | — | Yes | Yes | — |
| Host created date | — | — | — | Yes | — |
| Room type | — | Yes | Partial | — | Yes |
| Price band | — | Yes | — | — | Yes |
| Minimum nights band | — | Yes | — | — | Yes |
| Superhost | — | Yes | — | Yes | Yes |
| Host segment | — | — | — | Yes | Yes |
| Sentiment | — | — | Yes | — | — |
| Topic | — | — | Yes | — | — |
| Active last 12m | — | — | — | — | Yes |
| Price range | — | Yes | — | — | Yes |
| Text search | — | — | — | Host name | Listing name |

"Partial" means the filter applies only to cards built on the joined review
model; `mart_review_topics` is month × topic and cannot accept room type or
sentiment filters.

---

## Formatting rules

- **KPI cards:** number visualization, no grouping, 0–2 decimals. Percentages
  show one decimal and a `%` suffix.
- **Currency:** the source price is unnormalized. Label it "price units" or
  "source price" rather than `$` if you want to be strict; the source data is
  Berlin Airbnb pricing and is conventionally treated as EUR. Choose one and
  keep it consistent across all cards.
- **Pie charts:** show the legend and percentage labels; hide the "total" row.
- **Bar charts:** sort popularity charts descending. For price bands and
  minimum-night bands, use the explicit band order, not alphabetical.
- **Line charts:** month on the X-axis, one series per room type or sentiment.
  Cap review trends at `2021-10-01`.
- **Tables:** hide technical IDs unless they are useful, set a row limit, and
  enable downloads on `Table - Listing Detail` and `Table - Top Hosts`.
- **Chart colors:** use one consistent color per room type across dashboards.
  Set it in the card visualization settings, not per dashboard.

### Sorting price and minimum-night bands

Alphabetical sorting produces `<30, 100-149, 150-249, 250+, 30-49, ...`. Use
one of these fixes:

1. In the chart settings, set a custom sort order for the band dimension.
2. Add a custom column `price_band_order` with a `CASE` expression
   (`<30` → 1, `30-49` → 2, …, `250+` → 7), group by both columns, sort by the
   order column, and hide it.
3. Use the native SQL alternative in Appendix B, accepting that the card
   cannot accept dashboard filters.

---

## QA checklist

Run these in order after building each dashboard.

### Data reconciliation

- [ ] `KPI - Total Listings` = `17,499`
- [ ] `KPI - Total Hosts` = `14,111`
- [ ] `KPI - Total Reviews` = `410,283`
- [ ] Room type counts sum to `17,499`
- [ ] Sentiment counts sum to `410,283`
- [ ] Price band counts sum to `17,499`
- [ ] Host segment counts on the host dashboard sum to `14,111`
- [ ] Listing-grain host segment counts sum to `17,499`
- [ ] Topic mentions total `588,037` (not unique reviews)

### Filter behavior

- [ ] No filters selected: every card loads without error and matches the
      expected values above.
- [ ] Apply `Room type = Entire home/apt`: listing count becomes `9,890`;
      review count becomes `261,438` on cards that expose room type.
- [ ] Apply `Price band = 50-74`: listing count becomes `4,319`.
- [ ] Apply `Superhost = true`: listing count becomes `2,738`; host count
      becomes `1,920` on the host dashboard.
- [ ] Apply `Host segment = Enterprise`: host count becomes `14`.
- [ ] Apply `Sentiment = positive`: review count becomes `232,554`.
- [ ] Clear every filter: values return to the unfiltered baseline.
- [ ] Multi-value filters (if enabled): Count cards return the sum of the
      selected values; Average cards recompute across the selected rows.

### Visual and access checks

- [ ] Every card has a description explaining its grain.
- [ ] No card shows "There was a problem displaying this chart."
- [ ] The date range filter does not include `2021-11` on review trend cards.
- [ ] The `metabase` user cannot see `staging` in the data browser.
- [ ] All five dashboards are saved in the `Airbnb Analytics` collection.

---

## Known gotchas

1. **2021-11 is partial.** Supply marts include a November 2021 row because
   the listing snapshot is 2021-11-19. Review data ends in October 2021.
   Exclude `2021-11` from review trends; label supply charts "through the
   2021-11-19 snapshot".
2. **Price outliers stay in the data.** `is_price_outlier = true` marks zero
   prices and prices above the p99.5 for the room type (97 rows). Filter them
   out of price averages. Do not delete them.
3. **Superhost is nullable.** `is_superhost` can be NULL when the source did
   not disclose the status (15 hosts). A filter `is_superhost = true` excludes
   NULLs, which is correct. Do not coerce NULL to false in Metabase.
4. **Host grain vs listing grain.** `Model - Hosts` has one row per host;
   `Model - Listings` has one row per listing. Segment charts on the two
   dashboards will not match, and that is expected.
5. **`staging` is not a reporting schema.** Do not build cards on
   `staging.*`. The `metabase` user has no `USAGE` there, and the dbt contract
   treats `analytics` as the only BI surface.
6. **Native SQL cards do not accept dashboard filters.** The ratio and median
   KPI cards in Appendix A are fixed. If you need them filterable, rebuild
   them as query-builder cards or add Field Filter variables and map them.
7. **Metabase caching.** If a card shows stale values after a `dbt build`,
   use the card menu → **Refresh** or clear the dashboard cache. The data is
   read live from Postgres unless caching is enabled in admin settings.
8. **Relative date filters are evaluated against today.** The dataset ends in
   2021, so presets such as "Past 12 months" or "Previous 24 months" return
   nothing in 2026. Use absolute ranges for every dashboard filter and card
   filter. For timestamp/date columns the safe end dates are `2021-10-31`
   for reviews and `2021-11-19` for supply; for `month_start` columns use the
   first of the month (`2021-10-01` for reviews, `2021-11-01` for supply).

---

## Appendix A — Native SQL KPI cards

These cards are intentionally fixed (no dashboard filters). Save each as a
native SQL question on the `Airbnb Analytics` database.

### Median nightly price

```sql
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM analytics.dim_listings
WHERE NOT is_price_outlier;
```

Expected: `55`.

### Positive review share

```sql
SELECT
    COUNT(*) FILTER (WHERE review_sentiment = 'positive')::numeric
        / NULLIF(COUNT(*), 0) AS positive_share
FROM analytics.fct_reviews;
```

Expected: `0.5668` — format as `56.7%`.

### Negative review share

```sql
SELECT
    COUNT(*) FILTER (WHERE review_sentiment = 'negative')::numeric
        / NULLIF(COUNT(*), 0) AS negative_share
FROM analytics.fct_reviews;
```

Expected: `0.0733` — format as `7.3%`.

### Active listing share (optional)

```sql
SELECT
    COUNT(*) FILTER (WHERE is_active_last_12m)::numeric
        / NULLIF(COUNT(*), 0) AS active_share
FROM analytics.mart_listing_performance;
```

Expected: `0.3457` — format as `34.6%`.

---

## Appendix B — Native SQL ordered distributions

Use these only if the custom sort order in the query builder is unavailable.
They cannot accept dashboard filters because they have no template tags.

### Listings by price band, in band order

```sql
SELECT
    price_band,
    COUNT(*) AS listings
FROM analytics.dim_listings
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

### Listings by minimum-night band, in band order

```sql
SELECT
    minimum_nights_band,
    COUNT(*) AS listings
FROM analytics.dim_listings
GROUP BY minimum_nights_band
ORDER BY CASE minimum_nights_band
    WHEN '1' THEN 1
    WHEN '2-6' THEN 2
    WHEN '7-29' THEN 3
    ELSE 4
END;
```

---

## Appendix C — Optional card: full moon sentiment

`mart_full_moon_reviews` is a novelty mart and is not part of the executive
dashboard. If you want it on Guest Experience, add:

- `Chart - Full Moon Sentiment` — group by `is_full_moon`; **Sum** of
  `reviews`; breakout `review_sentiment`. Expected: `8` rows across two
  full-moon groups. Label it "Novelty analysis, not causal."

---

## Build order checklist

1. Connect the database and wait for the first sync to finish.
2. Create the `Airbnb Analytics` collection.
3. Create the four models.
4. Build Executive Overview cards 1–14 and save them with the `KPI -`,
   `Chart -` prefixes.
5. Create the Executive Overview dashboard, add the cards in layout order,
   add the `Month range` filter, and save.
6. Repeat for Supply and Pricing, Guest Experience, Host Portfolio, and
   Listing Explorer.
7. Apply the formatting rules and set consistent room-type colors.
8. Run the QA checklist section by section.
9. Update `airbnb_dbt/models/dashboards.yml` with the real dashboard URLs
   (`http://localhost:3000/dashboard/<id>`) if they differ from the
   placeholders.
10. Save the definitions for Git: `uv run python scripts\export_metabase.py`,
    then commit `metabase/export/`. The full workflow is in
    [`../metabase/README.md`](../metabase/README.md).
