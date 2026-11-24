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

The range filters were chosen for localized muscle measurements (5-500 ohm, phase -30 to +5 deg);
adjust them for other tissues. They screen corrupted rows; they are not physiological limits.

Input: CSV with sweep (or rep), freq_hz, mag_ohm, phase_deg; one file per measurement.
Usage: python3 myohm_spectra.py measurement.csv [--out spectrum.csv]
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.optimize import least_squares

REF_BAND = (5_000.0, 10_000.0)
MAD_FACTOR = 2.0
MIN_REL = 0.01
RESIDUAL_OK = 0.005
ROW_LIMITS = {"freq_hz": (3_000, 250_000), "mag_ohm": (5, 500), "phase_deg": (-30, 5)}
COLE_BOUNDS = ([0.1, 0.0, 1e-7, 0.05], [1e3, 1e3, 1e-2, 0.99])
N_STARTS = 12


def load(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path).rename(columns={"rep": "sweep", "repetition_index": "sweep", "frequency_hz": "freq_hz",
                                            "magnitude_ohm": "mag_ohm"})
    df["phase_deg"] = (df.phase_deg + 180) % 360 - 180
    keep = np.ones(len(df), bool)
    for col, (lo, hi) in ROW_LIMITS.items():
        keep &= df[col].between(lo, hi).to_numpy()
    return df[keep].reset_index(drop=True)


def select_sweeps(df: pd.DataFrame) -> tuple[list[int], str]:
    """Return the sweeps kept by the consistency filter and a quality flag."""
    band = df[df.freq_hz.between(*REF_BAND)]
    refs = band.groupby("sweep").mag_ohm.median().reindex(sorted(df.sweep.unique()))
    sweeps = list(refs.index)
    values = refs.to_numpy(float)
    if np.isnan(values).all():
        return sweeps, "needs_review"
    med = float(np.nanmedian(values))
    threshold = max(MAD_FACTOR * float(np.nanmedian(np.abs(values - med))), MIN_REL * med)
    outliers = [i for i, v in enumerate(values) if np.isnan(v) or abs(v - med) > threshold]
    if not outliers:
        return sweeps, "clean"
    kept = [s for i, s in enumerate(sweeps) if i not in outliers]
    n = len(sweeps)
    leading = outliers == list(range(len(outliers)))
    trailing = outliers == list(range(n - len(outliers), n))
    if kept and (leading or trailing) and len(outliers) <= n // 2:
        return kept, "trimmed_" + ("initial" if leading else "final")
    kept_values = values[[i for i in range(n) if i not in outliers]]
    if kept and np.nanstd(kept_values) / np.nanmean(kept_values) < RESIDUAL_OK:
        return kept, "trimmed_dispersed"
    return sweeps, "noisy_kept_all"


def aggregate(df: pd.DataFrame, sweeps: list[int]) -> pd.DataFrame:
    g = df[df.sweep.isin(sweeps)].groupby("freq_hz")
    out = pd.DataFrame({"mag_ohm": g.mag_ohm.median(), "phase_deg": g.phase_deg.median(),
                        "mag_iqr": g.mag_ohm.quantile(0.75) - g.mag_ohm.quantile(0.25),
                        "n_sweeps": g.sweep.nunique()}).reset_index()
    phi = np.deg2rad(out.phase_deg)
    out["r_ohm"] = out.mag_ohm * np.cos(phi)
    out["xc_ohm"] = -out.mag_ohm * np.sin(phi)
    return out


def cole(params, w):
    r0, rinf, tau, alpha = params
    return rinf + (r0 - rinf) / (1 + (1j * w * tau) ** (1 - np.clip(alpha, 0.05, 0.99)))


def fit_cole(freq_hz: np.ndarray, z: np.ndarray, seed: int = 0) -> dict:
    w = 2 * np.pi * freq_hz
    scale = max(float(np.abs(z).max()), 1.0)

    def residuals(p):
        d = cole(p, w) - z
        return np.concatenate([d.real, d.imag]) / scale

    peak = float(freq_hz[int(np.argmax(-z.imag))])
    start = [float(z.real.max()), 0.8 * float(z.real.min()), 1 / (2 * math.pi * max(peak, 1.0)), 0.75]
    rng = np.random.default_rng(seed)
    best = least_squares(residuals, start, bounds=COLE_BOUNDS, max_nfev=20000, ftol=1e-12, xtol=1e-12)
    for _ in range(N_STARTS - 1):
        guess = [start[0] * rng.uniform(0.5, 1.5), max(start[1] * rng.uniform(0.5, 1.5), 1e-3),
                 start[2] * 10 ** rng.uniform(-2, 2), float(np.clip(start[3] + rng.uniform(-0.4, 0.4), 0.1, 0.95))]
        guess = [float(np.clip(v, lo, hi)) for v, lo, hi in zip(guess, *COLE_BOUNDS)]
        trial = least_squares(residuals, guess, bounds=COLE_BOUNDS, max_nfev=20000, ftol=1e-12, xtol=1e-12)
        if trial.cost < best.cost:
            best = trial
    r0, rinf, tau, alpha = best.x
    r0, rinf = max(r0, rinf), min(r0, rinf)
    rmse_pct = 100 * float(np.sqrt(np.mean(np.abs(cole([r0, rinf, tau, alpha], w) - z) ** 2))) / float(np.abs(z).mean())
    fc = 1 / (2 * np.pi * tau)
    accepted = rmse_pct <= 2 and 2e3 <= fc <= 300e3 and 0.06 < alpha < 0.95
    return {"R0": r0, "Rinf": rinf, "tau_s": tau, "alpha": alpha, "fc_hz": fc, "rmse_pct": rmse_pct,
            "accepted": bool(accepted)}


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
        spectrum.to_csv(args.out, index=False, float_format="%.6g")
    print(json.dumps({k: (round(v, 6) if isinstance(v, float) else v) for k, v in summary.items()}, indent=2))


if __name__ == "__main__":
    main()
