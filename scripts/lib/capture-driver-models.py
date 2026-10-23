#!/usr/bin/env python3
"""Capture one CUPS driver family's advertised models, with provenance, on a build image."""

from __future__ import annotations

import argparse
import glob
import gzip
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

PPD_SEARCH_ROOTS = ("/usr/share/ppd", "/usr/share/cups/model")
GUTENPRINT_SEARCH_ROOTS = ("/usr/share/ppd/gutenprint", "/usr/share/cups/model/gutenprint")
DRV_SEARCH_GLOB = "/usr/share/cups/drv/*.drv"

DRV_MODEL = re.compile(r'^\s*ModelName\s+"([^"]+)"')
DRV_DEVICE_ID = re.compile(r'^\s*Attribute\s+"1284DeviceID"\s+"[^"]*"\s+"([^"]*)"')
PPD_DEVICE_ID = re.compile(r'^\*1284DeviceID:\s*"([^"]*)"', re.MULTILINE)
GUTENPRINT_MANUFACTURER = re.compile(r'^\*Manufacturer:\s*"([^"]*)"', re.MULTILINE)
GUTENPRINT_MODEL = re.compile(r'^\*ModelName:\s*"([^"]*)"', re.MULTILINE)
PROGRAM_ENTRY = re.compile(r'"([^"]+)"\s+\S+\s+"[^"]*"\s+"[^"]*"\s+"([^"]*)"')

CUPS_DRIVERD = "/usr/lib/cups/daemon/cups-driverd"
IGNORED_URIS = {"everywhere", "raw"}
IGNORED_NAMESPACES = ("driverless:", "driverless-fax:")


def run(*argv: str) -> str:
    process = subprocess.run(argv, capture_output=True, text=True)
    return (process.stdout or "") + (process.stderr or "")


def run_checked(*argv: str) -> str:
    return subprocess.run(argv, capture_output=True, text=True, check=True).stdout


APT_RELEASE_GLOBS = ("/var/lib/apt/lists/*_Release", "/var/lib/apt/lists/*_InRelease")


def repository_identity(patterns: tuple[str, ...] = APT_RELEASE_GLOBS) -> str:
    identities = set()
    paths = sorted({path for pattern in patterns for path in glob.glob(pattern)})
    for path in paths:
        lines = sorted(
            line.strip() for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
            if re.match(r"^(Origin|Label|Suite|Codename):", line.strip()))
        if lines:
            identities.add("|".join(lines))
    return ";".join(sorted(identities))


def index_sha256() -> str:
    digest = hashlib.sha256()
    for path in sorted(glob.glob("/var/lib/apt/lists/*_Packages*")):
        digest.update(Path(path).read_bytes())
    return digest.hexdigest()


def package_sha256(package: str) -> str:
    version = run_checked("dpkg-query", "-W", "-f=${Version}", package).strip()
    candidates = sorted(glob.glob(f"/var/cache/apt/archives/{package}_{version}*.deb"))
    if not candidates:
        return ""
    digest = hashlib.sha256()
    digest.update(Path(candidates[-1]).read_bytes())
    return digest.hexdigest()


def tool_versions() -> dict:
    versions = {"python": run("python3", "-V").strip()}
    for tool in ("cups", "cups-filters", "ghostscript"):
        versions[tool] = run("dpkg-query", "-W", "-f=${Version}", tool).strip()
    return versions


def parse_drv(text: str, prefix: str) -> list[dict]:
    """One entry per ModelName block carrying an 1284DeviceID attribute."""
    entries = []
    model = None
    device_id = None
    for line in (text or "").splitlines():
        name = DRV_MODEL.match(line)
        if name:
            if model is not None and device_id:
                entries.append({"uri": f"{prefix}{model}", "device_id": device_id, "package": ""})
            model = name.group(1)
            device_id = None
            continue
        device = DRV_DEVICE_ID.match(line)
        if device and model is not None and device_id is None:
            device_id = device.group(1)
    if model is not None and device_id:
        entries.append({"uri": f"{prefix}{model}", "device_id": device_id, "package": ""})
    return entries


def parse_ppd(text: str, prefix: str) -> list[dict]:
    """A single PPD file yields its *1284DeviceID under the caller-supplied URI."""
    match = PPD_DEVICE_ID.search(text or "")
    if not match:
        return []
    return [{"uri": prefix, "device_id": match.group(1), "package": ""}]


def parse_gutenprint(text: str, prefix: str) -> list[dict]:
    """A Gutenprint PPD yields its *Manufacturer/*ModelName pair under prefix plus model."""
    manufacturer = GUTENPRINT_MANUFACTURER.search(text or "")
    model = GUTENPRINT_MODEL.search(text or "")
    if not manufacturer or not model:
        return []
    device = PPD_DEVICE_ID.search(text or "")
    return [{"uri": f"{prefix}{model.group(1)}",
             "device_id": device.group(1) if device else "", "package": ""}]


