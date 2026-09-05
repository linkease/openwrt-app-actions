import json
import pathlib
import re
import unittest


APP_DIR = pathlib.Path(__file__).resolve().parents[1]


class DesktopManifestContractTest(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(
            (APP_DIR / "files" / "agentflow-plugin.json").read_text()
        )
        self.entry = (APP_DIR / "files" / "www" / "desktop-entry.js").read_text()

    def test_manifest_uses_agentflow_app_base_proxy(self):
        self.assertEqual(self.manifest["id"], "agentflow")
        self.assertEqual(self.manifest["staticRoot"], "/usr/share/agentflow/www")
        self.assertEqual(self.manifest["standalone"]["basePath"], "/apps/agentflow/")

        backend = self.manifest["backend"]
        self.assertEqual(backend["upstreamBasePath"], "/apps/agentflow/")
        self.assertEqual(backend["pathMode"], "preserve")
        self.assertEqual(backend["proxyMode"], "app-base")

    def test_desktop_entry_matches_manifest_contract(self):
        desktop = self.manifest["desktop"]
        self.assertEqual(desktop["mode"], "module")
        self.assertEqual(desktop["entry"], "desktop-entry.js")
        self.assertEqual(desktop["isolation"], "shadow-dom")

        self.assertRegex(self.entry, r"export\s+async\s+function\s+bootstrap\s*\(")
        self.assertRegex(self.entry, r"export\s+async\s+function\s+mount\s*\(")
        self.assertRegex(self.entry, r"export\s+async\s+function\s+unmount\s*\(")
        self.assertIn("/apps/agentflow/", self.entry)
        self.assertRegex(
            self.entry,
            re.compile(r"props\.context\s*&&\s*props\.context\.basePath"),
        )


if __name__ == "__main__":
    unittest.main()
