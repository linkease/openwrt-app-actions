from pathlib import Path
import unittest


APP_DIR = Path(__file__).resolve().parents[1]


class ClassicKaiEntryContractTest(unittest.TestCase):
    def read(self, relative):
        return (APP_DIR / relative).read_text(encoding="utf-8")

    def test_status_reports_classic_kai_manifest(self):
        controller = self.read("luasrc/controller/kaiplus.lua")

        self.assertIn(
            'kai_installed = fs.access("/usr/share/kai/kai-plugin.json")',
            controller,
        )

    def test_entry_opens_installed_kai_and_prompts_when_missing(self):
        status = self.read("luasrc/view/kaiplus/kaiplus_status.htm")

        self.assertIn('url("admin/services/linkease_apps/open")', status)
        self.assertIn("?id=kai", status)
        self.assertIn("st.kai_installed === true", status)
        self.assertIn("function openClassicKai()", status)
        self.assertIn("Classic KAI is not installed. Please install KAI first.", status)
        self.assertIn("window.open(kaiOpenUrl, '_blank', 'noopener')", status)


if __name__ == "__main__":
    unittest.main()
