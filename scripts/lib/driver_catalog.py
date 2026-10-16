#!/usr/bin/env python3
"""Strict device-ID parsing and the curated/generated driver-profile registry."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
CURATED_PROFILES_PATH = REPO_ROOT / "vars/driver_profiles.yml"
GENERATED_DIR = Path(os.environ.get("DRIVER_CATALOG_GENERATED_DIR", REPO_ROOT / "vars/generated"))

ARCHITECTURE_FACTS = {"armv6l": "armhf", "aarch64": "arm64", "x86_64": "amd64"}


class CatalogError(ValueError):
    pass


def normalize(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip()).lower()


def parse_printer_device_id(evidence: str) -> str | None:
    values = []
    for line in (evidence or "").splitlines():
        if "printer-device-id" not in line:
            continue
        _, separator, value = line.partition("=")
        if separator and value.strip():
            values.append(value.strip())
    return values[0] if len(values) == 1 else None


def device_id_key(device_id: str) -> str | None:
    makes = re.findall(r"MFG:([^;]*)", device_id or "")
    models = re.findall(r"MDL:([^;]*)", device_id or "")
    if len(makes) != 1 or len(models) != 1:
        return None
    if not makes[0].strip() or not models[0].strip():
        return None
    return f"{normalize(makes[0])}|{normalize(models[0])}"


def _load_yaml(path: Path) -> dict:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        raise CatalogError(f"registry is unavailable: {error}") from error
    return data if isinstance(data, dict) else {}


def load_catalog(suite=None, package_architecture=None, repository_identity=None) -> dict:
    curated = _load_yaml(CURATED_PROFILES_PATH).get("package_profiles")
    curated = curated if isinstance(curated, dict) else {}
    requested = bool(suite and package_architecture)
    matched = False
    identity_matched = False
    generated: dict = {}
    model_index: dict = {}
    metadata: dict = {}
    if requested and GENERATED_DIR.is_dir():
        candidates = []
        for path in sorted(GENERATED_DIR.glob("driver_profiles_*.yml")):
            document = _load_yaml(path)
            meta = document.get("catalog_metadata")
            if not isinstance(meta, dict):
                continue
            if meta.get("suite") != suite or meta.get("package_architecture") != package_architecture:
                continue
            candidates.append((meta, document))
        # prefer an exact repository-identity match
        chosen = next((c for c in candidates if not repository_identity
                       or c[0].get("repository_identity") == repository_identity),
                      candidates[0] if candidates else None)
        if chosen is not None:
            metadata, document = chosen
            profiles = document.get("generated_package_profiles")
            if isinstance(profiles, dict):
                generated = dict(profiles)
            index = document.get("model_index")
            if isinstance(index, dict):
                model_index = dict(index)
            matched = True
            identity_matched = bool(not repository_identity
                                    or metadata.get("repository_identity") == repository_identity)
    merged = dict(generated)
    merged.update(curated)  # curated wins whole-entry
    return {"package_profiles": merged, "model_index": model_index, "metadata": metadata,
            "requested": requested, "matched": matched, "identity_matched": identity_matched}


def profile_names(catalog: dict) -> list[str]:
    return list(catalog["package_profiles"])


def model_prefix(catalog: dict, name: str) -> str:
    profile = catalog["package_profiles"].get(name)
    if not isinstance(profile, dict):
        raise CatalogError(f"unknown package profile {name!r}")
    prefix = profile.get("model_prefix")
    if not isinstance(prefix, str) or not prefix.strip():
        raise CatalogError(f"package profile {name!r} has no model_prefix")
    return prefix


def resolve_identity(suite, architecture_fact, repository_identity) -> dict:
    package_architecture = ARCHITECTURE_FACTS.get(architecture_fact)
    if package_architecture is None:
        raise CatalogError(f"unsupported architecture fact {architecture_fact!r}")
    return {"suite": str(suite), "package_architecture": package_architecture,
            "repository_identity": str(repository_identity)}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    select = commands.add_parser("select")
    select.add_argument("--suite", required=True)
    select.add_argument("--architecture", required=True)
    select.add_argument("--repository", required=True)
    select.add_argument("--enable-generated-catalog", action="store_true")
    return parser


def main() -> int:
    arguments = build_parser().parse_args()
    if arguments.command != "select":
        return 2
    catalog = load_catalog(arguments.suite, arguments.architecture, arguments.repository)
    if not arguments.enable_generated_catalog:
        catalog = {"package_profiles": load_catalog()["package_profiles"], "model_index": {},
                   "metadata": {}, "requested": catalog["requested"], "matched": False,
                   "identity_matched": False}
    print(json.dumps(catalog, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
