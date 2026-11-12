#!/usr/bin/env python3
"""Verify the Metabase service account can read analytics and nothing else.

Checks both metadata listing and query execution. Exits non-zero on failure.

Usage:
    uv run python scripts/check_metabase_access.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from google.api_core.exceptions import Forbidden
from google.cloud import bigquery

PROJECT_ROOT = Path(__file__).resolve().parents[1]
KEY_PATH = PROJECT_ROOT / ".secrets" / "metabase-bigquery-key.json"
PROJECT = "orbital-scene-422012-h0"
ALLOWED_DATASET = "analytics"
DENIED_DATASETS = ("raw", "staging", "snapshots")


def list_tables(client: bigquery.Client, dataset: str) -> list[str]:
    return [table.table_id for table in client.list_tables(dataset)]


def main() -> int:
    if not KEY_PATH.exists():
        print(f"Missing service account key: {KEY_PATH}", file=sys.stderr)
        return 2

    client = bigquery.Client.from_service_account_json(str(KEY_PATH), project=PROJECT)
    failures = 0

    try:
        analytics_tables = list_tables(client, ALLOWED_DATASET)
        if len(analytics_tables) == 12:
            print(f"PASS  list analytics tables ({len(analytics_tables)})")
        else:
            print(f"FAIL  analytics table count {len(analytics_tables)}, expected 12")
            failures += 1
    except Exception as exc:  # noqa: BLE001 - report the driver error verbatim
        print(f"FAIL  list analytics tables: {exc}")
        failures += 1

    for dataset in DENIED_DATASETS:
        try:
            list_tables(client, dataset)
            print(f"FAIL  list {dataset} tables: expected Forbidden")
            failures += 1
        except Forbidden:
            print(f"PASS  list {dataset} tables denied")
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL  list {dataset} tables: {exc}")
            failures += 1

    try:
        client.query(
            f"SELECT COUNT(*) FROM `{PROJECT}.{ALLOWED_DATASET}.dim_listings`"
        ).result(timeout=60)
        print("PASS  query analytics")
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL  query analytics: {exc}")
        failures += 1

    try:
        client.query(f"SELECT COUNT(*) FROM `{PROJECT}.raw.raw_listings`").result(
            timeout=60
        )
        print("FAIL  query raw: expected Forbidden")
        failures += 1
    except Forbidden:
        print("PASS  query raw denied")
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL  query raw: {exc}")
        failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
