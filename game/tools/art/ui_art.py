"""
Logo, project icon (SVG) and the Android launcher icons.

The lettering is drawn from stroke paths on a small grid (chamfered corners, a spire for the "I"),
so the logotype is original artwork rather than an installed font.
"""
import math
import os

import numpy as np
from PIL import Image

from .tile import Tile, circle, darken, ellipse, hex_color, lighten, line, mix, poly, rect, rrect, sparkle, union

# ---------------------------------------------------------------------------------- lettering
# Glyphs on a 4 x 6 grid (x right, y down). A glyph is a list of polylines.
GLYPHS = {
    "S": [[(4.0, 1.0), (3.4, 0.3), (0.9, 0.3), (0.0, 1.2), (0.0, 2.0), (0.9, 2.9), (3.1, 3.1), (4.0, 4.0), (4.0, 4.8), (3.1, 5.7), (0.6, 5.7), (0.0, 5.0)]],
    "P": [[(0.0, 5.7), (0.0, 0.3), (3.0, 0.3), (4.0, 1.2), (4.0, 2.2), (3.0, 3.1), (0.0, 3.1)]],
    "R": [[(0.0, 5.7), (0.0, 0.3), (3.0, 0.3), (4.0, 1.2), (4.0, 2.2), (3.0, 3.1), (0.0, 3.1)], [(1.8, 3.1), (4.0, 5.7)]],
    "E": [[(4.0, 0.3), (0.0, 0.3), (0.0, 5.7), (4.0, 5.7)], [(0.0, 3.0), (3.0, 3.0)]],
    "T": [[(0.0, 0.3), (4.0, 0.3)], [(2.0, 0.3), (2.0, 5.7)]],
    "N": [[(0.0, 5.7), (0.0, 0.3), (4.0, 5.7), (4.0, 0.3)]],
}
ADVANCE = 5.2          # glyph advance in grid units
SPIRE_I = "I"          # drawn specially: a tapering spire with a star


def word_width(word):
    return len(word) * ADVANCE - (ADVANCE - 4.0)


def draw_word(T, word, x0, y0, unit, stroke_w, fill_top, fill_bottom, outline, shear=0.16, stars=True):
    """Draws a word onto Tile `T` with an outline, a vertical gradient fill and a highlight."""
    strokes = []
    spires = []
    x = 0.0
    for ch in word:
        if ch == SPIRE_I:
            spires.append(x + 2.0)
        else:
            for path in GLYPHS[ch]:
                strokes.append([(x + gx, gy) for gx, gy in path])
        x += ADVANCE

    def tr(pt):
        gx, gy = pt
        sx = gx * unit + (6.0 - gy) * unit * shear
        return (x0 + sx, y0 + gy * unit)

    stroke_drawers = [line([tr(p) for p in path], stroke_w * unit) for path in strokes]
    spire_shapes = []
    for cx in spires:
        top = tr((cx, -0.7))
        bl = tr((cx - 0.75, 0.9))
        br = tr((cx + 0.75, 0.9))
        b0 = tr((cx - 0.75, 5.7))
        b1 = tr((cx + 0.75, 5.7))
        spire_shapes.append(poly([top, br, b1, b0, bl]))
        spire_shapes.append(poly([tr((cx - 1.4, 5.7)), tr((cx + 1.4, 5.7)), tr((cx + 1.4, 5.7 + 0.35)), tr((cx - 1.4, 5.7 + 0.35))]))
    everything = union(*(stroke_drawers + spire_shapes))
    # outline: a thicker version of the same strokes
    out_drawers = [line([tr(p) for p in path], (stroke_w + 0.55) * unit) for path in strokes]
    out_shapes = []
    for cx in spires:
        top = tr((cx, -0.95))
        out_shapes.append(poly([top, tr((cx + 1.05, 0.95)), tr((cx + 1.05, 6.15)), tr((cx - 1.05, 6.15)), tr((cx - 1.05, 0.95))]))
    T.fill(union(*(out_drawers + out_shapes)), outline, 1.0)
    # gradient fill: paint the word mask with a vertical gradient
    mask = T.mask(everything)
    yy = np.clip((T._yy - (y0 - 0.9 * unit)) / (7.0 * unit), 0.0, 1.0)[..., None]
    col = np.asarray(fill_top, np.float32)[None, None, :] * (1 - yy) + np.asarray(fill_bottom, np.float32)[None, None, :] * yy
    a = mask.astype(np.float32)
    T.p[..., :3] = col * a[..., None] + T.p[..., :3] * (1 - a[..., None])
    T.p[..., 3] = a + T.p[..., 3] * (1 - a)
    # top highlight and bottom shade
    lit = mask * np.clip(1.0 - (T._yy - (y0 - 0.5 * unit)) / (1.6 * unit), 0.0, 1.0)
    T.over(lit.astype(np.float32), (1.0, 1.0, 1.0), 0.35)
    # stars above the spires
    for cx in (spires if stars else []):
        sx, sy = tr((cx, -1.9))
        T.glow(sx, sy, unit * 1.9, (1.0, 0.95, 0.7), 0.6)
        T.fill(sparkle(sx, sy, unit * 1.05, 0.22), (1.0, 0.98, 0.85), 1.0)
    return x0 + word_width(word) * unit


