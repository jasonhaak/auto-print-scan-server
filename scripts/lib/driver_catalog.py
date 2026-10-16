#!/usr/bin/env python3
"""Strict device-ID parsing and the curated/generated driver-profile registry."""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
CURATED_PROFILES_PATH = REPO_ROOT / "vars/driver_profiles.yml"
GENERATED_DIR = REPO_ROOT / "vars/generated"

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
