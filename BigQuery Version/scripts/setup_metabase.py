#!/usr/bin/env python3
"""Provision Metabase and connect it to the BigQuery analytics dataset.

The script is idempotent:
- completes first-run setup only when a setup token exists;
- reuses an API key from .env when it is valid, otherwise creates one;
- reuses the BigQuery database by name and only creates it when missing.

Usage:
    uv run python scripts/setup_metabase.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = PROJECT_ROOT / ".env"
KEY_PATH = PROJECT_ROOT / ".secrets" / "metabase-bigquery-key.json"
API_KEY_NAME = "git-export"
DATABASE_NAME = "Airbnb Analytics"
ANALYTICS_SCHEMA = "analytics"


def load_dotenv(path: Path) -> None:
    """Load simple KEY=VALUE lines without overriding existing environment."""
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def write_env_value(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    replaced = False
    output: list[str] = []
    for line in lines:
        if line.startswith(f"{key}="):
            output.append(f"{key}={value}")
            replaced = True
        else:
            output.append(line)
    if not replaced:
        output.append(f"{key}={value}")
    path.write_text("\n".join(output) + "\n", encoding="utf-8")


class MetabaseClient:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.session_id: str | None = None

    def request(self, method: str, path: str, payload: dict | None = None):
        data = json.dumps(payload).encode() if payload is not None else None
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if self.session_id:
            headers["X-Metabase-Session"] = self.session_id
        request = urllib.request.Request(
            self.base_url + path, data=data, headers=headers, method=method
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

    def post(self, path: str, payload: dict | None = None):
        return self.request("POST", path, payload)

    def delete(self, path: str):
        return self.request("DELETE", path)


def wait_for_health(base_url: str, timeout_seconds: int = 180) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(
                base_url.rstrip("/") + "/api/health", timeout=5
            ) as response:
                if response.status == 200:
                    print("Metabase health check: ok")
                    return
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(3)
    raise TimeoutError(f"Metabase did not become healthy within {timeout_seconds}s")


def get_setup_token(client: MetabaseClient) -> str | None:
    properties = client.get("/api/session/properties")
    return properties.get("setup-token")


def complete_setup(client: MetabaseClient, token: str) -> None:
    payload = {
        "token": token,
        "user": {
            "email": os.environ["METABASE_ADMIN_EMAIL"],
            "password": os.environ["METABASE_ADMIN_PASSWORD"],
            "first_name": os.environ.get("METABASE_ADMIN_FIRST_NAME", "Airbnb"),
            "last_name": os.environ.get("METABASE_ADMIN_LAST_NAME", "Admin"),
        },
        "prefs": {"site_name": "Airbnb Analytics", "site_locale": "en"},
    }
    client.post("/api/setup", payload)
    print("Completed Metabase first-run setup")


def login(client: MetabaseClient) -> None:
    response = client.post(
        "/api/session",
        {
            "username": os.environ["METABASE_ADMIN_EMAIL"],
            "password": os.environ["METABASE_ADMIN_PASSWORD"],
        },
    )
    client.session_id = response["id"]
    print("Logged in to Metabase")


def api_key_is_valid(base_url: str, api_key: str) -> bool:
    request = urllib.request.Request(
        base_url.rstrip("/") + "/api/user/current",
        headers={"X-API-Key": api_key, "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status == 200
    except (urllib.error.HTTPError, urllib.error.URLError):
        return False


def list_api_keys(client: MetabaseClient) -> list[dict]:
    payload = client.get("/api/api-key")
    if isinstance(payload, list):
        return payload
    return payload.get("data", [])


def ensure_api_key(client: MetabaseClient) -> str:
    existing = os.environ.get("METABASE_API_KEY", "").strip()
    if existing and api_key_is_valid(client.base_url, existing):
        print("Reusing METABASE_API_KEY from .env")
        return existing

    for key in list_api_keys(client):
        if key.get("name") == API_KEY_NAME:
            # A saved key cannot be read back; replace it so the .env value and
            # the Metabase key stay in sync.
            client.delete(f"/api/api-key/{key['id']}")
            print(f"Replaced stale API key {API_KEY_NAME!r}")

    response = client.post(
        "/api/api-key", {"group_id": get_admin_group_id(client), "name": API_KEY_NAME}
    )
    key = response.get("unmasked_key") or response.get("key")
    if not key:
        raise RuntimeError(f"API key response did not include a key: {response}")
    write_env_value(ENV_PATH, "METABASE_API_KEY", key)
    os.environ["METABASE_API_KEY"] = key
    print(f"Created API key {API_KEY_NAME!r} and wrote it to .env")
    return key


def get_admin_group_id(client: MetabaseClient) -> int:
    groups = client.get("/api/permissions/group")
    for group in groups:
        if group.get("name") == "Administrators":
            return group["id"]
    raise RuntimeError("Administrators group not found")


def find_database(client: MetabaseClient) -> dict | None:
    payload = client.get("/api/database")
    databases = payload if isinstance(payload, list) else payload.get("data", [])
    for database in databases:
        if database.get("name") == DATABASE_NAME:
            return database
    return None


def create_database(client: MetabaseClient) -> dict:
    if not KEY_PATH.exists():
        raise FileNotFoundError(f"Missing service account key: {KEY_PATH}")
    service_account = json.loads(KEY_PATH.read_text(encoding="utf-8"))
    payload = {
        "name": DATABASE_NAME,
        # Metabase v0.64 names the BigQuery driver `bigquery-cloud-sdk`.
        "engine": "bigquery-cloud-sdk",
        "details": {
            "project-id": os.environ["GCP_PROJECT_ID"],
            "service-account-json": json.dumps(service_account),
            "dataset-filters-type": "inclusion",
            "dataset-filters-patterns": ANALYTICS_SCHEMA,
        },
    }
    created = client.post("/api/database", payload)
    print(f"Created database {DATABASE_NAME!r} (id={created['id']})")
    return created


def table_names(metadata: dict) -> set[tuple[str, str]]:
    names = set()
    for table in metadata.get("tables", []):
        names.add((table.get("schema"), table.get("name")))
    return names


def sync_database(client: MetabaseClient, database_id: int) -> dict:
    client.post(f"/api/database/{database_id}/sync_schema")
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        metadata = client.get(f"/api/database/{database_id}/metadata")
        if (ANALYTICS_SCHEMA, "dim_listings") in table_names(metadata):
            return metadata
        time.sleep(5)
    raise TimeoutError("Timed out waiting for analytics.dim_listings to sync")


def main() -> int:
    load_dotenv(ENV_PATH)
    base_url = os.environ.get("METABASE_URL", "http://127.0.0.1:3000")
    client = MetabaseClient(base_url)

    wait_for_health(base_url)
    setup_token = get_setup_token(client)
    if setup_token:
        complete_setup(client, setup_token)
    login(client)

    ensure_api_key(client)
    database = find_database(client)
    if database is None:
        database = create_database(client)
    else:
        print(f"Reusing database {DATABASE_NAME!r} (id={database['id']})")

    metadata = sync_database(client, database["id"])
    tables = [
        table for table in metadata.get("tables", []) if table.get("schema") == ANALYTICS_SCHEMA
    ]
    field_count = sum(len(table.get("fields", [])) for table in tables)
    print(
        f"Database id={database['id']}; "
        f"analytics tables={len(tables)}; fields={field_count}"
    )
    for table in sorted(tables, key=lambda item: item["name"]):
        print(f"  {ANALYTICS_SCHEMA}.{table['name']} ({len(table.get('fields', []))} fields)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # fail loudly with the operation that broke
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
