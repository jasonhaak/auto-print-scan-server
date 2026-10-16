#!/usr/bin/env python3
"""Generate the checked-in driver-profile catalog from a captured CUPS model listing."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from driver_catalog import device_id_key  # noqa: E402  (shared strict parser)


def slug(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()


def profile_name(package: str, package_prefixes: list[str], prefix: str) -> str:
    base = "debian_" + slug(package).removeprefix("printer_driver_")
    if len(package_prefixes) <= 1:
        return base
    tail = slug(prefix.rstrip("/").rsplit("/", 1)[-1].removesuffix(".drv"))
    tail = tail.removeprefix(slug(package).removeprefix("printer_driver_")).strip("_")
    return f"{base}_{tail}" if tail else base


def entry_prefix(uri: str) -> str:
    head, separator, _ = uri.rpartition("/")
    return f"{head}{separator}" if separator else uri


VIRTUAL_PACKAGES = {"printer-driver-cups-pdf"}
VIRTUAL_PREFIXES = {"cups-pdf:/"}
GENERIC_PCL_PATTERN = re.compile(r"Generic-PCL_", re.IGNORECASE)


def is_physical(entry: dict) -> bool:
    return (entry.get("package") not in VIRTUAL_PACKAGES
            and entry_prefix(entry["uri"]) not in VIRTUAL_PREFIXES)


def shared_uris(entries: list[dict]) -> set[str]:
    owners: dict[str, set[str]] = {}
    for entry in entries:
        owners.setdefault(entry["uri"], set()).add(entry["package"])
    return {uri for uri, packages in owners.items() if len(packages) > 1}


def build_catalog(capture: dict) -> dict:
    entries = capture.get("entries", []) or []
    shared = shared_uris(entries)
    excluded = sorted({entry["package"] for entry in entries if not is_physical(entry)})
    by_package: dict[str, list[dict]] = {}
    for entry in entries:
        if not is_physical(entry):
            continue
        by_package.setdefault(entry["package"], []).append(entry)
    profiles: dict[str, dict] = {}
    model_index: dict[str, list[str]] = {}
    for package, package_entries in by_package.items():
        prefixes = sorted({entry_prefix(entry["uri"]) for entry in package_entries})
        for prefix in prefixes:
            name = profile_name(package, prefixes, prefix)
            profiles[name] = {
                "description": f"Models advertised by Debian package {package}",
                "packages": [package],
                "model_prefix": prefix,
                "family": "captured-cups-models",
                "prefix_status": "verified",
            }
            for entry in package_entries:
                if entry_prefix(entry["uri"]) != prefix:
                    continue
                if entry["uri"] in shared or GENERIC_PCL_PATTERN.search(entry["uri"]):
                    continue
                key = device_id_key(entry.get("device_id", ""))
                if key is None:
                    continue
                model_index.setdefault(key, [])
                if name not in model_index[key]:
                    model_index[key].append(name)
    return {"generated_package_profiles": profiles, "model_index": model_index,
            "catalog_metadata": {"excluded_packages": excluded, "shared_uris": sorted(shared)}}


def main() -> int:
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
