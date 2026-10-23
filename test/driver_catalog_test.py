#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
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
            "debian_splix_samsung_drv")

    def test_instance_indexes_share_one_prefix(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = [
            {"uri": "postscript-hp:0/ppd/hplip/HP/a.ppd", "device_id": "MFG:HP;MDL:A;",
             "package": "printer-driver-postscript-hp"},
            {"uri": "postscript-hp:1/ppd/hplip/HP/b.ppd", "device_id": "MFG:HP;MDL:B;",
             "package": "printer-driver-postscript-hp"},
        ]
        catalog = generator.build_catalog(capture)
        self.assertEqual(list(catalog["generated_package_profiles"]), ["debian_postscript_hp"])
        self.assertEqual(catalog["generated_package_profiles"]["debian_postscript_hp"]["model_prefix"],
                         "postscript-hp:")


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
            "model_prefix": "foomatic-db-compressed-ppds:",
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

    def test_gutenprint_uris_share_one_prefix(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = [
            {"uri": "gutenprint.5.3://bjc-30/expert", "device_id": "MFG:Canon;MDL:BJC-30;",
             "package": "printer-driver-gutenprint"},
            {"uri": "gutenprint.5.3://bjc-50/expert", "device_id": "MFG:Canon;MDL:BJC-50;",
             "package": "printer-driver-gutenprint"},
        ]
        catalog = generator.build_catalog(capture)
        self.assertEqual(list(catalog["generated_package_profiles"]), ["debian_gutenprint"])
        self.assertEqual(catalog["generated_package_profiles"]["debian_gutenprint"]["model_prefix"],
                         "gutenprint.5.3://")


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

    def test_sample_driver_is_excluded(self):
        generator = load_generator()
        capture = dict(CAPTURE)
        capture["entries"] = [{"uri": "drv:///sample.drv/deskjet.ppd",
                               "device_id": "MFG:HP;MDL:DeskJet;", "package": "cups-common"}]
        catalog = generator.build_catalog(capture)
        self.assertEqual(catalog["generated_package_profiles"], {})
        self.assertEqual(catalog["catalog_metadata"]["excluded_packages"], ["cups-common"])


class RenderTest(unittest.TestCase):
    def test_artifact_round_trips_with_provenance(self):
        generator = load_generator()
        catalog = generator.build_catalog(CAPTURE)
        document = yaml.safe_load(generator.render_artifact(catalog, CAPTURE))
        self.assertEqual(set(document), {"generated_package_profiles", "model_index", "catalog_metadata"})
        self.assertEqual(document["catalog_metadata"]["repository_identity"], CAPTURE["repository_identity"])
        self.assertEqual(document["catalog_metadata"]["provenance"], CAPTURE["provenance"])

    def test_rendered_artifact_indents_sequences(self):
        generator = load_generator()
        text = generator.render_artifact(generator.build_catalog(CAPTURE), CAPTURE)
        self.assertIn("\n    - ", text)

    def test_manifest_records_required_provenance(self):
        generator = load_generator()
        manifest = generator.write_manifest(CAPTURE, generator.build_catalog(CAPTURE))
        self.assertEqual(manifest["provenance"]["index_sha256"], "abc")
        self.assertEqual(manifest["provenance"]["package_sha256"]["foomatic-db-compressed-ppds"], "def")
        self.assertEqual(manifest["entries"][0]["uri"], CAPTURE["entries"][0]["uri"])


class GeneratorCliTest(unittest.TestCase):
    def test_cli_writes_artifact_and_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            capture_path = tmp / "capture.json"
            capture_path.write_text(json.dumps(CAPTURE), encoding="utf-8")
            output = tmp / "artifact.yml"
            manifest = tmp / "manifest.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/generate-driver-catalog.py"),
                 "--capture", str(capture_path), "--output", str(output), "--manifest", str(manifest)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("generated_package_profiles", output.read_text(encoding="utf-8"))
            self.assertEqual(json.loads(manifest.read_text(encoding="utf-8"))["provenance"], CAPTURE["provenance"])

    def test_cli_creates_nested_output_directories(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            capture_path = tmp / "capture.json"
            capture_path.write_text(json.dumps(CAPTURE), encoding="utf-8")
            output = tmp / "nested/generated/artifact.yml"
            manifest = tmp / "nested/manifests/manifest.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "scripts/generate-driver-catalog.py"),
                 "--capture", str(capture_path), "--output", str(output), "--manifest", str(manifest)],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.is_file())
            self.assertTrue(manifest.is_file())


