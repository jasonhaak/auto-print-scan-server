#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class CupsRoleTest(unittest.TestCase):
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
            profile_task["when"],
            None if "when" not in profile_task else profile_task["when"],
        )
        self.assertIn("cups_available_models.stdout", profile_task["ansible.builtin.assert"]["that"])

    def test_brlaser_profile_uses_the_mfc_7360n_ppd(self):
        profiles = yaml.safe_load((ROOT / "vars/package_profiles.yml").read_text(encoding="utf-8"))
        self.assertEqual(
            profiles["package_profiles"]["brlaser"]["cups_model"],
            "drv:///brlaser.drv/br7360.ppd",
        )


if __name__ == "__main__":
    unittest.main()
