# Metabase Dashboard Filter Automation

**Status:** applied on 2026-11-12 against Metabase `v0.64.3.5` and BigQuery;
post-apply verification passed with 0 failures.

**Verdict:** the 23 Field Filter dashboard filters on all five dashboards are
created and mapped entirely through the Metabase API. No manual UI mapping was
required. The only work that cannot be done purely by adding dashboard
parameters is the two text-search filters (`Host name`, `Listing name`),
because their target cards do not yet contain a text template tag.

---

## 1. Project snapshot

| Layer | Implementation |
| --- | --- |
| Warehouse | Google BigQuery `orbital-scene-422012-h0`, datasets `raw`/`staging`/`analytics`/`snapshots` |
| Transformation | dbt Core 1.12 / dbt-bigquery 1.12; staging → intermediate → analytics marts |
| Orchestration | Dagster 1.13 at port `3001`; one `@dbt_assets` asset runs `dbt build` |
| BI | Metabase OSS `v0.64.3.5`, app DB stored in local PostgreSQL (`metabase` database) |
| Analytics models | 3 staging views, 3 intermediate views, 12 analytics relations (dims, facts, marts) |
| Metabase content | root collection `Airbnb Analytics` → 5 subcollections → 66 saved questions → 5 dashboards |
| Persistence | `metabase/definitions.json` (seed input), `metabase/export/` (JSON snapshot), `metabase/backups/*.dump` (exact restore) |

Everything relevant to filtering is already in place:

- Every question is native SQL with Field Filter template tags.
- Every card aliases its BigQuery table and each tag stores the full
  `table.column` alias, which is required by the BigQuery driver.
- Every card's `parameters` array mirrors its tags.
- Every tag is bound to a numeric Metabase field ID resolved from live metadata.
- Dashboard/card IDs are stable and documented.

---

## 2. Current filter state

Live API audit after the apply (`GET /api/dashboard/{id}`):

| # | Dashboard | Cards | Dashboard filters | Mapped cards |
| ---: | --- | ---: | --- | ---: |
| 1 | Executive Overview | 14 | `Month range` (`date/all-options`) | 6 |
| 2 | Supply and Pricing | 13 | 5 | 38 |
| 3 | Guest Experience | 14 | 6 | 33 |
| 4 | Host Portfolio | 13 | 4 | 32 |
| 5 | Listing Explorer | 12 | 7 | 80 |

The Executive filter is mapped to the six `month_start` trend cards. KPIs and
all-time mix cards intentionally have no date variable.

All tags on all five dashboards exist. The tags, mapped fields, and widget types
match `docs/METABASE_SQL_WITH_FILTERS.md`. The dashboard-level parameters and
their `parameter_mappings` are created by the filter script.

---

## 3. What was verified live

A throwaway dashboard was created, five filters were mapped to
`KPI - Total Listings` (card 54), each filter was executed against the
dashboard card, and the dashboard was deleted again. A second test covered
category dropdown values and `number/>=`. A third covered a date filter and a
category filter spanning two different source fields.

| Filter applied | Parameter type | Result |
| --- | --- | ---: |
| Room type = `Private room` | `string/=` | 7,233 |
| Price band = `30-49` | `string/=` | 4,849 |
| Minimum nights band = `2-6` | `string/=` | 10,027 |
| Superhost = `true` | `boolean/=` | 2,738 |
| Price between `50` and `100` | `number/between` | 7,181 |
| Host segment = `Professional` | `string/=` | 144 |
| Superhost = `true` (host grain) | `boolean/=` | 1,920 |
| Minimum listings >= `10` | `number/>=` | 60 |

Additional observations:

- `string/=` with `values_query_type: "list"` returns live distinct values from
  the mapped field(s). Host segments came back as `Enterprise`,
  `Large professional`, `Professional`, `Single listing`, `Small portfolio`.
  Supply's `Room type` filter, mapped to both `dim_listings.room_type` and
  `mart_room_type_benchmark.room_type`, returned the four room types once each.
  `Topic` returned the 11 seeded topics.
- `number/between` and `number/>=` both work against a card tag whose widget
  type is `number/=`. The dashboard parameter type controls the SQL operator.
