#!/usr/bin/env python3
"""Generate the checked-in driver-profile catalog from a captured CUPS model listing."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from driver_catalog import device_id_key  # noqa: E402  (shared strict parser)


def slug(text: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()


class _IndentedDumper(yaml.SafeDumper):
    """Indent block sequences to match the repository's yamllint profile."""

    def increase_indent(self, flow=False, indentless=False):
        return super().increase_indent(flow, False)


def profile_name(package: str, package_prefixes: list[str], prefix: str) -> str:
    base = "debian_" + slug(package).removeprefix("printer_driver_")
    if len(package_prefixes) <= 1:
        return base
    common = os.path.commonprefix(package_prefixes)
    tail = slug(prefix[len(common):])
    return f"{base}_{tail}" if tail else f"{base}_{slug(prefix)}"


INSTANCE_PREFIX = re.compile(r"^([A-Za-z0-9_.+-]+):\d+/")


def entry_prefix(uri: str) -> str:
    if uri.startswith("gutenprint.5.3://"):
        return "gutenprint.5.3://"
    instance = INSTANCE_PREFIX.match(uri)
    if instance:
        return instance.group(1) + ":"
    head, separator, _ = uri.rpartition("/")
    return f"{head}{separator}" if separator else uri


VIRTUAL_PACKAGES = {"printer-driver-cups-pdf"}
EXCLUDED_PREFIXES = {"cups-pdf:/", "drv:///sample.drv/"}
GENERIC_PCL_PATTERN = re.compile(r"Generic-PCL_", re.IGNORECASE)


def is_physical(entry: dict) -> bool:
    return (entry.get("package") not in VIRTUAL_PACKAGES
            and entry_prefix(entry["uri"]) not in EXCLUDED_PREFIXES)


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
            if name in profiles and profiles[name]["model_prefix"] != prefix:
                raise ValueError(f"profile name collision for {name!r}")
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


def render_artifact(catalog: dict, capture: dict) -> str:
    metadata = dict(catalog.get("catalog_metadata", {}))
    used = {name for profile in catalog["generated_package_profiles"].values()
            for name in profile.get("packages", [])}
    provenance = dict(capture.get("provenance", {}))
    provenance["package_sha256"] = {name: digest for name, digest in provenance.get("package_sha256", {}).items()
                                    if name in used}
    metadata.update({
        "suite": capture["suite"],
        "package_architecture": capture["package_architecture"],
        "repository_identity": capture["repository_identity"],
        "label": capture.get("label", ""),
        "generated_on": capture.get("generated_on", ""),
        "generator_version": capture.get("generator_version", ""),
        "package_versions": {name: version for name, version in capture.get("packages", {}).items()
                             if name in used},
        "provenance": provenance,
    })
    document = {
        "generated_package_profiles": catalog["generated_package_profiles"],
        "model_index": catalog["model_index"],
        "catalog_metadata": metadata,
    }
    return ("# Generated by scripts/generate-driver-catalog.py. Do not edit by hand.\n"
            + yaml.dump(document, Dumper=_IndentedDumper, sort_keys=True,
                        default_flow_style=False, width=1000, allow_unicode=True))


def write_manifest(capture: dict, catalog: dict) -> dict:
    metadata = catalog.get("catalog_metadata", {})
    used = {name for profile in catalog["generated_package_profiles"].values()
            for name in profile.get("packages", [])}
    provenance = dict(capture.get("provenance", {}))
    provenance["package_sha256"] = {name: digest for name, digest in provenance.get("package_sha256", {}).items()
                                    if name in used}
    return {
        "suite": capture["suite"],
        "package_architecture": capture["package_architecture"],
        "repository_identity": capture["repository_identity"],
        "generator_version": capture.get("generator_version", ""),
        "packages": {name: version for name, version in capture.get("packages", {}).items() if name in used},
        "provenance": provenance,
        "excluded_packages": metadata.get("excluded_packages", []),
        "shared_uris": metadata.get("shared_uris", []),
        "entries": [
            {"uri": entry["uri"], "device_id": entry.get("device_id", ""), "package": entry["package"]}
            for entry in capture.get("entries", []) if is_physical(entry)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    arguments = parser.parse_args()
    capture = json.loads(arguments.capture.read_text(encoding="utf-8"))
    catalog = build_catalog(capture)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.manifest.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(render_artifact(catalog, capture), encoding="utf-8")
    arguments.manifest.write_text(
        json.dumps(write_manifest(capture, catalog), indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Wrote {arguments.output} and {arguments.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
