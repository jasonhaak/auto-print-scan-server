#!/usr/bin/env python3
"""Validate and atomically update managed device and direct-link definitions."""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import shutil
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import yaml


PRINTER_CONNECTIONS = {"ipp", "ipps", "socket", "lpd", "usb"}
SCANNER_CONNECTIONS = {"ipp", "ipps", "network", "usb"}
USB_MODES = {"ipp_usb", "legacy_usb"}
QUEUE_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+$")
USB_IDENTITY_PATTERN = re.compile(r"^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}$")
PRINTER_URI_SCHEMES = {
    "ipp": {"ipp"},
    "ipps": {"ipps"},
    "socket": {"socket"},
    "lpd": {"lpd"},
    "usb": {"dnssd", "ipp", "ipps", "usb"},
}
OCR_LANGUAGE_PATTERN = re.compile(r"^[A-Za-z0-9_]+$")
PACKAGE_PROFILES_PATH = Path(__file__).resolve().parents[2] / "vars/driver_profiles.yml"


class InventoryError(ValueError):
    pass


def known_package_profiles() -> set[str]:
    try:
        data = yaml.safe_load(PACKAGE_PROFILES_PATH.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        raise InventoryError(f"package profile registry is unavailable: {error}") from error
    profiles = data.get("package_profiles") if isinstance(data, dict) else None
    if not isinstance(profiles, dict):
        raise InventoryError("package profile registry must contain package_profiles")
    return set(profiles)


def package_profile_model_prefix(name: str) -> str:
    try:
        data = yaml.safe_load(PACKAGE_PROFILES_PATH.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        raise InventoryError(f"package profile registry is unavailable: {error}") from error
    profiles = data.get("package_profiles") if isinstance(data, dict) else None
    profile = profiles.get(name) if isinstance(profiles, dict) else None
    if not isinstance(profile, dict):
        raise InventoryError(f"unknown package profile {name!r}")
    return require_text(profile.get("model_prefix"), f"package profile {name!r} model_prefix")


def matching_package_profiles(identity_evidence: str) -> list[tuple[str, str]]:
    try:
        data = yaml.safe_load(PACKAGE_PROFILES_PATH.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        raise InventoryError(f"package profile registry is unavailable: {error}") from error
    profiles = data.get("package_profiles") if isinstance(data, dict) else None
    if not isinstance(profiles, dict):
        raise InventoryError("package profile registry must contain package_profiles")
    matches = []
    for name, profile in profiles.items():
        if not isinstance(profile, dict):
            continue
        pattern = profile.get("make_model_pattern")
        if isinstance(pattern, str) and re.search(pattern, identity_evidence):
            matches.append((name, str(profile.get("description", "repository package profile"))))
    return matches


def printer_uri_is_valid(connection: str, uri: str) -> bool:
    """Authoritative printer URI-scheme rule, shared with the interactive Bash prompts."""
    if connection not in PRINTER_URI_SCHEMES:
        return False
    if not uri or any(character.isspace() for character in uri):
        return False
    return urlsplit(uri).scheme.lower() in PRINTER_URI_SCHEMES[connection]


def usb_identity_is_valid(identity: str) -> bool:
    """Authoritative USB vendor:product identity rule, shared with the interactive Bash prompts."""
    return bool(USB_IDENTITY_PATTERN.fullmatch(identity))


def load_inventory(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise InventoryError(f"inventory file does not exist: {path}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as error:
        raise InventoryError(f"inventory YAML is invalid: {error}") from error
    if not isinstance(data, dict):
        raise InventoryError("inventory must contain a YAML mapping")
    data.setdefault("managed_printers", [])
    data.setdefault("managed_scanners", [])
    data.setdefault("direct_ethernet_links", [])
    validate_inventory(data)
    return data


def require_text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip() or "\n" in value or "\r" in value:
        raise InventoryError(f"{label} must be a non-empty single-line value")
    return value


def validate_printer(printer: Any) -> None:
    if not isinstance(printer, dict):
        raise InventoryError("every managed printer must be a mapping")
    name = require_text(printer.get("name"), "printer name")
    if not QUEUE_PATTERN.fullmatch(name):
        raise InventoryError(f"printer name {name!r} is not a safe CUPS queue name")

    connection = printer.get("connection")
    if connection not in PRINTER_CONNECTIONS:
        raise InventoryError(f"printer {name!r} has unsupported connection {connection!r}")
    uri = require_text(printer.get("device_uri"), f"printer {name!r} device URI")
    scheme = urlsplit(uri).scheme.lower()
    expected_schemes = PRINTER_URI_SCHEMES[connection]
    if scheme not in expected_schemes:
        expected = " or ".join(f"{item}://" for item in sorted(expected_schemes))
        raise InventoryError(f"printer {name!r} with connection {connection!r} requires {expected}")

    driver_mode = printer.get("driver_mode")
    if driver_mode not in {"driverless", "package_profile"}:
        raise InventoryError(f"printer {name!r} has unsupported driver mode {driver_mode!r}")
    if driver_mode == "package_profile":
        profile = require_text(printer.get("package_profile"), f"printer {name!r} package profile")
        if profile not in known_package_profiles():
            raise InventoryError(f"printer {name!r} has unknown package profile {profile!r}")
        require_text(printer.get("cups_model"), f"printer {name!r} CUPS model")

    shared = printer.get("shared", True)
    if not isinstance(shared, bool):
        raise InventoryError(f"printer {name!r} shared must be true or false")
    dns_sd_name = printer.get("dns_sd_name")
    if dns_sd_name is not None:
        dns_sd_name = require_text(dns_sd_name, f"printer {name!r} DNS-SD name")
        if not QUEUE_PATTERN.fullmatch(dns_sd_name):
            raise InventoryError(f"printer {name!r} DNS-SD name {dns_sd_name!r} is not a safe DNS-SD label")
    if connection == "usb":
        usb_mode = printer.get("usb_mode")
        if usb_mode not in USB_MODES:
            raise InventoryError(f"USB printer {name!r} must select ipp_usb or legacy_usb")
        identity = require_text(printer.get("usb_identity"), f"USB printer {name!r} identity")
        if not USB_IDENTITY_PATTERN.fullmatch(identity):
            raise InventoryError(f"USB printer {name!r} identity must use vendor:product form")
        if usb_mode == "ipp_usb" and (driver_mode != "driverless" or scheme == "usb"):
            raise InventoryError(f"IPP-over-USB printer {name!r} requires a driverless IPP or DNS-SD URI")
        if usb_mode == "legacy_usb" and (driver_mode != "package_profile" or scheme != "usb"):
            raise InventoryError(f"legacy USB printer {name!r} requires a usb:// URI and package profile")


def validate_scanner(scanner: Any) -> None:
    if not isinstance(scanner, dict):
        raise InventoryError("every managed scanner must be a mapping")
    name = require_text(scanner.get("device_name"), "scanner device name")
    connection = scanner.get("connection")
    if connection not in SCANNER_CONNECTIONS:
        raise InventoryError(f"scanner {name!r} has unsupported connection {connection!r}")
    require_text(scanner.get("backend"), f"scanner {name!r} backend")
    backend_install = scanner.get("backend_install", True)
    if not isinstance(backend_install, bool):
        raise InventoryError(f"scanner {name!r} backend_install must be true or false")
    if connection == "usb" and scanner.get("usb_mode") not in USB_MODES:
        raise InventoryError(f"USB scanner {name!r} must select ipp_usb or legacy_usb")
    identity = scanner.get("usb_identity")
    if identity is not None and not USB_IDENTITY_PATTERN.fullmatch(str(identity)):
        raise InventoryError(f"scanner {name!r} identity must use vendor:product form")
    display_name = scanner.get("display_name")
    if display_name is not None:
        require_text(display_name, f"scanner {name!r} display name")


def validate_direct_link(link: Any) -> None:
    if not isinstance(link, dict):
        raise InventoryError("every direct Ethernet link must be a mapping")
    interface = require_text(link.get("interface"), "direct Ethernet interface")
    if not QUEUE_PATTERN.fullmatch(interface):
        raise InventoryError(f"direct Ethernet interface {interface!r} is invalid")
    try:
        pi = ipaddress.ip_interface(require_text(link.get("pi_ipv4_cidr"), f"link {interface!r} Pi IPv4 CIDR"))
        device = ipaddress.ip_address(require_text(link.get("device_ipv4"), f"link {interface!r} device IPv4"))
    except ValueError as error:
        raise InventoryError(f"direct Ethernet link {interface!r} has an invalid IPv4 value: {error}") from error
    valid = (
        pi.version == 4
        and pi.network.prefixlen == 30
        and device.version == 4
        and device in pi.network
        and device not in {pi.ip, pi.network.network_address, pi.network.broadcast_address}
    )
    if not valid:
        raise InventoryError(f"direct Ethernet link {interface!r} requires two host addresses in the same IPv4 /30")


def validate_inventory(data: dict[str, Any]) -> None:
    printers = data.get("managed_printers")
    scanners = data.get("managed_scanners")
    if not isinstance(printers, list) or not isinstance(scanners, list):
        raise InventoryError("managed_printers and managed_scanners must be lists")
    if not printers and not scanners:
        raise InventoryError("inventory must contain at least one managed printer or managed scanner")
    for printer in printers:
        validate_printer(printer)
    for scanner in scanners:
        validate_scanner(scanner)
    printer_names = [printer["name"] for printer in printers]
    scanner_names = [scanner["device_name"] for scanner in scanners]
    if len(set(printer_names)) != len(printer_names):
        raise InventoryError("managed printer names must be unique")
    if len(set(scanner_names)) != len(scanner_names):
        raise InventoryError("managed scanner device names must be unique")
    links = data.get("direct_ethernet_links")
    if not isinstance(links, list):
        raise InventoryError("direct_ethernet_links must be a list")
    for link in links:
        validate_direct_link(link)
    link_interfaces = [link["interface"] for link in links]
    if len(set(link_interfaces)) != len(link_interfaces):
        raise InventoryError("direct Ethernet link interfaces must be unique")
    trusted_networks: list[ipaddress.IPv4Network | ipaddress.IPv6Network] = []
    for cidr in data.get("trusted_lan_cidrs", []):
        try:
            trusted_networks.append(ipaddress.ip_network(cidr, strict=True))
        except ValueError as error:
            raise InventoryError(f"trusted LAN CIDR {cidr!r} is invalid: {error}") from error
    for link in links:
        link_network = ipaddress.ip_interface(link["pi_ipv4_cidr"]).network
        if any(network.version == 4 and link_network.overlaps(network) for network in trusted_networks):
            raise InventoryError(f"direct Ethernet link {link['interface']!r} overlaps trusted LAN")
    if scanners:
        port = data.get("scanservjs_port")
        if not isinstance(port, int) or not 1 <= port <= 65535:
            raise InventoryError("scanner inventory requires scanservjs_port from 1 to 65535")
        retention = data.get("scanservjs_retention_days")
        if not isinstance(retention, int) or not 1 <= retention <= 900:
            raise InventoryError("scanner inventory requires scanservjs_retention_days from 1 to 900")
        languages = data.get("scanservjs_ocr_languages")
        if not isinstance(languages, list) or not languages:
            raise InventoryError("scanner inventory requires at least one OCR language")
        if any(not isinstance(item, str) or not OCR_LANGUAGE_PATTERN.fullmatch(item) for item in languages):
            raise InventoryError("OCR languages must contain only letters, numbers and underscores")
        page_splitting = data.get("scanservjs_page_splitting")
        if page_splitting is not None and not isinstance(page_splitting, bool):
            raise InventoryError("scanservjs_page_splitting must be true or false")


def devices(data: dict[str, Any], kind: str) -> list[dict[str, Any]]:
    collection = {"printer": "managed_printers", "scanner": "managed_scanners", "link": "direct_ethernet_links"}[kind]
    return data[collection]


def identity_key(kind: str) -> str:
    return {"printer": "name", "scanner": "device_name", "link": "interface"}[kind]


def find_device(data: dict[str, Any], kind: str, identity: str) -> dict[str, Any]:
    key = identity_key(kind)
    for device in devices(data, kind):
        if device.get(key) == identity:
            return device
    raise InventoryError(f"managed {kind} not found: {identity}")


def backup_and_write(path: Path, backup_directory: Path, data: dict[str, Any]) -> Path:
    validate_inventory(data)
    backup_directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = backup_directory / f"{path.name}.{stamp}"
    shutil.copy2(path, backup)

    header = "---\n# Maintained by scripts/onboard and scripts/manage-devices. Do not store passwords here.\n"
    rendered = header + yaml.safe_dump(data, sort_keys=False, default_flow_style=False, width=1000)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(rendered)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, path.stat().st_mode & 0o777)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)
    return backup


def validate_yaml_document(path: Path, label: str) -> None:
    if not path.is_file():
        raise InventoryError(f"{label} file does not exist: {path}")
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as error:
        raise InventoryError(f"{label} YAML is invalid: {error}") from error
    if not isinstance(document, dict):
        raise InventoryError(f"{label} must contain a YAML mapping")


def write_initial_inventory(
    host_target: Path, variables_target: Path, host_document: Path, variables_document: Path, backup_directory: Path
) -> tuple[Path, Path]:
    if host_target == variables_target:
        raise InventoryError("host and device-variable inventory targets must be different")
    validate_yaml_document(host_document, "host inventory document")
    variables = load_inventory(variables_document)
    rendered = {
        host_target: host_document.read_text(encoding="utf-8"),
        variables_target: "---\n# Maintained by scripts/onboard and scripts/manage-devices. Do not store passwords here.\n"
        + yaml.safe_dump(variables, sort_keys=False, default_flow_style=False, width=1000),
    }
    for target in rendered:
        if not target.is_file():
            raise InventoryError(f"inventory target does not exist: {target}")
    backup_directory.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backups = {target: backup_directory / f"{target.name}.{stamp}" for target in rendered}
    temporary_names: dict[Path, str] = {}
    try:
        for target, content in rendered.items():
            shutil.copy2(target, backups[target])
            descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
            temporary_names[target] = temporary_name
            with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
                temporary.write(content)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.chmod(temporary_name, target.stat().st_mode & 0o777)
        for target in (host_target, variables_target):
            os.replace(temporary_names.pop(target), target)
    finally:
        for temporary_name in temporary_names.values():
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)
    return backups[host_target], backups[variables_target]


def parse_bool(value: str) -> bool:
    if value not in {"true", "false"}:
        raise argparse.ArgumentTypeError("expected true or false")
    return value == "true"


def upsert(data: dict[str, Any], kind: str, original: str | None, replacement: dict[str, Any]) -> str:
    collection = devices(data, kind)
    key = identity_key(kind)
    target = original or replacement[key]
    existing_index = next((index for index, item in enumerate(collection) if item.get(key) == target), None)
    if original and existing_index is None:
        raise InventoryError(f"managed {kind} not found: {original}")
    duplicate = next((item for item in collection if item.get(key) == replacement[key] and item.get(key) != target), None)
    if duplicate:
        raise InventoryError(f"managed {kind} already exists: {replacement[key]}")
    if existing_index is None:
        collection.append(replacement)
        return "added"
    merged = dict(collection[existing_index])
    merged.update(replacement)
    collection[existing_index] = merged
    return "updated"


def command_list(data: dict[str, Any]) -> None:
    printers = data["managed_printers"]
    scanners = data["managed_scanners"]
    print("Managed printers:")
    for printer in printers:
        sharing = "shared" if printer.get("shared", True) else "not shared"
        print(f"  {printer['name']}: {printer['connection']} -> {printer['device_uri']} ({sharing})")
    if scanners:
        print("Managed scanners:")
        for scanner in scanners:
            label = f" ({scanner['display_name']})" if scanner.get("display_name") else ""
            print(f"  {scanner['device_name']}{label}: {scanner['connection']} via {scanner['backend']}")
    else:
        print("No managed scanners.")
    links = data["direct_ethernet_links"]
    if links:
        print("Direct Ethernet links:")
        for link in links:
            print(f"  {link['interface']}: {link['pi_ipv4_cidr']} -> {link['device_ipv4']}")
    else:
        print("No direct Ethernet links.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path)
    parser.add_argument("--backup-directory", type=Path)
    parser.add_argument("--host-inventory", type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list")

    validate_uri = commands.add_parser(
        "validate-uri", help="check a printer device URI against a connection type, without an inventory file"
    )
    validate_uri.add_argument("connection", choices=sorted(PRINTER_CONNECTIONS))
    validate_uri.add_argument("uri")

    validate_usb_identity = commands.add_parser(
        "validate-usb-identity", help="check a USB vendor:product identity, without an inventory file"
    )
    validate_usb_identity.add_argument("identity")

    names = commands.add_parser("names")
    names.add_argument("kind", choices=["printer", "scanner", "link"])
    field = commands.add_parser("field")
    field.add_argument("kind", choices=["printer", "scanner", "link"])
    field.add_argument("identity")
    field.add_argument("field")
    show = commands.add_parser("show")
    show.add_argument("kind", choices=["printer", "scanner", "link"])
    show.add_argument("identity")

    printer = commands.add_parser("upsert-printer")
    printer.add_argument("--original-name")
    printer.add_argument("--name", required=True)
    printer.add_argument("--connection", required=True, choices=sorted(PRINTER_CONNECTIONS))
    printer.add_argument("--device-uri", required=True)
    printer.add_argument("--driver-mode", required=True, choices=["driverless", "package_profile"])
    printer.add_argument("--shared", required=True, type=parse_bool)
    printer.add_argument("--dns-sd-name")
    printer.add_argument("--package-profile")
    printer.add_argument("--cups-model")
    printer.add_argument("--usb-mode", choices=sorted(USB_MODES))
    printer.add_argument("--usb-identity")

    scanner = commands.add_parser("upsert-scanner")
    scanner.add_argument("--original-device-name")
    scanner.add_argument("--device-name", required=True)
    scanner.add_argument("--connection", required=True, choices=sorted(SCANNER_CONNECTIONS))
    scanner.add_argument("--backend", required=True)
    scanner.add_argument("--backend-install", type=parse_bool, default=True)
    scanner.add_argument("--usb-mode", choices=sorted(USB_MODES))
    scanner.add_argument("--usb-identity")
    scanner.add_argument("--display-name")
    scanner.add_argument("--retention-days", type=int)
    scanner.add_argument("--ocr-languages")
    scanner.add_argument("--port", type=int)
    scanner.add_argument("--page-splitting", type=parse_bool)

    link = commands.add_parser("upsert-link")
    link.add_argument("--original-interface")
    link.add_argument("--interface", required=True)
    link.add_argument("--pi-ipv4-cidr", required=True)
    link.add_argument("--device-ipv4", required=True)

    delete = commands.add_parser("delete")
    delete.add_argument("kind", choices=["printer", "scanner", "link"])
    delete.add_argument("identity")
    commands.add_parser("validate")
    initial_write = commands.add_parser("write-initial")
    initial_write.add_argument("--host-document", required=True, type=Path)
    initial_write.add_argument("--variables-document", required=True, type=Path)
    profiles = commands.add_parser("profiles-for-evidence")
    profiles.add_argument("identity_evidence")
    profile_prefix = commands.add_parser("profile-model-prefix")
    profile_prefix.add_argument("profile")
    return parser


def main() -> int:
    arguments = build_parser().parse_args()
    if arguments.command == "validate-uri":
        return 0 if printer_uri_is_valid(arguments.connection, arguments.uri) else 1
    if arguments.command == "validate-usb-identity":
        return 0 if usb_identity_is_valid(arguments.identity) else 1
    if arguments.command == "profile-model-prefix":
        try:
            print(package_profile_model_prefix(arguments.profile))
            return 0
        except InventoryError as error:
            print(f"Error: {error}", file=sys.stderr)
            return 2
    if arguments.inventory is None or arguments.backup_directory is None:
        print("Error: --inventory and --backup-directory are required for this command", file=sys.stderr)
        return 2
    try:
        if arguments.command == "write-initial":
            if arguments.host_inventory is None:
                raise InventoryError("--host-inventory is required for write-initial")
            host_backup, variables_backup = write_initial_inventory(
                arguments.host_inventory,
                arguments.inventory,
                arguments.host_document,
                arguments.variables_document,
                arguments.backup_directory,
            )
            print(f"Wrote initial production inventory. Backups: {host_backup}, {variables_backup}")
            return 0
        data = load_inventory(arguments.inventory)
        if arguments.command == "profiles-for-evidence":
            for name, description in matching_package_profiles(arguments.identity_evidence):
                print(f"{name}|{description}")
            return 0
        if arguments.command == "list":
            command_list(data)
            return 0
        if arguments.command == "names":
            key = identity_key(arguments.kind)
            sys.stdout.write("".join(f"{item[key]}\n" for item in devices(data, arguments.kind)))
            return 0
        if arguments.command == "field":
            value = find_device(data, arguments.kind, arguments.identity).get(arguments.field, "")
            if isinstance(value, bool):
                value = str(value).lower()
            sys.stdout.write(str(value))
            return 0
        if arguments.command == "show":
            sys.stdout.write(yaml.safe_dump(find_device(data, arguments.kind, arguments.identity), sort_keys=False))
            return 0
        if arguments.command == "validate":
            print("Device inventory is valid.")
            return 0

        if arguments.command == "upsert-printer":
            replacement: dict[str, Any] = {
                "name": arguments.name,
                "connection": arguments.connection,
                "device_uri": arguments.device_uri,
                "driver_mode": arguments.driver_mode,
                "shared": arguments.shared,
            }
            if arguments.package_profile:
                replacement["package_profile"] = arguments.package_profile
            if arguments.cups_model:
                replacement["cups_model"] = arguments.cups_model
            if arguments.dns_sd_name:
                replacement["dns_sd_name"] = arguments.dns_sd_name
            if arguments.usb_mode:
                replacement["usb_mode"] = arguments.usb_mode
            if arguments.usb_identity:
                replacement["usb_identity"] = arguments.usb_identity
            action = upsert(data, "printer", arguments.original_name, replacement)
            selected = find_device(data, "printer", arguments.name)
            if selected["driver_mode"] == "driverless":
                selected.pop("package_profile", None)
                selected.pop("cups_model", None)
            if selected["connection"] != "usb":
                selected.pop("usb_mode", None)
                selected.pop("usb_identity", None)
            label = arguments.name
        elif arguments.command == "upsert-scanner":
            replacement = {
                "device_name": arguments.device_name,
                "connection": arguments.connection,
                "backend": arguments.backend,
            }
            if not arguments.backend_install:
                replacement["backend_install"] = False
            if arguments.usb_mode:
                replacement["usb_mode"] = arguments.usb_mode
            if arguments.usb_identity:
                replacement["usb_identity"] = arguments.usb_identity
            if arguments.display_name:
                replacement["display_name"] = arguments.display_name
            action = upsert(data, "scanner", arguments.original_device_name, replacement)
            selected = find_device(data, "scanner", arguments.device_name)
            if selected["connection"] != "usb":
                selected.pop("usb_mode", None)
                selected.pop("usb_identity", None)
            if arguments.retention_days is not None:
                data["scanservjs_retention_days"] = arguments.retention_days
            if arguments.ocr_languages is not None:
                data["scanservjs_ocr_languages"] = [
                    item.strip() for item in arguments.ocr_languages.split(",") if item.strip()
                ]
            if arguments.port is not None:
                data["scanservjs_port"] = arguments.port
            if arguments.page_splitting is not None:
                data["scanservjs_page_splitting"] = arguments.page_splitting
            label = arguments.device_name
        elif arguments.command == "upsert-link":
            replacement = {
                "interface": arguments.interface,
                "pi_ipv4_cidr": arguments.pi_ipv4_cidr,
                "device_ipv4": arguments.device_ipv4,
            }
            action = upsert(data, "link", arguments.original_interface, replacement)
            label = arguments.interface
        else:
            collection = devices(data, arguments.kind)
            key = identity_key(arguments.kind)
            find_device(data, arguments.kind, arguments.identity)
            collection[:] = [item for item in collection if item[key] != arguments.identity]
            action = "deleted"
            label = arguments.identity

        backup = backup_and_write(arguments.inventory, arguments.backup_directory, data)
        print(f"{action.capitalize()} {label}. Backup: {backup}")
        return 0
    except InventoryError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
