#!/usr/bin/env python3
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


class AvahiRoleTest(unittest.TestCase):
    def test_restart_avahi_daemon_handler_exists(self):
        handlers = yaml.safe_load((ROOT / "roles/avahi/handlers/main.yml").read_text(encoding="utf-8"))
        handler = next(item for item in handlers if item["name"] == "Restart avahi-daemon")
        self.assertEqual(handler["ansible.builtin.service"]["name"], "avahi-daemon")
        self.assertEqual(handler["ansible.builtin.service"]["state"], "restarted")
        # avahi-daemon is only installed when a printer is shared (roles/avahi/tasks/main.yml);
        # restarting it unconditionally would fail on a host with no shared printer.
        self.assertEqual(handler.get("when"), "device_has_shared_printer | bool")


if __name__ == "__main__":
    unittest.main()
