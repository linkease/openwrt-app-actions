import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "sync-agentflow.py"
SPEC = importlib.util.spec_from_file_location("sync_agentflow", SCRIPT)
sync_agentflow = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = sync_agentflow
SPEC.loader.exec_module(sync_agentflow)


MAKEFILE = """\
AGENTFLOW_HASH_x86_64:={amd64}
AGENTFLOW_HASH_aarch64:={arm64}

PKG_NAME:=agentflow
PKG_VERSION:={version}
PKG_RELEASE:={release}
"""


def digest(content: bytes) -> str:
    return sync_agentflow.hashlib.sha256(content).hexdigest()


class SyncAgentFlowTest(unittest.TestCase):
    def release(self, version="0.4.0-20260914-deadbeef", amd64="a" * 64, arm64="b" * 64):
        return sync_agentflow.Release(
            published_version=version,
            package_version=version.split("-", 1)[0],
            artifacts=(
                sync_agentflow.Artifact("x86_64", "amd64", "agentflow-linux-amd64", amd64, "unused"),
                sync_agentflow.Artifact("aarch64", "arm64", "agentflow-linux-arm64", arm64, "unused"),
            ),
        )

    def test_new_version_resets_package_release(self):
        source = MAKEFILE.format(amd64="1" * 64, arm64="2" * 64, version="0.3.1", release=9)
        updated, package_release, changed = sync_agentflow.updated_makefile(source, self.release())

        self.assertTrue(changed)
        self.assertEqual(package_release, 1)
        self.assertIn("PKG_VERSION:=0.4.0", updated)
        self.assertIn("PKG_RELEASE:=1", updated)

    def test_new_build_increments_package_release(self):
        source = MAKEFILE.format(amd64="1" * 64, arm64="2" * 64, version="0.4.0", release=3)
        updated, package_release, changed = sync_agentflow.updated_makefile(source, self.release())

        self.assertTrue(changed)
        self.assertEqual(package_release, 4)
        self.assertIn("PKG_RELEASE:=4", updated)

    def test_current_build_does_not_change_makefile(self):
        release = self.release()
        source = MAKEFILE.format(amd64="a" * 64, arm64="b" * 64, version="0.4.0", release=3)

        updated, package_release, changed = sync_agentflow.updated_makefile(source, release)

        self.assertFalse(changed)
        self.assertEqual(package_release, 3)
        self.assertEqual(updated, source)

    def test_load_and_verify_local_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binaries = {
                "amd64": b"agentflow-amd64",
                "arm64": b"agentflow-arm64",
            }
            platforms = {}
            for arch, content in binaries.items():
                artifact = root / f"agentflow-linux-{arch}"
                artifact.write_bytes(content)
                platforms[arch] = {
                    "file": artifact.name,
                    "sha256": digest(content),
                    "url": artifact.as_uri(),
                }
            metadata = root / "version.json"
            metadata.write_text(
                json.dumps({"version": "0.4.0-20260914-deadbeef", "platforms": {"linux": platforms}}),
                encoding="utf-8",
            )

            release = sync_agentflow.load_release(metadata.as_uri())
            sync_agentflow.verify_artifacts(release)

            self.assertEqual(release.package_version, "0.4.0")

    def test_verification_rejects_bad_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "agentflow-linux-amd64"
            artifact.write_bytes(b"wrong content")
            release = sync_agentflow.Release(
                published_version="0.4.0-build",
                package_version="0.4.0",
                artifacts=(
                    sync_agentflow.Artifact(
                        "x86_64", "amd64", artifact.name, "0" * 64, artifact.as_uri()
                    ),
                ),
            )

            with self.assertRaises(sync_agentflow.SyncError):
                sync_agentflow.verify_artifacts(release)


if __name__ == "__main__":
    unittest.main()
