#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader


ROOT = Path(__file__).resolve().parents[1]


class CupsRoleTest(unittest.TestCase):
    def render_cupsd_conf(self, shared):
        environment = Environment(loader=FileSystemLoader(ROOT / "roles/cups/templates"))
        return environment.get_template("cupsd.conf.j2").render(
            device_has_shared_printer=shared,
            cups_completed_job_history_seconds=86400,
            trusted_lan_cidrs=["192.168.178.0/24"],
        )

    def test_shared_cups_listener_does_not_conflict_with_local_listener(self):
        shared_config = self.render_cupsd_conf(True)
        local_config = self.render_cupsd_conf(False)

        self.assertIn("Port 631", shared_config)
        self.assertNotIn("Listen localhost:631", shared_config)
        self.assertIn("Listen localhost:631", local_config)
        self.assertNotIn("Port 631", local_config)

    def test_starts_and_checks_cups_before_reconciling_queues(self):
        tasks = yaml.safe_load((ROOT / "roles/cups/tasks/main.yml").read_text(encoding="utf-8"))
        names = [task["name"] for task in tasks]

        start_index = names.index("Ensure the CUPS scheduler is enabled and running")
        ready_index = names.index("Wait for the CUPS scheduler to accept commands")
        models_index = names.index("List installed CUPS models for selected package profiles")
        profile_index = names.index("Require each selected package-profile CUPS model")
        reconcile_index = names.index("Reconcile managed CUPS queues")

        self.assertLess(start_index, ready_index)
        self.assertLess(ready_index, models_index)
        self.assertLess(models_index, profile_index)
        self.assertLess(profile_index, reconcile_index)

        readiness_task = tasks[ready_index]
        self.assertEqual(readiness_task["ansible.builtin.command"]["argv"], ["lpstat", "-r"])
        self.assertEqual(readiness_task["retries"], 5)

        profile_task = tasks[profile_index]
        self.assertEqual(
            profile_task["loop"],
            "{{ managed_printers | selectattr('driver_mode', 'equalto', 'package_profile') | list }}",
        )
        self.assertIn("cups_available_models.stdout", profile_task["ansible.builtin.assert"]["that"])

    def test_printer_assert_does_not_require_at_least_one_printer(self):
        tasks = yaml.safe_load((ROOT / "roles/cups/tasks/main.yml").read_text(encoding="utf-8"))
        printer_assert = next(
            task for task in tasks
            if task["name"] == "Validate managed printer configuration"
        )
        conditions = printer_assert["ansible.builtin.assert"]["that"]
        self.assertFalse(any("managed_printers | length > 0" == condition for condition in conditions))

    def test_brlaser_profile_is_generic_and_models_are_selected_per_queue(self):
        profiles = yaml.safe_load((ROOT / "vars/driver_profiles.yml").read_text(encoding="utf-8"))
        self.assertEqual(
            profiles["package_profiles"]["brlaser"]["model_prefix"],
            "drv:///brlaser.drv/",
        )
        self.assertNotIn("cups_model", profiles["package_profiles"]["brlaser"])

    def test_queue_reconciliation_uses_the_inventory_model(self):
        tasks = yaml.safe_load((ROOT / "roles/cups/tasks/main.yml").read_text(encoding="utf-8"))
        reconcile = next(task for task in tasks if task["name"] == "Reconcile managed CUPS queues")
        self.assertIn(
            "else item.cups_model",
            reconcile["ansible.builtin.command"]["argv"][7],
        )

    def test_queue_reconciliation_advertises_the_dns_sd_name(self):
        # printer-dns-sd-name is a read-only, CUPS-reported attribute, not a settable lpadmin -o
        # option -- setting it via -o silently does nothing. CUPS actually derives the advertised
        # Bonjour/DNS-SD service name from printer-info (-D) plus the hostname, so -D is the only
        # lever that actually controls what a client sees.
        tasks = yaml.safe_load((ROOT / "roles/cups/tasks/main.yml").read_text(encoding="utf-8"))
        reconcile = next(task for task in tasks if task["name"] == "Reconcile managed CUPS queues")
        argv = reconcile["ansible.builtin.command"]["argv"]
        self.assertFalse(any("printer-dns-sd-name=" in entry for entry in argv))
        description_index = argv.index("-D") + 1
        description = argv[description_index]
        self.assertIn("item.dns_sd_name", description)
        self.assertIn("default(item.name)", description)

    def test_validate_asserts_the_dns_sd_name_is_a_safe_label(self):
        tasks = yaml.safe_load((ROOT / "roles/cups/tasks/main.yml").read_text(encoding="utf-8"))
        validate = next(task for task in tasks if task["name"] == "Validate managed printer configuration")
        self.assertTrue(
            any(
                "dns_sd_name" in condition and "default(item.name)" in condition
                for condition in validate["ansible.builtin.assert"]["that"]
            )
        )


if __name__ == "__main__":
    unittest.main()
