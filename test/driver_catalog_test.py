#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_real_module():
    spec = importlib.util.spec_from_file_location("driver_catalog", ROOT / "scripts/lib/driver_catalog.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DeviceIdTest(unittest.TestCase):
    def test_parse_requires_exactly_one_device_id_line(self):
        module = load_real_module()
        single = "    printer-device-id (textWithoutLanguage) = MFG:Brother;MDL:HL-2270DW;\n"
        self.assertEqual(module.parse_printer_device_id(single), "MFG:Brother;MDL:HL-2270DW;")
        self.assertIsNone(module.parse_printer_device_id("no device id here"))
        self.assertIsNone(module.parse_printer_device_id(single + single))

    def test_key_requires_exactly_one_make_and_model(self):
        module = load_real_module()
        self.assertEqual(module.device_id_key("MFG:Brother;MDL:HL-2270DW;"), "brother|hl-2270dw")
        self.assertIsNone(module.device_id_key("MFG:Brother;"))
        self.assertIsNone(module.device_id_key("MFG:A;MFG:B;MDL:X;"))
        self.assertIsNone(module.device_id_key("MFG:;MDL:HL-2270DW;"))


if __name__ == "__main__":
    unittest.main()
