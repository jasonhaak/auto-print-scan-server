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


def main() -> int:
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
