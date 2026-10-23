#!/usr/bin/env python3
import importlib.util
import tempfile
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
                '  PCFileName "dcp1510.ppd"\n'
                '  Attribute "1284DeviceID" "" "MFG:Brother;MDL:DCP-1510 series;CLS:PRINTER;"\n')
        self.assertEqual(capture.parse_drv(text, "drv:///brlaser.drv/"),
                         [{"uri": "drv:///brlaser.drv/dcp1510.ppd",
                           "device_id": "MFG:Brother;MDL:DCP-1510 series;CLS:PRINTER;",
                           "package": ""}])


class RepositoryIdentityTest(unittest.TestCase):
    def test_reads_both_release_and_inrelease_files(self):
        capture = load_capture()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a_Release").write_text("Origin: Raspbian\nLabel: Raspbian\n", encoding="utf-8")
            (root / "b_InRelease").write_text("Origin: Debian\nLabel: Debian\n", encoding="utf-8")
            identity = capture.repository_identity(
                (str(root / "*_Release"), str(root / "*_InRelease")))
            self.assertIn("Origin: Raspbian", identity)
            self.assertIn("Origin: Debian", identity)


class ProgramCaptureTest(unittest.TestCase):
    def test_is_elf_distinguishes_binaries_from_scripts(self):
        capture = load_capture()
        with tempfile.TemporaryDirectory() as tmp:
            binary = Path(tmp) / "binary"
            binary.write_bytes(b"\x7fELFrest")
            script = Path(tmp) / "script"
            script.write_bytes(b"#!/usr/bin/python3\n")
            self.assertTrue(capture.is_elf(binary))
            self.assertFalse(capture.is_elf(script))

    def test_program_entry_parses_full_uri_and_device_id(self):
        capture = load_capture()
        line = ('"gutenprint.5.3://bjc-50/expert" en "Canon" "Canon BJC-50 - CUPS+Gutenprint v5.3.4" '
                '"MFG:Canon;MDL:BJC-50;"')
        match = capture.PROGRAM_ENTRY.match(line)
        self.assertEqual(match.group(1), "gutenprint.5.3://bjc-50/expert")
        self.assertEqual(match.group(2), "MFG:Canon;MDL:BJC-50;")


if __name__ == "__main__":
    unittest.main()
