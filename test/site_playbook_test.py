#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class SitePlaybookTest(unittest.TestCase):
    def test_force_handlers_so_a_later_task_failure_cannot_strand_a_pending_restart(self):
        # A role earlier or later in this play failing after "Configure ScanservJS" (or any
        # other notify-ing task) has already run would otherwise leave its handler unflushed,
        # silently leaving the changed config file in place without restarting the service that
        # reads it -- this is exactly what happened in production: config.local.js was updated
        # on 2026-08-12 but scanservjs kept running with hooks loaded at its 2026-08-06 boot
        # until it was restarted by hand a week later.
        play = yaml.safe_load((ROOT / "playbooks/site.yml").read_text(encoding="utf-8"))[0]
        self.assertTrue(play.get("force_handlers"))


if __name__ == "__main__":
    unittest.main()
