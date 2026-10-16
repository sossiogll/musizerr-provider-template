"""
Write or update the entry of this provider in catalog.json (a Musizerr catalog, version 2).

Standard library only: scripts/publish.sh runs it with the Python of the base image. The entry is made of what
the build produced: the image name, the digest of the multi-architecture index GHCR returned, and the image's
labels (the org.musizerr.provider.* ones, which the gateway checks against the entry, plus the standard
org.opencontainers.image.description and .url). An entry of the same name is replaced where it stands; others
are kept.

    python catalog_entry.py --catalog catalog.json --image ghcr.io/owner/musizerr-provider-x \\
        --digest sha256:... --labels labels.txt [--catalog-name "My providers"]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

CATALOG_VERSION = 2
PREFIX = "org.musizerr.provider."


def read_labels(text: str) -> dict[str, str]:
    labels: dict[str, str] = {}
    for line in text.splitlines():
        key, separator, value = line.partition("=")
        if separator and key:
            labels[key] = value
    return labels


def entry_from_labels(labels: dict[str, str], image: str, digest: str) -> dict:
    missing = [key for key in ("name", "roles", "api-version", "permissions") if PREFIX + key not in labels]
    if missing:
        raise SystemExit("the labels of the image lack: " + ", ".join(PREFIX + key for key in missing))
    entry = {
        "name": labels[PREFIX + "name"],
        "image": image,
        "digest": digest,
        "provider_api_version": int(labels[PREFIX + "api-version"]),
        "roles": [role for role in labels[PREFIX + "roles"].split(",") if role],
        "label": labels.get(PREFIX + "label") or labels[PREFIX + "name"],
        "description": labels.get("org.opencontainers.image.description", ""),
    }
    homepage = labels.get("org.opencontainers.image.url", "")
    if homepage.startswith(("http://", "https://")):
        entry["homepage"] = homepage
    entry["permissions"] = json.loads(labels[PREFIX + "permissions"])
    return entry


def merge(catalog: dict | None, entry: dict, catalog_name: str) -> dict:
    if catalog is None:
        catalog = {"name": catalog_name, "version": CATALOG_VERSION, "providers": []}
    if not isinstance(catalog, dict) or catalog.get("version") != CATALOG_VERSION or not isinstance(catalog.get("providers"), list):
        raise SystemExit(f"the existing file is not a version {CATALOG_VERSION} catalog; not touching it")
    providers = list(catalog["providers"])
    for index, current in enumerate(providers):
        if isinstance(current, dict) and current.get("name") == entry["name"]:
            providers[index] = entry
            break
    else:
        providers.append(entry)
    return {**catalog, "providers": providers}


def write_atomically(path: Path, document: dict) -> None:
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            json.dump(document, out, indent=2, ensure_ascii=False)
            out.write("\n")
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--image", required=True, help="registry/repository, no tag")
    parser.add_argument("--digest", required=True)
    parser.add_argument("--labels", required=True, type=Path, help="key=value lines: the image's labels")
    parser.add_argument("--catalog-name", default="Musizerr providers", help="the catalog's name, when this creates it")
    args = parser.parse_args(argv)
    entry = entry_from_labels(read_labels(args.labels.read_text(encoding="utf-8")), args.image, args.digest)
    existing = json.loads(args.catalog.read_text(encoding="utf-8")) if args.catalog.exists() else None
    write_atomically(args.catalog, merge(existing, entry, args.catalog_name))
    print(f"{entry['name']} -> {args.image}@{args.digest} in {args.catalog}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