def advertised_models() -> set[str]:
    return {line.split(" ", 1)[0] for line in run_checked("lpinfo", "-m").splitlines() if line.strip()}


def run_stdout(*argv: str) -> str:
    return subprocess.run(argv, capture_output=True, text=True).stdout


def is_elf(path: Path) -> bool:
    try:
        return path.read_bytes()[:4] == b"\x7fELF"
    except OSError:
        return False


def program_list(path: Path) -> str:
    if is_elf(path):
        return run_checked(str(path), "list")
    return run_checked("python3", str(path), "list")


def dpkg_package(path: str) -> str:
    process = subprocess.run(["dpkg", "-S", path], capture_output=True, text=True)
    if process.returncode != 0:
        return ""
    return process.stdout.split(":", 1)[0].strip()


def package_for_uri(uri: str, cache: dict[str, str]) -> str:
    if uri.startswith("drv:///"):
        file_name = uri[len("drv:///"):].split("/", 1)[0]
        key = f"drv:///{file_name}"
        if key not in cache:
            cache[key] = dpkg_package(f"/usr/share/cups/drv/{file_name}")
        return cache[key]
    if uri.startswith("lsb/usr/"):
        key = "lsb/usr"
        if key not in cache:
            name = Path(uri[len("lsb/usr/"):]).name
            matches: list[str] = []
            for root in ("/usr/share/cups/model", "/usr/share/ppd"):
                matches.extend(glob.glob(f"{root}/**/{name}", recursive=True))
            cache[key] = dpkg_package(matches[0]) if matches else ""
        return cache[key]
    program = uri.split(":", 1)[0]
    key = f"program:{program}"
    if key not in cache:
        cache[key] = dpkg_package(f"/usr/lib/cups/driver/{program}")
    return cache[key]


def ppd_device_id(uri: str) -> str:
    match = PPD_DEVICE_ID.search(run_stdout(CUPS_DRIVERD, "cat", uri))
    return match.group(1) if match else ""


def capture_programs(advertised: set[str]) -> list[dict]:
    entries = []
    for path in sorted(Path("/usr/lib/cups/driver").glob("*")):
        if not path.is_file() or path.name.startswith("driverless"):
            continue
        try:
            listed = program_list(path)
        except subprocess.CalledProcessError:
            continue
        for line in listed.splitlines():
            match = PROGRAM_ENTRY.match(line)
            if not match or match.group(1) not in advertised:
                continue
            entries.append({"uri": match.group(1), "device_id": match.group(2), "package": ""})
    return entries


def capture_lpinfo() -> list[dict]:
    """Capture every advertised model: programs via list, the rest via cups-driverd."""
    advertised = advertised_models() - IGNORED_URIS
    cache: dict[str, str] = {}
    entries: list[dict] = []
    covered: set[str] = set()
    for entry in capture_programs(advertised):
        entry["package"] = package_for_uri(entry["uri"], cache)
        entries.append(entry)
        covered.add(entry["uri"])
    for uri in sorted(advertised - covered):
        if uri.startswith(IGNORED_NAMESPACES):
            continue
        entries.append({"uri": uri, "device_id": ppd_device_id(uri),
                        "package": package_for_uri(uri, cache)})
    return entries


def read_text_maybe_gz(path: Path) -> str:
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8", errors="replace") as handle:
            return handle.read()
    return path.read_text(encoding="utf-8", errors="replace")


def capture_program(family: str, advertised: set[str]) -> list[dict]:
    program = Path("/usr/lib/cups/driver") / family
    listed = run_checked("python3", str(program), "list")
    entries = []
    for line in listed.splitlines():
        match = re.match(r'"([^"]+)"\s+\S+\s+"[^"]*"\s+"[^"]*"\s+"([^"]*)"', line)
        if not match:
            continue
        uri = match.group(1)
        if uri not in advertised:
            continue
        entries.append({"uri": uri, "device_id": match.group(2), "package": family})
    return entries


def capture_drv(family: str, advertised: set[str]) -> list[dict]:
    entries = []
    for path in sorted(glob.glob(DRV_SEARCH_GLOB)):
        prefix = f"drv:///{Path(path).name}/"
        for entry in parse_drv(Path(path).read_text(encoding="utf-8", errors="replace"), prefix):
            if entry["uri"] not in advertised:
                continue
            entry["package"] = family
            entries.append(entry)
    return entries


