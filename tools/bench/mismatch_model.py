# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy", "matplotlib"]
# ///
"""Modelo circuital (análisis nodal AC, equivalente a SPICE) de la medida
tetrapolar AD5941 + cinta + Z Test Board, incluyendo mismatch de contactos.

Topología (PCB AllInOne-corrected + firmware BodyImpedance.c):
  CE0 (fuente de tensión, lazo cerrado en el pin) ─ RL1 1k ─ C5 4.7µ ─ I+ pad
  I+ pad ─ Zf+ ─ ZB+ ─ ZB ─ ZB− ─ Zf− ─ I− pad ─ C4 4.7µ ─ AIN1 (masa virtual
  del HSTIA; la corriente medida es la que entra aquí)
  ZB+ ─ Zs+ ─ V+ pad ─ C3 4.7µ ─ AIN2 ;  ZB− ─ Zs− ─ V− pad ─ C2 4.7µ ─ AIN3
  Z medida = (V(AIN2) − V(AIN3)) / I(AIN1)

Parásitos (desconocidos, se ajustan):
  c_sense : capacidad a masa de cada línea de tensión (pin AIN + ESD + pista + flex + cable)
  c_node  : capacidad a masa de los nodos ZB± (placa Z Test + cables)
  c_cpl   : acoplamiento entre pista I y pista V del mismo lado (flex)
Se ajustan con los montajes de mismatch y se validan con los de contactos bajos.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy.optimize import least_squares

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ztest  # noqa: E402

HERE = Path(__file__).resolve().parent
RL1, CBLK = 1e3, 4.7e-6

NODES = ["ce_int", "ip", "zbp", "zbm", "im", "vp", "vm", "ain2", "ain3"]
IDX = {n: i for i, n in enumerate(NODES)}


def column_z(dip: str, positions, w):
    """Impedancia en serie de los elementos en OFF de una columna."""
    z = 0j
    for p in positions:
        v = ztest.DIP_VALUES[dip][p - 1]
        z += 1 / (1j * w * {"1n": 1e-9, "10n": 10e-9}[v]) if isinstance(v, str) else v
    return z


def simulate(off: dict, f: np.ndarray, c_sense, c_node, c_cpl, c_x=0.0, tau_cm=0.0, r_short=0.0,
             r_cm=np.inf, r_diff=np.inf):
    out = np.empty(len(f), complex)
    for k, fk in enumerate(f):
        w = 2 * np.pi * fk
        n = len(NODES)
        Y = np.zeros((n, n), complex)
        I = np.zeros(n, complex)

        def adm(a, b, y):
            ia = IDX.get(a)
            ib = IDX.get(b)
            if ia is not None:
                Y[ia, ia] += y
            if ib is not None:
                Y[ib, ib] += y
            if ia is not None and ib is not None:
                Y[ia, ib] -= y
                Y[ib, ia] -= y

        def z(a, b, zz):
            adm(a, b, 1 / (zz if abs(zz) > 1e-6 else 1e-6))

        # Fuente CE0: 1 V detrás de RL1 → equivalente Norton en ce_int.
        zr = RL1
        Y[IDX["ce_int"], IDX["ce_int"]] += 1 / zr
        I[IDX["ce_int"]] += 1.0 / zr
        zc = 1 / (1j * w * CBLK)
        z("ce_int", "ip", zc)
        # Cableado de la foto: I+ → F− (S4), V+ → S− (S5), V− → S+ (S3), I− → F+ (S2).
        z("ip", "zbp", column_z("S4", off["S4"], w))
        z("zbp", "zbm", column_z("S1", off["S1"], w) + r_short)
        z("zbm", "im", column_z("S2", off["S2"], w))
        z("im", "gnd", zc)  # C4 a AIN1 = masa virtual
        z("zbp", "vp", column_z("S5", off["S5"], w))
        z("zbm", "vm", column_z("S3", off["S3"], w))
        z("vp", "ain2", zc)
        z("vm", "ain3", zc)
        for nd in ("ain2", "ain3"):
            adm(nd, "gnd", 1j * w * c_sense + 1 / r_cm)
        adm("ain2", "ain3", 1 / r_diff)
        for nd in ("zbp", "zbm"):
            adm(nd, "gnd", 1j * w * c_node)
        adm("ip", "vp", 1j * w * c_cpl)
        adm("im", "vm", 1j * w * c_cpl)
        adm("ip", "vm", 1j * w * c_x)
        v = np.linalg.solve(Y, I)
        i_meas = v[IDX["im"]] / zc
        # CMRR finita del canal de tensión, polo único: Vd += jωτ·Vcm
        vcm = 0.5 * (v[IDX["ain2"]] + v[IDX["ain3"]])
        out[k] = (v[IDX["ain2"]] - v[IDX["ain3"]] + 1j * w * tau_cm * vcm) / i_meas
    return out


def real_off(strip, name, default):
    """Switches realmente montados (el JSON puede corregir errores de montaje)."""
    j = HERE / "data" / strip / f"{name}.json"
    if j.exists():
        return {k: tuple(v) for k, v in json.loads(j.read_text())["switches_off"].items()}
    return default


def load(strip, name):
    p = HERE / "data" / strip / f"{name}.csv"
    a = np.genfromtxt(p, delimiter=",", names=True)
    a = a[a["freq_hz"] <= 199e3]
    f = np.unique(a["freq_hz"])
    mag = np.array([a["mag_ohm"][a["freq_hz"] == x].mean() for x in f])
    ph = np.array([a["phase_deg"][a["freq_hz"] == x].mean() for x in f])
    return f, mag * np.exp(1j * np.radians(ph))


FIT = ["zb100_fhi", "zb100_shi", "zb100_s1M"]
VALIDATE = ["zb100", "zb100_c402", "zb1k", "zb4k99"]


def main(strip="VV150"):
    cfgs = {c.name: c for c in ztest.FULL}
    for n, c in cfgs.items():
        c.off = real_off(strip, n, c.off)
    data = {n: load(strip, n) for n in FIT + VALIDATE if (HERE / "data" / strip / f"{n}.csv").exists()}

    def resid(logp):
        cs, cn, cc, cx = 10 ** logp[:4]
        tau = logp[4] * 1e-9
        r = []
        for n in FIT:
            f, zm = data[n]
            zs = simulate(cfgs[n].off, f, cs, cn, cc, cx, tau)
            r.append(np.log(zm / zs))  # error relativo complejo: magnitud y fase
        r = np.concatenate(r)
        return np.concatenate([r.real, r.imag])

    best = None
    for x0 in ([-11, -11, -12, -12, 0], [-10, -12, -13, -11, 50], [-12, -10, -11, -13, -50], [-11, -12, -11, -10, 10]):
        sol = least_squares(resid, x0, bounds=([-15] * 4 + [-1000], [-8] * 4 + [1000]))
        if best is None or sol.cost < best.cost:
            best = sol
    cs, cn, cc, cx = 10 ** best.x[:4]
    tau = best.x[4] * 1e-9
    print(f"Ajuste ({strip}): c_sense={cs * 1e12:.1f} pF, c_node={cn * 1e12:.1f} pF, "
          f"c_cpl={cc * 1e12:.2f} pF, c_x={cx * 1e12:.2f} pF, tau_cm={tau * 1e9:.1f} ns, coste={best.cost:.3g}")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    summary = {}
    print(f"\n{'config':12} {'uso':9} {'|Zmed|/|Zmod|−1 (mediana, máx) %':>34} {'Δfase máx °':>12}")
    for n, (f, zm) in data.items():
        zs = simulate(cfgs[n].off, f, cs, cn, cc, cx, tau)
        e = 100 * (np.abs(zm) / np.abs(zs) - 1)
        dph = (np.degrees(np.angle(zm / zs)) + 180) % 360 - 180
        use = "ajuste" if n in FIT else "validación"
        print(f"{n:12} {use:9} {np.median(e):+10.2f} {np.max(np.abs(e)):10.2f} {np.max(np.abs(dph)):18.2f}")
        summary[n] = {"use": use, "median_err_pct": float(np.median(e)),
                      "max_abs_err_pct": float(np.max(np.abs(e))), "max_abs_dphase": float(np.max(np.abs(dph)))}
        l, = axes[0].loglog(f, np.abs(zm), "o", ms=3, label=f"{n} medido")
        axes[0].loglog(f, np.abs(zs), "-", color=l.get_color(), label=f"{n} modelo")
        axes[1].semilogx(f, np.degrees(np.angle(zm)), "o", ms=3, color=l.get_color())
        axes[1].semilogx(f, np.degrees(np.angle(zs)), "-", color=l.get_color())
    axes[0].set_ylabel("|Z| (Ω)")
    axes[1].set_ylabel("Fase (°)")
    axes[1].set_xlabel("Frecuencia (Hz)")
    axes[0].legend(fontsize=6, ncol=2)
    for ax in axes:
        ax.grid(True, which="both", alpha=0.3)
    fig.tight_layout()
    fig.savefig(HERE / f"model_{strip}.png", dpi=150)
    (HERE / f"model_{strip}.json").write_text(json.dumps(
        {"tau_cm_ns": tau * 1e9, "c_x_pF": cx * 1e12, "c_sense_pF": cs * 1e12, "c_node_pF": cn * 1e12, "c_cpl_pF": cc * 1e12, "configs": summary},
        indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main(*sys.argv[1:])
