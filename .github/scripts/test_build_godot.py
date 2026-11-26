"""Exercise build preflight with Godot while stopping before import and export."""

import os
import runpy
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
ORDINARY_CONFIG = """\
config_version=5

[application]
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")

[rendering]
renderer/rendering_method="gl_compatibility"
"""
IMPORT_MARKER = "Preflight reached import."


class BuildGodotTest(unittest.TestCase):
    def run_build(self, configuration):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            shutil.copytree(ROOT / ".github/scripts", project / ".github/scripts")
            shutil.copy(ROOT / ".godot-version", project)
            (project / "project.godot").write_text(configuration, encoding="utf-8")
            wrapper = project / "godot-wrapper"
            wrapper.write_text(
                "#!/usr/bin/env bash\n"
                'if [[ "$*" == "--headless --path . --import" ]]; then\n'
                f'    echo "{IMPORT_MARKER}"\n'
                "    exit 97\n"
                "fi\n"
                'exec "$TEST_GODOT_EDITOR" "$@"\n',
                encoding="utf-8",
            )
            wrapper.chmod(0o755)
            editor = shutil.which(os.environ.get("GODOT", "godot"))
            self.assertIsNotNone(editor, "Install the pinned Godot editor.")
            result = subprocess.run(
                ["bash", ".github/scripts/build-godot.sh", str(project / "output")],
                cwd=project,
                env={**os.environ, "GODOT": str(wrapper), "TEST_GODOT_EDITOR": editor},
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
            )
            self.assertEqual(result.returncode, 1, result.stdout)
            return result.stdout

    def test_ordinary_values(self):
        self.assertIn(IMPORT_MARKER, self.run_build(ORDINARY_CONFIG))

    def test_project_camera_dictionaries(self):
        configuration = (ROOT / "project.godot").read_text(encoding="utf-8-sig")
        self.assertIn(IMPORT_MARKER, self.run_build(configuration))

    def test_multiline_features_and_web_renderer_override(self):
        configuration = ORDINARY_CONFIG.replace(
            'PackedStringArray("4.6", "GL Compatibility")',
            'PackedStringArray(\n"4.6",\n"GL Compatibility"\n)',
        ).replace(
            'renderer/rendering_method="gl_compatibility"',
            'renderer/rendering_method="mobile"\n'
            'renderer/rendering_method.web="gl_compatibility"',
        )
        self.assertIn(IMPORT_MARKER, self.run_build(configuration))

    def test_preflight_rejects_invalid_export_settings(self):
        for original, replacement, diagnostic in (
            ('"gl_compatibility"', '"mobile"', "Web export requires the Compatibility renderer"),
            ('"res://main.tscn"', '""', "Set a main scene before exporting."),
            ('"4.6"', '"4.5"', "must use the same Godot major/minor."),
            ('"GL Compatibility"', '"C#"', "does not support .NET or GDExtension."),
        ):
            with self.subTest(replacement=replacement):
                log = self.run_build(ORDINARY_CONFIG.replace(original, replacement))
                self.assertIn(diagnostic, log)
                self.assertNotIn(IMPORT_MARKER, log)


class ExportLogClassificationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.check = staticmethod(
            runpy.run_path(str(ROOT / ".github/scripts/validate-export-log.py"))[
                "only_shutdown_resource_leak"
            ]
        )

    def test_completed_export_with_exact_shutdown_leak_is_nonfatal(self):
        log = (
            "[   0% ] savepack | Started Packing\n"
            "\x1b[92m[ DONE ]\x1b[39m savepack\n"
            "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).\n"
            "   at: cleanup (core/object/object.cpp:2663)\n"
            "ERROR: 1 resources still in use at exit (run with --verbose for details).\n"
            "   at: clear (core/io/resource.cpp:810)\n"
        )
        self.assertTrue(self.check(log))
        self.assertFalse(self.check(log.replace("[ DONE ]", "[  96% ]")))
        for count in (2, 3, 12, 100):
            with self.subTest(resource_count=count):
                self.assertTrue(self.check(log.replace("1 resources", f"{count} resources")))
        for invalid in ("0 resources", "-1 resources", "unknown resources"):
            with self.subTest(invalid_count=invalid):
                self.assertFalse(self.check(log.replace("1 resources", invalid)))
        self.assertFalse(self.check(log.replace("ERROR: 1 resources", "SCRIPT ERROR: 1 resources")))
        self.assertFalse(self.check(log + "ERROR: Another problem.\n"))
        self.assertFalse(self.check("ERROR: Export failed.\n" + log))
        self.assertFalse(self.check(log + "WARNING: More problems.\n"))

    def test_real_script_or_export_errors_remain_fatal(self):
        self.assertFalse(self.check("SCRIPT ERROR: Parse Error: Unexpected token\n"))
        self.assertFalse(self.check("[ DONE ] savepack\nERROR: Could not save export.\n"))


if __name__ == "__main__":
    unittest.main()
