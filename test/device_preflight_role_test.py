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

    def test_printer_probes_distinguish_missing_tool_from_unavailable_device(self):
        tasks = yaml.safe_load(
            (ROOT / "roles/device_preflight/tasks/printer.yml").read_text(encoding="utf-8")
        )
        names = [task["name"] for task in tasks]

        device_unavailable_assert = next(
            task for task in tasks if task["name"] == "Require available declared printer during commissioning"
        )
        self.assertEqual(
            device_unavailable_assert["ansible.builtin.assert"]["fail_msg"],
            "Declared printer {{ managed_device.name }} is unavailable.",
        )

        missing_tool_asserts = {
            "Require ipptool during commissioning": ("cups-ipp-utils", "ipptool"),
            "Require lsusb during commissioning": ("usbutils", "lsusb"),
            "Require lpstat during commissioning": ("cups", "lpstat"),
        }
        for task_name, (package, binary) in missing_tool_asserts.items():
            task = next(task for task in tasks if task["name"] == task_name)
            fail_msg = task["ansible.builtin.assert"]["fail_msg"]
            self.assertIn(package, fail_msg)
            self.assertIn(binary, fail_msg)
            self.assertNotEqual(fail_msg, device_unavailable_assert["ansible.builtin.assert"]["fail_msg"])
            self.assertEqual(task["when"], "print_server_commissioning | default(false) | bool")

        # The tool-presence checks and their asserts must run before the generic
        # device-unavailable assert, so a missing tool is reported distinctly.
        self.assertLess(names.index("Check ipptool is installed"), names.index("Require ipptool during commissioning"))
        self.assertLess(
            names.index("Require ipptool during commissioning"),
            names.index("Require available declared printer during commissioning"),
        )
        self.assertLess(
            names.index("Require lsusb during commissioning"),
            names.index("Require available declared printer during commissioning"),
        )
        self.assertLess(
            names.index("Require lpstat during commissioning"),
            names.index("Require available declared printer during commissioning"),
        )

    def test_scanner_probe_distinguishes_missing_tool_from_unavailable_device(self):
        tasks = yaml.safe_load(
            (ROOT / "roles/device_preflight/tasks/scanner.yml").read_text(encoding="utf-8")
        )
        names = [task["name"] for task in tasks]

        device_unavailable_assert = next(
            task for task in tasks if task["name"] == "Require declared scanner during commissioning"
        )
        self.assertEqual(
            device_unavailable_assert["ansible.builtin.assert"]["fail_msg"],
            "Declared scanner {{ managed_device.device_name }} is unavailable.",
        )

        missing_tool_assert = next(
            task for task in tasks if task["name"] == "Require scanimage during commissioning"
        )
        fail_msg = missing_tool_assert["ansible.builtin.assert"]["fail_msg"]
        self.assertIn("sane-utils", fail_msg)
        self.assertIn("scanimage", fail_msg)
        self.assertNotEqual(fail_msg, device_unavailable_assert["ansible.builtin.assert"]["fail_msg"])
        self.assertEqual(
            missing_tool_assert["when"], "print_server_commissioning | default(false) | bool"
        )

        self.assertLess(names.index("Check scanimage is installed"), names.index("Require scanimage during commissioning"))
        self.assertLess(
            names.index("Require scanimage during commissioning"),
            names.index("Require declared scanner during commissioning"),
        )


if __name__ == "__main__":
    unittest.main()
