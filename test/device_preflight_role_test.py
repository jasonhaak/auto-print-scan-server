#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


def task_names(path: Path) -> list[str]:
    tasks = yaml.safe_load(path.read_text(encoding="utf-8"))
    return [task["name"] for task in tasks]


class DevicePreflightRoleTest(unittest.TestCase):
    def test_installs_probe_tools_before_device_queries(self):
        tasks = yaml.safe_load(
            (ROOT / "roles/device_preflight/tasks/main.yml").read_text(encoding="utf-8")
        )
        names = [task["name"] for task in tasks]
        install_index = names.index("Install device preflight probe tools")
        printer_index = names.index("Check each declared printer")
        scanner_index = names.index("Check each declared scanner")
        self.assertLess(install_index, printer_index)
        self.assertLess(install_index, scanner_index)
        self.assertEqual(
            tasks[install_index]["ansible.builtin.apt"]["name"],
            ["cups-ipp-utils", "usbutils"],
        )

    def test_runs_after_cups_and_sane_are_configured(self):
        roles = yaml.safe_load((ROOT / "playbooks/site.yml").read_text(encoding="utf-8"))[0]["roles"]
        names = [role["role"] for role in roles]
        preflight_index = names.index("device_preflight")
        self.assertLess(names.index("cups"), preflight_index)
        self.assertLess(names.index("sane"), preflight_index)

    def test_legacy_usb_queue_requires_the_configured_cups_endpoint(self):
        tasks = yaml.safe_load(
            (ROOT / "roles/device_preflight/tasks/printer.yml").read_text(encoding="utf-8")
        )
        endpoint_task = next(
            task for task in tasks if task["name"] == "Check declared legacy USB printer CUPS endpoint"
        )
        self.assertEqual(endpoint_task["ansible.builtin.command"]["argv"][:3], ["lpstat", "-v", "{{ managed_device.name }}"])
        self.assertEqual(
            endpoint_task["when"],
            "managed_device.connection == 'usb' and managed_device.usb_mode == 'legacy_usb'",
        )


if __name__ == "__main__":
    unittest.main()