def render_logo(path):
    W, H = 780, 420
    T = Tile(W, H, ss=2, wrap=False)
    unit = 24.0
    stroke = 1.05
    y1, y2 = 72.0, 226.0
    # a soft glow behind the lettering
    T.glow(W * 0.5, H * 0.5, 340.0, (0.35, 0.25, 0.7), 0.35)
    w1 = word_width("SPIRE") * unit
    w2 = word_width("SPRINT") * unit
    x1 = (W - w1) / 2.0 - 6.0
    x2 = (W - w2) / 2.0 - 6.0
    outline = hex_color("1a1030")
    shade = darken(hex_color("2a1450"), 0.3)
    # drop shadow first, then the two words
    draw_word(T, "SPIRE", x1 + 5.0, y1 + 7.0, unit, stroke, shade, shade, shade, stars=False)
    draw_word(T, "SPRINT", x2 + 5.0, y2 + 7.0, unit, stroke, shade, shade, shade, stars=False)
    draw_word(T, "SPIRE", x1, y1, unit, stroke, hex_color("ffe08a"), hex_color("ff8c2b"), outline)
    draw_word(T, "SPRINT", x2, y2, unit, stroke, hex_color("9ff6ff"), hex_color("2aa8ff"), outline, stars=False)
    img = T.to_image()
    img.save(path, optimize=True)
    return img


# ---------------------------------------------------------------------------------- icons
def _icon_background(T, size):
    T.gradient_v(hex_color("0c0f22"), hex_color("3b1f6e"), 1.0)
    T.glow(size * 0.5, size * 0.72, size * 0.62, hex_color("ff8c42"), 0.45, 1.6)
    T.glow(size * 0.5, size * 0.28, size * 0.5, hex_color("35f2ff"), 0.22, 1.8)
    rng = np.random.default_rng(5)
    T.fill(union(*[circle(float(rng.uniform(0, size)), float(rng.uniform(0, size * 0.7)), float(rng.uniform(0.8, 2.2))) for _ in range(40)]), (1, 1, 1), 0.7)


