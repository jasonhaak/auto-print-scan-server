#!/usr/bin/env python3
import re
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class ScanservjsRoleTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
