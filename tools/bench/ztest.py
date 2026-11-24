# /// script
# requires-python = ">=3.11"
# dependencies = ["bleak>=0.22", "numpy", "matplotlib"]
# ///
"""Caracterización guiada de PCB + cinta flex con la AD5940 Z Test Board.

Uso:
    uv run ztest.py --strip VV100            # plan completo
    uv run ztest.py --strip VV50 --plan short
    uv run ztest.py --report                 # solo regenera el informe

Lógica de los DIP de la Z Test Board: OFF = elemento conectado (invertido
respecto a la serigrafía). El script indica qué posiciones dejar en OFF;
todas las demás deben quedar en ON.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import json
import struct
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"

UUID = lambda x: f"0000{x:04x}-0000-1000-8000-00805f9b34fb"  # noqa: E731
CMD = UUID(0xC000)
START, STOP, POINTS, SPACING, REPS = (UUID(0xC013), UUID(0xC014), UUID(0xC015),
                                      UUID(0xC016), UUID(0xC017))
NAME_PREFIXES = ("BioMess", "Messi-")

# Valores por posición (1..12) de cada DIP, según el esquemático 02-049393 rev A.
DIP_VALUES = {
    "S1": [100, 200, 300, 340, 510, 1e3, 2e3, 3.01e3, 4.02e3, 4.99e3, "1n", "10n"],      # ZB
    "S2": [100, 200, 300, 402, 10e3, 23.7e3, 42.2e3, 42.2e3, 100e3, 200e3, "1n", "10n"],  # F+
    "S3": [100, 200, 300, 402, 4.22e6, 4.22e6, 1.43e6, 1e6, 300e3, 300e3, "1n", "10n"],   # S+
    "S4": [100, 200, 300, 402, 499, 1e3, 2e3, 3.01e3, 4.02e3, 4.99e3, "1n", "10n"],      # F-
    "S5": [100, 200, 300, 402, 499, 1e3, 2e3, 3.01e3, 4.02e3, 4.99e3, "1n", "10n"],      # S-
}
# Orden físico en la placa, de izquierda a derecha: S2, S3, S5, S4 (y S1 abajo).
PHYSICAL_ORDER = ("S2", "S3", "S5", "S4", "S1")
DIP_ROLE = {"S1": "ZB (tejido)", "S2": "F+", "S3": "S+", "S4": "F-", "S5": "S-"}


@dataclass
class Config:
    name: str
    off: dict[str, tuple[int, ...]]  # DIP -> posiciones en OFF (conectadas)
    note: str = ""
    tol_pct: float = 2.0  # tolerancia de |Z| para aviso

    def nominal(self, f: np.ndarray) -> np.ndarray:
        """Impedancia esperada de ZB: los elementos en OFF quedan en serie
        (cada switch en ON cortocircuita su elemento; comprobado con 100+200)."""
        z = np.zeros_like(f, dtype=complex)
        for pos in self.off["S1"]:
            v = DIP_VALUES["S1"][pos - 1]
            if isinstance(v, str):
                c = {"1n": 1e-9, "10n": 10e-9}[v]
                z += 1 / (1j * 2 * np.pi * f * c)
            else:
                z += v
        return z


C100 = {"S2": (1,), "S3": (1,), "S4": (1,), "S5": (1,)}  # contactos de 100 Ω


def cfg(name, zb, contacts=C100, **kw):
    return Config(name, {"S1": zb, **contacts}, **kw)


C402 = {"S2": (4,), "S3": (4,), "S4": (4,), "S5": (4,)}
FULL = [
    cfg("zb100", (1,), note="referencia"),
    cfg("zb200", (2,)),
    cfg("zb100p200", (1, 2), note="100 + 200 en serie = 300 Ω"),
    cfg("zb0", (), note="ZB en cortocircuito (todo S1 en ON): offset en serie"),
    cfg("zb510", (5,)),
    cfg("zb1k", (6,)),
    cfg("zb4k99", (10,)),
    cfg("zb1k_10n", (6, 12), note="R + C en serie, |Xc| = R a 15.9 kHz; C al ±10 %", tol_pct=15),
    cfg("zb4k99_1n", (10, 11), note="R + C en serie, |Xc| = R a 31.9 kHz; C al ±5 %", tol_pct=10),
    cfg("zb100_c402", (1,), C402, note="contactos 402 Ω"),
    cfg("zb100_f1k", (1,), {"S2": (1, 2, 3, 4), "S3": (4,), "S4": (6,), "S5": (4,)},
        note="contactos corriente equilibrados ≈1k (F+ 1002, F- 1k)", tol_pct=5),
    cfg("zb100_fhi", (1,), {"S2": (5,), "S3": (4,), "S4": (10,), "S5": (4,)},
        note="contactos corriente altos: F+ 10k, F- 4.99k", tol_pct=5),
    cfg("zb100_shi", (1,), {"S2": (5,), "S3": (9,), "S4": (10,), "S5": (10,)},
        note="además S+ 300k, S- 4.99k", tol_pct=5),
    cfg("zb100_s1M", (1,), {"S2": (5,), "S3": (8,), "S4": (10,), "S5": (10,)},
        note="S+ 1M (caso extremo)", tol_pct=10),
    cfg("zb100_flex", (1,), note="repite la referencia doblando/tocando la cinta"),
]
SHORT_NAMES = {"zb0", "zb100", "zb1k", "zb1k_10n", "zb4k99_1n", "zb100_f1k", "zb100_fhi", "zb100_flex"}
DIAG = [
    next(c for c in FULL if c.name == "zb100_f1k"),
    cfg("zb100_fplus10k", (1,), {"S2": (5,), "S3": (4,), "S4": (4,), "S5": (4,)},
        note="solo F+ alto (10k); con el cableado actual es el lado de retorno (I−)", tol_pct=5),
    cfg("zb100_fminus5k", (1,), {"S2": (4,), "S3": (4,), "S4": (10,), "S5": (4,)},
        note="solo F− alto (4.99k); con el cableado actual es el lado de excitación (I+)", tol_pct=5),
]
PLANS = {"all": FULL[:-1] + DIAG[1:] + FULL[-1:], "full": FULL, "diag": DIAG, "short": [c for c in FULL if c.name in SHORT_NAMES]}


def fmt(v) -> str:
    if isinstance(v, str):
        return v + "F"
    for div, suf in ((1e6, "M"), (1e3, "k")):
        if v >= div:
            return f"{v / div:g}{suf}"
    return f"{v:g}"


def beep(kind: str = "done"):
    """Aviso sonoro no bloqueante (macOS); en otros sistemas, campana de terminal."""
    import subprocess
    sound = {"done": "Glass", "warn": "Basso"}[kind]
    try:
        subprocess.Popen(["afplay", f"/System/Library/Sounds/{sound}.aiff"])
    except Exception:
        print("\a", end="", flush=True)


def switch_diff(prev: dict | None, new: dict) -> list[str]:
    """Estado completo de los 5 DIP; marca con ◀ los que hay que cambiar."""
    lines = []
    for dip in PHYSICAL_ORDER:
        b = sorted(new[dip])
        vals = " + ".join(fmt(DIP_VALUES[dip][p - 1]) for p in b) or "0 (corto)"
        pos = " y ".join(str(p) for p in b) or "ninguna"
        line = f"  {dip} {DIP_ROLE[dip]:12} OFF: {pos:6} (resto ON)  = {vals}"
        if prev is not None and sorted(prev[dip]) != b:
            a = sorted(prev[dip])
            steps = [f"pon {p} en ON" for p in a if p not in b] + [f"pon {p} en OFF" for p in b if p not in a]
            line += "   ◀ CAMBIA: " + ", ".join(steps)
        lines.append(line)
    if prev is not None and all(sorted(prev[d]) == sorted(new[d]) for d in new):
        lines.append("  No cambies nada.")
    return lines


@dataclass
class Device:
    client: object
    buf: bytearray = field(default_factory=bytearray)
    event: asyncio.Event = field(default_factory=asyncio.Event)
    expected: int = 0

    def on_notify(self, _h, data: bytearray):
        self.buf.extend(data)
        if self.expected and len(self.buf) >= self.expected:
            self.event.set()

    def ch(self, uuid):
        """Característica del servicio Config (AF01); están duplicadas en AF00."""
        svc = self.client.services.get_service(UUID(0xAF01))
        return svc.get_characteristic(uuid) if svc else uuid

    async def configure(self, start, stop, points, reps):
        c = self.client
        START_, STOP_, POINTS_, SPACING_, REPS_ = map(self.ch, (START, STOP, POINTS, SPACING, REPS))
        await c.write_gatt_char(START_, struct.pack("<f", start), response=True)
        await c.write_gatt_char(STOP_, struct.pack("<f", stop), response=True)
        await c.write_gatt_char(POINTS_, struct.pack("<I", points), response=True)
        await c.write_gatt_char(REPS_, struct.pack("<B", reps), response=True)
        try:
            await c.write_gatt_char(SPACING_, b"\x01", response=True)
        except Exception:
            pass  # firmware antiguo: siempre logarítmico
        p = struct.unpack("<I", await c.read_gatt_char(POINTS_))[0]
        r = (await c.read_gatt_char(REPS_))[0]
        return p, r

    async def sweep(self, points, reps, timeout=180) -> np.ndarray:
        self.buf.clear()
        self.event.clear()
        self.expected = points * reps * 12
        await self.client.write_gatt_char(CMD, b"\x01", response=True)
        await asyncio.wait_for(self.event.wait(), timeout)
        raw = np.frombuffer(bytes(self.buf[: self.expected]), dtype="<f4")
        return raw.reshape(reps, points, 3)  # f, |Z|, fase


async def find_device(name: str | None):
    from bleak import BleakScanner
    print("Buscando dispositivo BLE…")
    devs = await BleakScanner.discover(timeout=6.0)
    ok = [d for d in devs if d.name and (d.name == name if name else d.name.startswith(NAME_PREFIXES))]
    if not ok:
        sys.exit("No encuentro la placa. Pulsa el botón para reactivar el advertising.")
    if len(ok) > 1 and not name:
        sys.exit("Hay varias: " + ", ".join(d.name for d in ok) + ". Usa --device.")
    return ok[0]


def summarize(cfg_: Config, data: np.ndarray) -> tuple[list[str], bool]:
    data = data[:, data[0, :, 0] <= 199e3]  # el AD5940 da basura a 200 kHz
    f = data[0, :, 0].astype(float)
    mag = data[:, :, 1].mean(0)
    ph = data[:, :, 2].mean(0)
    znom = cfg_.nominal(f)
    if not cfg_.off["S1"]:  # corto: error absoluto
        out = [f"  {f[i] / 1e3:6.1f} kHz  |Z|={mag[i]:7.3f} Ω   fase {ph[i]:+7.2f}°"
               for i in [int(np.argmin(np.abs(f - x))) for x in (5e3, 10e3, 50e3, 100e3, 198e3)]]
        out.append(f"  offset medio {mag.mean():.3f} Ω (esperado ≈ 0)")
        return out, False
    err = 100 * (mag - np.abs(znom)) / np.abs(znom)
    dph = (ph - np.degrees(np.angle(znom)) + 180) % 360 - 180
    cv = 100 * data[:, :, 1].std(0) / mag
    out, bad = [], False
    for ft in (5e3, 10e3, 50e3, 100e3, 198e3):
        i = int(np.argmin(np.abs(f - ft)))
        out.append(f"  {f[i] / 1e3:6.1f} kHz  |Z|={mag[i]:9.2f} Ω (nom {abs(znom[i]):9.2f})"
                   f"  err {err[i]:+6.2f} %   fase {ph[i]:+6.2f}° (Δ {dph[i]:+5.2f}°)   CV {cv[i]:.2f} %")
    worst = float(np.max(np.abs(err)))
    bad = worst > cfg_.tol_pct
    out.append(f"  peor error |Z| {worst:.2f} % (tolerancia {cfg_.tol_pct} %), "
               f"peor Δfase {np.max(np.abs(dph)):.2f}°")
    return out, bad


def save(strip: str, cfg_: Config, data: np.ndarray, meta: dict) -> Path:
    d = DATA / strip
    d.mkdir(parents=True, exist_ok=True)
    path = d / f"{cfg_.name}.csv"
    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["rep", "freq_hz", "mag_ohm", "phase_deg", "nom_mag_ohm", "nom_phase_deg"])
        znom = cfg_.nominal(data[0, :, 0].astype(float))
        for r in range(data.shape[0]):
            for i in range(data.shape[1]):
                w.writerow([r, *map(float, data[r, i]), abs(znom[i]), np.degrees(np.angle(znom[i]))])
    meta_path = d / f"{cfg_.name}.json"
    meta_path.write_text(json.dumps({**meta, "config": cfg_.name, "switches_off": cfg_.off,
                                     "note": cfg_.note}, indent=2, ensure_ascii=False))
    return path


async def run(args):
    from bleak import BleakClient
    plan = PLANS[args.plan]
    if args.start_at:
        plan = plan[[c.name for c in plan].index(args.start_at):]
    if args.only:
        plan = [c for c in plan if c.name in args.only.split(",")]
    dev_info = await find_device(args.device)
    print(f"Conectando a {dev_info.name}…")
    async with BleakClient(dev_info) as client:
        dev = Device(client)
        await client.start_notify(CMD, dev.on_notify)
        points, reps = await dev.configure(args.start, args.stop, args.points, args.reps)
        print(f"Barrido {args.start / 1e3:g}–{args.stop / 1e3:g} kHz, {points} puntos, {reps} reps.\n")
        print(f"Cinta: {args.strip}. Recuerda: OFF = conectado; todo lo no indicado, en ON.\n")
        prev = None
        i = 0
        while i < len(plan):
            c = plan[i]
            print(f"━━ [{i + 1}/{len(plan)}] {c.name}  {c.note}")
            print("\n".join(switch_diff(prev, c.off)) or "  (sin cambios de switches)")
            ans = input("Enter = medir · s = saltar · q = salir > ").strip().lower()
            if ans == "q":
                break
            if ans == "s":
                i += 1
                continue
            t0 = time.time()
            data = await dev.sweep(points, reps)
            lines, bad = summarize(c, data)
            beep("warn" if bad else "done")
            print("\n".join(lines) + f"\n  ({time.time() - t0:.1f} s)")
            save(args.strip, c, data, {"device": dev_info.name, "strip": args.strip,
                                       "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
                                       "points": points, "reps": reps})
            prev = c.off
            if bad:
                ans = input("⚠  Fuera de tolerancia. r = repetir (revisa switches) · Enter = seguir > ")
                if ans.strip().lower() == "r":
                    continue
            i += 1
            print()
    beep("done")
    print("Hecho. Genera el informe con: uv run ztest.py --report")


def report():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    strips = sorted(p for p in DATA.iterdir() if p.is_dir()) if DATA.exists() else []
    if not strips:
        sys.exit("No hay datos en data/.")
    names = [c.name for c in FULL]
    rows = []
    fig, axes = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    for s in strips:
        for n in names:
            p = s / f"{n}.csv"
            if not p.exists():
                continue
            a = np.genfromtxt(p, delimiter=",", names=True)
            a = a[a["freq_hz"] <= 199e3]  # el AD5940 da basura a 200 kHz
            f = np.unique(a["freq_hz"])
            mag = np.array([a["mag_ohm"][a["freq_hz"] == x].mean() for x in f])
            ph = np.array([a["phase_deg"][a["freq_hz"] == x].mean() for x in f])
            cfg_ = next(c for c in FULL if c.name == n)
            if not cfg_.off["S1"]:
                rows.append((s.name, n, float(mag.mean()), float(mag.max()), float(np.abs(ph).max())))
                continue
            znom = cfg_.nominal(f)
            nm, nph = np.abs(znom), np.degrees(np.angle(znom))
            err = 100 * (mag - nm) / nm
            rows.append((s.name, n, float(np.median(err)), float(np.max(np.abs(err))),
                         float(np.max(np.abs((ph - nph + 180) % 360 - 180)))))
            if n in ("zb100", "zb1k", "zb1k_10n", "zb100_shi"):
                axes[0].semilogx(f, err, label=f"{s.name} · {n}")
                axes[1].semilogx(f, (ph - nph + 180) % 360 - 180, label=f"{s.name} · {n}")
    axes[0].set_ylabel("Error |Z| (%)")
    axes[1].set_ylabel("Error de fase (°)")
    axes[1].set_xlabel("Frecuencia (Hz)")
    for ax in axes:
        ax.axhline(0, color="0.5", lw=0.8)
        ax.grid(True, which="both", alpha=0.3)
    axes[0].legend(fontsize=7, ncol=2)
    fig.tight_layout()
    fig.savefig(HERE / "report_errors.png", dpi=150)

    with (HERE / "report_summary.csv").open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["strip", "config", "median_err_pct", "max_abs_err_pct", "max_abs_dphase_deg"])
        w.writerows(rows)
    print(f"{'cinta':10} {'config':14} {'med %':>7} {'máx %':>7} {'máx Δ°':>7}")
    for r in rows:
        print(f"{r[0]:10} {r[1]:14} {r[2]:+7.2f} {r[3]:7.2f} {r[4]:7.2f}")
    print(f"\nGuardado: {HERE / 'report_errors.png'} y report_summary.csv")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strip", help="identificador de la cinta, p. ej. VV100")
    ap.add_argument("--plan", choices=PLANS, default="all")
    ap.add_argument("--start-at", help="empieza en esta config")
    ap.add_argument("--only", help="lista de configs separadas por comas")
    ap.add_argument("--device", help="nombre BLE exacto (p. ej. Messi-05)")
    ap.add_argument("--start", type=float, default=4e3)
    ap.add_argument("--stop", type=float, default=198e3)
    ap.add_argument("--points", type=int, default=40)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="muestra el plan sin conectar")
    args = ap.parse_args()
    if args.report:
        return report()
    if args.dry_run:
        prev = None
        for i, c in enumerate(PLANS[args.plan], 1):
            print(f"[{i}] {c.name}  {c.note}")
            print("\n".join(switch_diff(prev, c.off)) or "  (sin cambios)")
            prev = c.off
        return
    if not args.strip:
        ap.error("--strip es obligatorio para medir")
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
