"""Derive the iOS and Android app icons from the Myohm master logo (white wordmark on #092568).

Requires rsvg-convert (librsvg) and Pillow. Run from the repository root:
    python3 design/myohm/make_app_icons.py
"""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "design" / "myohm" / "myohm-editable.svg"
NAVY = (9, 37, 104)
IOS_ICON = ROOT / "mobile/ios/BioMessApp/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
ANDROID_RES = ROOT / "mobile/android/app/src/main/res"
# Launcher icon edge in px per density; the adaptive foreground layer is 108/48 of it.
DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def wordmark(width: int, tmp: Path) -> Image.Image:
    white = tmp / "white.svg"
    white.write_text(MASTER.read_text().replace('stroke="#092568"', 'stroke="#FFFFFF"'))
    out = tmp / f"wordmark_{width}.png"
    subprocess.run(["rsvg-convert", "-w", str(width), "-o", str(out), str(white)], check=True)
    return Image.open(out).convert("RGBA")


def tile(size: int, mark_fraction: float, tmp: Path, background: bool = True, round_mask: bool = False) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), NAVY + (255,) if background else (0, 0, 0, 0))
    mark = wordmark(int(size * mark_fraction), tmp)
    canvas.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    if round_mask:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        canvas.putalpha(mask)
    return canvas


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        tile(1024, 0.78, tmp).convert("RGB").save(IOS_ICON)  # iOS app icons must be opaque
        for density, px in DENSITIES.items():
            folder = ANDROID_RES / f"mipmap-{density}"
            tile(px, 0.80, tmp).save(folder / "ic_launcher.png")
            tile(px, 0.70, tmp, round_mask=True).save(folder / "ic_launcher_round.png")
            # Adaptive foreground: keep the wordmark inside the 66 dp safe zone of the 108 dp layer.
            tile(px * 108 // 48, 0.52, tmp, background=False).save(folder / "ic_launcher_foreground.png")
    colors = ANDROID_RES / "values" / "colors.xml"
    colors.write_text(colors.read_text().replace(
        '<color name="ic_launcher_background">#FFFFFF</color>', '<color name="ic_launcher_background">#092568</color>'))
    print("icons written")


if __name__ == "__main__":
    main()
