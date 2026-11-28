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

@pytest.mark.parametrize("freq,z,reason", [
    ([], [], "insufficient_frequencies"),
    ([5000]*4, [70-5j]*4, "insufficient_frequencies"),
    (FREQS, [70]*len(FREQS), "constant_spectrum"),
    (FREQS, 70 - 1/(1+(1j*FREQS/50000)**0.75), "no_capacitive_response"),
])
def test_unidentifiable_spectra(freq, z, reason):
    result = ms.fit_cole(freq, z)
    assert not result["accepted"]
    assert result["failure_reason"] == reason
    assert result["fc_hz"] is None


def test_matlab_convention_and_residual():
    z = 40 + 50/(1+(1j*FREQS/50000)**0.75)
    result = ms.fit_cole(FREQS, z)
    assert result["success"] and result["accepted"]
    assert result["cole_exponent"] == pytest.approx(0.75)
    assert result["Ri"] == pytest.approx(72)
    predicted = result["Rinf"] + (result["R0"]-result["Rinf"])/(1+(
        2j*np.pi*FREQS*result["tau_s"])**result["cole_exponent"])
    assert result["rmse_pct"] == pytest.approx(100*np.sqrt(np.mean(abs(predicted-z)**2))/np.mean(abs(z)))


def test_failed_solver(monkeypatch):
    from types import SimpleNamespace
    monkeypatch.setattr(ms, "least_squares", lambda *a, **kw: SimpleNamespace(
        success=False, message="evaluation limit", cost=1.0))
    result = ms.fit_cole(FREQS, 40 + 50/(1+(1j*FREQS/50000)**0.75))
    assert not result["success"] and not result["accepted"]
    assert result["solver_message"] == "evaluation limit"
    assert result["tau_s"] is None


def test_noisy_sweeps_and_missing_band():
    df = pd.DataFrame(dict(freq_hz=[5000]*5, sweep=range(5), mag_ohm=range(98,103)))
    assert ms.select_sweeps(df) == (list(range(5)), "noisy_kept_all")
    assert ms.select_sweeps(df.assign(freq_hz=50000)) == ([], "needs_review")


def test_empty_cli_reports_reason(tmp_path, capsys):
    import json
    path = tmp_path / "empty.csv"
    path.write_text("sweep,freq_hz,mag_ohm,phase_deg\n")
    ms.main([str(path)])
    report = json.loads(capsys.readouterr().out)
    assert report["failure_reason"] == "insufficient_frequencies"
    assert report["sweeps_kept"] == []


def test_cli_preserves_tau_precision(tmp_path, capsys):
    import json
    ms.main([str(measurement(tmp_path))])
    report = json.loads(capsys.readouterr().out)
    assert 2*np.pi*report["fc_hz"]*report["tau_s"] == pytest.approx(1, abs=1e-14)


def test_web_csv_filters_invalid_points_and_prevents_pooling_runs(tmp_path):
    path = measurement(tmp_path)
    df = pd.read_csv(path).rename(columns={"freq_hz": "frequency_hz", "mag_ohm": "magnitude_ohm",
                                          "sweep": "repetition"})
    df["valid"] = True
    df["run_id"] = "first"
    df.loc[0, "valid"] = False
    df.to_csv(path, index=False)
    assert len(ms.load(path)) == len(df) - 1
    assert ms.process(path)[1]["accepted"]
    df.loc[1, "run_id"] = "second"
    df.to_csv(path, index=False)
    with pytest.raises(ValueError, match="multiple run_id"):
        ms.process(path)
