# Metabase content: export, backup, and restore

This folder keeps the Metabase work reproducible outside the running container.

```text
metabase/
├── README.md
├── .gitignore
├── definitions.json          # 66 documented cards and 5 dashboards
├── dashboard_filters.json    # dashboard filter specs for the four non-Executive dashboards
├── backups/                  # gitignored pg_dump files
│   └── .gitkeep
└── export/                   # committed, Git-friendly JSON snapshot
    ├── manifest.json
    ├── collections/
    ├── cards/
    └── dashboards/
```

## What gets saved, and how big it is

| Artifact | What it contains | Current size | Commit to Git? |
| --- | --- | ---: | --- |
| `metabase/backups/*.dump` | Full Metabase application database (users, settings, collections, questions, dashboards) | ~1.1 MB per dump; app DB is 25 MB | **No** |
| `metabase/export/**/*.json` | Collections, questions/models, dashboards, SQL, visualization settings, filter mappings | 26.5 KB for 14 cards + 1 dashboard; under 1 MB for the full 66-card set | **Yes** |
| `.env` | `METABASE_URL`, `METABASE_API_KEY` | Tiny | **No** |

The JSON export is deliberately cleaned: timestamps, view counts, last-editor
identity, public-sharing tokens, and permission flags are removed. It contains
no user accounts or passwords. The `.dump` file *does* contain account data and
application secrets, so keep it private.

## Export the definitions to JSON

The local `.env` already contains `METABASE_URL` and `METABASE_API_KEY`. The
key is in the Administrators group so it can read every collection. Never commit
`.env`.

From `Postgres Version/`:

```powershell
uv run python scripts\export_metabase.py
```

The script:

1. Reads `METABASE_URL` and `METABASE_API_KEY` from `.env`.
2. Starts at collection `5` (`Airbnb Analytics`).
3. Recursively walks subcollections.
4. Fetches every question, model, and dashboard through the Metabase API.
5. Rewrites `metabase/export/` and `metabase/export/manifest.json`.

Options:

```powershell
# Export a different root collection
uv run python scripts\export_metabase.py --collection-id 5

# Include archived items
uv run python scripts\export_metabase.py --include-archived
```

The export is read-only. It never changes anything in Metabase.

Do not edit files under `metabase/export/` by hand: the next export replaces
them. Make changes in Metabase, then re-run the exporter.

## Seed the documented questions and dashboards

`metabase/definitions.json` contains the 66 documented cards, grouped by the
five dashboards. The seeder creates any missing collections, questions, and
dashboards through the Metabase API:

```powershell
# Preview what would be created
uv run python scripts\seed_metabase.py --dry-run

# Create everything (Executive Overview is skipped because it already exists)
uv run python scripts\seed_metabase.py

# Work on one dashboard only
uv run python scripts\seed_metabase.py --dashboard supply

# Reposition the cards to the generated grid layout
uv run python scripts\seed_metabase.py --dashboard supply --relayout
```

The seeder is idempotent by name:

- Existing cards are reused; it does not overwrite a card that already has the
  documented name.
- The four partially-created Supply cards are adopted and renamed to the
  documented `KPI - ...` names.
- Missing cards are created with native SQL and Field Filter template tags.
- The Executive Overview dashboard is not touched.
- Dashboard filters are **not** created in this pass. The cards are
  filter-ready; run `scripts/add_dashboard_filters.py` after seeding to create
  and map them.
- Text-search filters (`host_name`, `listing_name`) are omitted; the table
  cards work without them.

After seeding, run the exporter again and commit the updated
`metabase/export/`:

```powershell
uv run python scripts\export_metabase.py
```

### Add the dashboard filters

`metabase/dashboard_filters.json` contains the filter specs for Supply and
Pricing, Guest Experience, Host Portfolio, and Listing Explorer. The script
creates the dashboard parameters and maps them to every card that exposes the
matching template tag:

