#!/usr/bin/env python3
"""Convert the Metabase card definitions from Postgres SQL to BigQuery SQL.

The converter is idempotent: Postgres-only constructs are rewritten once, and
every template tag receives a stable `analytics.<table>.<column>` field
reference (replacing the Postgres `field_id`).

Usage:
    uv run python scripts/convert_metabase_sql.py
    uv run python scripts/convert_metabase_sql.py --dry-run-bigquery
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = PROJECT_ROOT / "metabase" / "definitions.json"

# BigQuery cannot resolve Postgres field IDs. Map every tag to its physical
# column; most tags use the card's source table, with a few cross-table joins.
FIELD_OVERRIDES = {
    ("Chart - Reviews by Room Type", "room_type"): "analytics.dim_listings.room_type",
    ("Chart - Reviews by Room Type", "review_date"): "analytics.fct_reviews.review_date",
    ("Chart - Reviews by Room Type", "review_sentiment"): "analytics.fct_reviews.review_sentiment",
    ("Chart - Reviews by Room Type", "has_comment"): "analytics.fct_reviews.has_comment",
    ("Chart - Reviews by Room Type", "review_month"): "analytics.fct_reviews.review_month",
}

# The physical mart column is month_start even though the tag is review_month.
TAG_COLUMN_OVERRIDES = {
    ("mart_review_topics", "review_month"): "month_start",
}

POSTGRES_SYNTAX = re.compile(
    r"FILTER\s*\(|::|DATE_TRUNC\s*\(\s*'"
    r"|TO_CHAR|ISODOW|WITHIN\s+GROUP|~\*",
    re.IGNORECASE,
)

PERCENTILE_RE = re.compile(
    r"SELECT\s+PERCENTILE_CONT\((?P<p>[0-9.]+)\)\s+WITHIN\s+GROUP\s*"
    r"\(ORDER\s+BY\s+(?P<expr>[^)]+)\)\s+AS\s+(?P<alias>\w+)\s+FROM\s+(?P<body>.+?);?\s*$",
    re.IGNORECASE | re.DOTALL,
)

FILTER_RATIO_RE = re.compile(
    r"COUNT\(\*\)\s+FILTER\s*\(WHERE\s+(?P<cond>.+?)\)\s*::numeric\s*"
    r"/\s*NULLIF\(COUNT\(\*\),\s*0\)",
    re.IGNORECASE | re.DOTALL,
)

NUMERIC_CAST_RE = re.compile(r"(?P<expr>[A-Za-z_][A-Za-z0-9_.]*)::numeric", re.IGNORECASE)
DATE_TRUNC_RE = re.compile(
    r"DATE_TRUNC\(\s*'month'\s*,\s*(?P<expr>[A-Za-z_][A-Za-z0-9_.]*)\s*\)::date",
    re.IGNORECASE,
)
TIMESTAMP_DATE_RE = re.compile(
    r"\b(?P<column>host_created_at|listing_created_at|listing_updated_at|created_at|updated_at)"
    r"\s*(?P<op>>=|<=|>|<|=)\s*(?P<literal>DATE\s+'[^']+')",
    re.IGNORECASE,
)
TABLE_ALIAS_RE = re.compile(
    r"\b(?P<join>FROM|INNER\s+JOIN|LEFT\s+JOIN|RIGHT\s+JOIN)\s+"
    r"analytics\.(?P<table>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?!\s+AS\b)",
    re.IGNORECASE,
)


def add_table_aliases(sql: str) -> str:
    """Alias every BigQuery table so Metabase field filters can qualify columns.

    Metabase's BigQuery driver renders a field filter as `alias.column`.
    Without a table alias the driver emits the dataset path as one quoted
    identifier and BigQuery rejects it.
    """
    return TABLE_ALIAS_RE.sub(
        lambda match: (
            f"{match.group('join')} analytics.{match.group('table')} "
            f"AS {match.group('table')}"
        ),
        sql,
    )


def convert_sql(sql: str) -> str:
    percentile = PERCENTILE_RE.search(sql)
    if percentile:
        alias = percentile.group("alias")
        sql = (
            "SELECT\n"
            f"    MAX({alias}) AS {alias}\n"
            "FROM (\n"
            "    SELECT\n"
            f"        PERCENTILE_CONT({percentile.group('expr').strip()}, "
            f"{percentile.group('p')}) OVER () AS {alias}\n"
            f"    FROM {percentile.group('body').strip().rstrip(';')}\n"
            ");"
        )

    sql = FILTER_RATIO_RE.sub(
        lambda match: (
            f"SAFE_DIVIDE(COUNTIF({match.group('cond').strip()}), COUNT(*))"
        ),
        sql,
    )
    sql = DATE_TRUNC_RE.sub(
        lambda match: (
            f"DATE_TRUNC(DATE({match.group('expr')}), MONTH)"
        ),
        sql,
    )
    sql = NUMERIC_CAST_RE.sub(
        lambda match: f"CAST({match.group('expr')} AS FLOAT64)",
        sql,
    )
    sql = TIMESTAMP_DATE_RE.sub(
        lambda match: (
            f"DATE({match.group('column')}) {match.group('op')} {match.group('literal')}"
        ),
        sql,
    )
    sql = add_table_aliases(sql)
    return sql


def field_reference(card: dict, tag_name: str) -> str:
    override = FIELD_OVERRIDES.get((card["name"], tag_name))
    if override:
        return override
    column = TAG_COLUMN_OVERRIDES.get((card["source"], tag_name), tag_name)
    return f"analytics.{card['source']}.{column}"


def convert_definitions(data: dict) -> dict:
    data.pop("database_id", None)
    for dashboard in data["dashboards"]:
        for card in dashboard["cards"]:
            card["sql"] = convert_sql(card["sql"])
            for tag in card["tags"]:
                tag.pop("field_id", None)
                tag["field"] = field_reference(card, tag["name"])
                _, table, column = tag["field"].split(".", 2)
                tag["alias"] = f"{table}.{column}"
    return data


def dry_run_bigquery(data: dict) -> int:
    project = os.environ.get("GCP_PROJECT_ID", "orbital-scene-422012-h0")
    bq = shutil.which("bq") or "bq"
    failures = 0
    total = 0
    for dashboard in data["dashboards"]:
        for card in dashboard["cards"]:
            total += 1
            sql = re.sub(r"\[\[.*?\]\]", "", card["sql"], flags=re.DOTALL)
            sql = re.sub(r"\{\{[^}]+\}\}", "TRUE", sql)
            # bq is a .cmd shim on Windows; passing multi-line SQL as an
            # argument breaks quoting, so feed the query on stdin instead.
            result = subprocess.run(
                [
                    bq,
                    "query",
                    f"--project_id={project}",
                    "--use_legacy_sql=false",
                    "--dry_run",
                    "--format=none",
                ],
                input=sql,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if result.returncode != 0:
                failures += 1
                detail = "\n".join(
                    line
                    for line in (result.stderr or result.stdout).splitlines()
                    if "RequestsDependencyWarning" not in line
                    and "warnings.warn" not in line
                ).strip()
                print(f"FAIL  {dashboard['key']} {card['key']} {card['name']}")
                print(detail[:1500])
    print(f"BigQuery dry run: {total - failures}/{total} valid")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run-bigquery",
        action="store_true",
        help="Validate converted SQL with bq --dry_run instead of writing",
    )
    args = parser.parse_args()

    data = json.loads(DEFINITIONS.read_text(encoding="utf-8"))
    data = convert_definitions(data)

    if args.dry_run_bigquery:
        return dry_run_bigquery(data)

    remaining = [
        (dashboard["key"], card["key"], card["name"], card["sql"])
        for dashboard in data["dashboards"]
        for card in dashboard["cards"]
        if POSTGRES_SYNTAX.search(card["sql"])
    ]
    if remaining:
        for dashboard_key, card_key, name, sql in remaining:
            print(f"Postgres syntax remains in {dashboard_key} {card_key} {name}", file=sys.stderr)
            print(sql, file=sys.stderr)
        return 1

    DEFINITIONS.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    card_count = sum(len(dashboard["cards"]) for dashboard in data["dashboards"])
    print(
        f"Converted {card_count} cards in {len(data['dashboards'])} dashboards "
        f"to BigQuery SQL: {DEFINITIONS}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
