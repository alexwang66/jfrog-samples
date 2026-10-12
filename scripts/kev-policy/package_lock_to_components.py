#!/usr/bin/env python3
"""Turn an npm lockfile into an Xray component-summary request body.

Xray's component summary API takes a list of component IDs:

    POST /xray/api/v1/summary/component
    {"component_details": [{"component_id": "npm://handlebars:4.7.9"}, ...]}

This reads the resolved dependency tree from package-lock.json (v2/v3) and
emits exactly that body on stdout, so the pipeline can pipe it straight into
`jf api --input`.

    python3 package_lock_to_components.py npm-sample/package-lock.json

Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import sys

PREFIX = "node_modules/"


def collect(lock: dict) -> list[str]:
    packages = lock.get("packages")
    components: set[str] = set()

    if isinstance(packages, dict):
        for path, meta in packages.items():
            if not path:
                continue  # the root project itself
            if not path.startswith(PREFIX):
                continue  # workspace / link entries
            if not isinstance(meta, dict):
                continue
            if meta.get("link"):
                continue
            version = meta.get("version")
            if not version:
                continue
            name = path[len(PREFIX):]
            # Skip nested copies: node_modules/a/node_modules/b -> take ab?  No -
            # the leaf name after the last node_modules/ segment is the package.
            if PREFIX in name:
                name = name.rsplit(PREFIX, 1)[-1]
            components.add(f"npm://{name}:{version}")
    else:
        # lockfileVersion 1 fallback
        def walk(node: dict) -> None:
            for name, meta in (node.get("dependencies") or {}).items():
                if not isinstance(meta, dict):
                    continue
                version = meta.get("version")
                if version:
                    components.add(f"npm://{name}:{version}")
                walk(meta)

        walk(lock)

    def sort_key(component_id: str) -> tuple[str, str]:
        body = component_id[len("npm://"):]
        name, _, version = body.rpartition(":")
        return name, version

    return sorted(components, key=sort_key)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build an Xray component_details payload from package-lock.json"
    )
    parser.add_argument("lockfile", nargs="?", default="package-lock.json")
    parser.add_argument(
        "--raw",
        action="store_true",
        help="Print one component ID per line instead of the API payload",
    )
    args = parser.parse_args()

    with open(args.lockfile, "r", encoding="utf-8") as handle:
        lock = json.load(handle)

    components = collect(lock)

    if args.raw:
        for component in components:
            print(component)
        return 0

    print(json.dumps({"component_details": [{"component_id": c} for c in components]}))
    print(
        f"resolved {len(components)} components from {args.lockfile}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