```powershell
# Preview the full plan; no writes
uv run python scripts\add_dashboard_filters.py --dry-run

# Apply one dashboard first
uv run python scripts\add_dashboard_filters.py --dashboard supply

# Apply all four
uv run python scripts\add_dashboard_filters.py
```

The script is idempotent by filter slug and preserves unrelated parameters,
mappings, layout, and tabs. It does not touch the Executive Overview dashboard,
which already has its manual date filter. Take an application-database backup
before the first real run. The full analysis is in
[`docs/METABASE_FILTER_AUTOMATION.md`](../docs/METABASE_FILTER_AUTOMATION.md).

### Create or replace the API key manually

If the key is lost:

1. Open Metabase → **Admin** → **Settings** → **Authentication** → **API Keys**.
2. **Create API Key**, name it `git-export`, assign the **Administrators** group.
3. Copy the key into `Postgres Version/.env`:

```dotenv
METABASE_URL=http://127.0.0.1:3000
METABASE_API_KEY=mb_...
```

> Use `127.0.0.1`, not `localhost`, in `METABASE_URL`. On Windows, Python
> resolves `localhost` to IPv6 first and falls back to IPv4, adding about two
> seconds to every API request. The browser can still use `localhost`.

## Back up the full application database

```powershell
.\scripts\backup_metabase.ps1
```

This runs `pg_dump -Fc` against the `metabase` database and writes
`metabase/backups/metabase_<timestamp>.dump`. It is the exact restore point.

Restore (destructive — replaces the current Metabase app DB):

```powershell
.\scripts\restore_metabase.ps1 -DumpFile .\metabase\backups\metabase_20261106_120000.dump
```

Type `RESTORE` when prompted, or pass `-Force`. The script stops Metabase,
recreates the `metabase` database, restores the dump, and waits for
`/api/health`. The analytics `airbnb` database is not touched.

When to use each:

| Need | Use |
| --- | --- |
| Review a change in a Git diff | JSON export |
| Publish dashboard definitions to GitHub | JSON export |
| Recover after a bad upgrade or accidental deletion | `.dump` restore |
| Move to another Metabase instance | `.dump` restore (same version), or Pro serialization |

## What to commit

Commit:

```text
metabase/definitions.json
metabase/dashboard_filters.json
metabase/export/manifest.json
metabase/export/collections/*.json
metabase/export/cards/*.json
metabase/export/dashboards/*.json
scripts/export_metabase.py
scripts/seed_metabase.py
scripts/add_dashboard_filters.py
scripts/backup_metabase.ps1
scripts/restore_metabase.ps1
```

Do not commit:

```text
.env
metabase/backups/*.dump
```

`metabase/.gitignore` already excludes the dump files.

## Native Git workflow: Metabase Pro serialization

Metabase's native **serialization** feature exports collections, questions, and
dashboards as YAML and imports them by stable entity ID. It is designed for
version control and staging-to-production workflows, but it is only available
on **Pro and Enterprise** plans. The current `metabase/metabase` OSS image does
not include it.

If you upgrade to Pro/Enterprise, the equivalent workflow is:

```powershell
# Export YAML
docker compose exec -T metabase java -jar /app/metabase.jar export /tmp/metabase_yaml
docker compose cp metabase:/tmp/metabase_yaml .\metabase\serialized
```

The exact CLI path inside the image may differ; use `docker compose exec metabase
ls /app` to confirm. The API endpoints are `/api/ee/serialization/export` and
`/api/ee/serialization/import` and require a Pro/Enterprise license.

## Security notes

- The Metabase admin password was shared during setup. Rotate it in Metabase →
  **Account Settings** if this conversation is stored anywhere shared.
- Treat `METABASE_API_KEY` like a password. It has admin read access.
- Treat every `.dump` file like a copy of the Metabase app database: it includes
  `core_user` rows (emails and password hashes) and `setting` values.
- The JSON export contains SQL and instance-local database/table/field IDs. It
  is safe to commit for this project, but review it before publishing a public
  repository.
