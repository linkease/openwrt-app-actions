#!/usr/bin/env python3
"""Synchronize the OpenWrt AgentFlow package with the latest published build."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO
from urllib.parse import urlparse


DEFAULT_METADATA_URL = (
    "https://fw.koolcenter.com/binary/geili/agentflow/build/version.json"
)
DEFAULT_MAKEFILE = Path("applications/agentflow/Makefile")
ARCHES = {"x86_64": "amd64", "aarch64": "arm64"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
VERSION_RE = re.compile(r"^(?P<package>\d+\.\d+\.\d+)(?:[-+].*)?$")


class SyncError(RuntimeError):
    """Raised when published data cannot be safely synchronized."""


@dataclass(frozen=True)
class Artifact:
    package_arch: str
    upstream_arch: str
    file: str
    sha256: str
    url: str


@dataclass(frozen=True)
class Release:
    published_version: str
    package_version: str
    artifacts: tuple[Artifact, ...]


def open_url(url: str) -> BinaryIO:
    request = urllib.request.Request(url, headers={"User-Agent": "openwrt-app-actions-sync/1"})
    try:
        return urllib.request.urlopen(request, timeout=60)
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SyncError(f"request failed for {url}: {exc}") from exc


def load_release(metadata_url: str) -> Release:
    try:
        with open_url(metadata_url) as response:
            metadata = json.load(response)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise SyncError(f"invalid release metadata from {metadata_url}: {exc}") from exc

    if not isinstance(metadata, dict):
        raise SyncError("release metadata must be a JSON object")

    published_version = metadata.get("version")
    version_match = (
        VERSION_RE.fullmatch(published_version)
        if isinstance(published_version, str)
        else None
    )
    if not version_match:
        raise SyncError(f"unsupported AgentFlow version: {published_version!r}")

    try:
        linux = metadata["platforms"]["linux"]
    except (KeyError, TypeError) as exc:
        raise SyncError("release metadata has no Linux artifacts") from exc

    artifacts: list[Artifact] = []
    for package_arch, upstream_arch in ARCHES.items():
        try:
            item = linux[upstream_arch]
            file_name = item["file"]
            sha256 = item["sha256"]
            url = item["url"]
        except (KeyError, TypeError) as exc:
            raise SyncError(f"release metadata has no Linux {upstream_arch} artifact") from exc

        if not all(isinstance(value, str) for value in (file_name, sha256, url)):
            raise SyncError(f"invalid Linux {upstream_arch} artifact fields")

        expected_file = f"agentflow-linux-{upstream_arch}"
        if file_name != expected_file or Path(urlparse(url).path).name != expected_file:
            raise SyncError(f"unexpected Linux {upstream_arch} artifact: {file_name!r}, {url!r}")
        if not isinstance(sha256, str) or not SHA256_RE.fullmatch(sha256):
            raise SyncError(f"invalid Linux {upstream_arch} SHA-256: {sha256!r}")

        artifacts.append(Artifact(package_arch, upstream_arch, file_name, sha256, url))

    return Release(
        published_version=published_version,
        package_version=version_match.group("package"),
        artifacts=tuple(artifacts),
    )


def verify_artifacts(release: Release) -> None:
    for artifact in release.artifacts:
        digest = hashlib.sha256()
        with open_url(artifact.url) as response:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
        actual = digest.hexdigest()
        if actual != artifact.sha256:
            raise SyncError(
                f"Linux {artifact.upstream_arch} SHA-256 mismatch: "
                f"metadata={artifact.sha256}, downloaded={actual}"
            )
        print(f"verified {artifact.file}: {actual}")


def required_value(text: str, name: str, pattern: str) -> str:
    matches = re.findall(pattern, text, flags=re.MULTILINE)
    if len(matches) != 1:
        raise SyncError(f"expected exactly one {name} assignment in Makefile")
    return matches[0]


def updated_makefile(text: str, release: Release) -> tuple[str, int, bool]:
    current_version = required_value(text, "PKG_VERSION", r"^PKG_VERSION:=(.+)$")
    current_release_text = required_value(text, "PKG_RELEASE", r"^PKG_RELEASE:=(\d+)$")
    current_release = int(current_release_text)

    hashes = {
        artifact.package_arch: artifact.sha256 for artifact in release.artifacts
    }
    current_hashes = {
        arch: required_value(
            text,
            f"AGENTFLOW_HASH_{arch}",
            rf"^AGENTFLOW_HASH_{re.escape(arch)}:=([0-9a-f]{{64}})$",
        )
        for arch in ARCHES
    }

    hashes_changed = current_hashes != hashes
    if current_version != release.package_version:
        next_release = 1
    elif hashes_changed:
        next_release = current_release + 1
    else:
        next_release = current_release

    replacements = {
        "PKG_VERSION": release.package_version,
        "PKG_RELEASE": str(next_release),
        **{f"AGENTFLOW_HASH_{arch}": digest for arch, digest in hashes.items()},
    }
    updated = text
    for name, value in replacements.items():
        updated, count = re.subn(
            rf"^{re.escape(name)}:=.*$", f"{name}:={value}", updated, flags=re.MULTILINE
        )
        if count != 1:
            raise SyncError(f"expected exactly one {name} assignment in Makefile")

    return updated, next_release, updated != text


def write_atomic(path: Path, content: str) -> None:
    path = path.resolve()
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as temporary:
        temporary.write(content)
        temporary_path = Path(temporary.name)
    try:
        os.chmod(temporary_path, stat.S_IMODE(path.stat().st_mode))
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata-url", default=DEFAULT_METADATA_URL)
    parser.add_argument("--makefile", type=Path, default=DEFAULT_MAKEFILE)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the release and report whether the Makefile is current without writing",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        release = load_release(args.metadata_url)
        verify_artifacts(release)
        original = args.makefile.read_text(encoding="utf-8")
        updated, package_release, changed = updated_makefile(original, release)
        package_id = f"{release.package_version}-{package_release}"

        if args.check:
            if changed:
                print(f"AgentFlow {release.published_version} requires package {package_id}")
                return 1
            print(f"AgentFlow package {package_id} is current ({release.published_version})")
            return 0

        if not changed:
            print(f"AgentFlow package {package_id} is already current ({release.published_version})")
            return 0

        write_atomic(args.makefile, updated)
        print(f"updated {args.makefile} to AgentFlow package {package_id} ({release.published_version})")
        return 0
    except (OSError, SyncError) as exc:
        print(f"sync-agentflow: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
