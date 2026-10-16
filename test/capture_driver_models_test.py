#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load_capture():
    spec = importlib.util.spec_from_file_location(
        "capture_driver_models", ROOT / "scripts/lib/capture-driver-models.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class DrvParseTest(unittest.TestCase):
    def test_drv_blocks_yield_model_and_device_id(self):
        capture = load_capture()
        text = ('Manufacturer "Brother"\n'
                '  ModelName "DCP-1510 series"\n'
                '  Attribute "1284DeviceID" "" "MFG:Brother;MDL:DCP-1510 series;CLS:PRINTER;"\n')
        self.assertEqual(capture.parse_drv(text, "drv:///brlaser.drv/"),
                         [{"uri": "drv:///brlaser.drv/DCP-1510 series",
                           "device_id": "MFG:Brother;MDL:DCP-1510 series;CLS:PRINTER;",
                           "package": ""}])


if __name__ == "__main__":
    unittest.main()
