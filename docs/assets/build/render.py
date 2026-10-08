#!/usr/bin/env python3
"""Regenerates every README image from the app's own drawing code.

    python3 docs/assets/build/render.py

Steps: compile ExportFrames.swift against app/Sources (export_frames.sh), export looping
cell frames for each scene in scenes/ (pose data, props, effects and scarves come from the
app), then compose the images with Pillow. Pixel art is only drawn at whole-number scale.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ASSETS = ROOT / "docs" / "assets"
DOCS = ROOT / "docs"

INK, CREAM = (20, 17, 15), (246, 241, 231)
ORANGE = (217, 119, 87)
THEMES = {
    "dark": {"bg": INK, "dot": (34, 29, 26), "fg": CREAM, "mute": (150, 140, 128), "pill": (31, 27, 24),
             "edge": (58, 51, 44), "shadow": (10, 9, 8)},
    "light": {"bg": CREAM, "dot": (230, 222, 207), "fg": INK, "mute": (120, 108, 96), "pill": (255, 252, 246),
              "edge": (222, 211, 194), "shadow": (214, 203, 185)},
}
FPS_MS = 83  # 12 fps


def font(size, bold=False):
    for path, idx in (("/System/Library/Fonts/SFNSMono.ttf", 0), ("/System/Library/Fonts/Menlo.ttc", 1 if bold else 0)):
        if os.path.exists(path):
            f = ImageFont.truetype(path, size, index=idx)
            if path.endswith("SFNSMono.ttf"):
                try:
                    f.set_variation_by_name("Semibold" if bold else "Medium")
                except Exception:
                    pass
            return f
    return ImageFont.load_default()


def export():
    return Path(subprocess.check_output([str(HERE / "export_frames.sh")], text=True).strip())


def poses(work, name):
    out = work / f"{name}-poses.json"
    env = dict(os.environ, HOME=str(work / "home"))
    subprocess.check_call([str(work / "export-frames"), "poses", str(HERE / "scenes" / f"{name}.json"), str(out)], env=env)
    return json.loads(out.read_text())["items"]


# ---------- drawing helpers ----------
def backdrop(w, h, t, grid=24):
    im = Image.new("RGB", (w, h), t["bg"])
    d = ImageDraw.Draw(im)
    for y in range(grid // 2, h, grid):
        for x in range(grid // 2, w, grid):
            d.rectangle((x, y, x + 1, y + 1), fill=t["dot"])
    return im


def stamp(im, cells, ox, oy, cell, t):
    """Draws one frame's cells. Cell (0,0) of the sprite lands at (ox, oy). Ground row is y=8."""
    px = im.load()
    W, H = im.size
    # grounded shadow under the feet
    d = ImageDraw.Draw(im)
    d.rectangle((ox + 2 * cell, oy + 8 * cell, ox + 10 * cell - 1, oy + 8 * cell + cell // 2), fill=t["shadow"])
    for x, y, c in cells:
        a = (c & 255) / 255
        if a <= 0:
            continue
        col = ((c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255)
        x0, y0 = ox + x * cell, oy + y * cell
        for yy in range(max(0, y0), min(H, y0 + cell)):
            for xx in range(max(0, x0), min(W, x0 + cell)):
                if a >= 0.999:
                    px[xx, yy] = col
                else:
                    o = px[xx, yy]
                    px[xx, yy] = tuple(int(o[i] * (1 - a) + col[i] * a) for i in range(3))


def pill(d, cx, y, parts, t, accent=None, alert=False, size=15):
    """parts: [(text, bold)] drawn left to right inside a rounded pill centred on cx."""
    f_b, f_r = font(size, True), font(size)
    widths = [d.textlength(s, font=f_b if b else f_r) for s, b in parts]
    dot = 10 if accent else 0
    w = int(sum(widths) + 28 + (dot + 8 if accent else 0))
    h = size + 16
    x0 = int(cx - w / 2)
    d.rounded_rectangle((x0, y, x0 + w, y + h), radius=h // 2, fill=t["pill"], outline=ORANGE if alert else t["edge"], width=2 if alert else 1)
    x = x0 + 14
    if accent:
        d.rounded_rectangle((x, y + h / 2 - dot / 2, x + dot, y + h / 2 + dot / 2), radius=2, fill=accent)
        x += dot + 8
    for (s, b), wd in zip(parts, widths):
        col = ORANGE if (alert and not b) else (t["fg"] if b else t["mute"])
        d.text((x, y + h / 2), s, font=f_b if b else f_r, fill=col, anchor="lm")
        x += wd


def hexrgb(h):
    v = int(h.lstrip("#"), 16)
    return (v >> 16 & 255, v >> 8 & 255, v & 255)


def save_gif(frames, path, colors=96):
    # One shared palette from a sample of frames; no dithering keeps cells crisp.
    sample = Image.new("RGB", (frames[0].width, frames[0].height * 4))
    for i, k in enumerate(range(0, len(frames), max(1, len(frames) // 4))):
        if i < 4:
            sample.paste(frames[k], (0, frames[0].height * i))
    pal = sample.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    q[0].save(path, save_all=True, append_images=q[1:], duration=FPS_MS, loop=0, optimize=True, disposal=1)


def save_png(im, path, colors=96):
    im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(path, optimize=True)


# ---------- scenes ----------
BANNER = [("web", "needs you", True), ("api", "building", False), ("docs", "deploying", False)]


def banner(items):
    W, H, cell = 1280, 440, 18
    floor = 318
    out = {}
    for theme, t in THEMES.items():
        frames = []
        for f in range(len(items[0]["frames"])):
            im = backdrop(W, H, t)
            for i, item in enumerate(items):
                cx = int(W * (i + 1) / 4)
                stamp(im, item["frames"][f], cx - 6 * cell, floor - 8 * cell, cell, t)
            d = ImageDraw.Draw(im)
            for i, (name, state, alert) in enumerate(BANNER):
                cx = int(W * (i + 1) / 4)
                pill(d, cx, floor + 30, [(name, True), (" · " + state, False)], t, accent=hexrgb(SCENE_ACCENTS["banner"][i]), alert=alert, size=17)
            frames.append(im)
        save_gif(frames, ASSETS / f"hero-{theme}.gif")
        out[theme] = frames
    return out


GALLERY_LABELS = ["read", "edit", "search", "web", "test", "build", "git", "install", "tests pass", "deploy", "tea break", "sleep"]


def gallery(items):
    cols, tw, th, cell, gap = 4, 232, 196, 10, 12
    rows = (len(items) + cols - 1) // cols
    W, H = cols * tw + (cols + 1) * gap, rows * th + (rows + 1) * gap
    for theme, t in THEMES.items():
        frames = []
        for f in range(len(items[0]["frames"])):
            im = Image.new("RGB", (W, H), t["bg"])
            d = ImageDraw.Draw(im)
            for n, item in enumerate(items):
                x0, y0 = gap + (n % cols) * (tw + gap), gap + (n // cols) * (th + gap)
                d.rounded_rectangle((x0, y0, x0 + tw, y0 + th), radius=14, fill=t["pill"], outline=t["edge"])
                tile = Image.new("RGB", (tw - 2, th - 40), t["pill"])
                stamp(tile, item["frames"][f], (tw - 2) // 2 - 6 * cell, (th - 40) - 9 * cell, cell, {**t, "shadow": t["edge"]})
                im.paste(tile, (x0 + 1, y0 + 1))
                d.text((x0 + 16, y0 + th - 20), GALLERY_LABELS[n], font=font(14, True), fill=t["mute"], anchor="lm")
            frames.append(im)
        save_gif(frames, ASSETS / f"gallery-{theme}.gif")


TEAM = [("web", "needs you", True), ("api", "editing", False), ("docs", "reading", False),
        ("infra", "building", False), ("mobile", "searching", False), ("ml", "installing", False)]


def team(items):
    W, H, cell, slot = 1280, 280, 9, 186
    floor = 196
    for theme, t in THEMES.items():
        frames = []
        for f in range(len(items[0]["frames"])):
            im = backdrop(W, H, t)
            x_start = (W - slot * 6 - 90) // 2 + slot // 2
            for i, item in enumerate(items):
                cx = x_start + i * slot
                stamp(im, item["frames"][f], cx - 6 * cell, floor - 8 * cell, cell, t)
            d = ImageDraw.Draw(im)
            for i, (name, state, alert) in enumerate(TEAM):
                cx = x_start + i * slot
                pill(d, cx, floor + 22, [(name, True)], t, accent=hexrgb(SCENE_ACCENTS["team"][i]), alert=alert, size=14)
            bx = x_start + 6 * slot - slot // 2 + 46
            pill(d, bx, floor - 4 * cell - 16, [("+2", True)], t, size=15)
            frames.append(im)
        save_gif(frames, ASSETS / f"team-{theme}.gif")


def social(banner_frames):
    W, H = 1280, 640
    im = Image.new("RGB", (W, H), INK)
    art = banner_frames["dark"][14]
    im.paste(art, (0, H - art.height))
    d = ImageDraw.Draw(im)
    d.text((72, 70), "Clawd Pet", font=font(64, True), fill=CREAM)
    d.text((72, 150), "One Clawd for every Claude Code session.", font=font(26), fill=(170, 160, 148))
    d.text((W - 72, 84), "unofficial fan project", font=font(16), fill=(120, 110, 100), anchor="ra")
    d.rectangle((0, H - 8, W, H), fill=ORANGE)
    save_png(im, ASSETS / "social-preview.png", colors=128)


def card(work):
    """The real hover card (ActivityView), rendered offscreen for a demo session. Glass becomes a solid panel."""
    out = work / "card.png"
    env = dict(os.environ, HOME=str(work / "home"))
    subprocess.check_call([str(work / "export-frames"), "card", str(HERE / "scenes" / "card.json"), str(out)], env=env)
    art = Image.open(out).convert("RGBA")
    im = backdrop(art.width + 80, art.height + 80, THEMES["dark"])
    im.paste(art, (40, 40), art)
    save_png(im, ASSETS / "hover-card.png", colors=128)


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
            parts.append(f'<rect x="{x}" y="8" width="{bw}" height="{bh}" rx="10" fill="{hexc(t["pill"])}" stroke="{stroke}" stroke-width="1.5"/>')
            parts.append(f'<rect x="{x + 14}" y="22" width="6" height="6" fill="#d97757" shape-rendering="crispEdges"/>')
            parts.append(f'<text x="{x + 14}" y="48" font-family="ui-monospace, SFMono-Regular, Menlo, monospace" font-size="14" font-weight="700" fill="{hexc(t["fg"])}">{title}</text>')
            parts.append(f'<text x="{x + 14}" y="68" font-family="ui-monospace, SFMono-Regular, Menlo, monospace" font-size="11" fill="{hexc(t["mute"])}">{sub}</text>')
            if not last:
                ax = x + bw
                parts.append(f'<path d="M{ax + 8} {8 + bh / 2} h{gap - 20}" stroke="{hexc(t["mute"])}" stroke-width="1.5"/>')
                parts.append(f'<path d="M{ax + gap - 14} {8 + bh / 2 - 5} l6 5 l-6 5 z" fill="{hexc(t["mute"])}"/>')
            x += bw + gap
        width = x - gap + 8
        svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{bh + 16}" viewBox="0 0 {width} {bh + 16}" role="img" '
               f'aria-label="Claude Code hooks write one JSON file per session; Clawd Pet watches the folder and shows one Clawd per session">'
               + "".join(parts) + "</svg>\n")
        (ASSETS / f"how-it-works-{theme}.svg").write_text(svg)


def animations_md(work):
    table = (work / "catalog.md").read_text().strip()
    n = sum(1 for line in table.splitlines()[2:] if line.startswith("| "))
    (DOCS / "ANIMATIONS.md").write_text(
        "# Animations\n\n"
        f"{n} clips, generated from the app's catalog (`ClawdPet --dump-catalog`). Do not edit by hand: "
        "run `python3 docs/assets/build/render.py`.\n\n"
        "Status `needs-verify` means the trigger is implemented but no recorded hook payload in `fixtures/` exercises it yet.\n\n"
        + table + "\n")


SCENE_ACCENTS = {}


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    work = export()
    for name in ("banner", "team"):
        SCENE_ACCENTS[name] = [i.get("accent", "#FFFFFF") for i in json.loads((HERE / "scenes" / f"{name}.json").read_text())["items"]]
    frames = banner(poses(work, "banner"))
    gallery(poses(work, "gallery"))
    team(poses(work, "team"))
    social(frames)
    card(work)
    diagram()
    animations_md(work)
    total = 0
    for p in sorted(ASSETS.glob("*.*")):
        total += p.stat().st_size
        print(f"{p.stat().st_size / 1024:8.1f} KB  {p.relative_to(ROOT)}")
    print(f"{total / 1024 / 1024:8.2f} MB  total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
