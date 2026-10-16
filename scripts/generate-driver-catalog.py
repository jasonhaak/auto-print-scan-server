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


def build_catalog(capture: dict) -> dict:
    by_package: dict[str, list[dict]] = {}
    for entry in capture.get("entries", []) or []:
        by_package.setdefault(entry["package"], []).append(entry)
    profiles: dict[str, dict] = {}
    model_index: dict[str, list[str]] = {}
    for package, entries in by_package.items():
        prefixes = sorted({entry_prefix(entry["uri"]) for entry in entries})
        for prefix in prefixes:
            name = profile_name(package, prefixes, prefix)
            profiles[name] = {
                "description": f"Models advertised by Debian package {package}",
                "packages": [package],
                "model_prefix": prefix,
                "family": "captured-cups-models",
                "prefix_status": "verified",
            }
            for entry in entries:
                if entry_prefix(entry["uri"]) != prefix:
                    continue
                key = device_id_key(entry.get("device_id", ""))
                if key is None:
                    continue
                model_index.setdefault(key, [])
                if name not in model_index[key]:
                    model_index[key].append(name)
    return {"generated_package_profiles": profiles, "model_index": model_index,
            "catalog_metadata": {"excluded_packages": [], "shared_uris": []}}


def main() -> int:
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
