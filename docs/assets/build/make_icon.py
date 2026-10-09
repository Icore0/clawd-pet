#!/usr/bin/env python3
"""App icons.

AppIcon.icns: the mascot on a dark rounded square. macOS 26+ puts any icon that isn't that shape on a
light-gray tile, so the bundle icon brings its own (Apple's grid: an 824 pt square, ~185 pt corners, in 1024).
Mascot.png: the mascot alone on transparent, set as the Dock icon while Wigglet runs (not tiled by macOS).

    python3 docs/assets/build/make_icon.py

Writes app/Resources/AppIcon.icns (via iconutil) and docs/assets/icon.png.
Geometry matches drawWigglet in app/Sources/Sprite.swift: body 8x6 cells, 2x2 arms, 1x1 eyes, four legs.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
BODY, INK = (217, 119, 87, 255), (0, 0, 0, 255)

# (x, y, w, h) in sprite cells, sprite is 12 x 8
CELLS = [(2, 0, 8, 6, BODY), (0, 2, 2, 2, BODY), (10, 2, 2, 2, BODY),
         (2, 6, 1, 2, BODY), (4, 6, 1, 2, BODY), (7, 6, 1, 2, BODY), (9, 6, 1, 2, BODY),
         (3, 1, 1, 1, INK), (8, 1, 1, 1, INK)]


def render(size, tile=False, fill=0.84):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if tile:
        from PIL import ImageDraw
        s = size / 1024
        ImageDraw.Draw(im).rounded_rectangle((100 * s, 100 * s, 924 * s, 924 * s), radius=185 * s, fill=(20, 20, 19, 255))
        fill = 0.56
    cell = max(1, int(size * fill) // 12)       # whole pixels per cell, so edges stay hard
    w, h = 12 * cell, 8 * cell
    ox, oy = (size - w) // 2, (size - h) // 2
    px = im.load()
    for x, y, cw, ch, col in CELLS:
        for yy in range(oy + y * cell, oy + (y + ch) * cell):
            for xx in range(ox + x * cell, ox + (x + cw) * cell):
                px[xx, yy] = col
    return im


def main():
    iconset = Path(tempfile.mkdtemp()) / "AppIcon.iconset"
    iconset.mkdir()
    for base in (16, 32, 128, 256, 512):
        render(base, tile=True).save(iconset / f"icon_{base}x{base}.png")
        render(base * 2, tile=True).save(iconset / f"icon_{base}x{base}@2x.png")
    out = ROOT / "app" / "Resources"
    out.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(["iconutil", "-c", "icns", str(iconset), "-o", str(out / "AppIcon.icns")])
    render(512).save(ROOT / "docs" / "assets" / "icon.png", optimize=True)
    render(512).save(out / "Mascot.png", optimize=True)
    shutil.rmtree(iconset.parent)
    print(out / "AppIcon.icns")


if __name__ == "__main__":
    main()