def _icon_foreground(T, size, mono=False):
    """The spire, a few floating platforms, the scarf swoosh and a star. Drawn in the middle 60 percent."""
    s = size / 432.0
    ink = hex_color("1a1030")
    gold, orange = hex_color("ffe08a"), hex_color("ff8c2b")
    cyan, blue = hex_color("9ff6ff"), hex_color("2aa8ff")
    if mono:
        gold = orange = cyan = blue = (1.0, 1.0, 1.0)
        ink = (1.0, 1.0, 1.0)

    def P(x, y):
        return (x * s, y * s)

    # scarf swoosh winding up around the spire
    swoosh = [P(96 + 260 * t, 350 - 250 * t + 46 * math.sin(t * 7.0)) for t in np.linspace(0.0, 1.0, 40)]
    if not mono:
        T.fill(line(swoosh, 26 * s), ink, 1.0)
        T.fill(line(swoosh, 17 * s), cyan, 1.0)
        T.fill(line(swoosh[6:30], 6 * s), (1, 1, 1), 0.55)
    else:
        T.fill(line(swoosh, 16 * s), (1, 1, 1), 1.0)
    # spire body: three stepped tiers
    tiers = [
        [P(150, 352), P(282, 352), P(262, 268), P(170, 268)],
        [P(172, 268), P(260, 268), P(246, 196), P(186, 196)],
        [P(190, 196), P(242, 196), P(228, 138), P(204, 138)],
    ]
    for k, pts in enumerate(tiers):
        T.fill(poly(pts), ink, 1.0, blur=0.0)
    for k, pts in enumerate(tiers):
        inset = [P(x / s + (4 if x / s < 216 else -4), y / s + (4 if k > 0 else -2)) for (x, y) in pts]
        col_top, col_bot = (gold, orange) if not mono else ((1, 1, 1), (1, 1, 1))
        T.fill(poly(pts), mix(col_top, col_bot, 0.25 * k + 0.1), 1.0)
        T.fill(poly([pts[0], pts[1], (pts[1][0], pts[1][1] - 10 * s), (pts[0][0], pts[0][1] - 10 * s)]), darken(col_bot, 0.25), 0.6 if not mono else 0.0)
    # roof needle
    T.fill(poly([P(203, 140), P(229, 140), P(216, 84)]), ink, 1.0)
    T.fill(poly([P(208, 138), P(224, 138), P(216, 96)]), gold if not mono else (1, 1, 1), 1.0)
    # windows
    if not mono:
        wins = [rrect(*P(190, 296), *P(202, 322), 3 * s), rrect(*P(230, 296), *P(242, 322), 3 * s), rrect(*P(208, 214), *P(224, 240), 4 * s)]
        T.fill(union(*wins), hex_color("35f2ff"), 0.95)
    # floating platforms
    for (x0, y0, x1, col) in ((70, 300, 150, cyan), (282, 236, 362, orange), (76, 190, 132, gold)):
        T.fill(rrect(*P(x0, y0), *P(x1, y0 + 20), 8 * s), ink, 1.0)
        T.fill(rrect(*P(x0 + 4, y0 + 3), *P(x1 - 4, y0 + 15), 5 * s), col if not mono else (1, 1, 1), 1.0)
    # star on top
    sx, sy = P(216, 70)
    if not mono:
        T.glow(sx, sy, 60 * s, (1.0, 0.95, 0.7), 0.7)
    T.fill(sparkle(sx, sy, 34 * s, 0.24), ink, 1.0)
    T.fill(sparkle(sx, sy, 27 * s, 0.24), (1.0, 0.98, 0.86) if not mono else (1, 1, 1), 1.0)


