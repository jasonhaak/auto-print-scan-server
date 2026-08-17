#!/usr/bin/env python3
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/lib/device_inventory.py"


def run_standalone(*arguments, check=True):
    """Run the helper without --inventory/--backup-directory, for the standalone
    validate-uri and validate-usb-identity subcommands."""
    return subprocess.run(
        [sys.executable, str(HELPER), *arguments],
        check=check,
        text=True,
        capture_output=True,
    )


class DeviceInventoryTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.directory = Path(self.tempdir.name)
        self.inventory = self.directory / "print_servers.yml"
        self.host_inventory = self.directory / "hosts.yml"
        self.backups = self.directory / "backups"
        self.inventory.write_text(
            """---
common_hostname: print-server
trusted_lan_cidrs:
  - 192.168.178.0/24
managed_printers:
  - name: office
    connection: ipp
    device_uri: ipp://office.local/ipp/print
    driver_mode: driverless
    shared: true
managed_scanners: []
direct_ethernet_links: []
scanservjs_retention_days: null
scanservjs_ocr_languages: [eng]
""",
            encoding="utf-8",
        )
        self.host_inventory.write_text("---\nall: {children: {print_servers: {hosts: {print-server: {}}}}}\n", encoding="utf-8")

    def run_helper(self, *arguments, check=True):
        return subprocess.run(
            [sys.executable, str(HELPER), "--inventory", str(self.inventory),
             "--backup-directory", str(self.backups), *arguments],
            check=check,
            text=True,
            capture_output=True,
        )

    def load(self):
        return yaml.safe_load(self.inventory.read_text(encoding="utf-8"))

    def test_accepts_a_scanner_only_inventory(self):
        self.inventory.write_text(
            """---
common_hostname: print-server
trusted_lan_cidrs:
  - 192.168.178.0/24
managed_printers: []
managed_scanners:
  - device_name: "airscan:e0:Office Scanner"
    connection: network
    backend: sane-airscan
direct_ethernet_links: []
scanservjs_retention_days: 90
scanservjs_ocr_languages: [eng]
scanservjs_port: 8080
""",
            encoding="utf-8",
        )
        result = self.run_helper("list")
        self.assertIn("Office Scanner", result.stdout)

    def test_rejects_an_inventory_with_neither_printers_nor_scanners(self):
        self.inventory.write_text(
            """---
common_hostname: print-server
trusted_lan_cidrs:
  - 192.168.178.0/24
managed_printers: []
managed_scanners: []
direct_ethernet_links: []
scanservjs_retention_days: null
scanservjs_ocr_languages: [eng]
""",
            encoding="utf-8",
        )
        result = self.run_helper("list", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("at least one managed printer or managed scanner", result.stderr)

    def test_lists_existing_devices(self):
        result = self.run_helper("list")
        self.assertIn("office", result.stdout)
        self.assertIn("No managed scanners", result.stdout)

    def test_writes_initial_host_and_device_inventory_with_unique_backups(self):
        host_document = self.directory / "new-hosts.yml"
        variables_document = self.directory / "new-variables.yml"
        host_document.write_text("---\nall: {children: {print_servers: {hosts: {print-server: {ansible_host: 192.0.2.20}}}}}\n", encoding="utf-8")
        variables_document.write_text(self.inventory.read_text(encoding="utf-8").replace("print-server", "new-server"), encoding="utf-8")
        self.inventory.chmod(0o640)
        result = subprocess.run(
            [sys.executable, str(HELPER), "--inventory", str(self.inventory), "--host-inventory", str(self.host_inventory),
             "--backup-directory", str(self.backups), "write-initial", "--host-document", str(host_document),
             "--variables-document", str(variables_document)],
            check=True, text=True, capture_output=True,
        )
        self.assertIn("Wrote initial production inventory", result.stdout)
        self.assertIn("192.0.2.20", self.host_inventory.read_text(encoding="utf-8"))
        self.assertIn("new-server", self.inventory.read_text(encoding="utf-8"))
        self.assertEqual(self.inventory.stat().st_mode & 0o777, 0o640)
        self.assertEqual(len(list(self.backups.iterdir())), 2)

    def test_rejects_invalid_initial_variables_without_replacing_either_inventory(self):
        host_document = self.directory / "new-hosts.yml"
        variables_document = self.directory / "invalid-variables.yml"
        host_document.write_text("---\nall: {}\n", encoding="utf-8")
        variables_document.write_text("---\nmanaged_printers: []\n", encoding="utf-8")
        before_host = self.host_inventory.read_text(encoding="utf-8")
        before_variables = self.inventory.read_text(encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(HELPER), "--inventory", str(self.inventory), "--host-inventory", str(self.host_inventory),
             "--backup-directory", str(self.backups), "write-initial", "--host-document", str(host_document),
             "--variables-document", str(variables_document)],
            check=False, text=True, capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.host_inventory.read_text(encoding="utf-8"), before_host)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before_variables)
        self.assertFalse(self.backups.exists())

    def test_adds_and_edits_a_printer_atomically_with_backup(self):
        self.run_helper(
            "upsert-printer", "--name", "label", "--connection", "socket",
            "--device-uri", "socket://label.local:9100", "--driver-mode", "driverless",
            "--shared", "false",
        )
        self.run_helper(
            "upsert-printer", "--original-name", "label", "--name", "labels",
            "--connection", "socket", "--device-uri", "socket://labels.local:9100",
            "--driver-mode", "driverless", "--shared", "false",
        )

        printers = self.load()["managed_printers"]
        self.assertEqual([printer["name"] for printer in printers], ["office", "labels"])
        self.assertEqual(printers[1]["device_uri"], "socket://labels.local:9100")
        self.assertGreaterEqual(len(list(self.backups.iterdir())), 2)

    def test_printer_dns_sd_name_defaults_to_the_queue_name_when_omitted(self):
        self.run_helper(
            "upsert-printer", "--name", "label", "--connection", "socket",
            "--device-uri", "socket://label.local:9100", "--driver-mode", "driverless",
            "--shared", "false",
        )

        printer = next(printer for printer in self.load()["managed_printers"] if printer["name"] == "label")
        self.assertNotIn("dns_sd_name", printer)

    def test_printer_dns_sd_name_is_persisted_when_supplied(self):
        self.run_helper(
            "upsert-printer", "--name", "label", "--connection", "socket",
            "--device-uri", "socket://label.local:9100", "--driver-mode", "driverless",
            "--shared", "false", "--dns-sd-name", "haak-drucker",
        )

        printer = next(printer for printer in self.load()["managed_printers"] if printer["name"] == "label")
        self.assertEqual(printer["dns_sd_name"], "haak-drucker")

    def test_rejects_an_unsafe_dns_sd_name_without_writing(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-printer", "--name", "label", "--connection", "socket",
            "--device-uri", "socket://label.local:9100", "--driver-mode", "driverless",
            "--shared", "false", "--dns-sd-name", "bad name!", check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_adds_scanner_settings_when_first_scanner_is_added(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng,deu", "--port", "8080",
        )

        data = self.load()
        self.assertEqual(data["managed_scanners"][0]["device_name"], "airscan:e0:Office Scanner")
        self.assertEqual(data["scanservjs_retention_days"], 90)
        self.assertEqual(data["scanservjs_ocr_languages"], ["eng", "deu"])
        self.assertEqual(data["scanservjs_port"], 8080)

    def test_scanner_display_name_defaults_to_omitted(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng", "--port", "8080",
        )

        scanner = next(scanner for scanner in self.load()["managed_scanners"] if scanner["device_name"] == "airscan:e0:Office Scanner")
        self.assertNotIn("display_name", scanner)

    def test_scanner_display_name_is_persisted_when_supplied(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng", "--port", "8080",
            "--display-name", "Office Scanner",
        )

        scanner = next(scanner for scanner in self.load()["managed_scanners"] if scanner["device_name"] == "airscan:e0:Office Scanner")
        self.assertEqual(scanner["display_name"], "Office Scanner")

    def test_scanservjs_page_splitting_defaults_to_false_and_can_be_enabled(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng", "--port", "8080",
        )
        self.assertNotIn("scanservjs_page_splitting", self.load())

        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Second Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--page-splitting", "true",
        )
        self.assertIs(self.load()["scanservjs_page_splitting"], True)

    def test_rejects_a_non_boolean_page_splitting_value_without_writing(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--page-splitting", "sometimes", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_rejects_a_scanner_with_an_out_of_range_port_without_writing(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng", "--port", "70000",
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scanservjs_port", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_adds_a_generic_network_scanner_without_usb_fields(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "net:192.0.2.40:vendor:dev0",
            "--connection", "network", "--backend", "sane-utils",
            "--retention-days", "90", "--ocr-languages", "eng", "--port", "8080",
        )

        scanner = self.load()["managed_scanners"][0]
        self.assertEqual(scanner["connection"], "network")
        self.assertNotIn("usb_mode", scanner)
        self.assertNotIn("usb_identity", scanner)

    def test_preserves_a_preinstalled_scanner_backend_without_apt_ownership(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "brother:bus2;dev1",
            "--connection", "usb", "--backend", "brother", "--backend-install", "false",
            "--usb-mode", "legacy_usb", "--retention-days", "90",
            "--ocr-languages", "eng", "--port", "8080",
        )

        scanner = self.load()["managed_scanners"][0]
        self.assertEqual(scanner["backend"], "brother")
        self.assertIs(scanner["backend_install"], False)
        self.assertEqual(scanner["usb_mode"], "legacy_usb")

    def test_deletes_a_device_without_changing_other_definitions(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng", "--port", "8080",
        )
        self.run_helper("delete", "scanner", "airscan:e0:Office Scanner")

        data = self.load()
        self.assertEqual(data["managed_scanners"], [])
        self.assertEqual(data["managed_printers"][0]["name"], "office")

    def test_rejects_deleting_the_last_printer(self):
        result = self.run_helper("delete", "printer", "office", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("at least one managed printer", result.stderr)
        self.assertEqual(self.load()["managed_printers"][0]["name"], "office")

    def test_rejects_a_connection_uri_mismatch_without_writing(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-printer", "--name", "bad", "--connection", "socket",
            "--device-uri", "ipp://printer.local/ipp/print", "--driver-mode", "driverless",
            "--shared", "true", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("socket://", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_rejects_unknown_profiles_and_incompatible_usb_modes(self):
        before = self.inventory.read_text(encoding="utf-8")
        unknown = self.run_helper(
            "upsert-printer", "--name", "bad-profile", "--connection", "usb",
            "--device-uri", "usb://Brother/Printer", "--driver-mode", "package_profile",
            "--package-profile", "invented", "--usb-mode", "legacy_usb",
            "--usb-identity", "04f9:0270", "--shared", "true", check=False,
        )
        incompatible = self.run_helper(
            "upsert-printer", "--name", "bad-usb", "--connection", "usb",
            "--device-uri", "usb://Brother/Printer", "--driver-mode", "driverless",
            "--usb-mode", "ipp_usb", "--usb-identity", "04f9:0270",
            "--shared", "true", check=False,
        )
        self.assertIn("unknown package profile", unknown.stderr)
        self.assertIn("driverless IPP or DNS-SD URI", incompatible.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_package_profile_requires_and_persists_an_exact_cups_model(self):
        missing = self.run_helper(
            "upsert-printer", "--name", "legacy", "--connection", "usb",
            "--device-uri", "usb://Brother/Printer", "--driver-mode", "package_profile",
            "--package-profile", "brlaser", "--usb-mode", "legacy_usb",
            "--usb-identity", "04f9:0270", "--shared", "true", check=False,
        )
        self.assertIn("CUPS model", missing.stderr)
        self.run_helper(
            "upsert-printer", "--name", "legacy", "--connection", "usb",
            "--device-uri", "usb://Brother/Printer", "--driver-mode", "package_profile",
            "--package-profile", "brlaser", "--cups-model", "drv:///brlaser.drv/br7360.ppd",
            "--usb-mode", "legacy_usb", "--usb-identity", "04f9:0270", "--shared", "true",
        )
        self.assertEqual(self.load()["managed_printers"][1]["cups_model"], "drv:///brlaser.drv/br7360.ppd")

    def test_reports_a_profile_model_prefix_without_inventory(self):
        result = run_standalone("profile-model-prefix", "brlaser")
        self.assertEqual(result.stdout, "drv:///brlaser.drv/\n")

    def test_reads_fields_for_prompt_defaults(self):
        result = self.run_helper("field", "printer", "office", "device_uri")
        self.assertEqual(result.stdout, "ipp://office.local/ipp/print")

    def test_adds_edits_lists_and_deletes_a_direct_ethernet_link(self):
        self.run_helper(
            "upsert-link", "--interface", "eth1", "--server-ipv4-cidr", "192.168.50.1/30",
            "--device-ipv4", "192.168.50.2",
        )
        names = self.run_helper("names", "link")
        self.assertEqual(names.stdout, "eth1\n")
        self.run_helper(
            "upsert-link", "--original-interface", "eth1", "--interface", "enx1234",
            "--server-ipv4-cidr", "192.168.60.1/30", "--device-ipv4", "192.168.60.2",
        )
        link = self.load()["direct_ethernet_links"][0]
        self.assertEqual(link["interface"], "enx1234")
        self.assertEqual(link["device_ipv4"], "192.168.60.2")
        self.run_helper("delete", "link", "enx1234")
        self.assertEqual(self.load()["direct_ethernet_links"], [])
        self.assertGreaterEqual(len(list(self.backups.iterdir())), 3)

    def test_rejects_an_invalid_direct_ethernet_link_without_writing(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-link", "--interface", "eth1", "--server-ipv4-cidr", "192.168.50.1/30",
            "--device-ipv4", "192.168.60.2", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("same IPv4 /30", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_rejects_a_direct_link_overlapping_the_trusted_lan(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-link", "--interface", "eth1", "--server-ipv4-cidr", "192.168.178.1/30",
            "--device-ipv4", "192.168.178.2", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlaps trusted LAN", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_reports_matching_profile_from_ipp_identity_evidence(self):
        result = self.run_helper(
            "profiles-for-evidence",
            "printer-make-and-model (name-with-language Brother MFC-7360N)",
        )
        self.assertEqual(
            result.stdout,
            "brlaser|Brother laser printers supported by Debian's brlaser package\n",
        )

    def test_reports_no_profile_for_unqueryable_protocol_evidence(self):
        result = self.run_helper("profiles-for-evidence", "socket port 9100 is open")
        self.assertEqual(result.stdout, "")

    def test_validate_uri_subcommand_matches_upsert_printer_scheme_rule(self):
        # The standalone validate-uri subcommand (used by prompts.sh valid_printer_uri)
        # must agree with the connection/scheme rule that upsert-printer enforces,
        # since both now derive from the single PRINTER_URI_SCHEMES rule.
        accepted = run_standalone("validate-uri", "ipp", "ipp://printer.local/ipp/print")
        self.assertEqual(accepted.returncode, 0)
        rejected = run_standalone("validate-uri", "socket", "ipp://printer.local/ipp/print", check=False)
        self.assertNotEqual(rejected.returncode, 0)

        before = self.inventory.read_text(encoding="utf-8")
        mismatched = self.run_helper(
            "upsert-printer", "--name", "mismatched", "--connection", "socket",
            "--device-uri", "ipp://printer.local/ipp/print", "--driver-mode", "driverless",
            "--shared", "true", check=False,
        )
        self.assertNotEqual(mismatched.returncode, 0)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_validate_usb_identity_subcommand_matches_upsert_printer_pattern(self):
        # The standalone validate-usb-identity subcommand (used by prompts.sh
        # valid_usb_identity) must agree with the pattern upsert-printer enforces.
        accepted = run_standalone("validate-usb-identity", "04a9:1909")
        self.assertEqual(accepted.returncode, 0)
        rejected = run_standalone("validate-usb-identity", "04a9:190", check=False)
        self.assertNotEqual(rejected.returncode, 0)

        before = self.inventory.read_text(encoding="utf-8")
        invalid = self.run_helper(
            "upsert-printer", "--name", "bad-identity", "--connection", "usb",
            "--device-uri", "usb://Brother/Printer", "--driver-mode", "package_profile",
            "--package-profile", "brlaser", "--usb-mode", "legacy_usb",
            "--usb-identity", "04a9:190", "--shared", "true", check=False,
        )
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_onboard_and_manage_devices_persist_identical_printer_yaml(self):
        # scripts/onboard's additional-printer loop persists a printer definition by
        # printf/quote-ing YAML directly (see the managed_printers block near the end
        # of scripts/onboard), while scripts/manage-devices persists through
        # device_inventory.py's upsert-printer. Given identical inputs, both paths
        # must produce an identical persisted printer definition.
        name, connection, uri, driver = "printer-2", "ipp", "ipp://printer.local/ipp/print", "driverless"

        onboard_script = f'''
set -euo pipefail
root={shlex.quote(str(ROOT))}
source "$root/scripts/lib/onboarding/prompts.sh"
printf '%s\\n' 'managed_printers:'
printf '  - name: %s\\n    connection: %s\\n    device_uri: %s\\n    driver_mode: %s\\n    shared: true\\n' \\
  "$(quote {shlex.quote(name)})" "$(quote {shlex.quote(connection)})" \\
  "$(quote {shlex.quote(uri)})" "$(quote {shlex.quote(driver)})"
'''
        onboard_output = subprocess.run(
            ["bash", "-c", onboard_script], check=True, text=True, capture_output=True
        ).stdout
        onboard_printer = yaml.safe_load(onboard_output)["managed_printers"][0]

        self.run_helper(
            "upsert-printer", "--name", name, "--connection", connection,
            "--device-uri", uri, "--driver-mode", driver, "--shared", "true",
        )
        manage_devices_printer = next(
            printer for printer in self.load()["managed_printers"] if printer["name"] == name
        )

        self.assertEqual(onboard_printer, manage_devices_printer)


if __name__ == "__main__":
    unittest.main()
