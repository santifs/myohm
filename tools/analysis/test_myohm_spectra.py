# SPDX-License-Identifier: Apache-2.0
"""Synthetic checks of myohm_spectra: Cole parameters are recovered and drifting sweeps are trimmed.

Run: python3 -m pytest tools/analysis
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import myohm_spectra as ms  # noqa: E402

FREQS = np.geomspace(4e3, 198e3, 48)
TRUE = {"R0": 90.0, "Rinf": 40.0, "tau_s": 1 / (2 * np.pi * 50e3), "alpha": 0.25}


def measurement(tmp_path: Path, drift_first: float = 0.0) -> Path:
    rng = np.random.default_rng(4)
    z = ms.cole([TRUE["R0"], TRUE["Rinf"], TRUE["tau_s"], TRUE["alpha"]], 2 * np.pi * FREQS)
    rows = []
    for sweep in range(5):
        gain = 1 + (drift_first if sweep == 0 else 0.0)
        zs = z * gain * (1 + rng.normal(0, 2e-4, len(FREQS)))
        rows += [{"sweep": sweep, "freq_hz": f, "mag_ohm": abs(v), "phase_deg": np.degrees(np.angle(v))}
                 for f, v in zip(FREQS, zs)]
    path = tmp_path / "m.csv"
    pd.DataFrame(rows).to_csv(path, index=False)
    return path


def test_cole_parameters_recovered(tmp_path):
    _, summary = ms.process(measurement(tmp_path))
    assert summary["quality_flag"] == "clean"
    assert summary["accepted"]
    assert summary["R0"] == pytest.approx(TRUE["R0"], rel=0.01)
    assert summary["Rinf"] == pytest.approx(TRUE["Rinf"], rel=0.02)
    assert summary["fc_hz"] == pytest.approx(50e3, rel=0.03)
    assert summary["alpha"] == pytest.approx(TRUE["alpha"], abs=0.02)


def test_initial_settling_sweep_is_trimmed(tmp_path):
    _, summary = ms.process(measurement(tmp_path, drift_first=0.05))
    assert summary["quality_flag"] == "trimmed_initial"
    assert summary["sweeps_kept"] == [1, 2, 3, 4]