def capture_ppds(family: str, advertised: set[str], roots: tuple[str, ...]) -> list[dict]:
    entries = []
    for root in roots:
        for pattern in ("*.ppd", "*.ppd.gz"):
            for path in sorted(glob.glob(f"{root}/**/{pattern}", recursive=True)):
                uri = str(Path(path).relative_to(root))
                for entry in parse_ppd(read_text_maybe_gz(Path(path)), uri):
                    if entry["uri"] not in advertised:
                        continue
                    entry["package"] = family
                    entries.append(entry)
    return entries


def capture_gutenprint(family: str, advertised: set[str]) -> list[dict]:
    entries = []
    for root in GUTENPRINT_SEARCH_ROOTS:
        for pattern in ("*.ppd", "*.ppd.gz"):
            for path in sorted(glob.glob(f"{root}/**/{pattern}", recursive=True)):
                relative = Path(path).relative_to(root)
                prefix = f"{relative.parent}/" if str(relative.parent) != "." else ""
                for entry in parse_gutenprint(read_text_maybe_gz(Path(path)), prefix):
                    if entry["uri"] not in advertised:
                        continue
                    entry["package"] = family
                    entries.append(entry)
    return entries


def capture_envelope(entries: list[dict], packages: dict, label: str = "raspberrypi") -> dict:
    return {
        "suite": "trixie",
        "package_architecture": run_checked("dpkg", "--print-architecture").strip(),
        "repository_identity": repository_identity(),
        "label": label,
        "generated_on": "2026-10-17",
        "generator_version": "1",
        "packages": packages,
        "provenance": {
            "index_sha256": index_sha256(),
            "package_sha256": {name: package_sha256(name) for name in packages},
            "tool_versions": tool_versions(),
        },
        "entries": entries,
    }


def merge_captures(parts: list[dict]) -> dict:
    first = parts[0]
    for part in parts[1:]:
        for field in ("suite", "package_architecture", "repository_identity"):
            if part.get(field) != first.get(field):
                raise ValueError(f"merge parts disagree on {field}: {part.get(field)!r} != {first.get(field)!r}")
    entries: list[dict] = []
    seen: set[str] = set()
    packages: dict = {}
    package_sha256s: dict = {}
    tool_version_map: dict = {}
    for part in parts:
        packages.update(part.get("packages", {}))
        provenance = part.get("provenance", {})
        package_sha256s.update(provenance.get("package_sha256", {}))
        tool_version_map.update(provenance.get("tool_versions", {}))
        for entry in part.get("entries", []):
            if entry["uri"] not in seen:
                seen.add(entry["uri"])
                entries.append(entry)
    merged = dict(first)
    merged["packages"] = packages
    merged["provenance"] = {
        "index_sha256": first.get("provenance", {}).get("index_sha256", ""),
        "package_sha256": package_sha256s,
        "tool_versions": tool_version_map,
    }
    merged["entries"] = entries
    return merged


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=["program", "drv", "ppd", "gutenprint", "lpinfo"],
                        default="program")
    parser.add_argument("--family")
    parser.add_argument("--label", default="raspberrypi")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--merge", nargs="*", default=None)
    arguments = parser.parse_args()
    if arguments.merge is not None:
        if not arguments.merge:
            parser.error("--merge requires at least one capture file")
        try:
            parts = [json.loads(Path(path).read_text(encoding="utf-8")) for path in arguments.merge]
            document = merge_captures(parts)
        except (OSError, ValueError) as error:
            print(f"Error: {error}", file=sys.stderr)
            return 1
        arguments.output.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"Merged {len(parts)} captures into {arguments.output}")
        return 0
    if arguments.source == "lpinfo":
        entries = capture_lpinfo()
        packages = {
            name: run_checked("dpkg-query", "-W", "-f=${Version}", name).strip()
            for name in sorted({entry["package"] for entry in entries if entry["package"]})
        }
    else:
        if not arguments.family:
            parser.error("--family is required unless --merge or --source lpinfo is given")
        advertised = advertised_models()
        if arguments.source == "program":
            entries = capture_program(arguments.family, advertised)
        elif arguments.source == "drv":
            entries = capture_drv(arguments.family, advertised)
        elif arguments.source == "ppd":
            entries = capture_ppds(arguments.family, advertised, PPD_SEARCH_ROOTS)
        else:
            entries = capture_gutenprint(arguments.family, advertised)
        packages = {arguments.family: run_checked("dpkg-query", "-W", "-f=${Version}", arguments.family).strip()}
    arguments.output.write_text(
        json.dumps(capture_envelope(entries, packages, arguments.label), indent=2, sort_keys=True) + "\n",
        encoding="utf-8")
    print(f"Captured {len(entries)} entries to {arguments.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
