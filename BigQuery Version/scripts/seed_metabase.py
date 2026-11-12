#!/usr/bin/env python3
"""Create the documented Metabase collections, questions, and dashboards.

Reads metabase/definitions.json and uses the Metabase API to create missing
items against the live BigQuery database. Existing cards/dashboards are reused;
the four partially-created Supply cards are adopted and renamed to the
documented names. Dashboard filters are not created here; use
scripts/add_dashboard_filters.py for those.

Usage:
    uv run python scripts/seed_metabase.py --dry-run
    uv run python scripts/seed_metabase.py --dashboard supply
    uv run python scripts/seed_metabase.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = PROJECT_ROOT / "metabase" / "definitions.json"
EXPORT_DASHBOARDS = PROJECT_ROOT / "metabase" / "export" / "dashboards"
DATABASE_NAME = "Airbnb Analytics"
PAGE_SIZE = 200

ALIASES = {
    "KPI - Total Listings": ["Total Listings"],
    "KPI - Median Nightly Price": ["Median Nightly Price"],
    "KPI - Avg Nightly Price (excl. outliers)": ["Avg Nightly Price"],
    "KPI - Outlier Listings": ["Outlier Listings"],
}

FULL_WIDTH = {
    "Chart - Topic Mention Rate Trend",
    "Table - Topic Detail",
    "Table - Listing Detail",
    "Table - Top Hosts",
    "Table - Room Type Benchmark",
}


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


class MetabaseClient:
    def __init__(self, base_url: str, api_key: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key

    def request(self, method: str, path: str, payload: dict | None = None):
        data = json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(
            self.base_url + path,
            data=data,
            headers={
                "X-API-Key": self.api_key,
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                raw = response.read().decode()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")[:1000]
            raise RuntimeError(f"{method} {path} -> HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"{method} {path} failed: {exc.reason}") from exc

    def get(self, path: str):
        return self.request("GET", path)

    def post(self, path: str, payload: dict):
        return self.request("POST", path, payload)

    def put(self, path: str, payload: dict):
        return self.request("PUT", path, payload)

    def collection_items(self, collection_id: int | str, model: str) -> list[dict]:
        items: list[dict] = []
        offset = 0
        while True:
            query = urllib.parse.urlencode(
                [("models", model), ("archived", "false"), ("limit", PAGE_SIZE), ("offset", offset)]
            )
            payload = self.get(f"/api/collection/{collection_id}/items?{query}")
            data = payload.get("data", []) if isinstance(payload, dict) else payload
            items.extend(data)
            offset += len(data)
            total = payload.get("total") if isinstance(payload, dict) else None
            if not data or total is None or offset >= total:
                return items


def find_database(client: MetabaseClient) -> dict:
    payload = client.get("/api/database")
    databases = payload if isinstance(payload, list) else payload.get("data", [])
    for database in databases:
        if database.get("name") == DATABASE_NAME:
            return database
    raise RuntimeError(
        f"Database {DATABASE_NAME!r} not found. Run scripts/setup_metabase.py first."
    )


def load_field_ids(client: MetabaseClient, database_id: int) -> dict[tuple[str, str, str], int]:
    metadata = client.get(f"/api/database/{database_id}/metadata")
    field_ids: dict[tuple[str, str, str], int] = {}
    for table in metadata.get("tables", []):
        schema = table.get("schema")
        table_name = table.get("name")
        for field in table.get("fields", []):
            field_ids[(schema, table_name, field["name"])] = field["id"]
    return field_ids


def resolve_field_id(
    field_ids: dict[tuple[str, str, str], int], card_name: str, tag_name: str, reference: str
) -> int:
    parts = reference.split(".", 2)
    if len(parts) != 3:
        raise RuntimeError(
            f"Card {card_name!r} tag {tag_name!r} has invalid field reference {reference!r}"
        )
    schema, table, column = parts
    key = (schema, table, column)
    if key not in field_ids:
        raise RuntimeError(
            f"Card {card_name!r} tag {tag_name!r} requests missing field "
            f"{schema}.{table}.{column}"
        )
    return field_ids[key]


def build_card_payload(
    card: dict,
    collection_id: int,
    database_id: int,
    field_ids: dict[tuple[str, str, str], int],
) -> dict:
    template_tags = []
    parameters = []
    for tag in card["tags"]:
        tag_id = str(uuid.uuid4())
        field_id = resolve_field_id(field_ids, card["name"], tag["name"], tag["field"])
        template_tags.append(
            {
                "id": tag_id,
                "type": "dimension",
                "widget-type": tag["widget_type"],
                "name": tag["name"],
                "display-name": tag["display_name"],
                "dimension": ["field", {"lib/uuid": str(uuid.uuid4())}, field_id],
            }
        )
        parameters.append(
            {
                "id": tag_id,
                "type": tag["widget_type"],
                "target": ["dimension", ["template-tag", tag["name"]]],
                "name": tag["display_name"],
                "slug": tag["name"],
                "isMultiSelect": tag["widget_type"] != "boolean/=",
            }
        )
    return {
        "name": card["name"],
        "description": card["description"] or None,
        "collection_id": collection_id,
        "display": card["display"],
        "dataset_query": {
            "database": database_id,
            "lib/type": "mbql/query",
            "stages": [
                {
                    "lib/type": "mbql.stage/native",
                    "native": card["sql"],
                    "template-tags": template_tags,
                }
            ],
        },
        "visualization_settings": card["visualization_settings"],
        "parameters": parameters,
        "type": "question",
        "parameter_mappings": [],
    }


def find_collection(client: MetabaseClient, parent_id: int | str, name: str) -> dict | None:
    for item in client.collection_items(parent_id, "collection"):
        if item.get("name") == name:
            return item
    return None


def ensure_root_collection(
    client: MetabaseClient, name: str, dry_run: bool
) -> dict:
    existing = find_collection(client, "root", name)
    if existing:
        print(f"root collection exists: {name} (id={existing['id']})")
        return existing
    print(f"root collection create: {name}")
    if dry_run:
        return {"id": -1, "name": name}
    return client.post(
        "/api/collection",
        {
            "name": name,
            "description": "Airbnb analytics collections on BigQuery.",
            "parent_id": None,
        },
    )


def ensure_collection(
    client: MetabaseClient, parent_id: int, name: str, description: str, dry_run: bool
) -> dict:
    if dry_run and parent_id < 0:
        print(f"  collection create: {name}")
        return {"id": -1, "name": name}
    existing = find_collection(client, parent_id, name)
    if existing:
        print(f"  collection exists: {name} (id={existing['id']})")
        return existing
    print(f"  collection create: {name}")
    if dry_run:
        return {"id": -1, "name": name}
    return client.post(
        "/api/collection",
        {"name": name, "description": description, "parent_id": parent_id},
    )


def find_card(client: MetabaseClient, collection_id: int, name: str) -> dict | None:
    for item in client.collection_items(collection_id, "card"):
        if item.get("name") == name:
            return item
    return None


def resolve_card(
    client: MetabaseClient,
    collection_id: int,
    card: dict,
    dry_run: bool,
    database_id: int,
    field_ids: dict[tuple[str, str, str], int],
) -> dict:
    if dry_run and collection_id < 0:
        print(f"    card create: {card['name']}")
        return {"id": -1, "name": card["name"], "display": card["display"]}

    existing = find_card(client, collection_id, card["name"])
    if existing:
        print(f"    card exists: {card['name']} (id={existing['id']})")
        return {**existing, "name": card["name"], "display": card["display"]}

    for alias in ALIASES.get(card["name"], []):
        existing = find_card(client, collection_id, alias)
        if existing:
            print(f"    card adopt: {alias!r} -> {card['name']!r} (id={existing['id']})")
            if not dry_run:
                payload = build_card_payload(card, collection_id, database_id, field_ids)
                payload.pop("collection_id", None)
                client.put(f"/api/card/{existing['id']}", payload)
            return {**existing, "name": card["name"], "display": card["display"]}

    print(f"    card create: {card['name']}")
    if dry_run:
        return {"id": -1, "name": card["name"], "display": card["display"]}
    created = client.post(
        "/api/card", build_card_payload(card, collection_id, database_id, field_ids)
    )
    return created


def find_dashboard(client: MetabaseClient, collection_id: int, name: str) -> dict | None:
    for item in client.collection_items(collection_id, "dashboard"):
        if item.get("name") == name:
            return item
    return None


def ensure_dashboard(
    client: MetabaseClient, collection_id: int, meta: dict, dry_run: bool
) -> dict:
    if dry_run and collection_id < 0:
        print(f"  dashboard create: {meta['dashboard']}")
        return {"id": -1, "name": meta["dashboard"], "dashcards": []}
    existing = find_dashboard(client, collection_id, meta["dashboard"])
    if existing:
        print(f"  dashboard exists: {meta['dashboard']} (id={existing['id']})")
        return existing
    print(f"  dashboard create: {meta['dashboard']}")
    if dry_run:
        return {"id": -1, "name": meta["dashboard"], "dashcards": []}
    return client.post(
        "/api/dashboard",
        {
            "name": meta["dashboard"],
            "description": meta["description"],
            "collection_id": collection_id,
            "parameters": [],
        },
    )


def load_layouts() -> dict[str, dict[str, dict]]:
    """Return dashboard name -> card name -> exported dashcard layout."""
    layouts: dict[str, dict[str, dict]] = {}
    for path in sorted(EXPORT_DASHBOARDS.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        layouts[payload["name"]] = {
            dashcard["card_name"]: dashcard
            for dashcard in payload.get("dashcards", [])
            if dashcard.get("card_name")
        }
    return layouts


def dashboard_layout(layouts: dict[str, dict[str, dict]], dashboard: dict) -> dict[str, dict]:
    name = dashboard["dashboard"]
    if name not in layouts:
        raise RuntimeError(f"No layout export found for dashboard {name!r}")
    layout = layouts[name]
    for card in dashboard["cards"]:
        if card["name"] not in layout:
            raise RuntimeError(
                f"Dashboard {name!r} layout is missing card {card['name']!r}"
            )
    return layout


def fallback_positions(cards: list[dict]) -> list[tuple[int, int, int, int]]:
    positions = []
    row = 0
    col = 0
    row_height = 0
    kpi_index = 0
    for card in cards:
        if card["name"].startswith("KPI -"):
            width = [5, 5, 5, 5, 4][kpi_index] if kpi_index < 5 else 4
            height = 3
            kpi_index += 1
        elif card["display"] == "table" or card["name"] in FULL_WIDTH:
            width = 24
            height = 7 if card["display"] == "table" else 6
        else:
            width = 12
            height = 6

        if col + width > 24:
            row += row_height
            col = 0
            row_height = 0
        positions.append((row, col, width, height))
        col += width
        row_height = max(row_height, height)
        if col >= 24:
            row += row_height
            col = 0
            row_height = 0
    return positions


def populate_dashboard(
    client: MetabaseClient,
    dashboard_id: int,
    cards: list[dict],
    layout: dict[str, dict],
    dry_run: bool,
    force_layout: bool = False,
) -> None:
    if dry_run or dashboard_id <= 0:
        print(f"    dashboard {dashboard_id}: would ensure {len(cards)} cards")
        return

    dashboard = client.get(f"/api/dashboard/{dashboard_id}")
    existing_dashcards = {dc.get("card_id"): dc for dc in dashboard.get("dashcards", [])}
    target_card_ids = {card["id"] for card in cards if card.get("id", -1) > 0}
    all_present = target_card_ids and target_card_ids.issubset(existing_dashcards)

    if all_present and not force_layout:
        print(f"    dashboard {dashboard_id}: all {len(cards)} cards already present; layout left untouched")
        return

    payload_cards = []
    next_negative = -1
    for card in cards:
        entry = layout[card["name"]]
        existing = existing_dashcards.get(card.get("id"))
        dashcard = {
            "id": existing["id"] if existing else next_negative,
            "card_id": card["id"],
            "row": entry.get("row", 0),
            "col": entry.get("col", 0),
            "size_x": entry.get("size_x", 12),
            "size_y": entry.get("size_y", 6),
            "parameter_mappings": existing.get("parameter_mappings", []) if existing else [],
            "visualization_settings": entry.get("visualization_settings", {}),
            "inline_parameters": existing.get("inline_parameters", []) if existing else [],
        }
        if entry.get("dashboard_tab_id") is not None:
            dashcard["dashboard_tab_id"] = entry["dashboard_tab_id"]
        if not existing:
            next_negative -= 1
        payload_cards.append(dashcard)

    # Preserve any existing dashboard cards that are not part of this definition.
    for card_id, dashcard in existing_dashcards.items():
        if card_id not in target_card_ids:
            payload_cards.append(
                {
                    "id": dashcard["id"],
                    "card_id": card_id,
                    "row": dashcard.get("row", 0),
                    "col": dashcard.get("col", 0),
                    "size_x": dashcard.get("size_x", 12),
                    "size_y": dashcard.get("size_y", 6),
                    "parameter_mappings": dashcard.get("parameter_mappings", []),
                    "visualization_settings": dashcard.get("visualization_settings", {}),
                    "inline_parameters": dashcard.get("inline_parameters", []),
                }
            )

    client.put(
        f"/api/dashboard/{dashboard_id}",
        {
            "dashcards": payload_cards,
            "parameters": dashboard.get("parameters", []),
            "tabs": dashboard.get("tabs", []),
        },
    )
    print(f"    dashboard {dashboard_id}: ensured {len(payload_cards)} cards")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dashboard", help="Only seed one dashboard key (executive, supply, guest, host, listing)")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without writing")
    parser.add_argument("--relayout", action="store_true", help="Reposition all cards even if they are already present")
    args = parser.parse_args()

    load_dotenv(PROJECT_ROOT / ".env")
    base_url = os.environ.get("METABASE_URL", "http://127.0.0.1:3000")
    api_key = os.environ.get("METABASE_API_KEY", "").strip()
    if not api_key:
        print("METABASE_API_KEY is not set in the environment or .env", file=sys.stderr)
        return 2

    definitions = json.loads(DEFINITIONS.read_text(encoding="utf-8"))
    client = MetabaseClient(base_url, api_key)
    database = find_database(client)
    field_ids = load_field_ids(client, database["id"])
    layouts = load_layouts()

    selected = [
        dashboard
        for dashboard in definitions["dashboards"]
        if (args.dashboard is None or dashboard["key"] == args.dashboard)
        and not dashboard.get("skip", False)
    ]
    if not selected:
        print(f"No dashboard matched {args.dashboard!r}.")
        return 2

    root = ensure_root_collection(
        client, definitions.get("root_collection_name", "Airbnb Analytics"), args.dry_run
    )
    root_id = root["id"]

    collection_count = 1  # root collection
    card_count = 0
    dashboard_count = 0
    for dashboard in selected:
        print(f"\n[{dashboard['key']}] {dashboard['dashboard']}")
        layout = dashboard_layout(layouts, dashboard)
        collection = ensure_collection(
            client,
            root_id,
            dashboard["collection"],
            f"Questions and dashboard for {dashboard['dashboard']}.",
            args.dry_run,
        )
        collection_count += 1
        collection_id = collection["id"]

        cards = []
        for card in dashboard["cards"]:
            resolved = resolve_card(
                client, collection_id, card, args.dry_run, database["id"], field_ids
            )
            if resolved:
                cards.append(resolved)
                card_count += 1

        if args.dry_run:
            print(f"  dashboard would be ensured: {dashboard['dashboard']}")
            dashboard_count += 1
            continue

        dash = ensure_dashboard(client, collection_id, dashboard, args.dry_run)
        populate_dashboard(client, dash["id"], cards, layout, args.dry_run, args.relayout)
        dashboard_count += 1

    print(
        f"\nDone. collections={collection_count} cards={card_count} "
        f"dashboards={dashboard_count} database={database['id']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
