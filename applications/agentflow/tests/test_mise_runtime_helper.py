import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "applications/mise/files/istore_runtime.sh"


MOCK_FUNCTIONS = r"""
config_load() {
	MOCK_CONFIG_PACKAGE="$1"
}

config_get() {
	local variable="$1" section="$2" option="$3" default_value="$4" value=""

	case "$MOCK_CONFIG_PACKAGE:$section:$option" in
		quickstart:main:main_dir) value="$MOCK_MAIN_DIR" ;;
		quickstart:main:conf_dir) value="$MOCK_CONF_DIR" ;;
		mise:main:runtime_dir)
			[ -f "$MOCK_STATE_DIR/runtime_dir" ] && value="$(cat "$MOCK_STATE_DIR/runtime_dir")"
			;;
		mise:main:auto_discover) value="${MOCK_AUTO_DISCOVER:-1}" ;;
	esac

	[ -n "$value" ] || value="$default_value"
	eval "$variable=\$value"
}

config_get_bool() {
	config_get "$@"
}
"""


MOCK_UCI = r"""#!/bin/sh
if [ "$1" = "-q" ]; then
	shift
fi

case "$1:$2" in
	get:mise.main)
		printf '%s\n' mise
		;;
	get:linkease.@linkease\[0\].local_home)
		exit 1
		;;
	set:mise.main.runtime_dir=*)
		printf '%s\n' "${2#mise.main.runtime_dir=}" > "$MOCK_STATE_DIR/runtime_dir"
		;;
	commit:mise)
		;;
	*)
		exit 1
		;;
esac
"""


class MiseRuntimeHelperTest(unittest.TestCase):
    def run_helper(
        self,
        commands,
        *,
        main_dir="",
        conf_dir="",
        runtime_dir="",
        auto_discover="1",
        env_conf_dir="",
    ):
        with tempfile.TemporaryDirectory() as temporary_dir:
            temporary = Path(temporary_dir)
            main_dir = main_dir.format(tmp=temporary_dir)
            conf_dir = conf_dir.format(tmp=temporary_dir)
            runtime_dir = runtime_dir.format(tmp=temporary_dir)
            env_conf_dir = env_conf_dir.format(tmp=temporary_dir)
            mock_functions = temporary / "functions.sh"
            mock_functions.write_text(textwrap.dedent(MOCK_FUNCTIONS))

            if runtime_dir:
                (temporary / "runtime_dir").write_text(runtime_dir)

            bin_dir = temporary / "bin"
            bin_dir.mkdir()
            mock_uci = bin_dir / "uci"
            mock_uci.write_text(textwrap.dedent(MOCK_UCI))
            mock_uci.chmod(0o755)

            helper = HELPER.read_text().replace(
                ". /lib/functions.sh", '. "$MOCK_FUNCTIONS"', 1
            )
            script = helper + "\n" + textwrap.dedent(commands)
            env = os.environ.copy()
            env.pop("ISTORE_RUNTIME_CONF_DIR", None)
            env.update(
                {
                    "MOCK_AUTO_DISCOVER": auto_discover,
                    "MOCK_CONF_DIR": conf_dir,
                    "MOCK_FUNCTIONS": str(mock_functions),
                    "MOCK_MAIN_DIR": main_dir,
                    "MOCK_STATE_DIR": str(temporary),
                    "PATH": f"{bin_dir}:{env['PATH']}",
                }
            )
            if env_conf_dir:
                env["ISTORE_RUNTIME_CONF_DIR"] = env_conf_dir
            return subprocess.run(
                ["/bin/sh"],
                input=script,
                text=True,
                capture_output=True,
                env=env,
                check=False,
            )

    def test_auto_discovery_tracks_the_current_configs_directory(self):
        result = self.run_helper(
            """
            first="$(istore_runtime_init)" || exit 10
            [ "$first" = "$MOCK_STATE_DIR/first-configs/Runtime/home" ] || exit 12
            MOCK_CONF_DIR="$MOCK_STATE_DIR/second-configs"
            second="$(istore_runtime_home)" || exit 11
            [ "$second" = "$MOCK_STATE_DIR/second-configs/Runtime/home" ] || exit 13
            printf '%s\n%s\n' "$first" "$second"
            """,
            main_dir="{tmp}",
            conf_dir="{tmp}/first-configs",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), 2)

    def test_explicit_quickstart_conf_dir_does_not_require_main_dir(self):
        result = self.run_helper(
            """
            istore_runtime_home
            """,
            conf_dir="/explicit-configs",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "/explicit-configs/Runtime/home\n")

    def test_explicit_runtime_directory_overrides_discovery(self):
        result = self.run_helper(
            """
            istore_runtime_home
            """,
            conf_dir="/quickstart-configs",
            runtime_dir="/explicit-runtime",
            env_conf_dir="/application-configs",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "/explicit-runtime/home\n")

    def test_discovery_can_be_disabled(self):
        result = self.run_helper(
            """
            istore_runtime_home
            """,
            conf_dir="/quickstart-configs",
            auto_discover="0",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_application_configs_directory_takes_discovery_precedence(self):
        result = self.run_helper(
            """
            istore_runtime_home
            """,
            main_dir="/quickstart",
            conf_dir="/quickstart-configs",
            env_conf_dir="/application-configs",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "/application-configs/Runtime/home\n")

    def test_export_initializes_the_runtime_environment(self):
        result = self.run_helper(
            r"""
            istore_runtime_export_env || exit 20
            [ "$HOME" = "$MOCK_STATE_DIR/configs/Runtime/home" ] || exit 21
            [ "$XDG_DATA_HOME" = "$HOME/.local/share" ] || exit 22
            [ "$XDG_CACHE_HOME" = "$HOME/.cache" ] || exit 23
            [ "$XDG_CONFIG_HOME" = "$HOME/.config" ] || exit 24
            [ "$XDG_STATE_HOME" = "$HOME/.local/state" ] || exit 25
            [ "$MISE_DATA_DIR" = "$XDG_DATA_HOME/mise" ] || exit 26
            [ "$MISE_CACHE_DIR" = "$XDG_CACHE_HOME/mise" ] || exit 27
            [ "$MISE_CONFIG_DIR" = "$XDG_CONFIG_HOME/mise" ] || exit 28
            [ "$MISE_STATE_DIR" = "$XDG_STATE_HOME/mise" ] || exit 29
            [ "${PATH%%:*}" = "$MISE_DATA_DIR/shims" ] || exit 30
            [ -d "$MISE_DATA_DIR" ] || exit 31
            [ -d "$MISE_CACHE_DIR" ] || exit 32
            [ -d "$MISE_CONFIG_DIR" ] || exit 33
            [ -d "$MISE_STATE_DIR" ] || exit 34
            printf 'ok\n'
            """,
            main_dir="{tmp}",
            conf_dir="{tmp}/configs",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "ok\n")


if __name__ == "__main__":
    unittest.main()
