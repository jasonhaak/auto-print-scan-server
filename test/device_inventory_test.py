#!/usr/bin/env python3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/lib/device_inventory.py"


class DeviceInventoryTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.directory = Path(self.tempdir.name)
        self.inventory = self.directory / "print_servers.yml"
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

    def test_lists_existing_devices(self):
        result = self.run_helper("list")
        self.assertIn("office", result.stdout)
        self.assertIn("No managed scanners", result.stdout)

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

    def test_adds_scanner_settings_when_first_scanner_is_added(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng,deu",
        )

        data = self.load()
        self.assertEqual(data["managed_scanners"][0]["device_name"], "airscan:e0:Office Scanner")
        self.assertEqual(data["scanservjs_retention_days"], 90)
        self.assertEqual(data["scanservjs_ocr_languages"], ["eng", "deu"])

    def test_adds_a_generic_network_scanner_without_usb_fields(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "net:192.0.2.40:vendor:dev0",
            "--connection", "network", "--backend", "sane-utils",
            "--retention-days", "90", "--ocr-languages", "eng",
        )

        scanner = self.load()["managed_scanners"][0]
        self.assertEqual(scanner["connection"], "network")
        self.assertNotIn("usb_mode", scanner)
        self.assertNotIn("usb_identity", scanner)

    def test_deletes_a_device_without_changing_other_definitions(self):
        self.run_helper(
            "upsert-scanner", "--device-name", "airscan:e0:Office Scanner",
            "--connection", "ipp", "--backend", "sane-airscan",
            "--retention-days", "90", "--ocr-languages", "eng",
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

    def test_reads_fields_for_prompt_defaults(self):
        result = self.run_helper("field", "printer", "office", "device_uri")
        self.assertEqual(result.stdout, "ipp://office.local/ipp/print")

    def test_adds_edits_lists_and_deletes_a_direct_ethernet_link(self):
        self.run_helper(
            "upsert-link", "--interface", "eth1", "--pi-ipv4-cidr", "192.168.50.1/30",
            "--device-ipv4", "192.168.50.2",
        )
        names = self.run_helper("names", "link")
        self.assertEqual(names.stdout, "eth1\n")
        self.run_helper(
            "upsert-link", "--original-interface", "eth1", "--interface", "enx1234",
            "--pi-ipv4-cidr", "192.168.60.1/30", "--device-ipv4", "192.168.60.2",
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
            "upsert-link", "--interface", "eth1", "--pi-ipv4-cidr", "192.168.50.1/30",
            "--device-ipv4", "192.168.60.2", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("same IPv4 /30", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)

    def test_rejects_a_direct_link_overlapping_the_trusted_lan(self):
        before = self.inventory.read_text(encoding="utf-8")
        result = self.run_helper(
            "upsert-link", "--interface", "eth1", "--pi-ipv4-cidr", "192.168.178.1/30",
            "--device-ipv4", "192.168.178.2", check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlaps trusted LAN", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), before)


if __name__ == "__main__":
    unittest.main()
