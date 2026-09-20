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
        for agent in ("codexcli", "claude-code", "opencode", "kimi", "reasonix"):
            self.assertIn(f'<option value="{agent}">', status)
        self.assertNotIn('type="radio"', status)
        self.assertIn('id="agentflow-open"', status)
        self.assertIn('id="agentflow-agent-open"', status)
        self.assertGreater(status.index('id="agentflow-agent-open"'), status.index('id="agentflow_status"'))
        self.assertIn('margin:12px;', status)
        self.assertIn("var selected = document.getElementById('agentflow-agent-select')", status)
        self.assertIn("window.taskd.show_log(data.task_id", status)
        self.assertNotIn('local token =', status)
        self.assertIn("window.taskd.csrfToken", status)
        self.assertIn("token: agentflowCsrfToken", status)
        self.assertIn('http.formvalue("agent")', controller)
        self.assertIn('codexcli = true', controller)
        self.assertIn('["claude-code"] = true', controller)
        self.assertIn('opencode = true', controller)
        self.assertIn('kimi = true', controller)
        self.assertIn('reasonix = true', controller)
        self.assertIn('context.authtoken or context.token', controller)
        self.assertIn('http.formvalue("token") ~= expected', controller)
        self.assertIn('/etc/init.d/tasks task_add ', controller)
        self.assertIn('task_id = "agentflow-agent-install"', controller)

    def test_installer_downloads_script_and_passes_whitelisted_agent(self):
        installer = self.read("root/usr/libexec/istorec/agentflow-agent.sh")

        self.assertIn("installapp/installapp-mise.sh", installer)
        self.assertIn("codexcli|claude-code|opencode|kimi|reasonix", installer)
        self.assertIn("istore_runtime_env", installer)
        self.assertIn('download_installer', installer)
        self.assertIn('/bin/sh "$remote_installer" "$agent"', installer)
        self.assertIn('Unsupported agent:', installer)


if __name__ == "__main__":
    unittest.main()