- A dashboard parameter with `sectionId` `string`, `number`, `boolean`, or
  `date` is accepted and persisted.
- A `date/all-options` filter accepted `2020-01-01~2021-10-01` and returned the
  expected 22 monthly rows on card 89.
- The mapping target
  `["dimension", ["template-tag", "<tag>"], {"stage-number": 0}]` works for
  every Field Filter tag.
- All three temporary dashboards were deleted; `GET /api/dashboard/7`, `/8`,
  and `/9` return HTTP 404. Before the apply, the five real dashboards reported
  1, 0, 0, 0, and 0 parameters respectively.
- A fresh application-database backup was taken before the first write:
  `metabase/backups/metabase_20261107_154845.dump`, and again immediately
  before the apply: `metabase/backups/metabase_20261107_161503.dump` (both
  gitignored, private).

### Post-apply verification

After the real apply, every dashboard reported the expected filter and mapping
counts, every string filter returned a non-empty value list, and every
representative filtered query executed:

| Check | Result |
| --- | --- |
| Supply KPI baseline | 17,499 |
| Room type = `Private room` | 7,233 |
| Price band = `30-49` | 4,849 |
| Minimum nights band = `2-6` | 10,027 |
| Superhost = `true` | 2,738 |
| Price between `50` and `100` | 7,181 |
| Guest KPI baseline | 410,283 |
| Guest sentiment = `positive` | 232,554 |
| Guest has comment = `true` | 409,697 |
| Host KPI baseline | 14,111 |
| Host segment = `Professional` | 144 |
| Host superhost = `true` | 1,920 |
| Minimum listings >= `10` | 60 |
| Listing KPI baseline | 17,499 |
| Active last 12m = `true` | 6,050 |
| Executed checks with errors or mismatches | 0 |

---

## 4. Filter plan

The mapping rule is mechanical: **one dashboard filter per template-tag name,
mapped to every card that exposes that tag**, minus the documented semantic
exclusions. Because the cards were built to the documented matrix, tag-based
mapping reproduces that matrix exactly.

### 4.1 Supply and Pricing — 5 filters, 38 mappings

| Filter | Type / section | Mapped cards | # |
| --- | --- | --- | ---: |
| Room type | `string/=`, `string`, list, multi | 2.1, 2.3–2.13 (all except 2.2) | 12 |
| Price band | `string/=`, `string`, list, multi | 2.1, 2.3, 2.4, 2.5, 2.6, 2.7, 2.10, 2.11, 2.12 | 9 |
| Minimum nights band | `string/=`, `string`, list, multi | 2.1, 2.3, 2.4, 2.5, 2.6, 2.10 | 6 |
| Superhost | `boolean/=`, `boolean` | 2.1, 2.3, 2.4, 2.6, 2.10 | 5 |
| Price range | `number/between`, `number` | 2.1, 2.3, 2.4, 2.5, 2.6, 2.10 | 6 |

Not filtered by design: 2.2 Median Nightly Price (fixed card),
2.5 Superhost Listings (defined by superhost status), and the room-type or
price-band share charts that would collapse to a single bar.

### 4.2 Guest Experience — 6 filters, 33 mappings

| Filter | Type / section | Mapped cards | # |
| --- | --- | --- | ---: |
| Review date | `date/all-options`, `date` | 3.1, 3.4–3.10 | 8 |
| Review month | `date/all-options`, `date` | 3.11–3.14 | 4 |
| Room type | `string/=`, `string`, list, multi | 3.9 | 1 |
| Sentiment | `string/=`, `string`, list, multi | 3.1, 3.4–3.10 | 8 |
| Has comment | `boolean/=`, `boolean` | 3.1, 3.4–3.10 | 8 |
| Topic | `string/=`, `string`, list, multi | 3.11–3.14 | 4 |

Not filtered by design: 3.2 and 3.3 (fixed share cards), and the topic marts
cannot accept room type or sentiment because they are aggregated at
month × topic grain.

### 4.3 Host Portfolio — 4 core filters, 32 mappings

