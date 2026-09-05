from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
APPLICATIONS = ROOT / "applications"


def read(relative):
    return (APPLICATIONS / relative).read_text()


class MiseRuntimeContractTest(unittest.TestCase):
    def test_mise_package_installs_shared_runtime_contract(self):
        makefile = read("mise/Makefile")
        config = read("mise/files/mise.config")
        defaults = read("mise/files/mise.uci-default")

        self.assertIn("/etc/config/mise", makefile)
        self.assertNotIn("istore_runtime.sh", makefile)
        self.assertIn("$(INSTALL_BIN) ./files/mise.uci-default", makefile)
        self.assertIn("[ -f /etc/uci-defaults/mise ]", makefile)

        self.assertIn("config mise 'main'", config)
        options = [
            line.strip()
            for line in config.splitlines()
            if line.strip().startswith("option ")
        ]
        self.assertEqual(options, ["option runtime_dir ''"])

        self.assertNotIn("istore_runtime", defaults)
        self.assertIn("uci -q delete mise.main.enabled", defaults)
        self.assertIn("uci -q delete mise.main.auto_discover", defaults)

    def test_agentflow_consumes_shared_runtime_home(self):
        init = read("agentflow/files/agentflow.init")
        cbi = read("luci-app-agentflow/luasrc/model/cbi/agentflow.lua")
        model = read("luci-app-agentflow/luasrc/model/agentflow.lua")
        translations = read("luci-app-agentflow/po/zh-cn/agentflow.po")

        self.assertNotIn("istore_runtime", init)
        self.assertIn("uci -q get mise.main.runtime_dir", init)
        self.assertIn('runtime_dir="$conf_dir/Runtime"', init)
        self.assertIn('AGENT_FLOW_DATA=$data_dir/data', init)
        self.assertIn('HOME=$HOME', init)
        self.assertIn('MISE_DATA_DIR=$MISE_DATA_DIR', init)
        self.assertNotIn("$data_dir/global", init)
        self.assertNotIn(".local/share/mise/shims:$PATH", init)

        self.assertIn('translate("Shared runtime home")', cbi)
        self.assertIn("agentflow_model.runtime_home", cbi)
        self.assertIn('return runtime_dir .. "/home"', model)
        self.assertIn('return conf_dir .. "/Runtime"', model)

        self.assertIn('msgid "Shared runtime home"', translations)
        self.assertIn('msgstr "共享运行时 HOME"', translations)


if __name__ == "__main__":
    unittest.main()
