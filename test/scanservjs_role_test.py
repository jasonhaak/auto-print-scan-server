#!/usr/bin/env python3
import re
import unittest
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader


ROOT = Path(__file__).resolve().parents[1]


class ScanservjsRoleTest(unittest.TestCase):
    def test_every_task_is_gated_on_managed_scanners_present(self):
        # playbooks/site.yml now includes this role exactly once, unconditionally, so its own
        # tasks must carry the present/absent branching that used to live on the role-level
        # `when:` in the (now removed) duplicate role entry.
        tasks = yaml.safe_load((ROOT / "roles/scanservjs/tasks/main.yml").read_text(encoding="utf-8"))
        for task in tasks:
            if task["name"] == "Remove ScanservJS when no scanner is managed":
                continue
            self.assertIn(
                "managed_scanners | length > 0", task.get("when") or "", task["name"]
            )

    def test_dispatches_to_absent_tasks_when_no_scanner_is_managed(self):
        tasks = yaml.safe_load((ROOT / "roles/scanservjs/tasks/main.yml").read_text(encoding="utf-8"))
        task = next(item for item in tasks if item["name"] == "Remove ScanservJS when no scanner is managed")
        self.assertEqual(task["ansible.builtin.include_tasks"], "absent.yml")
        self.assertEqual(task.get("when"), "managed_scanners | length == 0")

    def test_disk_cache_replacement_uses_unambiguous_backreferences(self):
        tasks = yaml.safe_load((ROOT / "roles/scanservjs/tasks/main.yml").read_text(encoding="utf-8"))
        task = next(item for item in tasks if item["name"] == "Set the managed ImageMagick disk-cache limit")
        replacement = task["ansible.builtin.replace"]["replace"].replace(
            "{{ scanservjs_imagemagick_disk_limit }}", "1024MiB"
        )
        self.assertEqual(
            re.sub(task["ansible.builtin.replace"]["regexp"], replacement,
                   '<policy domain="resource" name="disk" value="1GiB"/>'),
            '<policy domain="resource" name="disk" value="1024MiB"/>',
        )

    def test_storage_checks_do_not_combine_incompatible_df_modes(self):
        tasks = yaml.safe_load((ROOT / "roles/scanservjs/tasks/main.yml").read_text(encoding="utf-8"))
        task = next(item for item in tasks if item["name"] == "Check available scan storage during maintenance")
        self.assertEqual(task["ansible.builtin.command"]["argv"][:3], ["df", "-m", "--output=avail"])
        for template in ["scanservjs-storage-check.sh.j2", "scanservjs-low-space-warning.sh.j2"]:
            content = (ROOT / "roles/scanservjs/templates" / template).read_text(encoding="utf-8")
            self.assertIn("df -m --output=avail", content)
            self.assertNotIn("df -Pm --output=avail", content)


class ScanservjsPageSplittingTest(unittest.TestCase):
    def render_config(self, page_splitting, managed_scanners=()):
        environment = Environment(loader=FileSystemLoader(ROOT / "roles/scanservjs/templates"))
        return environment.get_template("config.local.js.j2").render(
            scanservjs_port=8080,
            scanservjs_data_directory="/var/lib/scanservjs/data",
            scanservjs_ocr_languages=["eng"],
            scanservjs_page_splitting=page_splitting,
            managed_scanners=managed_scanners,
        )

    def test_page_splitting_disabled_by_default_omits_after_scan(self):
        config = self.render_config(False)
        self.assertNotIn("afterScan", config)
        self.assertNotIn("pdfseparate", config)

    def test_page_splitting_enabled_adds_after_scan_with_pdfseparate(self):
        config = self.render_config(True)
        self.assertIn("afterScan", config)
        self.assertIn("pdfseparate", config)
        self.assertIn("-page-", config)

    def test_poppler_utils_is_installed_for_page_splitting(self):
        tasks = yaml.safe_load((ROOT / "roles/scanservjs/tasks/main.yml").read_text(encoding="utf-8"))
        task = next(item for item in tasks if item["name"] == "Install ScanservJS runtime dependencies")
        self.assertIn("poppler-utils", task["ansible.builtin.apt"]["name"])

    def test_after_devices_maps_a_display_name_onto_its_matching_device_id(self):
        config = self.render_config(
            False,
            managed_scanners=[
                {"device_name": "airscan:w0:Brother MFC-7360N", "display_name": "Office Scanner"},
                {"device_name": "airscan:e0:Other Scanner"},
            ],
        )
        self.assertIn("afterDevices(devices)", config)
        self.assertIn('"airscan:w0:Brother MFC-7360N": "Office Scanner"', config)
        self.assertNotIn("airscan:e0:Other Scanner", config)

    def test_after_devices_is_a_no_op_with_no_display_names_configured(self):
        config = self.render_config(False, managed_scanners=[{"device_name": "airscan:e0:Office Scanner"}])
        self.assertIn("afterDevices(devices)", config)
        self.assertNotIn("airscan:e0:Office Scanner", config)

    def test_validate_asserts_page_splitting_is_boolean(self):
        tasks = yaml.safe_load((ROOT / "roles/scanservjs/tasks/main.yml").read_text(encoding="utf-8"))
        validate = next(item for item in tasks if item["name"] == "Validate ScanservJS configuration")
        self.assertTrue(
            any("scanservjs_page_splitting" in condition for condition in validate["ansible.builtin.assert"]["that"])
        )


if __name__ == "__main__":
    unittest.main()
