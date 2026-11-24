#!/usr/bin/env python3
"""Check local Markdown links in firmware documentation."""

from __future__ import annotations

import re
from pathlib import Path
from urllib.parse import unquote


FIRMWARE_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = FIRMWARE_DIR.parents[1]
DOC_ROOTS = [
    REPO_ROOT / "README.md",
    REPO_ROOT / "firmware/README.md",
    REPO_ROOT / "hardware/README.md",
    FIRMWARE_DIR / "README.md",
    FIRMWARE_DIR / "docs",
    FIRMWARE_DIR / "tools" / "README.md",
]
LINK_RE = re.compile(r"!?\[[^\]]*]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
EXTERNAL_PREFIXES = (
    "http://",
    "https://",
    "mailto:",
    "tel:",
)


def markdown_files() -> list[Path]:
    files: list[Path] = []
    for root in DOC_ROOTS:
        if root.is_file():
            files.append(root)
        elif root.is_dir():
            files.extend(sorted(root.rglob("*.md")))
    return sorted(set(files))


def should_skip(target: str) -> bool:
    return (
        not target
        or target.startswith("#")
        or target.startswith("/")
        or target.startswith(EXTERNAL_PREFIXES)
    )


def target_path(source: Path, target: str) -> Path:
    clean = unquote(target.split("#", 1)[0])
    return (source.parent / clean).resolve()


def main() -> None:
    failures: list[str] = []
    checked = 0

    for source in markdown_files():
        text = source.read_text(encoding="utf-8", errors="replace")
        for match in LINK_RE.finditer(text):
            target = match.group(1).strip()
            if should_skip(target):
                continue
            checked += 1
            path = target_path(source, target)
            if not path.exists():
                failures.append(f"{source.relative_to(REPO_ROOT)} -> {target}")

    if failures:
        for failure in failures:
            print(f"broken_doc_link={failure}")
        raise SystemExit(f"Found {len(failures)} broken local Markdown link(s)")

    print("docs_links_ok=true")
    print(f"docs_files_checked={len(markdown_files())}")
    print(f"docs_links_checked={checked}")


if __name__ == "__main__":
    main()
