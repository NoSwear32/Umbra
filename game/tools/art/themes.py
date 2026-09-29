"""
The eleven tower environments: for each one a far parallax layer, a near parallax layer (both
512x512, seamless in x and y) and a wall strip (64x256, seamless in y).

Colours come straight from ThemeManager (src/autoload/theme_manager.gd), so the textures always
match the palette the game uses for gradients, platforms and effects.
"""
import ast
import math
import os
import re

import numpy as np

from .tile import (Tile, blur_wrap, circle, darken, ellipse, gear, hex_color, lighten, line, mix,
                   poly, rect, rrect, sparkle, star, union)

TILE = 512
WALL_W, WALL_H = 64, 256


class Pal:
    """One row of ThemeManager._add(...)."""

    def __init__(self, args):
        (self.name, self.subtitle, bt, bb, wa, wb, pt, pb, pe, pd, ac, self.style, self.panel_alpha) = args
        self.bg_top, self.bg_bottom = hex_color(bt), hex_color(bb)
        self.wall_a, self.wall_b = hex_color(wa), hex_color(wb)
        self.plat_top, self.plat_body = hex_color(pt), hex_color(pb)
        self.plat_edge, self.plat_deco = hex_color(pe), hex_color(pd)
        self.accent = hex_color(ac)
        self.bg_mid = mix(self.bg_top, self.bg_bottom, 0.5)


def load_palettes(gd_path):
    text = open(gd_path, encoding="utf-8").read()
    pals = []
    for m in re.finditer(r"^\t_add\((.*)\)\s*$", text, re.M):
        pals.append(Pal(ast.literal_eval("(" + m.group(1) + ")")))
    return pals


def _r(rng, a, b):
    return float(rng.uniform(a, b))


# ============================================================================ 0  Moss Vaults
def far_0(T, p, rng):
    stone = mix(p.bg_mid, p.wall_a, 0.35)
    for row in range(2):
        yb = 250 + 256 * row
        arches = []
        cut = []
        for i in range(4):
            x0 = i * 128
            arches.append(rect(x0 + 6, yb - 176, x0 + 122, yb))
            cut.append(union(rect(x0 + 26, yb - 128, x0 + 102, yb + 2), ellipse(x0 + 64, yb - 128, 38, 38)))
        T.fill(union(*arches), stone, 0.42, cut=union(*cut))
        T.fill(rect(0, yb - 8, TILE, yb + 6), darken(stone, 0.2), 0.42)
    T.glow(120, 130, 190, mix(p.bg_bottom, p.accent, 0.4), 0.16)
    T.glow(390, 400, 220, mix(p.bg_bottom, p.wall_b, 0.5), 0.18)


def near_0(T, p, rng):
    vine = mix(p.wall_b, p.bg_mid, 0.15)
    leaf = lighten(p.wall_b, 0.15)
    for k in range(5):
        x0 = _r(rng, 20, 490)
        length = _r(rng, 170, 300)
        pts = [(x0 + 14 * math.sin(i * 0.55 + k), i * length / 14.0) for i in range(15)]
        T.fill(line(pts, 3.0), vine, 0.75)
        leaves = []
        for i in range(2, 15):
            x, y = pts[i]
            side = 1 if i % 2 else -1
            leaves.append(ellipse(x + side * 9, y, 10, 5, side * 0.5 + 0.2))
        T.fill(union(*leaves), leaf, 0.7)
    # hanging lanterns
    for k in range(3):
        x = _r(rng, 40, 470)
        y = _r(rng, 60, 440)
        T.glow(x, y + 12, 70, p.accent, 0.5, 2.2)
        T.fill(line([(x, y - 60), (x, y)], 1.6), darken(p.plat_edge, 0.1), 0.9)
        T.fill(union(rect(x - 6, y, x + 6, y + 20), poly([(x - 6, y), (x + 6, y), (x, y - 6)])), p.plat_edge, 0.95)
        T.fill(rect(x - 3.5, y + 4, x + 3.5, y + 17), lighten(p.accent, 0.4), 0.95)


def wall_0(T, p, rng):
    base = p.wall_a
    rows = 16
    bh = WALL_H / rows
    bricks, mortar = [], []
    for r in range(rows):
        off = 0 if r % 2 == 0 else 16
        y0 = r * bh
        for i in range(-1, 3):
            x0 = i * 32 + off
            bricks.append((x0 + 1, y0 + 1, x0 + 31, y0 + bh - 1, r * 7 + i))
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.45))
    for (x0, y0, x1, y1, seed) in bricks:
        shade = ((seed * 37) % 11) / 11.0
        T.fill(rrect(x0, y0, x1, y1, 2.0), mix(base, lighten(base, 0.25), shade * 0.7), 1.0)
        T.fill(rect(x0 + 1, y0 + 1, x1 - 1, y0 + 2.5), lighten(base, 0.35), 0.35)
    # moss patches
    for k in range(9):
        x = _r(rng, 0, 64)
        y = _r(rng, 0, WALL_H)
        T.fill(union(ellipse(x, y, _r(rng, 6, 13), _r(rng, 3, 6)), circle(x + 5, y - 3, 3.5)), p.wall_b, 0.85)
    # tower-facing trim and outer shadow
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.35), 0.9)
    T.fill(rect(56, 0, 58, WALL_H), lighten(p.accent, 0.1), 0.4)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.35, (0, 0, 0), 1.0)


