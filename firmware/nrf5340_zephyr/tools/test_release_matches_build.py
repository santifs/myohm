#!/usr/bin/env python3
"""Check that a firmware release zip contains the current build/merged.hex."""

from __future__ import annotations

import argparse
import hashlib
import zipfile
from pathlib import Path


FIRMWARE_DIR = Path(__file__).resolve().parents[1]
DEFAULT_BUILD_HEX = FIRMWARE_DIR / "build/merged.hex"
DEFAULT_RELEASE_DIR = FIRMWARE_DIR / "build/releases"


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def latest_release() -> Path:
    packages = sorted(DEFAULT_RELEASE_DIR.glob("biomess-nrf5340-firmware-*.zip"), key=lambda path: path.stat().st_mtime)
    if not packages:
        raise SystemExit(f"No release packages found under {DEFAULT_RELEASE_DIR}")
    return packages[-1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-hex", type=Path, default=DEFAULT_BUILD_HEX)
    parser.add_argument("--release-package", type=Path, help="Release zip. Defaults to newest local release.")
    args = parser.parse_args()

    build_hex = args.build_hex
    release_package = args.release_package or latest_release()
    if not build_hex.exists():
        raise SystemExit(f"Build hex does not exist: {build_hex}")
    if not release_package.exists():
        raise SystemExit(f"Release package does not exist: {release_package}")

    build_sha = sha256_file(build_hex)
    build_size = build_hex.stat().st_size
    with zipfile.ZipFile(release_package) as archive:
        release_hex = archive.read("firmware/merged.hex")
    release_sha = sha256_bytes(release_hex)
    release_size = len(release_hex)
    match = build_sha == release_sha and build_size == release_size

    print(f"build_hex={build_hex}")
    print(f"build_hex_bytes={build_size}")
    print(f"build_hex_sha256={build_sha}")
    print(f"release_package={release_package}")
    print(f"release_hex_bytes={release_size}")
    print(f"release_hex_sha256={release_sha}")
    print(f"release_matches_build={str(match).lower()}")
    if not match:
        raise SystemExit("Release firmware does not match current build/merged.hex")
    print("release_matches_build_ok=true")


if __name__ == "__main__":
    main()