| Filter | Type / section | Mapped cards | # |
| --- | --- | --- | ---: |
| Host segment | `string/=`, `string`, list, multi | 4.1, 4.2, 4.5–4.8, 4.10–4.13 | 10 |
| Superhost | `boolean/=`, `boolean` | 4.1, 4.3–4.8, 4.12, 4.13 | 9 |
| Minimum listings | `number/>=`, `number` | 4.1–4.8, 4.10–4.13 | 12 |
| Host created date | `date/all-options`, `date` | 4.9 only | 1 |

Not filtered by design: 4.2 (defined by superhost), 4.3 and 4.4 (defined by
segment), 4.10 and 4.11 (group by superhost). Card 4.9 uses
`dim_hosts.host_created_at`, not the host mart, so only the date filter applies.

### 4.4 Listing Explorer — 7 core filters, 80 mappings

| Filter | Type / section | Mapped cards | # |
| --- | --- | --- | ---: |
| Room type | `string/=`, `string`, list, multi | 5.1–5.12 | 12 |
| Price band | `string/=`, `string`, list, multi | 5.1–5.12 | 12 |
| Minimum nights band | `string/=`, `string`, list, multi | 5.1–5.12 | 12 |
| Superhost | `boolean/=`, `boolean` | 5.1–5.12 | 12 |
| Host segment | `string/=`, `string`, list, multi | 5.1–5.9, 5.11, 5.12 (not 5.10) | 11 |
| Active last 12m | `boolean/=`, `boolean` | 5.1–5.3, 5.5, 5.7–5.9, 5.11, 5.12 (not 5.4, 5.6, 5.10) | 9 |
| Price range | `number/between`, `number` | 5.1–5.12 | 12 |

Not filtered by design: 5.4, 5.6, 5.10 already hard-filter
`is_active_last_12m = true`; 5.10 groups by `host_segment`, so that filter is
left off. Filters that match a chart's own grouping column collapse the chart
to one bar, which is expected.

### 4.5 Totals

| Scope | Filters | Mappings |
| --- | ---: | ---: |
| Five dashboards, Field Filters only | 23 | 189 |
| Plus text search (after card edits) | 25 | 191 |

---

## 5. The only gap: text search

The documented filter sets include two text-search filters:

| Dashboard | Filter | Target card | Missing piece |
| --- | --- | --- | --- |
| Host Portfolio | Host name (`Contains`) | 4.13 `Table - Top Hosts` | card 93 has no `host_name` template tag |
| Listing Explorer | Listing search (`Contains`) | 5.12 `Table - Listing Detail` | card 105 has no `listing_name` template tag |

The seeder deliberately omitted text-search variables. To add them:

1. Append an optional clause to the card SQL:
   `[[AND LOWER(host_name) LIKE '%' || LOWER({{host_name}}) || '%']]` (and the
   listing equivalent).
2. Add a plain **Text** template tag (not a Field Filter) plus a matching card
   parameter of type `string/contains`.
3. Add a dashboard parameter of type `string/contains`, `sectionId: "string"`,
   `values_query_type: "none"`.
4. Map the card with
   `["variable", ["template-tag", "host_name"]]` — exactly two elements, no
   `stage-number`.

This is automatable, but it edits saved questions (`PUT /api/card/{id}`), so it
carries more risk than adding dashboard parameters. Recommendation: ship the
23 Field Filters first, then decide on the two text filters as a separate
change.

---

## 6. Implementation design

The implementation is `scripts/add_dashboard_filters.py`. It does not modify the
existing seeder and only touches the five dashboards listed above:

1. Load `.env`; use `127.0.0.1`.
2. Discover each dashboard by name inside its collection.
3. Use a canonical filter spec per dashboard: name, slug, type, section ID,
   value-source mode, multi-select flag, target tag name, and an expected card
   count as a drift guard.
4. `GET /api/dashboard/{id}`; reuse an existing parameter by `slug`, otherwise
   create one with a random 8-character hex ID.
5. `GET /api/card/{id}` for every dashcard; read live template-tag names as the
   source of truth.
6. Build each dashcard's mapping list: preserve every existing mapping, add a
   mapping for each managed filter whose tag exists on that card, and remove
   stale mappings for managed filters whose tag disappeared.
7. `PUT /api/dashboard/{id}` with the full `dashcards` list, the updated
   `parameters` list, and the existing `tabs` array. The API replaces these
   collections wholesale, so the script must send all three.
