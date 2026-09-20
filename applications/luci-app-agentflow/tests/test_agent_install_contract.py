from pathlib import Path
import unittest


APP_DIR = Path(__file__).resolve().parents[1]


class AgentInstallContractTest(unittest.TestCase):
    def read(self, relative):
        return (APP_DIR / relative).read_text(encoding="utf-8")

    def test_luci_loads_task_window_and_starts_whitelisted_installer(self):
        makefile = self.read("Makefile")
        controller = self.read("luasrc/controller/agentflow.lua")
        status = self.read("luasrc/view/agentflow/status.htm")

        self.assertIn("+luci-lib-taskd", makefile)
        self.assertIn('<%+tasks/embed%>', status)
        self.assertIn('<select id="agentflow-agent-select"', status)
        self.assertIn('<option value="codex">', status)
        self.assertIn('<option value="claude-code">', status)
        self.assertNotIn('type="radio"', status)
        self.assertIn('id="agentflow-open"', status)
        self.assertIn('id="agentflow-agent-open"', status)
        self.assertGreater(status.index('id="agentflow-agent-open"'), status.index('id="agentflow_status"'))
        self.assertIn("var selected = document.getElementById('agentflow-agent-select')", status)
        self.assertIn("window.taskd.show_log", status)
        self.assertIn("dispatcher.context.token", status)
        self.assertIn("token: agentflowCsrfToken", status)
        self.assertIn('http.formvalue("agent")', controller)
        self.assertIn('codex = true', controller)
        self.assertIn('["claude-code"] = true', controller)
        self.assertIn('http.formvalue("token") ~= context.token', controller)
        self.assertIn('/etc/init.d/tasks task_add ', controller)
        self.assertIn('task_id = "agentflow-agent-install"', controller)

    def test_installer_maps_agent_ids_to_fixed_packages(self):
        installer = self.read("root/usr/libexec/istorec/agentflow-agent.sh")

        self.assertIn('package="@openai/codex@latest"', installer)
        self.assertIn('package="@anthropic-ai/claude-code@latest"', installer)
        self.assertIn('/usr/bin/mise use --global "node@$node_version"', installer)
        self.assertIn('"$npm_bin" install --global "$package"', installer)
        self.assertIn('/usr/bin/mise reshim', installer)
        self.assertIn('Unsupported agent:', installer)


if __name__ == "__main__":
    unittest.main()
