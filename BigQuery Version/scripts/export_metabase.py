#!/usr/bin/env python3
"""Export the Airbnb Analytics Metabase collection to Git-friendly JSON.

The exporter reads METABASE_URL and METABASE_API_KEY from the project .env or
the process environment, walks the root collection and its subcollections, and
writes one JSON file per collection, question/model, and dashboard.

It is intentionally read-only: it never creates, updates, or deletes anything
in Metabase. Volatile fields (timestamps, view counts, last-editor identity,
public sharing tokens, permissions) are removed so the files diff cleanly in
Git. The export is for versioning and review, not a database backup.

Usage:
    uv run python scripts/export_metabase.py
    uv run python scripts/export_metabase.py --collection-id 5 --output metabase/export
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = PROJECT_ROOT / "metabase" / "export"
DEFAULT_COLLECTION_ID = 5
PAGE_SIZE = 200

CARD_FIELDS = (
    "id",
    "entity_id",
    "name",
    "description",
    "collection_id",
    "type",
    "query_type",
    "dataset",
    "display",
    "dataset_query",
    "visualization_settings",
    "parameters",
    "parameter_mappings",
    "database_id",
    "table_id",
    "archived",
    "card_schema",
)

DASHBOARD_FIELDS = (
    "id",
    "entity_id",
    "name",
    "description",
    "collection_id",
    "parameters",
    "width",
    "auto_apply_filters",
    "archived",
)

DASHCARD_FIELDS = (
    "id",
    "entity_id",
    "card_id",
    "dashboard_tab_id",
    "row",
    "col",
    "size_x",
    "size_y",
    "parameter_mappings",
    "visualization_settings",
    "inline_parameters",
)

COLLECTION_FIELDS = (
    "id",
    "entity_id",
    "name",
    "description",
    "location",
    "namespace",
    "parent_id",
    "archived",
)


def load_dotenv(path: Path) -> None:
    """Load simple KEY=VALUE lines without overriding existing environment."""
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def slugify(value: str, fallback: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return (slug[:60] or fallback).strip("-")


class MetabaseClient:
    def __init__(self, base_url: str, api_key: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    def get(self, path: str) -> dict:
        request = urllib.request.Request(
            self.base_url + path,
            headers={"X-API-Key": self.api_key, "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode())
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:500]
            raise RuntimeError(f"GET {path} failed with HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"GET {path} failed: {exc.reason}") from exc

    def collection_items(self, collection_id: int, include_archived: bool) -> list[dict]:
        items: list[dict] = []
        offset = 0
        while True:
            params = [
                ("models", "collection"),
                ("models", "card"),
                ("models", "dashboard"),
                ("models", "dataset"),
                ("models", "metric"),
                ("archived", "true" if include_archived else "false"),
                ("limit", str(PAGE_SIZE)),
                ("offset", str(offset)),
            ]
            path = f"/api/collection/{collection_id}/items?{urllib.parse.urlencode(params)}"
            payload = self.get(path)
            data = payload.get("data", [])
            items.extend(data)
            offset += len(data)
            total = payload.get("total")
            if not data or total is None or offset >= total:
                return items


def clean_card(card: dict) -> dict:
    return {field: card[field] for field in CARD_FIELDS if field in card}


def clean_dashboard(dashboard: dict) -> dict:
    cleaned = {field: dashboard[field] for field in DASHBOARD_FIELDS if field in dashboard}
    dashcards = []
    for dashcard in dashboard.get("dashcards", []):
        cleaned_dashcard = {
            field: dashcard[field] for field in DASHCARD_FIELDS if field in dashcard
        }
        embedded_card = dashcard.get("card") or {}
        if embedded_card.get("name"):
            cleaned_dashcard["card_name"] = embedded_card["name"]
        series = dashcard.get("series") or []
        if series:
            cleaned_dashcard["series_card_ids"] = [
                item.get("id") for item in series if item.get("id") is not None
            ]
        dashcards.append(cleaned_dashcard)
    cleaned["dashcards"] = dashcards
    cleaned["tabs"] = [
        {key: tab[key] for key in ("id", "entity_id", "name", "position") if key in tab}
        for tab in dashboard.get("tabs", [])
    ]
    return cleaned


def clean_collection(collection: dict) -> dict:
    return {
        field: collection[field] for field in COLLECTION_FIELDS if field in collection
    }


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--collection-id",
        type=int,
        default=DEFAULT_COLLECTION_ID,
        help=f"Root collection ID (default: {DEFAULT_COLLECTION_ID})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output directory (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument("--url", default=None, help="Metabase base URL")
    parser.add_argument(
        "--include-archived",
        action="store_true",
        help="Include archived collections, cards, and dashboards",
    )
    args = parser.parse_args()

    load_dotenv(PROJECT_ROOT / ".env")
    base_url = args.url or os.environ.get("METABASE_URL", "http://127.0.0.1:3000")
    api_key = os.environ.get("METABASE_API_KEY", "").strip()
    if not api_key:
        print(
            "METABASE_API_KEY is not set.\n"
            "Create an API key in Metabase: Admin -> Settings -> Authentication -> "
            "API Keys, add METABASE_API_KEY to the project .env, and rerun.",
            file=sys.stderr,
        )
        return 2

    client = MetabaseClient(base_url, api_key)
    try:
        properties = client.get("/api/session/properties")
        root_collection = client.get(f"/api/collection/{args.collection_id}")
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    output: Path = args.output
    if not output.is_absolute():
        output = PROJECT_ROOT / output
    for subdirectory in ("collections", "cards", "dashboards"):
        shutil.rmtree(output / subdirectory, ignore_errors=True)
        (output / subdirectory).mkdir(parents=True, exist_ok=True)

    collections: list[dict] = []
    cards: dict[int, dict] = {}
    dashboards: dict[int, dict] = {}
    queue = [args.collection_id]
    visited: set[int] = set()

    while queue:
        collection_id = queue.pop(0)
        if collection_id in visited:
            continue
        visited.add(collection_id)
        collection = client.get(f"/api/collection/{collection_id}")
        collections.append(collection)
        for item in client.collection_items(collection_id, args.include_archived):
            model = item.get("model")
            item_id = item.get("id")
            if item_id is None:
                continue
            if model == "collection":
                queue.append(item_id)
            elif model in {"card", "dataset", "metric"}:
                cards[item_id] = client.get(f"/api/card/{item_id}")
            elif model == "dashboard":
                dashboards[item_id] = client.get(f"/api/dashboard/{item_id}")

    collection_files = []
    for collection in collections:
        cleaned = clean_collection(collection)
        filename = f"{cleaned['id']:06d}-{slugify(cleaned.get('name', ''), 'collection')}.json"
        write_json(output / "collections" / filename, cleaned)
        collection_files.append(f"collections/{filename}")

    card_files = []
    for card_id in sorted(cards):
        cleaned = clean_card(cards[card_id])
        filename = f"{card_id:06d}-{slugify(cleaned.get('name', ''), 'card')}.json"
        write_json(output / "cards" / filename, cleaned)
        card_files.append(f"cards/{filename}")

    dashboard_files = []
    for dashboard_id in sorted(dashboards):
        cleaned = clean_dashboard(dashboards[dashboard_id])
        filename = (
            f"{dashboard_id:06d}-{slugify(cleaned.get('name', ''), 'dashboard')}.json"
        )
        write_json(output / "dashboards" / filename, cleaned)
        dashboard_files.append(f"dashboards/{filename}")

    manifest = {
        "exported_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "metabase_url": base_url,
        "metabase_version": (properties.get("version") or {}).get("tag"),
        "root_collection_id": args.collection_id,
        "root_collection_name": root_collection.get("name"),
        "include_archived": args.include_archived,
        "counts": {
            "collections": len(collections),
            "cards": len(cards),
            "dashboards": len(dashboards),
        },
        "files": {
            "collections": collection_files,
            "cards": card_files,
            "dashboards": dashboard_files,
        },
    }
    write_json(output / "manifest.json", manifest)

    total_bytes = sum(path.stat().st_size for path in output.rglob("*.json"))
    print(
        f"Exported {len(collections)} collection(s), {len(cards)} card(s), "
        f"and {len(dashboards)} dashboard(s) to {output}"
    )
    print(f"Total JSON size: {total_bytes / 1024:.1f} KB")
    print(f"Manifest: {output / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