# ============================================================================ 1  Forge Deck
def far_1(T, p, rng):
    metal = mix(p.bg_mid, p.wall_a, 0.3)
    T.fill(union(*[rect(x, 0, x + 34, TILE) for x in (60, 250, 420)]), metal, 0.28)
    T.fill(union(*[rect(0, y, TILE, y + 14) for y in (120, 300, 470)]), metal, 0.3)
    gears = [gear(150, 200, 78, 12, 12, 26), gear(370, 350, 96, 14, 14, 34), gear(430, 90, 52, 10, 9, 18)]
    for g in gears:
        T.fill(g, metal, 0.32)
    T.glow(250, 500, 200, mix(p.bg_bottom, p.accent, 0.7), 0.25)


def near_1(T, p, rng):
    iron = mix(p.plat_body, p.bg_bottom, 0.55)
    for y in (90, 260, 430):
        T.fill(union(rect(0, y, TILE, y + 12), rect(0, y + 30, TILE, y + 42), rect(0, y + 12, TILE, y + 30)), iron, 0.7)
        T.fill(rect(0, y + 12, TILE, y + 30), darken(iron, 0.3), 0.7)
        T.fill(union(*[circle(x, y + 6, 2.5) for x in range(10, 512, 40)]), lighten(iron, 0.35), 0.7)
        T.fill(union(*[circle(x, y + 36, 2.5) for x in range(10, 512, 40)]), lighten(iron, 0.35), 0.7)
    for x in (100, 330, 460):
        T.fill(line([(x, 0), (x, 90)], 2.0), lighten(iron, 0.1), 0.6)
        T.fill(union(*[ellipse(x, 8 + i * 12, 3.2, 5.5) for i in range(8)]), lighten(iron, 0.15), 0.55)
    # furnace windows and sparks
    for (x, y) in ((230, 130), (40, 300), (400, 470)):
        T.glow(x, y, 80, p.accent, 0.55, 2.0)
        T.fill(rrect(x - 22, y - 12, x + 22, y + 12, 4), lighten(p.accent, 0.35), 0.85)
        T.fill(rrect(x - 26, y - 16, x + 26, y + 16, 5), iron, 0.8, cut=rrect(x - 21, y - 11, x + 21, y + 11, 3))
    sp = []
    for _ in range(40):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        sp.append(circle(x, y, _r(rng, 0.8, 2.0)))
    T.fill(union(*sp), lighten(p.accent, 0.5), 0.8)


def wall_1(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.35))
    for i in range(4):
        y0 = i * 64
        T.fill(rrect(2, y0 + 2, 62, y0 + 62, 3), mix(base, p.wall_b, 0.25 * ((i * 5) % 3) / 2.0), 1.0)
        T.fill(rect(4, y0 + 4, 60, y0 + 8), lighten(base, 0.3), 0.35)
        rivets = [circle(x, y, 2.6) for x in (8, 56) for y in (y0 + 8, y0 + 56)]
        T.fill(union(*rivets), lighten(base, 0.45), 0.9)
        T.fill(union(*[circle(x + 0.8, y + 0.8, 2) for x in (8, 56) for y in (y0 + 8, y0 + 56)]), darken(base, 0.4), 0.4)
        # glowing seam
        T.fill(rect(2, y0 + 62, 62, y0 + 64), p.accent, 0.8)
    for k in range(7):
        x = _r(rng, 6, 58)
        y = _r(rng, 0, WALL_H)
        T.fill(rect(x, y, x + 2, y + _r(rng, 14, 44)), darken(p.wall_b, 0.2), 0.35)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.4), 0.85)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.35, (0, 0, 0), 1.0)


# ============================================================================ 2  Neon Grid
def far_2(T, p, rng):
    grid = mix(p.bg_mid, p.wall_b, 0.45)
    T.fill(union(*[rect(x, 0, x + 1.5, TILE) for x in range(0, 512, 64)]), grid, 0.32)
    T.fill(union(*[rect(0, y, TILE, y + 1.5) for y in range(0, 512, 64)]), grid, 0.32)
    hexes = []
    for (cx, cy, r) in ((130, 140, 90), (390, 330, 120), (440, 60, 50)):
        pts = [(cx + r * math.cos(math.pi / 3 * i), cy + r * math.sin(math.pi / 3 * i)) for i in range(6)]
        hexes.append(line(pts + [pts[0]], 2.5))
    T.fill(union(*hexes), mix(p.wall_b, p.accent, 0.2), 0.32)
    T.glow(256, 256, 260, mix(p.bg_bottom, p.accent, 0.5), 0.12)