8. Print a plan and mapping counts. `--dry-run` performs every read and prints
   the payload summary without writing. `--dashboard supply|guest|host|listing`
   scopes one dashboard.

The dry run currently reports the exact expected totals: 38 + 33 + 32 + 80 =
183 mappings, with every filter matching its expected card count.

Suggested payload for a category filter:

```json
{
  "id": "a1b2c3d4",
  "name": "Room type",
  "slug": "room_type",
  "type": "string/=",
  "sectionId": "string",
  "values_query_type": "list",
  "isMultiSelect": true,
  "default": null
}
```

Suggested mapping:

```json
{
  "parameter_id": "a1b2c3d4",
  "card_id": 54,
  "target": ["dimension", ["template-tag", "room_type"], {"stage-number": 0}]
}
```

### Idempotency

- Filters are matched by `slug`, so a second run updates rather than
  duplicates.
- Existing mappings for other filters are preserved.
- Existing dashcards keep their IDs, positions, visualization settings, and
  inline parameters.
- Executive Overview filters are managed like every other dashboard.
- Re-running after a manual edit keeps manual parameters that the script does
  not manage.

### Safety sequence

1. `.\scripts\backup_metabase.ps1`
2. `uv run python scripts\export_metabase.py` (pre-change snapshot)
3. `uv run python scripts\add_dashboard_filters.py --dry-run`
4. Run one dashboard, inspect in the UI, then run the rest.
5. `uv run python scripts\export_metabase.py` (post-change snapshot)
6. Commit the updated `metabase/export/` JSON.

---

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| `PUT /api/dashboard` replaces the full dashcards/parameters lists | Lost layout or mappings if a field is omitted | GET → modify → PUT; preserve `visualization_settings`, `inline_parameters`, `tabs`; dry-run diff; backup |
| Omitting `tabs` while sending `dashcards` | FK error or orphaned tab references | Always send the existing `tabs` array |
| Category filter renders as a text box | Poor UX | Set `values_query_type: "list"`; verified live values |
| Filter mapped to one field but used across many cards | Values list may merge fields | All mapped fields share the same domain; spot-check each dropdown |
| Number filter type mismatch | Query error | Verified `number/between` and `number/>=` against `number/=` tags |
| Boolean filter mapped as text | `boolean = character varying` error | Use `boolean/=` + `sectionId: "boolean"`; verified |
| Duplicate filters on rerun | Cluttered dashboard | Match by slug; update in place |
| Script overwrites manual filter work | Lost customization | Only manage the documented slugs; preserve everything else |
| Text-search card edit breaks a saved question | Broken card | Separate phase; export and back up first; test card query after edit |
| Metabase API is unversioned | Payload drift after upgrade | Pin `v0.64.3.5`; re-verify after upgrades |

---

## 8. QA / acceptance criteria

- [x] Supply: 5 filters, 38 mappings; no filter on 2.2.
- [x] Guest: 6 filters, 33 mappings; topic cards only accept month and topic.
- [x] Host: 4 core filters, 32 mappings; 4.9 accepts only the date filter.
- [x] Listing: 7 core filters, 80 mappings; 5.10 has no host-segment filter.
- [x] Executive: 1 filter and 6 mappings.
- [x] Every representative filter returns rows and every baseline still runs.
- [x] `KPI - Total Listings` (Supply) returns 17,499 unfiltered, 7,233 for
  `Private room`, and 2,738 for superhost.
- [ ] Category filters show a dropdown in the browser; the API value lists are
  verified, visual confirmation is pending your dashboard check.
- [x] A second dry-run reports every filter and mapping as existing.
- [x] `metabase/export/manifest.json` still counts 5 dashboards and 66 cards.
- [x] No filter mapping references a tag that does not exist on its card.

---

## 9. Recommendation

The 22 Field Filters are applied and verified. The two text-search filters
remain a separate follow-up because they change saved SQL and use a different
mapping target shape (`["variable", ["template-tag", ...]]`).

The implementation is a standalone script so the existing seeder's
"filters are not created here" contract stays intact and the change is easy to
review. Re-running the script is idempotent: a second dry run reports every
filter as existing and every mapping count unchanged.

