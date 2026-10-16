#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]


class DriverCatalogRoleTest(unittest.TestCase):
    def test_role_resolves_identity_on_the_controller_and_gates_generated(self):
        tasks = (ROOT / "roles/driver_catalog/tasks/main.yml").read_text(encoding="utf-8")
        self.assertIn("delegate_to: localhost", tasks)
        self.assertIn("become: false", tasks)
        self.assertNotIn("run_once", tasks)
        self.assertIn("distribution_release", tasks)
        self.assertIn("--enable-generated-catalog", tasks)
        self.assertIn("combine(package_profiles)", tasks)
        defaults = yaml.safe_load((ROOT / "roles/driver_catalog/defaults/main.yml").read_text(encoding="utf-8"))
        self.assertIs(defaults["driver_catalog_generated_enabled"], True)


class GeneratedEnabledTest(unittest.TestCase):
    def test_generated_catalog_is_enabled_by_default(self):
        defaults = yaml.safe_load((ROOT / "roles/driver_catalog/defaults/main.yml").read_text(encoding="utf-8"))
        self.assertIs(defaults["driver_catalog_generated_enabled"], True)


if __name__ == "__main__":
    unittest.main()