def near_2(T, p, rng):
    cyan = p.wall_b
    mag = p.accent
    traces_c, traces_m, nodes_c, nodes_m = [], [], [], []
    for k in range(14):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        pts = [(x, y)]
        horizontal = k % 2 == 0
        for _ in range(4):
            step = _r(rng, 30, 90) * (1 if rng.random() > 0.5 else -1)
            if horizontal:
                x += step
            else:
                y += step
            pts.append((x, y))
            horizontal = not horizontal
        (traces_c if k % 3 else traces_m).append(line(pts, 2.0))
        (nodes_c if k % 3 else nodes_m).append(circle(pts[-1][0], pts[-1][1], 4.5))
        (nodes_c if k % 3 else nodes_m).append(circle(pts[0][0], pts[0][1], 3.0))
    for drawers, col in (((traces_c, nodes_c), cyan), ((traces_m, nodes_m), mag)):
        tr, nd = drawers
        if tr:
            T.fill(union(*tr), col, 0.5, blur=3.0)
            T.fill(union(*tr), lighten(col, 0.45), 0.55)
        if nd:
            T.fill(union(*nd), col, 0.4, blur=4.0)
            T.fill(union(*nd), lighten(col, 0.6), 0.7)


def wall_2(T, p, rng):
    base = darken(p.wall_a, 0.15)
    T.fill(rect(0, 0, WALL_W, WALL_H), base)
    T.fill(union(*[rect(0, y, WALL_W, y + 1) for y in range(0, WALL_H, 4)]), (0, 0, 0), 0.18)
    T.fill(union(*[rect(6, y, 22, y + 2) for y in range(0, WALL_H, 32)]), p.wall_b, 0.5)
    T.fill(rect(43, 0, 51, WALL_H), p.wall_b, 0.8, blur=3.0)
    T.fill(rect(45, 0, 49, WALL_H), lighten(p.wall_b, 0.7), 0.95)
    T.fill(union(*[rect(30, y, 42, y + 1.5) for y in range(8, WALL_H, 32)]), p.accent, 0.8)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.5), 0.9)
    T.fill(rect(62, 0, 64, WALL_H), p.accent, 0.9, blur=1.0)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.30, (0, 0, 0), 1.0)


# ============================================================================ 3  Overgrown Spire
def _leaf_shape(cx, cy, length, width, rot):
    return ellipse(cx + math.cos(rot) * length * 0.5, cy + math.sin(rot) * length * 0.5, length * 0.5, width * 0.5, rot, 24)


def far_3(T, p, rng):
    canopy = mix(p.bg_mid, p.wall_b, 0.28)
    blobs = []
    for _ in range(26):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        blobs.append(circle(x, y, _r(rng, 26, 62)))
    T.fill(union(*blobs), canopy, 0.34)
    T.fill(union(*[rect(x, 0, x + 26, 512) for x in (80, 300)]), darken(canopy, 0.25), 0.3)
    T.glow(400, 100, 170, mix(p.bg_bottom, p.accent, 0.5), 0.16)


def near_3(T, p, rng):
    green = p.wall_b
    for k in range(6):
        x0 = _r(rng, 10, 500)
        y0 = _r(rng, 0, 512)
        ang = _r(rng, -0.4, 0.4) + math.pi / 2
        pts = [(x0 + math.cos(ang + 0.6 * math.sin(i * 0.5)) * i * 22, y0 + math.sin(ang) * i * 22) for i in range(8)]
        T.fill(line(pts, 3.0), darken(green, 0.25), 0.8)
        leaves = []
        for i in range(1, 8):
            x, y = pts[i]
            leaves.append(_leaf_shape(x, y, 34, 15, _r(rng, -1.2, -0.3) if i % 2 else _r(rng, 3.4, 4.3)))
        T.fill(union(*leaves), mix(green, p.bg_bottom, 0.15), 0.85)
        T.fill(union(*[_leaf_shape(*(pts[i]), 20, 6, -0.8 if i % 2 else 3.9) for i in range(1, 8)]), lighten(green, 0.25), 0.5)
    for _ in range(8):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        petals = [circle(x + 6 * math.cos(a), y + 6 * math.sin(a), 4.2) for a in (0, 1.256, 2.513, 3.769, 5.026)]
        T.fill(union(*petals), p.plat_deco, 0.85)
        T.fill(circle(x, y, 3.0), p.accent, 0.95)
    for _ in range(14):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        T.glow(x, y, 16, p.accent, 0.8, 2.0)
        T.fill(circle(x, y, 1.4), lighten(p.accent, 0.7), 1.0)


