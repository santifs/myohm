#!/usr/bin/env python3
"""Create a local Python virtualenv for BioMess BLE/UART verification tools."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import venv
from pathlib import Path


FIRMWARE_DIR = Path(__file__).resolve().parents[1]
TOOLS_DIR = Path(__file__).resolve().parent
DEFAULT_VENV = FIRMWARE_DIR / ".venv"
REQUIREMENTS = TOOLS_DIR / "requirements.txt"


def venv_python(venv_dir: Path) -> Path:
    if os.name == "nt":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def run(command: list[str]) -> None:
    print(" ".join(command), flush=True)
    subprocess.run(command, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--venv", type=Path, default=DEFAULT_VENV, help="Virtualenv path.")
    parser.add_argument("--recreate", action="store_true", help="Recreate the virtualenv if it already exists.")
    args = parser.parse_args()

    venv_dir = args.venv
    if args.recreate and venv_dir.exists():
        if not (venv_dir / "pyvenv.cfg").exists():
            raise SystemExit(f"Refusing to remove non-virtualenv path: {venv_dir}")
        print(f"removing_venv={venv_dir}")
        shutil.rmtree(venv_dir)

    if not venv_dir.exists():
        print(f"creating_venv={venv_dir}")
        venv.EnvBuilder(with_pip=True, clear=False).create(venv_dir)
    else:
        print(f"using_venv={venv_dir}")

    python = venv_python(venv_dir)
    if not python.exists():
        raise SystemExit(f"Virtualenv Python not found: {python}")

    run([str(python), "-m", "pip", "install", "--upgrade", "pip"])
    run([str(python), "-m", "pip", "install", "-r", str(REQUIREMENTS)])

    print("python_env_ok=true")
    print(f"python={python}")
    print(f"preflight_command={python} {TOOLS_DIR / 'preflight.py'} --require-bleak --require-pyserial")


if __name__ == "__main__":
    main()
