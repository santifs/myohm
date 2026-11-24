#!/usr/bin/env python3
"""Syntax-check firmware verification tools without writing __pycache__ files."""

from __future__ import annotations

import py_compile
import tempfile
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent


def main() -> None:
    scripts = sorted(path for path in TOOLS_DIR.glob("*.py") if path.name != Path(__file__).name)
    with tempfile.TemporaryDirectory(prefix="biomess_pycompile_") as tmp:
        tmpdir = Path(tmp)
        for script in scripts:
            py_compile.compile(str(script), cfile=str(tmpdir / f"{script.name}.pyc"), doraise=True)
    print(f"python_syntax_ok=true")
    print(f"python_scripts_checked={len(scripts)}")


if __name__ == "__main__":
    main()
