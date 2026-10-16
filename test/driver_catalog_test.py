#!/usr/bin/env python3
import importlib.util
import unittest
from pathlib import Path

import yaml

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


def load_generator():
    spec = importlib.util.spec_from_file_location(
        "generate_driver_catalog", ROOT / "scripts/generate-driver-catalog.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ProfileNameTest(unittest.TestCase):
    def test_profile_name_is_stable_and_derived_from_package(self):
        generator = load_generator()
        self.assertEqual(generator.slug("printer-driver-splix"), "printer_driver_splix")
        self.assertEqual(
            generator.profile_name("foomatic-db-compressed-ppds",
                                   ["foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/"],
                                   "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/"),
            "debian_foomatic_db_compressed_ppds")
        self.assertEqual(
            generator.profile_name("printer-driver-splix",
                                   ["drv:///splix-samsung.drv/", "drv:///splix-dell.drv/"],
                                   "drv:///splix-samsung.drv/"),
            "debian_splix_samsung")


CAPTURE = {
    "suite": "trixie",
    "package_architecture": "armhf",
    "repository_identity": "Origin: Raspbian|Label: Raspbian|Suite: oldstable|Codename: trixie",
    "label": "raspberrypi",
    "generated_on": "2026-10-17",
    "generator_version": "1",
    "packages": {"foomatic-db-compressed-ppds": "20230202-1"},
    "provenance": {"index_sha256": "abc",
                   "package_sha256": {"foomatic-db-compressed-ppds": "def"},
                   "tool_versions": {"cups": "2.4.2", "python": "3.13"}},
    "entries": [
        {"uri": "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW.ppd",
         "device_id": "MFG:Brother;MDL:HL-2270DW;", "package": "foomatic-db-compressed-ppds"},
        {"uri": "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW-2.ppd",
         "device_id": "MFG:Brother;MDL:HL-2270DW;", "package": "foomatic-db-compressed-ppds"},
    ],
}


class BuildCatalogTest(unittest.TestCase):
    def test_groups_by_package_and_prefix(self):
        generator = load_generator()
        catalog = generator.build_catalog(CAPTURE)
        self.assertEqual(catalog["generated_package_profiles"]["debian_foomatic_db_compressed_ppds"], {
            "description": "Models advertised by Debian package foomatic-db-compressed-ppds",
            "packages": ["foomatic-db-compressed-ppds"],
            "model_prefix": "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/",
            "family": "captured-cups-models",
            "prefix_status": "verified",
        })
        self.assertEqual(catalog["model_index"],
                         {"brother|hl-2270dw": ["debian_foomatic_db_compressed_ppds"]})
        self.assertEqual(catalog["catalog_metadata"],
                         {"excluded_packages": [], "shared_uris": []})

    def test_uri_without_slash_becomes_its_own_prefix(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = [{"uri": "family:model", "device_id": "MFG:A;MDL:B;", "package": "p"}]
        catalog = generator.build_catalog(capture)
        self.assertEqual(catalog["generated_package_profiles"]["debian_p"]["model_prefix"], "family:model")


class ExclusionTest(unittest.TestCase):
    def test_virtual_backends_are_excluded(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = CAPTURE["entries"] + [
            {"uri": "cups-pdf:/", "device_id": "MFG:Generic;MDL:CUPS-PDF Printer;",
             "package": "printer-driver-cups-pdf"}]
        catalog = generator.build_catalog(capture)
        self.assertNotIn("debian_cups_pdf", catalog["generated_package_profiles"])
        self.assertEqual(catalog["catalog_metadata"]["excluded_packages"], ["printer-driver-cups-pdf"])

    def test_generic_pcl_models_stay_manual(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = CAPTURE["entries"] + [
            {"uri": "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Generic-PCL_6_PCL_XL_Printer.ppd",
             "device_id": "MFG:Generic;MDL:PCL 6/PCL XL Printer;", "package": "foomatic-db-compressed-ppds"}]
        catalog = generator.build_catalog(capture)
        self.assertIn("debian_foomatic_db_compressed_ppds", catalog["generated_package_profiles"])
        self.assertNotIn("generic|pcl 6/pcl xl printer", catalog["model_index"])

    def test_every_shared_uri_for_a_key_is_dropped(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = CAPTURE["entries"] + [
            {"uri": "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW.ppd",
             "device_id": "MFG:Brother;MDL:HL-2270DW;", "package": "printer-driver-other"},
            {"uri": "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW-2.ppd",
             "device_id": "MFG:Brother;MDL:HL-2270DW;", "package": "printer-driver-other"},
        ]
        catalog = generator.build_catalog(capture)
        self.assertEqual(catalog["model_index"], {})
        self.assertEqual(catalog["catalog_metadata"]["shared_uris"], [
            "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW-2.ppd",
            "foomatic-db-compressed-ppds:0/ppd/foomatic-ppd/Brother-HL-2270DW.ppd",
        ])


class RenderTest(unittest.TestCase):
    def test_artifact_round_trips_with_provenance(self):
        generator = load_generator()
        catalog = generator.build_catalog(CAPTURE)
        document = yaml.safe_load(generator.render_artifact(catalog, CAPTURE))
        self.assertEqual(set(document), {"generated_package_profiles", "model_index", "catalog_metadata"})
        self.assertEqual(document["catalog_metadata"]["repository_identity"], CAPTURE["repository_identity"])
        self.assertEqual(document["catalog_metadata"]["provenance"], CAPTURE["provenance"])

    def test_manifest_records_required_provenance(self):
        generator = load_generator()
        manifest = generator.write_manifest(CAPTURE, generator.build_catalog(CAPTURE))
        self.assertEqual(manifest["provenance"]["index_sha256"], "abc")
        self.assertEqual(manifest["provenance"]["package_sha256"]["foomatic-db-compressed-ppds"], "def")
        self.assertEqual(manifest["entries"][0]["uri"], CAPTURE["entries"][0]["uri"])


if __name__ == "__main__":
    unittest.main()