def render_icons(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    # adaptive layers (432 px)
    bg = Tile(432, 432, ss=2, wrap=False)
    _icon_background(bg, 432)
    bg.to_image().save(os.path.join(out_dir, "adaptive_background_432.png"), optimize=True)
    fg = Tile(432, 432, ss=2, wrap=False)
    _icon_foreground(fg, 432)
    fg.to_image().save(os.path.join(out_dir, "adaptive_foreground_432.png"), optimize=True)
    mono = Tile(432, 432, ss=2, wrap=False)
    _icon_foreground(mono, 432, mono=True)
    mono.to_image().save(os.path.join(out_dir, "adaptive_monochrome_432.png"), optimize=True)
    # legacy 192 px icon: background + foreground (the adaptive foreground is drawn in the centre 60 percent,
    # so scale it up a little), clipped to a rounded square
    full = Tile(192, 192, ss=3, wrap=False)
    _icon_background(full, 192)
    fg2 = Tile(432, 432, ss=1, wrap=False)
    _icon_foreground(fg2, 432)
    img = full.to_image()
    top = fg2.to_image().resize((260, 260), Image.LANCZOS)
    img.alpha_composite(top, (-34 + 0, -20))
    mask = Tile(192, 192, ss=3, wrap=False)
    mask.fill(rrect(0, 0, 191, 191, 40), (1, 1, 1), 1.0)
    rounded = np.asarray(mask.to_image().getchannel("A"), np.float32) / 255.0
    arr = np.asarray(img, np.float32)
    arr[..., 3] *= rounded
    Image.fromarray(arr.astype(np.uint8), "RGBA").save(os.path.join(out_dir, "icon_192.png"), optimize=True)


ICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0c0f22"/>
      <stop offset="1" stop-color="#3b1f6e"/>
    </linearGradient>
    <linearGradient id="tower" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffe08a"/>
      <stop offset="1" stop-color="#ff8c2b"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.75" r="0.6">
      <stop offset="0" stop-color="#ff8c42" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#ff8c42" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="128" height="128" rx="26" fill="url(#bg)"/>
  <rect width="128" height="128" rx="26" fill="url(#glow)"/>
  <path d="M28 96 C 44 88, 60 84, 74 74 S 96 56, 104 36" fill="none" stroke="#1a1030" stroke-width="9" stroke-linecap="round"/>
  <path d="M28 96 C 44 88, 60 84, 74 74 S 96 56, 104 36" fill="none" stroke="#9ff6ff" stroke-width="5.5" stroke-linecap="round"/>
  <path d="M43 104 h42 l-6 -26 h-30 z M49 78 h30 l-5 -22 h-20 z M55 56 h18 l-5 -18 h-8 z" fill="url(#tower)" stroke="#1a1030" stroke-width="3" stroke-linejoin="round"/>
  <path d="M60 38 h8 l-4 -20 z" fill="#ffe08a" stroke="#1a1030" stroke-width="3" stroke-linejoin="round"/>
  <rect x="20" y="70" width="24" height="7" rx="3" fill="#9ff6ff" stroke="#1a1030" stroke-width="2.5"/>
  <rect x="86" y="52" width="24" height="7" rx="3" fill="#ff8c2b" stroke="#1a1030" stroke-width="2.5"/>
  <path d="M64 6 l3 8 8 3 -8 3 -3 8 -3 -8 -8 -3 8 -3 z" fill="#fff7d6" stroke="#1a1030" stroke-width="2" stroke-linejoin="round"/>
</svg>
"""


def render_all(root, preview_dir=None):
    art_ui = os.path.join(root, "assets", "art", "ui")
    os.makedirs(art_ui, exist_ok=True)
    logo = render_logo(os.path.join(art_ui, "logo.png"))
    print("logo done")
    render_icons(os.path.join(root, "assets", "icons"))
    print("launcher icons done")
    with open(os.path.join(root, "icon.svg"), "w", encoding="utf-8") as f:
        f.write(ICON_SVG)
    print("icon.svg written")
    if preview_dir:
        canvas = Image.new("RGB", (1260, 430), (40, 44, 70))
        c = Image.new("RGBA", logo.size, (40, 44, 70, 255))
        c.alpha_composite(logo)
        canvas.paste(c.convert("RGB"), (0, 0))
        x = 800
        for name in ("icon_192.png", "adaptive_foreground_432.png", "adaptive_monochrome_432.png"):
            im = Image.open(os.path.join(root, "assets", "icons", name)).convert("RGBA")
            bg = Image.new("RGBA", im.size, (90, 96, 130, 255))
            bg.alpha_composite(im)
            canvas.paste(bg.convert("RGB").resize((150, 150)), (x, 20))
            x += 155
        canvas.save(os.path.join(preview_dir, "ui_art.png"))
