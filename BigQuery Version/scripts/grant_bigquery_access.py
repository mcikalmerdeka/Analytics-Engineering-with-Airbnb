#!/usr/bin/env python3
"""Grant read access to a BigQuery dataset for a service account.

The `bq` CLI in this environment cannot set dataset-level IAM policies
(`bq get-iam-policy` reports that the feature requires allowlisting), so the
official BigQuery client updates the dataset's access entries instead. This is
the same dataset ACL that `roles/bigquery.dataViewer` grants at dataset scope.

Usage:
    uv run python scripts/grant_bigquery_access.py \
        --dataset analytics \
        --email airbnb-metabase@orbital-scene-422012-h0.iam.gserviceaccount.com
"""

from __future__ import annotations

import argparse

from google.cloud import bigquery


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default="orbital-scene-422012-h0")
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--email", required=True)
    parser.add_argument(
        "--remove-project-readers",
        action="store_true",
        help="Remove the default projectReaders ACL entry from this dataset",
    )
    args = parser.parse_args()

    client = bigquery.Client(project=args.project)
    dataset = client.get_dataset(args.dataset)

    entries = list(dataset.access_entries)
    changed = False
    if args.remove_project_readers:
        filtered = [
            entry
            for entry in entries
            if not (
                entry.entity_type == "specialGroup"
                and entry.entity_id == "projectReaders"
            )
        ]
        if len(filtered) != len(entries):
            entries = filtered
            changed = True
            print(f"Removed projectReaders from {args.dataset}")

    if args.remove_project_readers:
        print(f"Skipped READER grant for {args.email} on {args.dataset}")
    else:
        target = bigquery.AccessEntry(
            role="READER",
            entity_type="userByEmail",
            entity_id=args.email,
        )
        already_present = any(
            entry.role == target.role
            and entry.entity_type == target.entity_type
            and entry.entity_id == target.entity_id
            for entry in entries
        )
        if already_present:
            print(f"READER access already present for {args.email} on {args.dataset}")
        else:
            entries.append(target)
            changed = True
            print(f"Granted READER access to {args.email} on {args.dataset}")

    if changed:
        dataset.access_entries = entries
        client.update_dataset(dataset, ["access_entries"])

    refreshed = client.get_dataset(args.dataset)
    for entry in refreshed.access_entries:
        if entry.entity_id == args.email:
            print(f"  {entry.role} {entry.entity_type} {entry.entity_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
