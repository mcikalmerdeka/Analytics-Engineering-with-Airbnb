#!/usr/bin/env python3
"""Create and map Metabase dashboard filters from a JSON source of truth.

The cards must already expose Field Filter template tags (or plain Text tags for
search filters). This script reconciles dashboard parameters and dashcard
`parameter_mappings` against `metabase/dashboard_filters.json`:

- Filters are matched by `slug`; existing parameters are updated, not duplicated.
- A filter is mapped to every card that exposes its `tag`, minus `exclude_cards`.
- Existing mappings for unrelated filters, layout, tabs, and visualization
  settings are preserved.
- `expected_cards` is an optional drift guard per filter.
- `--dry-run` performs every read and prints the plan without writing.

Schema: assets/dashboard_filters.example.json
Reference: references/metabase-api-provisioning.md

Usage:
    uv run python scripts/add_dashboard_filters.py --dry-run
    uv run python scripts/add_dashboard_filters.py --dashboard supply
    uv run python scripts/add_dashboard_filters.py
    uv run python scripts/add_dashboard_filters.py --definitions metabase/dashboard_filters.json

Back up the application database before the first real run:
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
DEFAULT_DEFINITIONS = PROJECT_ROOT / "metabase" / "dashboard_filters.json"
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


def card_meta(client: MetabaseClient, card_id: int, cache: dict[int, dict]) -> dict:
    """Return the card name and a tag-name -> tag-type map."""
    if card_id not in cache:
        card = client.get(f"/api/card/{card_id}")
        tags: dict[str, str] = {}
        for stage in (card.get("dataset_query") or {}).get("stages") or []:
            for tag in stage.get("template-tags") or []:
                if tag.get("name"):
                    tags[tag["name"]] = tag.get("type") or ""
        cache[card_id] = {"name": card.get("name"), "tags": tags}
    return cache[card_id]


def parameter_payload(spec: dict, current: dict | None) -> dict:
    payload = {
        **(current or {}),
        "id": (current or {}).get("id") or secrets.token_hex(4),
        "name": spec["name"],
        "slug": spec["slug"],
        "type": spec["type"],
        "sectionId": spec.get("section_id", spec["type"].split("/")[0]),
        "values_query_type": spec.get("values_query_type", "none"),
        "isMultiSelect": spec.get("is_multi", False),
    }
    if "default" in spec:
        payload["default"] = spec["default"]
    elif current is None:
        payload["default"] = None
    for key in ("values_source_type", "values_source_config", "filteringParameters", "temporal_units"):
        if key in spec:
            payload[key] = spec[key]
    return payload


def build_parameters(dashboard: dict, specs: list[dict]) -> tuple[list[dict], dict[str, str]]:
    existing = {param.get("slug"): param for param in dashboard.get("parameters", [])}
    parameters: list[dict] = []
    ids: dict[str, str] = {}

    for spec in specs:
        current = existing.get(spec["slug"])
        parameter = parameter_payload(spec, current)
        ids[spec["slug"]] = parameter["id"]
        parameters.append(parameter)
        action = "exists" if current else "create"
        print(f"    filter {action}: {spec['name']} ({spec['type']}, id={parameter['id']})")

    managed_slugs = {spec["slug"] for spec in specs}
    for slug, parameter in existing.items():
        if slug not in managed_slugs:
            parameters.append(parameter)
            print(f"    filter preserve: {parameter.get('name')} (id={parameter.get('id')})")

    return parameters, ids


def mapping_target(tag: str, tag_type: str) -> list:
    if tag_type == "dimension":
        return ["dimension", ["template-tag", tag], {"stage-number": 0}]
    # Plain Text/Number/Date variables use a two-element variable target.
    return ["variable", ["template-tag", tag]]


def build_dashcards(
    client: MetabaseClient,
    dashboard: dict,
    specs: list[dict],
    parameter_ids: dict[str, str],
    tag_cache: dict[int, dict],
) -> tuple[list[dict], dict[str, int]]:
    managed = {parameter_ids[spec["slug"]]: spec for spec in specs}
    counts = {spec["slug"]: 0 for spec in specs}
    payload: list[dict] = []

    for dashcard in dashboard.get("dashcards", []):
        card_id = dashcard.get("card_id")
        mappings = list(dashcard.get("parameter_mappings") or [])
        meta = card_meta(client, card_id, tag_cache) if card_id else {"name": None, "tags": {}}
        tags = meta["tags"]

        mappings = [
            mapping
            for mapping in mappings
            if not (
                mapping.get("parameter_id") in managed
                and managed[mapping["parameter_id"]]["tag"] not in tags
            )
        ]

        for parameter_id, spec in managed.items():
            tag = spec["tag"]
            if tag not in tags:
                continue
            excluded = set(spec.get("exclude_cards") or [])
            if meta["name"] in excluded:
                continue
            target = mapping_target(tag, tags[tag])
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
    failed = False
    for spec in specs:
        actual = counts[spec["slug"]]
        total += actual
        expected = spec.get("expected_cards")
        if expected is None:
            print(f"    map {spec['name']:<24} {actual:>2} cards")
            continue
        total_count = actual
        status = "ok" if total_count == expected else "MISMATCH"
        print(f"    map {spec['name']:<24} {total_count:>2} cards  (expected {expected}) {status}")
        if total_count != expected:
            failed = True
    print(f"    total mappings: {total}")

    if failed:
        raise RuntimeError(
            f"{config['dashboard']}: mapping counts differ from expected_cards. "
            "A card tag changed; update the filter spec or exclusions."
        )
    if dry_run:
        print("    dry run: no write")
        return

    client.put(
        f"/api/dashboard/{dashboard['id']}",
        {"dashcards": dashcards, "parameters": parameters, "tabs": dashboard.get("tabs", [])},
    )
    print("    dashboard updated")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--definitions", default=str(DEFAULT_DEFINITIONS), help="Filter definitions JSON")
    parser.add_argument("--env-file", default=str(PROJECT_ROOT / ".env"), help="Environment file with METABASE_*")
    parser.add_argument("--dashboard", help="Only process one dashboard key")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan without writing")
    args = parser.parse_args()

    definitions_path = Path(args.definitions).expanduser().resolve()
    if not definitions_path.exists():
        print(f"Definitions file not found: {definitions_path}", file=sys.stderr)
        return 2
    definitions = json.loads(definitions_path.read_text(encoding="utf-8"))
    dashboards = {item["key"]: item for item in definitions.get("dashboards", [])}
    if not dashboards:
        print("No dashboards in the definitions file.", file=sys.stderr)
        return 2
    if args.dashboard and args.dashboard not in dashboards:
        print(f"Unknown dashboard key: {args.dashboard}", file=sys.stderr)
        return 2

    load_dotenv(Path(args.env_file).expanduser().resolve())
    base_url = os.environ.get("METABASE_URL", "http://127.0.0.1:3000")
    api_key = os.environ.get("METABASE_API_KEY", "").strip()
    if not api_key:
        print("METABASE_API_KEY is not set in the environment or env file", file=sys.stderr)
        return 2

    root_id = definitions.get("root_collection_id")
    if root_id is None:
        print("root_collection_id is missing from the definitions file", file=sys.stderr)
        return 2

    client = MetabaseClient(base_url, api_key)
    keys = [args.dashboard] if args.dashboard else list(dashboards)
    for key in keys:
        process_dashboard(client, root_id, dashboards[key], args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