class LoadCatalogTest(unittest.TestCase):
    def _fixture(self, module, identity, repository_identity="R"):
        root = Path(tempfile.mkdtemp())
        (root / "vars/generated").mkdir(parents=True)
        (root / "vars/driver_profiles.yml").write_text(
            "package_profiles:\n  brlaser:\n    model_prefix: drv:///brlaser.drv/\n", encoding="utf-8")
        (root / "vars/generated/driver_profiles_trixie_armhf_raspberrypi.yml").write_text(
            "generated_package_profiles:\n"
            "  brlaser:\n    model_prefix: generated\n"
            "  debian_x:\n    model_prefix: drv:///x.drv/\n"
            "model_index: {}\n"
            f"catalog_metadata:\n  suite: trixie\n  package_architecture: armhf\n  repository_identity: {identity}\n",
            encoding="utf-8")
        module.CURATED_PROFILES_PATH = root / "vars/driver_profiles.yml"
        module.GENERATED_DIR = root / "vars/generated"

    def test_merge_curated_wins_and_reports_matched(self):
        module = load_real_module()
        self._fixture(module, "R")
        catalog = module.load_catalog("trixie", "armhf", "R")
        self.assertTrue(catalog["requested"])
        self.assertTrue(catalog["matched"])
        self.assertTrue(catalog["identity_matched"])
        self.assertEqual(catalog["package_profiles"]["brlaser"]["model_prefix"], "drv:///brlaser.drv/")
        self.assertIn("debian_x", catalog["package_profiles"])

    def test_repository_drift_still_matches_but_not_identity(self):
        module = load_real_module()
        self._fixture(module, "different")
        catalog = module.load_catalog("trixie", "armhf", "R")
        self.assertTrue(catalog["matched"])
        self.assertFalse(catalog["identity_matched"])

    def test_missing_artifact_reports_not_matched(self):
        module = load_real_module()
        root = Path(tempfile.mkdtemp())
        (root / "vars").mkdir(parents=True)
        (root / "vars/driver_profiles.yml").write_text("package_profiles: {}\n", encoding="utf-8")
        module.CURATED_PROFILES_PATH = root / "vars/driver_profiles.yml"
        module.GENERATED_DIR = root / "vars/generated"
        catalog = module.load_catalog("trixie", "armhf", "R")
        self.assertTrue(catalog["requested"])
        self.assertFalse(catalog["matched"])
        self.assertEqual(catalog["package_profiles"], {})


class ResolverTest(unittest.TestCase):
    def test_profile_names_and_prefix(self):
        module = load_real_module()
        catalog = {"package_profiles": {"a": {"model_prefix": "drv:///a.drv/"}}}
        self.assertEqual(module.profile_names(catalog), ["a"])
        self.assertEqual(module.model_prefix(catalog, "a"), "drv:///a.drv/")
        with self.assertRaises(module.CatalogError):
            module.model_prefix(catalog, "missing")

    def test_resolve_identity_maps_facts_and_rejects_unsupported(self):
        module = load_real_module()
        self.assertEqual(module.resolve_identity("trixie", "armv6l", "R"),
                         {"suite": "trixie", "package_architecture": "armhf", "repository_identity": "R"})
        with self.assertRaises(module.CatalogError):
            module.resolve_identity("trixie", "armv7l", "R")


class SelectCliTest(unittest.TestCase):
    def test_select_gates_generated_profiles(self):
        root = Path(tempfile.mkdtemp())
        generated = root / "generated"
        generated.mkdir()
        (generated / "driver_profiles_trixie_armhf_raspberrypi.yml").write_text(
            "generated_package_profiles:\n  debian_fixture:\n    model_prefix: drv:///f.drv/\n"
            "    prefix_status: verified\nmodel_index: {}\n"
            "catalog_metadata:\n  suite: trixie\n  package_architecture: armhf\n  repository_identity: R\n",
            encoding="utf-8")
        base = [sys.executable, str(ROOT / "scripts/lib/driver_catalog.py"), "select",
                "--suite", "trixie", "--architecture", "armhf", "--repository", "R"]
        environment = {**os.environ, "DRIVER_CATALOG_GENERATED_DIR": str(generated)}
        without = subprocess.run(base, capture_output=True, text=True, env=environment)
        self.assertEqual(without.returncode, 0, without.stderr)
        self.assertFalse(json.loads(without.stdout)["matched"])
        self.assertNotIn("debian_fixture", json.loads(without.stdout)["package_profiles"])
        with_switch = subprocess.run(base + ["--enable-generated-catalog"], capture_output=True, text=True, env=environment)
        self.assertTrue(json.loads(with_switch.stdout)["matched"])
        self.assertIn("debian_fixture", json.loads(with_switch.stdout)["package_profiles"])


class MatchEvidenceTest(unittest.TestCase):
    def test_only_verified_generated_profiles_are_eligible(self):
        module = load_real_module()
        catalog = {"package_profiles": {"a": {"model_prefix": "x/", "prefix_status": "verified", "description": "A"},
                                        "b": {"model_prefix": "y/"}},
                   "model_index": {"brother|hl-2270dw": ["a", "b"]}}
        evidence = "    printer-device-id (textWithoutLanguage) = MFG:Brother;MDL:HL-2270DW;\n"
        self.assertEqual(module.match_evidence(catalog, evidence), [("a", "A")])
        self.assertEqual(module.match_evidence(catalog, "no id"), [])


if __name__ == "__main__":
    unittest.main()
