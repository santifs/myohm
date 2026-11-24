# SPDX-License-Identifier: Apache-2.0
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""Separate gain, fixture residual and shunt capacitance in the bench data.

Model for a load Z_n mounted on the impedance test board:

    Z_m = (1 + g) * (Z_n || 1/(j w C_p) + R_r + j w L_r)

g is a frequency-independent relative gain error of the instrument, R_r and
L_r the residual series impedance of the fixture (measured directly with the
load bank shorted) and C_p a shunt capacitance across the load. The fit uses
the 0.1 % loads and the shorted bank of the 150 mm strip with 100 ohm contacts;
the 1 % 510 ohm resistor and the series RC loads are predicted, not fitted.

Usage: uv run bench_error_model.py  (writes bench_error_model.json next to this script)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy.optimize import least_squares

HERE = Path(__file__).resolve().parent
BENCH = HERE
sys.path.insert(0, str(BENCH))
import mismatch_model as M  # noqa: E402
import ztest  # noqa: E402

CFG = {c.name: c for c in ztest.FULL + ztest.DIAG}
STRIP = "VV150"
FIT = ["zb0", "zb100", "zb200", "zb100p200", "zb1k", "zb4k99"]
PREDICT = ["zb510", "zb1k_10n", "zb4k99_1n"]


def model(p, f, zn):
    g, rr, lr_uh, cp_pf = p
    w = 2 * np.pi * f
    if cp_pf > 0 and np.any(zn != 0):
        zl = zn / (1 + 1j * w * cp_pf * 1e-12 * zn)
    else:
        zl = zn
    return (1 + g) * (zl + rr + 1j * w * lr_uh * 1e-6)


def residuals(p, data):
    out = []
    for f, zm, zn in data:
        zh = model(p, f, zn)
        scale = np.maximum(np.abs(zn), 1.0)  # absolute ohms for the short
        out.append(((zm - zh) / scale).real)
        out.append(((zm - zh) / scale).imag)
    return np.concatenate(out)


def load(name):
    f, zm = M.load(STRIP, name)
    return f, zm, CFG[name].nominal(f)


def main():
    data = [load(n) for n in FIT]
    fit = least_squares(residuals, x0=[0.004, 0.3, 0.4, 10], args=(data,),
                        bounds=([-0.05, 0, 0, 0], [0.05, 5, 5, 100]))
    g, rr, lr, cp = fit.x
    jac = fit.jac
    dof = max(1, jac.shape[0] - jac.shape[1])
    s2 = float(np.sum(fit.fun ** 2) / dof)
    cov = np.linalg.pinv(jac.T @ jac) * s2
    se = np.sqrt(np.diag(cov))

    report = {
        "strip": STRIP,
        "fit_loads": FIT,
        "params": {"gain_error_pct": 100 * g, "R_residual_ohm": rr,
                   "L_residual_uH": lr, "C_shunt_pF": cp},
        "params_se": {"gain_error_pct": 100 * se[0], "R_residual_ohm": se[1],
                      "L_residual_uH": se[2], "C_shunt_pF": se[3]},
        "per_load": {},
    }
    for name in FIT + PREDICT:
        f, zm, zn = load(name)
        if name == "zb0":
            continue
        raw = 100 * (np.abs(zm) / np.abs(zn) - 1)
        # deviation that remains after removing the fitted fixture terms
        zfix = model([0, rr, lr, cp], f, zn)
        corr = 100 * (np.abs(zm) / np.abs(zfix) - 1)
        dph = np.degrees(np.angle(zm / model([g, rr, lr, cp], f, zn)))
        report["per_load"][name] = {
            "raw_median_pct": float(np.median(raw)),
            "fixture_corrected_median_pct": float(np.median(corr)),
            "fixture_corrected_range_pct": [float(corr.min()), float(corr.max())],
            "phase_residual_max_abs_deg": float(np.max(np.abs(dph))),
        }
    # 510 ohm: value implied by the fitted gain and residual
    f, zm, zn = load("zb510")
    implied = np.median(np.abs(zm) / (1 + g) - rr)
    report["zb510_implied_ohm"] = float(implied)
    report["zb510_implied_dev_pct"] = float(100 * (implied / 510 - 1))
    out = HERE / "bench_error_model.json"
    out.write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