def wall_3(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.4))
    for r in range(8):
        y0 = r * 32
        off = 0 if r % 2 == 0 else 20
        for i in range(-1, 3):
            x0 = i * 40 + off
            T.fill(rrect(x0 + 1, y0 + 1, x0 + 39, y0 + 31, 3), mix(base, lighten(base, 0.2), ((r * 3 + i) % 4) / 4.0), 1.0)
    pts = [(38 + 12 * math.sin(i * 0.35), i * 8.0) for i in range(33)]
    T.fill(line(pts, 6.0), darken(p.wall_b, 0.35), 1.0)
    T.fill(line(pts, 3.5), p.wall_b, 1.0)
    T.fill(union(*[ellipse(pts[i][0] + (12 if i % 2 else -12), pts[i][1], 11, 5, 0.5 if i % 2 else -0.5) for i in range(1, 33, 2)]), lighten(p.wall_b, 0.1), 0.95)
    T.fill(union(*[circle(pts[i][0] + 10, pts[i][1] + 3, 3) for i in (5, 15, 25)]), p.plat_deco, 0.95)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.35), 0.85)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.32, (0, 0, 0), 1.0)


# ============================================================================ 4  Prism Cavern
def _crystal(cx, base_y, w, h, lean=0.0):
    return poly([(cx - w / 2, base_y), (cx - w * 0.3 + lean, base_y - h * 0.8), (cx + lean, base_y - h),
                 (cx + w * 0.3 + lean, base_y - h * 0.8), (cx + w / 2, base_y)])


def far_4(T, p, rng):
    col = mix(p.bg_mid, p.wall_b, 0.4)
    cl = []
    for _ in range(9):
        cx = _r(rng, 0, 512)
        cl.append(_crystal(cx, 512.0 if rng.random() > 0.5 else 300.0, _r(rng, 40, 80), _r(rng, 110, 230), _r(rng, -18, 18)))
    T.fill(union(*cl), col, 0.3)
    T.fill(union(*[poly([(x, 0), (x + 30, 0), (x + 15, _r(rng, 70, 150))]) for x in (60, 200, 340, 470)]), col, 0.3)
    T.glow(256, 256, 250, mix(p.bg_bottom, p.accent, 0.4), 0.14)


def near_4(T, p, rng):
    for k in range(10):
        cx, by = _r(rng, 0, 512), _r(rng, 40, 512)
        w, h = _r(rng, 26, 46), _r(rng, 60, 120)
        lean = _r(rng, -10, 10)
        col = p.accent if k % 2 == 0 else p.plat_deco
        T.glow(cx, by - h * 0.5, h * 0.9, col, 0.25, 2.0)
        T.fill(_crystal(cx, by, w, h, lean), mix(col, p.bg_bottom, 0.35), 0.85)
        T.fill(poly([(cx - w * 0.5, by), (cx - w * 0.3 + lean, by - h * 0.8), (cx + lean, by - h), (cx + lean * 0.5, by - h * 0.2), (cx, by)]), lighten(col, 0.3), 0.55)
        T.fill(poly([(cx + lean, by - h), (cx + w * 0.3 + lean, by - h * 0.8), (cx + w * 0.5, by), (cx + lean * 0.5, by - h * 0.2)]), darken(col, 0.3), 0.35)
    T.fill(union(*[sparkle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 5, 11)) for _ in range(16)]), (1, 1, 1), 0.9)


def wall_4(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.3))
    for i in range(3):
        x0 = i * 21.5
        shade = 0.12 * ((i * 2) % 3)
        T.fill(rect(x0, 0, x0 + 21.5, WALL_H), mix(base, p.wall_b, 0.15 + shade))
        T.fill(rect(x0 + 1, 0, x0 + 3, WALL_H), lighten(p.wall_b, 0.4), 0.55)
        T.fill(rect(x0 + 19, 0, x0 + 21.5, WALL_H), darken(base, 0.4), 0.55)
    for k in range(5):
        x, y = _r(rng, 8, 56), k * 51 + _r(rng, 0, 30)
        T.glow(x, y, 20, p.accent, 0.6, 2.0)
        T.fill(poly([(x, y - 8), (x + 6, y), (x, y + 8), (x - 6, y)]), lighten(p.accent, 0.2), 0.95)
    T.fill(union(*[rect(0, y, 64, y + 1.2) for y in (0, 128)]), lighten(p.wall_b, 0.4), 0.5)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.35), 0.85)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.3, (0, 0, 0), 1.0)


