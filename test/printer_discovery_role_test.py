#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class PrinterDiscoveryRoleTest(unittest.TestCase):
    def setUp(self):
        self.tasks = yaml.safe_load(
            (ROOT / "roles/printer_discovery/tasks/main.yml").read_text(encoding="utf-8")
        )

    def test_ipptool_query_is_skipped_for_non_ipp_endpoints(self):
        # ipptool only understands ipp(s):// (and http(s)://) transports; a usb:// device_uri --
        # the common case for a package_profile legacy printer -- always fails with "URI required
        # before test file." Querying it is a guaranteed no-op, not an occasional flake.
        query_task = next(
            task for task in self.tasks if task["name"] == "Query declared legacy printers without changing them"
        )
        self.assertEqual(query_task.get("when"), "item.device_uri is match('^ipps?://')")

    def test_report_distinguishes_skipped_non_ipp_printers_from_a_failed_query(self):
        report_task = next(
            task for task in self.tasks if task["name"] == "Report legacy printer discovery results"
        )
        msg = report_task["ansible.builtin.debug"]["msg"]
        self.assertIn("skipped", msg)
        self.assertIn("cannot query directly", msg)

    def test_profile_matching_guards_against_a_skipped_query_result(self):
        profile_task = next(
            task for task in self.tasks if task["name"] == "Report matching repository package profiles"
        )
        self.assertIn("not (item.0.skipped | default(false))", profile_task["when"])


if __name__ == "__main__":
    unittest.main()
