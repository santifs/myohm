# SPDX-License-Identifier: Apache-2.0
"""Quality control, aggregation and Cole fitting of Myohm sweeps.

Processing steps:

1. Wrap phase to [-180, 180) and drop corrupted rows with broad range filters.
2. Repeat-sweep consistency filter on the median |Z| in the 5-10 kHz band of each sweep:
   outliers exceed max(2 MAD, 1 % of the measurement median); consecutive outliers at the
   start or end are removed; dispersed outliers are removed only if the remaining coefficient
   of variation is below 0.5 %, otherwise all sweeps are kept and flagged.
3. Median magnitude and phase per frequency; R = |Z| cos(phi), Xc = -|Z| sin(phi).
4. Cole fit Z = Rinf + (R0 - Rinf) / (1 + (j w tau)^(1 - alpha)) by bounded least squares
   with 12 starting points and the following acceptance criteria (relative RMS residual
   <= 2 %, 2 kHz <= fc <= 300 kHz, 0.06 < alpha < 0.95).

The five-sweep protocol flags other counts for review. accepted describes the fit;
inspect quality_flag separately. alpha is the BioMess Python dispersion convention.
cole_exponent = 1 - alpha is the exponent called alpha in the Swarthmore MATLAB model.
Ri is the equivalent intracellular resistance in ohms. success reports solver termination.

The range filters were chosen for localized muscle measurements (5-500 ohm, phase -30 to +5 deg);
adjust them for other tissues. They screen corrupted rows; they are not physiological limits.

Input: CSV with sweep (or rep), freq_hz, mag_ohm, phase_deg; one file per measurement.
Usage: python3 myohm_spectra.py measurement.csv [--out spectrum.csv]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.optimize import least_squares

REF_BAND = (5_000.0, 10_000.0)
MAD_FACTOR = 2.0
MIN_REL = 0.01
RESIDUAL_OK = 0.005
ROW_LIMITS = {"freq_hz": (3_000, 250_000), "mag_ohm": (5, 500), "phase_deg": (-30, 5)}
COLE_BOUNDS = ([0.1, 0.0, 1e-7, 0.05], [1e3, 1.0, 1e-2, 0.99])
N_STARTS = 12


def load(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path).rename(columns={"repetition": "sweep", "rep": "sweep", "repetition_index": "sweep", "frequency_hz": "freq_hz",
                                            "magnitude_ohm": "mag_ohm"})
    if "run_id" in df and df.run_id.nunique() > 1:
        raise ValueError("Select one measurement per file; CSV contains multiple run_id values")
    if "valid" in df:
        df = df[df.valid.astype(str).str.lower().isin(["true", "1"])]
    for col in ROW_LIMITS:
        df[col] = pd.to_numeric(df[col], errors="coerce").astype(float)
    df["phase_deg"] = (df.phase_deg + 180) % 360 - 180
    keep = np.ones(len(df), bool)
    for col, (lo, hi) in ROW_LIMITS.items():
        keep &= df[col].between(lo, hi).to_numpy()
    filtered = df[keep].reset_index(drop=True)
    filtered.attrs["input_sweeps"] = sorted(df.sweep.dropna().unique())
    return filtered


def select_sweeps(df: pd.DataFrame) -> tuple[list[int], str]:
    """Return the sweeps kept by the consistency filter and a quality flag."""
    band = df[df.freq_hz.between(*REF_BAND)]
    refs = band.groupby("sweep").mag_ohm.median().reindex(df.attrs.get("input_sweeps", sorted(df.sweep.dropna().unique())))
    sweeps = list(refs.index)
    values = refs.to_numpy(float)
    if np.isnan(values).all():
        return [], "needs_review"
    if len(sweeps) != 5:
        return [s for s, v in zip(sweeps, values) if np.isfinite(v)], "needs_review"
    med = float(np.nanmedian(values))
    threshold = max(MAD_FACTOR * float(np.nanmedian(np.abs(values - med))), MIN_REL * med)
    outliers = [i for i, v in enumerate(values) if np.isnan(v) or abs(v - med) > threshold]
    if not outliers:
        return sweeps, "noisy_kept_all" if np.std(values) / med > 0.01 else "clean"
    kept = [s for i, s in enumerate(sweeps) if i not in outliers]
    n = len(sweeps)
    leading = outliers == list(range(len(outliers)))
    trailing = outliers == list(range(n - len(outliers), n))
    if kept and (leading or trailing) and len(outliers) <= 3:
        return kept, "trimmed_" + ("initial" if leading else "final")
    kept_values = values[[i for i in range(n) if i not in outliers]]
    if kept and (np.isnan(values).any() or np.std(kept_values) / np.mean(kept_values) < RESIDUAL_OK):
        return kept, "trimmed_dispersed"
    return sweeps, "noisy_kept_all"


def aggregate(df: pd.DataFrame, sweeps: list[int]) -> pd.DataFrame:
    g = df[df.sweep.isin(sweeps)].groupby("freq_hz")
    out = pd.DataFrame({"mag_ohm": g.mag_ohm.median(), "phase_deg": g.phase_deg.median(),
                        "mag_iqr": g.mag_ohm.quantile(0.75) - g.mag_ohm.quantile(0.25),
                        "phase_iqr": g.phase_deg.quantile(0.75) - g.phase_deg.quantile(0.25),
                        "n_sweeps": g.sweep.nunique()}).reset_index()
    phi = np.deg2rad(out.phase_deg)
    out["r_ohm"] = out.mag_ohm * np.cos(phi)
    out["xc_ohm"] = -out.mag_ohm * np.sin(phi)
    return out


def cole(params, w):
    r0, rinf, tau, alpha = params
    return rinf + (r0 - rinf) / (1 + (1j * w * tau) ** (1 - np.clip(alpha, 0.05, 0.99)))


def fit_cole(freq_hz: np.ndarray, z: np.ndarray, seed: int = 0) -> dict:
    freq_hz = np.asarray(freq_hz, dtype=float)
    z = np.asarray(z, dtype=complex)
    summary = dict.fromkeys(("R0", "Rinf", "Re", "Ri", "tau_s", "alpha", "cole_exponent",
                             "fc_hz", "rmse_pct", "cost_spread"))
    summary.update(accepted=False, success=False, solver_message=None, n_starts=0)
    if freq_hz.ndim != 1 or freq_hz.shape != z.shape:
        raise ValueError("Expected matching one-dimensional frequency and impedance arrays")
    if not np.isfinite(z).all() or not np.isfinite(freq_hz).all() or np.any(freq_hz <= 0):
        return {**summary, "failure_reason": "invalid_spectrum"}
    # Require an overdetermined fit (four real parameters, two observations per frequency).
    if np.unique(freq_hz).size < 3:
        return {**summary, "failure_reason": "insufficient_frequencies"}
    if np.ptp(z.real) == 0 and np.ptp(z.imag) == 0:
        return {**summary, "failure_reason": "constant_spectrum"}
    if np.all(z.imag >= 0):
        return {**summary, "failure_reason": "no_capacitive_response"}

    w = 2 * np.pi * freq_hz
    scale = max(float(np.abs(z).max()), 1.0)

    def physical(p):
        r0, ratio, tau, alpha = p
        return r0, r0 * ratio, tau, alpha

    def residuals(p):
        d = cole(physical(p), w) - z
        return np.concatenate([d.real, d.imag]) / scale

    peak = freq_hz[np.argmax(-z.imag)]
    r0_guess = max(z.real.max(), 0.1)
    start = np.array([r0_guess, 0.8 * z.real.min() / r0_guess, 1 / (2 * np.pi * peak), 0.75])
    rng = np.random.default_rng(seed)
    trials = []
    for i in range(N_STARTS):
        guess = start.copy()
        if i:
            guess[0] *= rng.uniform(0.5, 1.5)
            guess[1] *= rng.uniform(0.5, 1.5)
            guess[2] *= 10 ** rng.uniform(-2, 2)
            guess[3] += rng.uniform(-0.4, 0.4)
        trials.append(least_squares(residuals, np.clip(guess, *COLE_BOUNDS), bounds=COLE_BOUNDS,
                                    x_scale="jac", max_nfev=20000, ftol=1e-12, xtol=1e-12))
    best = min(trials, key=lambda trial: (not trial.success, trial.cost))
    summary.update(success=bool(best.success), solver_message=str(best.message),
                   n_starts=len(trials), cost_spread=float(np.ptp([t.cost for t in trials])))
    if not best.success:
        return {**summary, "failure_reason": "solver_failed"}
    r0, rinf, tau, alpha = physical(best.x)
    if best.active_mask[1] == 1 or np.isclose(r0, rinf):
        return {**summary, "failure_reason": "unresolved_dispersion"}
    rmse_pct = 100 * np.sqrt(np.mean(np.abs(cole(physical(best.x), w) - z) ** 2)) / np.abs(z).mean()
    fc = 1 / (2 * np.pi * tau)
    accepted = bool(rmse_pct <= 2 and 2e3 <= fc <= 300e3 and 0.06 < alpha < 0.95)
    return {**summary, "R0": r0, "Rinf": rinf, "Re": r0, "Ri": r0 * rinf / (r0 - rinf),
            "tau_s": tau, "alpha": alpha, "cole_exponent": 1 - alpha, "fc_hz": fc,
            "rmse_pct": rmse_pct, "accepted": accepted,
            "failure_reason": None if accepted else "fit_outside_qc_limits"}


def process(path: Path) -> tuple[pd.DataFrame, dict]:
    df = load(path)
    sweeps, flag = select_sweeps(df)
    spectrum = aggregate(df, sweeps)
    z = spectrum.mag_ohm.to_numpy() * np.exp(1j * np.deg2rad(spectrum.phase_deg.to_numpy()))
    summary = {"quality_flag": flag, "sweeps_kept": [int(s) for s in sweeps],
               **fit_cole(spectrum.freq_hz.to_numpy(float), z)}
    return spectrum, summary


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("measurement", type=Path)
    parser.add_argument("--out", type=Path, help="write the aggregated spectrum to this CSV")
    args = parser.parse_args(argv)
    spectrum, summary = process(args.measurement)
    if args.out:
        spectrum.to_csv(args.out, index=False)
    print(json.dumps(summary, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