# ============================================================================ 5  Clockwork Hall
def far_5(T, p, rng):
    brass = mix(p.bg_mid, p.wall_b, 0.3)
    for (cx, cy, r, tn) in ((120, 130, 100, 14), (300, 60, 62, 10), (400, 270, 118, 16), (110, 380, 74, 12), (270, 470, 88, 13)):
        T.fill(gear(cx, cy, r, tn, r * 0.13, r * 0.22), brass, 0.3)
        T.fill(union(*[line([(cx, cy), (cx + r * 0.72 * math.cos(a), cy + r * 0.72 * math.sin(a))], r * 0.11) for a in (0.0, 1.05, 2.1, 3.14, 4.2, 5.25)]), brass, 0.3)
    T.glow(256, 256, 260, mix(p.bg_bottom, p.accent, 0.45), 0.13)


def near_5(T, p, rng):
    brass = p.wall_b
    for k, (cx, cy, r, tn) in enumerate(((70, 90, 46, 10), (190, 150, 30, 8), (350, 60, 40, 9), (450, 210, 54, 11), (120, 320, 38, 9), (300, 380, 58, 12), (450, 470, 32, 8), (40, 470, 44, 10))):
        col = mix(brass, p.bg_bottom, 0.15 + 0.1 * (k % 3))
        T.fill(gear(cx, cy, r, tn, r * 0.16, r * 0.3), darken(col, 0.35), 0.9)
        T.fill(gear(cx - 1, cy - 1, r * 0.92, tn, r * 0.13, r * 0.3), col, 0.95)
        T.fill(union(*[line([(cx, cy), (cx + r * 0.7 * math.cos(a), cy + r * 0.7 * math.sin(a))], r * 0.12) for a in (0.3, 1.9, 3.5, 5.1)]), darken(col, 0.2), 0.9)
        T.fill(circle(cx, cy, r * 0.22), lighten(col, 0.35), 0.95)
        T.fill(circle(cx, cy, r * 0.09), darken(col, 0.5), 0.95)
    T.fill(union(*[circle(x, y, 2.4) for (x, y) in ((20, 20), (490, 30), (250, 260), (30, 250), (480, 400))]), lighten(brass, 0.4), 0.8)
    T.fill(line([(230, 0), (230, 120)], 2.0), lighten(brass, 0.1), 0.7)
    T.fill(circle(230, 128, 9), lighten(brass, 0.25), 0.9)


def wall_5(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.3))
    for i in range(4):
        y0 = i * 64
        T.fill(rrect(3, y0 + 2, 61, y0 + 62, 4), mix(base, p.wall_b, 0.25 + 0.08 * (i % 2)), 1.0)
        T.fill(rect(6, y0 + 5, 58, y0 + 8), lighten(p.wall_b, 0.5), 0.4)
        T.fill(union(*[circle(x, y, 2.8) for x in (9, 55) for y in (y0 + 10, y0 + 54)]), lighten(p.wall_b, 0.55), 0.95)
        T.fill(circle(32, y0 + 32, 14), darken(p.wall_b, 0.35), 0.9)
        T.fill(gear(32, y0 + 32, 10, 8, 3, 3), lighten(p.wall_b, 0.2), 1.0)
    for x in (2, 58):
        T.fill(rect(x, 0, x + 4, WALL_H), darken(base, 0.4), 0.7)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.4), 0.85)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.3, (0, 0, 0), 1.0)


# ============================================================================ 6  Tempest Deck
def far_6(T, p, rng):
    cloud = mix(p.bg_mid, p.wall_b, 0.35)
    for _ in range(30):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        T.fill(ellipse(x, y, _r(rng, 40, 90), _r(rng, 16, 36)), cloud, 0.16, blur=10.0)
    for x in (110, 380):
        pts = [(x, 60), (x + 26, 150), (x + 4, 160), (x + 40, 260), (x + 8, 250), (x + 30, 330)]
        T.fill(line(pts, 5.0), lighten(p.wall_b, 0.4), 0.28, blur=4.0)


def near_6(T, p, rng):
    for _ in range(90):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        ln = _r(rng, 14, 30)
        T.fill(line([(x, y), (x - ln * 0.28, y + ln)], 1.4), lighten(p.wall_b, 0.5), 0.32)
    for x, y in ((90, 40), (350, 270)):
        pts = [(x, y), (x + 30, y + 90), (x + 6, y + 96), (x + 48, y + 200), (x + 12, y + 190), (x + 44, y + 280)]
        T.fill(line(pts, 7.0), p.plat_deco, 0.55, blur=6.0)
        T.fill(line(pts, 3.2), (1.0, 1.0, 0.92), 0.95)
    for _ in range(12):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        T.fill(ellipse(x, y, _r(rng, 30, 60), _r(rng, 8, 16)), lighten(p.bg_mid, 0.25), 0.16, blur=6.0)


