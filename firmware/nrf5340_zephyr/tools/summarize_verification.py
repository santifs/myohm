#!/usr/bin/env python3
"""Summarize one or more run_verification.py JSON summaries."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_summary(path: Path) -> dict[str, object]:
    if not path.exists():
        raise SystemExit(f"Verification summary does not exist: {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"Verification summary is not a JSON object: {path}")
    if "steps" not in data or not isinstance(data["steps"], list):
        raise SystemExit(f"Verification summary missing steps list: {path}")
    if "ok" not in data:
        raise SystemExit(f"Verification summary missing ok field: {path}")
    return data


def summarize(path: Path) -> bool:
    data = load_summary(path)
    steps = data["steps"]
    assert isinstance(steps, list)
    failed_steps = [
        step for step in steps
        if isinstance(step, dict) and not bool(step.get("ok"))
    ]

    print(f"summary={path}")
    print(f"summary_ok={str(bool(data.get('ok'))).lower()}")
    print(f"summary_steps={len(steps)}")
    print(f"summary_failed_steps={len(failed_steps)}")
    print(f"summary_board={data.get('board', '')}")
    print(f"summary_flash_requested={str(bool(data.get('flash_requested'))).lower()}")
    print(f"summary_ble_enabled={str(bool(data.get('ble_enabled'))).lower()}")
    print(f"summary_uart_enabled={str(bool(data.get('uart_capture_enabled'))).lower()}")

    for index, step in enumerate(steps):
        if not isinstance(step, dict):
            print(f"step_{index}_invalid=true")
            continue
        label = step.get("label", "")
        ok = bool(step.get("ok"))
        exit_code = step.get("exit_code", "")
        duration = step.get("duration_seconds", "")
        print(f"step_{index}_label={label}")
        print(f"step_{index}_ok={str(ok).lower()}")
        print(f"step_{index}_exit_code={exit_code}")
        print(f"step_{index}_duration_seconds={duration}")
        if not ok:
            tail = str(step.get("stdout_tail", "")).strip().splitlines()
            for line_index, line in enumerate(tail[-12:]):
                print(f"step_{index}_stdout_tail_{line_index}={line}")

    return bool(data.get("ok")) and not failed_steps


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summaries", type=Path, nargs="+")
    args = parser.parse_args()

    all_ok = True
    for summary in args.summaries:
        all_ok = summarize(summary) and all_ok

    print(f"verification_summary_ok={str(all_ok).lower()}")
    if not all_ok:
        raise SystemExit("At least one verification summary failed")


if __name__ == "__main__":
    main()
