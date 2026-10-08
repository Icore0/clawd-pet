#!/usr/bin/env python3
"""Regenerates every README image from the app's own drawing code.

    python3 docs/assets/build/render.py

Steps: compile ExportFrames.swift against app/Sources (export_frames.sh), dump the
catalog cells and render the real team panel offscreen, then compose the images
with Pillow. Pixel art is only ever scaled by whole numbers with NEAREST.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ASSETS = ROOT / "docs" / "assets"
DOCS = ROOT / "docs"

INK, CREAM = (20, 17, 15), (246, 241, 231)
ORANGE, SHADE = (217, 119, 87), (190, 104, 75)
THEMES = {
    "dark": {"bg": INK, "fg": CREAM, "mute": (150, 140, 128), "line": (52, 46, 40)},
    "light": {"bg": CREAM, "fg": INK, "mute": (110, 100, 90), "line": (222, 213, 198)},
}
# Single-sprite clips only: team moves and bubbles need the full panel (see team.png / hero gif).
GALLERY = ["read", "edit", "bash", "search", "web", "plan", "test", "build",
           "git", "install", "agent", "deploy", "tea", "bandage", "oops", "sleep"]


def font(size, bold=False):
    for path in ("/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/SFNSMono.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size, index=1 if bold and path.endswith(".ttc") else 0)
    return ImageFont.load_default()


def export():
    work = Path(subprocess.check_output([str(HERE / "export_frames.sh")], text=True).strip())
    return work


def scene(work, name):
    out = work / name
    shutil.rmtree(out, ignore_errors=True)
    env = dict(os.environ, HOME=str(work / "home"))
    subprocess.check_call([str(work / "export-frames"), "scene", str(HERE / "scenes" / f"{name}.json"), str(out)], env=env)
    return [Image.open(p).convert("RGBA") for p in sorted(out.glob("*.png"))]


def crop_all(frames, pad):
    box = None
    for f in frames:
        b = f.getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    x0, y0, x1, y1 = box
    return [f.crop((x0 - pad, y0 - pad, x1 + pad, y1 + pad)) for f in frames]


def on(bg, im):
    base = Image.new("RGBA", im.size, bg + (255,))
    base.alpha_composite(im)
    return base.convert("RGB")


def save_png(im, path, colors=96):
    im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


def hero(work):
    frames = crop_all(scene(work, "hero"), 12)
    for theme, t in THEMES.items():
        rgb = [on(t["bg"], f) for f in frames]
        pal = rgb[len(rgb) // 2].quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in rgb]
        q[0].save(ASSETS / f"hero-{theme}.gif", save_all=True, append_images=q[1:], duration=83, loop=0, optimize=True, disposal=1)


def tile(anim):
    # most props visible: the frame with the most non-body cells
    best = max(anim["frames"], key=lambda f: sum(1 for _, _, c in f if (c >> 8) != 0xD97757))
    cell, (x0, y0, w, h) = 8, (-2, -6, 20, 16)
    im = Image.new("RGBA", (w * cell, h * cell), (0, 0, 0, 0))
    px = im.load()
    for x, y, c in best:
        rgba = ((c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255, c & 255)
        for dy in range(cell):
            for dx in range(cell):
                X, Y = (x - x0) * cell + dx, (y - y0) * cell + dy
                if 0 <= X < im.width and 0 <= Y < im.height:
                    px[X, Y] = rgba
    return im


def gallery(cells):
    by_id = {a["id"]: a for a in cells["animations"]}
    tiles = [(i, tile(by_id[i])) for i in GALLERY if i in by_id]
    cols, tw, th, label, gap = 4, 160, 128, 34, 1
    W = cols * tw + (cols + 1) * gap
    rows = (len(tiles) + cols - 1) // cols
    H = rows * (th + label) + (rows + 1) * gap
    f = font(15)
    for theme, t in THEMES.items():
        im = Image.new("RGB", (W, H), t["line"])
        d = ImageDraw.Draw(im)
        for n, (name, sprite) in enumerate(tiles):
            cx, cy = gap + (n % cols) * (tw + gap), gap + (n // cols) * (th + label + gap)
            tbg = t["bg"] if theme == "dark" else (232, 224, 209)  # white props need contrast on cream
            d.rectangle((cx, cy, cx + tw - 1, cy + th + label - 1), fill=tbg)
            im.paste(on(tbg, sprite), (cx, cy))
            d.text((cx + 12, cy + th + 8), name, font=f, fill=t["mute"])
        save_png(im, ASSETS / f"gallery-{theme}.png")


def team(work):
    frames = crop_all(scene(work, "team"), 16)
    for theme, t in THEMES.items():
        save_png(on(t["bg"], frames[4]), ASSETS / f"team-{theme}.png", colors=128)


def social(work):
    frame = crop_all(scene(work, "hero2x"), 0)[3]
    W, H = 1280, 640
    im = Image.new("RGB", (W, H), INK)
    scale = min(1.0, 1100 / frame.width)
    art = frame.resize((int(frame.width * scale), int(frame.height * scale)), Image.LANCZOS) if scale < 1 else frame
    im.paste(on(INK, art), ((W - art.width) // 2, H - art.height - 56))
    d = ImageDraw.Draw(im)
    d.text((72, 64), "Clawd Pet", font=font(64, True), fill=CREAM)
    d.text((72, 148), "One Clawd for every Claude Code session.", font=font(28), fill=(170, 160, 148))
    d.text((W - 72, 76), "unofficial fan project", font=font(18), fill=(120, 110, 100), anchor="ra")
    d.rectangle((0, H - 8, W, H), fill=ORANGE)
    save_png(im, ASSETS / "social-preview.png", colors=128)


def diagram():
    steps = [("Claude Code", "hooks fire on tool use"), ("one JSON per session", "~/.claude/clawd/sessions/"),
             ("Clawd Pet", "watches the folder"), ("one Clawd per session", "on your desktop")]
    for theme, t in THEMES.items():
        hexc = lambda c: "#%02x%02x%02x" % c
        bw, bh, gap, x = 200, 76, 44, 8
        parts = []
        for i, (title, sub) in enumerate(steps):
            last = i == len(steps) - 1
            stroke = "#d97757" if last else hexc(t["mute"])
            parts.append(f'<rect x="{x}" y="8" width="{bw}" height="{bh}" fill="{hexc(t["bg"])}" stroke="{stroke}" stroke-width="2" shape-rendering="crispEdges"/>')
            parts.append(f'<rect x="{x + 6}" y="14" width="6" height="6" fill="#d97757" shape-rendering="crispEdges"/>')
            parts.append(f'<text x="{x + 16}" y="42" font-family="Menlo, ui-monospace, monospace" font-size="14" font-weight="700" fill="{hexc(t["fg"])}">{title}</text>')
            parts.append(f'<text x="{x + 16}" y="64" font-family="Menlo, ui-monospace, monospace" font-size="11" fill="{hexc(t["mute"])}">{sub}</text>')
            if not last:
                ax = x + bw
                parts.append(f'<path d="M{ax + 8} {8 + bh / 2} h{gap - 20}" stroke="{hexc(t["mute"])}" stroke-width="2" shape-rendering="crispEdges"/>')
                parts.append(f'<path d="M{ax + gap - 14} {8 + bh / 2 - 5} l6 5 l-6 5 z" fill="{hexc(t["mute"])}"/>')
            x += bw + gap
        width = x - gap + 8
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{bh + 16}" viewBox="0 0 {width} {bh + 16}" role="img" '
               f'aria-label="Claude Code hooks write one JSON file per session; Clawd Pet watches the folder and shows one Clawd per session">'
               + "".join(parts) + "</svg>\n")
        (ASSETS / f"how-it-works-{theme}.svg").write_text(svg)


def animations_md(work, cells):
    table = (work / "catalog.md").read_text().strip()
    n = len(cells["animations"])
    (DOCS / "ANIMATIONS.md").write_text(
        "# Animations\n\n"
        f"{n} clips, generated from the app's catalog (`ClawdPet --dump-catalog`). Do not edit by hand: "
        "run `python3 docs/assets/build/render.py`.\n\n"
        "Status `needs-verify` means the trigger is implemented but no recorded hook payload in `fixtures/` exercises it yet.\n\n"
        + table + "\n")


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    work = export()
    cells = json.loads((work / "frames.json").read_text())
    hero(work)
    gallery(cells)
    team(work)
    social(work)
    diagram()
    animations_md(work, cells)
    total = 0
    for p in sorted(ASSETS.glob("*.*")):
        total += p.stat().st_size
        print(f"{p.stat().st_size / 1024:8.1f} KB  {p.relative_to(ROOT)}")
    print(f"{total / 1024 / 1024:8.2f} MB  total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