def wall_6(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.3))
    for i in range(4):
        y0 = i * 64
        T.fill(rect(2, y0 + 2, 62, y0 + 62), mix(base, p.wall_b, 0.18 + 0.06 * (i % 3)), 1.0)
        T.fill(rect(2, y0 + 2, 62, y0 + 5), lighten(base, 0.3), 0.4)
        T.fill(union(*[circle(x, y, 2.6) for x in (8, 56) for y in (y0 + 8, y0 + 56)]), lighten(base, 0.4), 0.9)
    for k in range(10):
        x = _r(rng, 8, 56)
        y = _r(rng, 0, WALL_H)
        T.fill(rect(x, y, x + 1.2, y + _r(rng, 20, 70)), lighten(p.wall_b, 0.5), 0.28)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.4), 0.85)
    T.fill(rect(56, 0, 58, WALL_H), lighten(p.wall_b, 0.4), 0.5)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.3, (0, 0, 0), 1.0)


# ============================================================================ 7  Lumen Lattice
def far_7(T, p, rng):
    white = (1.0, 1.0, 1.0)
    dia = []
    for i in range(-8, 9):
        dia.append(line([(i * 64, 0), (i * 64 + 512, 512)], 1.6, False))
        dia.append(line([(i * 64 + 512, 0), (i * 64, 512)], 1.6, False))
    T.fill(union(*dia), white, 0.28)
    for _ in range(9):
        T.glow(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 60, 130), mix(p.accent, p.plat_deco, _r(rng, 0, 1)), 0.32, 1.6)


def near_7(T, p, rng):
    pastel = [p.plat_deco, (1.0, 0.85, 0.55), (0.72, 0.85, 1.0), (1.0, 1.0, 1.0)]
    for k in range(14):
        cx, cy = _r(rng, 0, 512), _r(rng, 0, 512)
        r = _r(rng, 18, 44)
        col = pastel[k % 4]
        kind = k % 3
        if kind == 0:
            shape = poly([(cx, cy - r), (cx + r * 0.75, cy), (cx, cy + r), (cx - r * 0.75, cy)])
        elif kind == 1:
            shape = poly([(cx, cy - r), (cx + r * 0.87, cy + r * 0.5), (cx - r * 0.87, cy + r * 0.5)])
        else:
            shape = circle(cx, cy, r * 0.75)
        T.fill(shape, col, 0.34)
        T.fill(line([(cx - r * 0.5, cy - r * 0.2), (cx + r * 0.5, cy + r * 0.2)], 1.3), (1, 1, 1), 0.7)
    for x in (70, 250, 420):
        T.fill(poly([(x, 0), (x + 40, 0), (x + 100, 512), (x + 30, 512)]), (1, 1, 1), 0.12, blur=10.0)
    T.fill(union(*[sparkle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 4, 9)) for _ in range(20)]), (1, 1, 1), 0.95)


def wall_7(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.12))
    dia = []
    for i in range(-4, 12):
        dia.append(line([(0, i * 32), (64, i * 32 + 64)], 1.8, False))
        dia.append(line([(0, i * 32 + 64), (64, i * 32)], 1.8, False))
    T.fill(union(*dia), lighten(p.wall_b, 0.2), 0.9)
    T.fill(union(*[rect(0, y, 64, y + 3) for y in range(0, WALL_H, 64)]), p.plat_body, 0.5)
    for k in range(12):
        x, y = _r(rng, 8, 56), _r(rng, 0, WALL_H)
        T.fill(poly([(x, y - 7), (x + 5, y), (x, y + 7), (x - 5, y)]), p.plat_deco, 0.6)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.25), 0.8)
    T.fill(rect(62, 0, 64, WALL_H), (1, 1, 1), 0.95, blur=0.8)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.16, (0, 0, 0), 1.0)


# ============================================================================ 8  Auroral Terrace
def far_8(T, p, rng):
    bands = [(0.0, p.accent, 0.30), (1.0, mix(p.accent, p.plat_deco, 0.5), 0.24), (2.0, p.wall_b, 0.22)]
    for (ph, col, al) in bands:
        pts = [(x, 110 + ph * 150 + 42 * math.sin(x / 512.0 * math.tau * 1.0 + ph * 1.7) + 18 * math.sin(x / 512.0 * math.tau * 3.0 + ph)) for x in range(-32, 545, 16)]
        T.fill(line(pts, 70.0), col, al, blur=22.0)
        T.fill(line(pts, 14.0), lighten(col, 0.3), al * 0.7, blur=6.0)
    T.fill(union(*[circle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 0.7, 1.7)) for _ in range(60)]), (1, 1, 1), 0.7)


