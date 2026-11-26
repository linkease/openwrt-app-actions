#!/usr/bin/env python3
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "applications/mise-runtime/Makefile"


def value(recipe: str, name: str) -> str:
    match = re.search(rf"^{name}:=(.+)$", recipe, re.MULTILINE)
    if not match:
        raise ValueError(f"missing {name} in {RUNTIME.relative_to(ROOT)}")
    return match.group(1)


def main() -> int:
    runtime_recipe = RUNTIME.read_text(encoding="utf-8")
    runtime_version = value(runtime_recipe, "PKG_VERSION")
    runtime_release = int(value(runtime_recipe, "PKG_RELEASE"))
    floor = re.compile(
        r"mise-runtime \(>=(?P<version>[0-9.]+)-"
        r"\$\(if \$\(CONFIG_USE_APK\),r\)(?P<release>\d+)\)"
    )
    errors = []
    checked = 0
    for makefile in sorted((ROOT / "applications").glob("*/Makefile")):
        recipe = makefile.read_text(encoding="utf-8")
        for match in floor.finditer(recipe):
            checked += 1
            required_version = match.group("version")
            required_release = int(match.group("release"))
            if required_version != runtime_version or required_release > runtime_release:
                errors.append(
                    f"{makefile.relative_to(ROOT)} requires mise-runtime "
                    f">={required_version}-r{required_release}, but the feed provides "
                    f"{runtime_version}-r{runtime_release}"
                )
    if checked == 0:
        errors.append("no mise-runtime dependency floors found")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(
        f"checked {checked} mise-runtime dependency floors against "
        f"{runtime_version}-r{runtime_release}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
