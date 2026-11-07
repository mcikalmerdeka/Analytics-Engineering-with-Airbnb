#!/usr/bin/env python3
"""Add the documented dashboard filters to the four remaining Metabase dashboards.

The cards already expose Field Filter template tags. This script creates the
dashboard parameters and maps them to every card that exposes the matching tag.
It is idempotent: filters are matched by slug, existing mappings are preserved,
and dashboards the script does not manage are never touched.

Filter definitions live in `metabase/dashboard_filters.json`.

The Executive Overview dashboard is intentionally excluded; its date filter was
added manually.

Usage:
    uv run python scripts/add_dashboard_filters.py --dry-run
    uv run python scripts/add_dashboard_filters.py --dashboard supply
    uv run python scripts/add_dashboard_filters.py

Take an application-database backup before the first real run:
    .\\scripts\\backup_metabase.ps1
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFINITIONS = PROJECT_ROOT / "metabase" / "dashboard_filters.json"
PAGE_SIZE = 200


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

    def put(self, path: str, payload: dict):
        return self.request("PUT", path, payload)

    def collection_items(self, collection_id: int, model: str) -> list[dict]:
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


def load_definitions() -> tuple[int, dict[str, dict]]:
    definitions = json.loads(DEFINITIONS.read_text(encoding="utf-8"))
    dashboards = {item["key"]: item for item in definitions["dashboards"]}
    return definitions["root_collection_id"], dashboards


def find_collection(client: MetabaseClient, root_id: int, name: str) -> dict:
    for item in client.collection_items(root_id, "collection"):
        if item.get("name") == name:
            return item
    raise RuntimeError(f"Collection not found under {root_id}: {name}")


def find_dashboard(client: MetabaseClient, collection_id: int, name: str) -> dict:
    for item in client.collection_items(collection_id, "dashboard"):
        if item.get("name") == name:
            return item
    raise RuntimeError(f"Dashboard not found in collection {collection_id}: {name}")


def card_tag_names(client: MetabaseClient, card_id: int, cache: dict[int, set[str]]) -> set[str]:
    if card_id not in cache:
        card = client.get(f"/api/card/{card_id}")
        tags: set[str] = set()
        for stage in (card.get("dataset_query") or {}).get("stages") or []:
            tags.update(tag.get("name") for tag in stage.get("template-tags") or [])
        cache[card_id] = {tag for tag in tags if tag}
    return cache[card_id]


def build_parameters(dashboard: dict, specs: list[dict]) -> tuple[list[dict], dict[str, str]]:
    """Return the full parameter list plus a slug -> parameter-id map."""
    existing = {param.get("slug"): param for param in dashboard.get("parameters", [])}
    parameters: list[dict] = []
    ids: dict[str, str] = {}

    for spec in specs:
        current = existing.get(spec["slug"])
        if current:
            parameter = {
                **current,
                "name": spec["name"],
                "slug": spec["slug"],
                "type": spec["type"],
                "sectionId": spec["section_id"],
                "values_query_type": spec["values_query_type"],
                "isMultiSelect": spec["is_multi"],
            }
            id_source = current["id"]
            print(f"    filter exists: {spec['name']} (id={id_source})")
        else:
            parameter = {
                "id": secrets.token_hex(4),
                "name": spec["name"],
                "slug": spec["slug"],
                "type": spec["type"],
                "sectionId": spec["section_id"],
                "values_query_type": spec["values_query_type"],
                "isMultiSelect": spec["is_multi"],
                "default": None,
            }
            id_source = parameter["id"]
            print(f"    filter create: {spec['name']} ({spec['type']})")
        ids[spec["slug"]] = id_source
        parameters.append(parameter)

    # Keep any unrelated parameters that the user added manually.
    managed_slugs = {spec["slug"] for spec in specs}
    for slug, parameter in existing.items():
        if slug not in managed_slugs:
            parameters.append(parameter)
            print(f"    filter preserve: {parameter.get('name')} (id={parameter.get('id')})")

    return parameters, ids


def build_dashcards(
    client: MetabaseClient,
    dashboard: dict,
    specs: list[dict],
    parameter_ids: dict[str, str],
    tag_cache: dict[int, set[str]],
) -> tuple[list[dict], dict[str, int]]:
    managed = {parameter_ids[spec["slug"]]: spec for spec in specs}
    counts = {spec["slug"]: 0 for spec in specs}
    payload: list[dict] = []

    for dashcard in dashboard.get("dashcards", []):
        card_id = dashcard.get("card_id")
        mappings = list(dashcard.get("parameter_mappings") or [])
        present_tags = card_tag_names(client, card_id, tag_cache) if card_id else set()

        # Drop stale mappings for managed filters whose tag is gone.
        mappings = [
            mapping
            for mapping in mappings
            if not (
                mapping.get("parameter_id") in managed
                and managed[mapping["parameter_id"]]["tag"] not in present_tags
            )
        ]

        for parameter_id, spec in managed.items():
            if spec["tag"] not in present_tags:
                continue
            target = ["dimension", ["template-tag", spec["tag"]], {"stage-number": 0}]
            current = next(
                (m for m in mappings if m.get("parameter_id") == parameter_id and m.get("card_id") == card_id),
                None,
            )
            if current:
                current["target"] = target
            else:
                mappings.append({"parameter_id": parameter_id, "card_id": card_id, "target": target})
            counts[spec["slug"]] += 1

        payload.append(
            {
                "id": dashcard["id"],
                "card_id": card_id,
                "dashboard_tab_id": dashcard.get("dashboard_tab_id"),
                "row": dashcard["row"],
                "col": dashcard["col"],
                "size_x": dashcard["size_x"],
                "size_y": dashcard["size_y"],
                "parameter_mappings": mappings,
                "visualization_settings": dashcard.get("visualization_settings") or {},
                "inline_parameters": dashcard.get("inline_parameters") or [],
            }
        )

    return payload, counts


def process_dashboard(
    client: MetabaseClient, root_id: int, config: dict, dry_run: bool
) -> None:
    specs = config["filters"]
    print(f"\n[{config['key']}] {config['dashboard']}")

    collection = find_collection(client, root_id, config["collection"])
    dashboard_item = find_dashboard(client, collection["id"], config["dashboard"])
    dashboard = client.get(f"/api/dashboard/{dashboard_item['id']}")
    print(f"  dashboard id={dashboard['id']}, cards={len(dashboard.get('dashcards', []))}")

    parameters, parameter_ids = build_parameters(dashboard, specs)
    dashcards, counts = build_dashcards(client, dashboard, specs, parameter_ids, {})

    total = 0
    for spec in specs:
        actual = counts[spec["slug"]]
        total += actual
        status = "ok" if actual == spec["expected_cards"] else "MISMATCH"
        print(f"    map {spec['name']:<22} {actual:>2} cards  (expected {spec['expected_cards']}) {status}")
        if actual != spec["expected_cards"]:
            raise RuntimeError(
                f"{config['dashboard']}: {spec['name']} maps {actual} cards, expected "
                f"{spec['expected_cards']}. A card tag changed; update the filter spec."
            )
    print(f"    total mappings: {total}")

    if dry_run:
        print("    dry run: no write")
        return

    client.put(
        f"/api/dashboard/{dashboard['id']}",
        {"dashcards": dashcards, "parameters": parameters, "tabs": dashboard.get("tabs", [])},
    )
    print("    dashboard updated")


def main() -> int:
    load_dotenv(PROJECT_ROOT / ".env")
    root_id, definitions = load_definitions()

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dashboard", choices=sorted(definitions), help="Only process one dashboard")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan without writing")
    args = parser.parse_args()

    base_url = os.environ.get("METABASE_URL", "http://127.0.0.1:3000")
    api_key = os.environ.get("METABASE_API_KEY", "").strip()
    if not api_key:
        print("METABASE_API_KEY is not set in the environment or .env", file=sys.stderr)
        return 2

    client = MetabaseClient(base_url, api_key)
    keys = [args.dashboard] if args.dashboard else list(definitions)
    for key in keys:
        process_dashboard(client, root_id, definitions[key], args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