def near_8(T, p, rng):
    marble = mix(p.wall_a, p.bg_mid, 0.25)
    cols = []
    for i in range(3):
        x = 80 + i * 170
        T.fill(rect(x - 14, 90, x + 14, 512), marble, 0.3)
        T.fill(rect(x - 20, 84, x + 20, 100), lighten(marble, 0.2), 0.34)
        T.fill(union(*[rect(x - 12 + j * 6, 100, x - 10 + j * 6, 512) for j in range(5)]), darken(marble, 0.3), 0.28)
    T.fill(union(*[ellipse(85 + i * 170 + 85, 92, 88, 46) for i in range(3)]), marble, 0.28, cut=union(*[ellipse(85 + i * 170 + 85, 100, 74, 40) for i in range(3)]))
    T.fill(union(*[circle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 1.0, 2.4)) for _ in range(40)]), (1, 1, 1), 0.85)
    T.fill(union(*[sparkle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 5, 9)) for _ in range(9)]), p.accent, 0.9)


def wall_8(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.25))
    T.fill(rect(6, 0, 58, WALL_H), base)
    flutes = [rect(10 + j * 9.5, 0, 12.5 + j * 9.5, WALL_H) for j in range(5)]
    T.fill(union(*flutes), darken(base, 0.22), 0.7)
    T.fill(union(*[rect(10 + j * 9.5 + 2.5, 0, 12 + j * 9.5 + 2.5, WALL_H) for j in range(5)]), lighten(base, 0.3), 0.6)
    for y in (0, 128):
        T.fill(rect(2, y + 2, 62, y + 12), lighten(base, 0.05), 1.0)
        T.fill(rect(2, y + 10, 62, y + 12), darken(base, 0.3), 0.8)
        T.fill(rect(4, y + 116, 60, y + 128), lighten(base, 0.05), 1.0)
        T.fill(rect(4, y + 116, 60, y + 118), darken(base, 0.3), 0.8)
    for k in range(4):
        y = _r(rng, 20, 230)
        T.fill(line([(_r(rng, 10, 20), y), (_r(rng, 40, 54), y + _r(rng, 6, 20))], 0.9), p.wall_b, 0.35)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.35), 0.85)
    T.fill(rect(56, 0, 58, WALL_H), p.accent, 0.45)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.28, (0, 0, 0), 1.0)


# ============================================================================ 9  Starwell
def far_9(T, p, rng):
    for (col, al) in ((p.wall_a, 0.36), (p.accent, 0.10), (p.plat_deco, 0.10)):
        for _ in range(6):
            T.fill(ellipse(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 60, 130), _r(rng, 40, 90), _r(rng, 0, 3.0)), col, al, blur=26.0)
    T.fill(union(*[circle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 0.6, 1.5)) for _ in range(110)]), (1, 1, 1), 0.65)


def near_9(T, p, rng):
    for k in range(3):
        x = _r(rng, 30, 480)
        y = _r(rng, 90, 470)
        w = _r(rng, 18, 30)
        h = _r(rng, 80, 150)
        col = mix(p.wall_a, p.bg_bottom, 0.3)
        T.fill(poly([(x - w, y), (x - w * 0.8, y - h), (x - w * 0.3, y - h - 14), (x + w * 0.5, y - h + 6), (x + w, y - h + 2), (x + w * 0.9, y)]), col, 0.9)
        T.fill(rect(x - w * 0.3, y - h * 0.9, x - w * 0.1, y), lighten(col, 0.2), 0.5)
        T.fill(line([(x - w * 0.9, y - h * 0.4), (x + w * 0.9, y - h * 0.5)], 1.5), p.accent, 0.8)
    T.glow(380, 140, 60, p.accent, 0.4, 2.0)
    T.fill(circle(380, 140, 15), mix(p.wall_b, p.bg_bottom, 0.2), 0.95)
    T.fill(ellipse(380, 140, 28, 6, -0.4), p.accent, 0.8, cut=ellipse(380, 140, 18, 3, -0.4))
    T.fill(union(*[sparkle(_r(rng, 0, 512), _r(rng, 0, 512), _r(rng, 5, 13)) for _ in range(22)]), lighten(p.accent, 0.4), 0.95)


def wall_9(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.35))
    T.fill(rect(6, 0, 58, WALL_H), base)
    T.fill(union(*[circle(_r(rng, 4, 60), _r(rng, 0, WALL_H), _r(rng, 0.6, 1.4)) for _ in range(46)]), (1, 1, 1), 0.7)
    pts = [(12, 10), (26, 40), (20, 80), (40, 110), (34, 150), (48, 190), (30, 230), (12, 10 + 256)]
    T.fill(line(pts, 1.6), p.wall_b, 0.85)
    T.fill(union(*[circle(x, y, 2.6) for (x, y) in pts[:-1]]), lighten(p.wall_b, 0.4), 0.95)
    T.fill(union(*[rect(6, y, 58, y + 3) for y in (0, 64, 128, 192)]), p.wall_b, 0.7)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.45), 0.85)
    T.fill(rect(56, 0, 58, WALL_H), p.wall_b, 0.6)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.3, (0, 0, 0), 1.0)


