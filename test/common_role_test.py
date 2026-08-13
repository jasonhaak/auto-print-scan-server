#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class CommonRoleTest(unittest.TestCase):
    def test_supported_architectures_are_not_raspberry_pi_only(self):
        defaults = yaml.safe_load((ROOT / "roles/common/defaults/main.yml").read_text(encoding="utf-8"))
        self.assertIn("aarch64", defaults["common_supported_architectures"])
        self.assertIn("x86_64", defaults["common_supported_architectures"])

    def test_platform_assert_does_not_require_raspberry_pi_os(self):
        tasks = yaml.safe_load((ROOT / "roles/common/tasks/main.yml").read_text(encoding="utf-8"))
        names = [task["name"] for task in tasks]
        self.assertNotIn("Detect Raspberry Pi OS", names)

        platform_assert = next(task for task in tasks if task["name"] == "Assert the supported operating system and architecture")
        conditions = platform_assert["ansible.builtin.assert"]["that"]
        self.assertFalse(any("raspberry_pi_os" in condition for condition in conditions))
        self.assertTrue(any("distribution ==" in condition for condition in conditions))
        self.assertTrue(any("architecture in common_supported_architectures" in condition for condition in conditions))

    def test_hostname_change_restarts_avahi_daemon(self):
        # avahi-daemon reads the system hostname once at its own startup and does not notice a
        # later hostname change on its own -- confirmed live: avahi-daemon had been running since
        # before a hostname rename and kept advertising every service (including CUPS printers)
        # under the old hostname indefinitely, with no restart to force it to pick up the new one.
        tasks = yaml.safe_load((ROOT / "roles/common/tasks/main.yml").read_text(encoding="utf-8"))
        hostname_task = next(task for task in tasks if task["name"] == "Set the system hostname")
        self.assertEqual(hostname_task.get("notify"), "Restart avahi-daemon")


if __name__ == "__main__":
    unittest.main()