# ============================================================================ 10  Zenith
def far_10(T, p, rng):
    for k in range(7):
        x = k * 512 / 7.0 + 20
        T.fill(poly([(x, 0), (x + 46, 0), (x + 120, 512), (x + 40, 512)]), lighten(p.accent, 0.3), 0.10, blur=12.0)
    for _ in range(9):
        cx, cy = _r(rng, 0, 512), _r(rng, 0, 512)
        blobs = [circle(cx + _r(rng, -50, 50), cy + _r(rng, -12, 12), _r(rng, 20, 44)) for _ in range(6)]
        T.fill(union(*blobs), lighten(p.wall_b, 0.15), 0.22, blur=8.0)
    T.glow(256, 480, 300, p.accent, 0.22, 1.5)


def near_10(T, p, rng):
    for k in range(6):
        cx, cy = _r(rng, 0, 512), _r(rng, 0, 512)
        w = _r(rng, 70, 130)
        blobs = [circle(cx + (i - 2) * w * 0.22, cy - abs(i - 2) * 6 + 6, w * (0.22 - 0.03 * abs(i - 2))) for i in range(5)]
        T.fill(union(*blobs), (1.0, 0.96, 0.85), 0.6)
        T.fill(ellipse(cx, cy + 12, w * 0.6, 7), p.wall_b, 0.55)
        T.fill(union(*[circle(cx + (i - 2) * w * 0.22 - 3, cy - abs(i - 2) * 6 + 2, w * 0.14) for i in range(5)]), (1, 1, 1), 0.5)
    for _ in range(30):
        x, y = _r(rng, 0, 512), _r(rng, 0, 512)
        T.glow(x, y, 12, (1.0, 0.95, 0.7), 0.85, 2.0)
    for (x, y, r) in ((110, 100, 46), (400, 380, 62)):
        T.fill(circle(x, y, r), p.accent, 0.25, cut=circle(x, y, r - 4))
        T.fill(circle(x, y, r * 0.55), p.accent, 0.16, cut=circle(x, y, r * 0.55 - 3))


def wall_10(T, p, rng):
    base = p.wall_a
    T.fill(rect(0, 0, WALL_W, WALL_H), darken(base, 0.12))
    T.fill(rect(6, 0, 58, WALL_H), base)
    T.fill(union(*[rect(10 + j * 9.5, 0, 12.5 + j * 9.5, WALL_H) for j in range(5)]), mix(base, p.wall_b, 0.5), 0.6)
    T.fill(union(*[rect(10 + j * 9.5 + 2.5, 0, 12 + j * 9.5 + 2.5, WALL_H) for j in range(5)]), (1, 1, 1), 0.55)
    for y in (0, 128):
        T.fill(rect(2, y + 2, 62, y + 14), p.wall_b, 1.0)
        T.fill(rect(2, y + 2, 62, y + 5), lighten(p.wall_b, 0.5), 0.8)
        T.fill(rect(2, y + 12, 62, y + 14), darken(p.wall_b, 0.4), 0.6)
        T.fill(rect(2, y + 112, 62, y + 126), p.wall_b, 1.0)
        T.fill(rect(2, y + 112, 62, y + 115), lighten(p.wall_b, 0.5), 0.8)
    for k in range(6):
        T.glow(_r(rng, 8, 56), _r(rng, 0, WALL_H), 14, (1.0, 0.95, 0.7), 0.6, 2.0)
    T.fill(rect(56, 0, 64, WALL_H), darken(base, 0.2), 0.7)
    T.fill(rect(62, 0, 64, WALL_H), (1.0, 0.96, 0.8), 0.95, blur=1.0)
    xs = np.clip(T._xx / 64.0, 0, 1)
    T.over((1.0 - xs) * 0.14, (0, 0, 0), 1.0)


FAR = [far_0, far_1, far_2, far_3, far_4, far_5, far_6, far_7, far_8, far_9, far_10]
NEAR = [near_0, near_1, near_2, near_3, near_4, near_5, near_6, near_7, near_8, near_9, near_10]
WALL = [wall_0, wall_1, wall_2, wall_3, wall_4, wall_5, wall_6, wall_7, wall_8, wall_9, wall_10]


def render_theme(index, pal, out_dir):
    """Renders and saves the three textures of one theme. Returns the three PIL images."""
    imgs = []
    for kind, fns, (w, h) in (("bg_far", FAR, (TILE, TILE)), ("bg_near", NEAR, (TILE, TILE)), ("wall", WALL, (WALL_W, WALL_H))):
        rng = np.random.default_rng(1000 + index * 10 + len(imgs))
        tile = Tile(w, h, ss=2, wrap=True)
        fns[index](tile, pal, rng)
        img = tile.to_image()
        img.save(os.path.join(out_dir, "%s_%02d.png" % (kind, index)), optimize=True)
        imgs.append(img)
    return imgs
