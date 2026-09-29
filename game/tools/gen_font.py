#!/usr/bin/env python3
"""
Builds "Spire Display", the game's own display typeface, from stroke paths (no existing font is
converted or traced):

    python3 tools/gen_font.py          # writes assets/fonts/spire_display.ttf

Letters, digits and common punctuation are defined below as centre-line paths on a small grid
(chamfered corners, round terminals - the same language as the logotype). Every path is thickened
into an outline with a stroker, overlapping strokes are merged, and the result is written as a real
TrueType font (straight-line contours, so it renders identically everywhere). Lower-case letters
map to the capital forms: it is an all-caps display face for headings, buttons and the HUD.
Text with characters the font lacks falls back to the engine's built-in font (see UIKit).

Requires: fonttools, shapely   (pip install fonttools shapely)
"""
import argparse
import math
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from shapely.geometry import LineString, MultiPolygon, Point, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

UPM = 1000
S = 115.0                # font units per grid unit
STROKE = 0.9             # stroke width in grid units
H = 5.1                  # centre-line height (outer cap height = H + STROKE = 6.0 units)
M = H / 2.0
W = 3.6                  # standard centre-line width
SIDE = 0.55              # side bearing in grid units


def cw(*pts):
    return list(pts)


def ring(cx, cy, rx, ry, n=16):
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n + 1)]


def o_shape(w, chamfer=1.0):
    c = chamfer
    return [(c, 0), (w - c, 0), (w, c), (w, H - c), (w - c, H), (c, H), (0, H - c), (0, c), (c, 0)]


# glyph: (paths, dots, width)   paths: list of polylines; dots: list of (x, y) discs; width: centre-line width
def G(paths, w=W, dots=()):
    return {"paths": paths, "dots": list(dots), "w": w}


GLYPHS = {
    "A": G([[(0, H), (0, 1.0), (1.0, 0), (W - 1.0, 0), (W, 1.0), (W, H)], [(0, M + 0.35), (W, M + 0.35)]]),
    "B": G([[(0, 0), (0, H)],
            [(0, 0), (2.6, 0), (W, 0.9), (W, 1.7), (2.7, M), (0, M)],
            [(0, M), (2.7, M), (W, M + 0.85), (W, H - 0.9), (2.6, H), (0, H)]]),
    "C": G([[(W, 1.0), (W - 1.0, 0), (1.0, 0), (0, 1.0), (0, H - 1.0), (1.0, H), (W - 1.0, H), (W, H - 1.0)]]),
    "D": G([[(0, 0), (0, H)], [(0, 0), (W - 1.2, 0), (W, 1.2), (W, H - 1.2), (W - 1.2, H), (0, H)]]),
    "E": G([[(W, 0), (0, 0), (0, H), (W, H)], [(0, M), (W - 0.6, M)]]),
    "F": G([[(W, 0), (0, 0), (0, H)], [(0, M), (W - 0.6, M)]]),
    "G": G([[(W, 1.0), (W - 1.0, 0), (1.0, 0), (0, 1.0), (0, H - 1.0), (1.0, H), (W - 1.0, H), (W, H - 1.0), (W, M + 0.3), (W - 1.5, M + 0.3)]]),
    "H": G([[(0, 0), (0, H)], [(W, 0), (W, H)], [(0, M), (W, M)]]),
    "I": G([[(0.8, 0), (0.8, H)], [(0, 0), (1.6, 0)], [(0, H), (1.6, H)]], w=1.6),
    "J": G([[(W, 0), (W, H - 1.0), (W - 1.0, H), (1.0, H), (0, H - 1.0)]]),
    "K": G([[(0, 0), (0, H)], [(W, 0), (0.2, M + 0.1)], [(1.0, M - 0.4), (W, H)]]),
    "L": G([[(0, 0), (0, H), (W, H)]]),
    "M": G([[(0, H), (0, 0), (2.2, 2.7), (4.4, 0), (4.4, H)]], w=4.4),
    "N": G([[(0, H), (0, 0), (W, H), (W, 0)]]),
    "O": G([o_shape(W)]),
    "P": G([[(0, H), (0, 0), (W - 1.0, 0), (W, 1.0), (W, M - 0.9), (W - 0.9, M), (0, M)]]),
    "Q": G([o_shape(W), [(2.0, H - 1.6), (W + 0.4, H + 0.4)]]),
    "R": G([[(0, H), (0, 0), (W - 1.0, 0), (W, 1.0), (W, M - 0.9), (W - 0.9, M), (0, M)], [(1.5, M), (W, H)]]),
    "S": G([[(W, 1.0), (W - 1.0, 0), (1.0, 0), (0, 1.0), (0, M - 0.8), (0.9, M), (W - 0.9, M), (W, M + 0.8), (W, H - 1.0), (W - 1.0, H), (1.0, H), (0, H - 1.0)]]),
    "T": G([[(0, 0), (W, 0)], [(W / 2, 0), (W / 2, H)]]),
    "U": G([[(0, 0), (0, H - 1.0), (1.0, H), (W - 1.0, H), (W, H - 1.0), (W, 0)]]),
    "V": G([[(0, 0), (W / 2, H), (W, 0)]]),
    "W": G([[(0, 0), (1.0, H), (2.6, 1.7), (4.2, H), (5.2, 0)]], w=5.2),
    "X": G([[(0, 0), (W, H)], [(W, 0), (0, H)]]),
    "Y": G([[(0, 0), (W / 2, M), (W, 0)], [(W / 2, M), (W / 2, H)]]),
    "Z": G([[(0, 0), (W, 0), (0, H), (W, H)]]),
    # digits
    "0": G([o_shape(3.2)], w=3.2),
    "1": G([[(0.4, 1.1), (1.8, 0), (1.8, H)], [(0.4, H), (3.2, H)]], w=3.2),
    "2": G([[(0, 1.0), (1.0, 0), (W - 1.0, 0), (W, 1.0), (W, 2.0), (0, H), (W, H)]]),
    "3": G([[(0, 0.9), (1.0, 0), (W - 1.0, 0), (W, 1.0), (W, M - 0.9), (W - 0.9, M), (1.2, M)],
            [(W - 0.9, M), (W, M + 0.9), (W, H - 1.0), (W - 1.0, H), (1.0, H), (0, H - 0.9)]]),
    "4": G([[(W - 1.1, H), (W - 1.1, 0), (0, 3.5), (W, 3.5)]]),
    "5": G([[(W, 0), (0.15, 0), (0, 2.5)],
            [(0, 2.5), (0.9, 2.0), (W - 1.0, 2.0), (W, 3.0), (W, H - 1.0), (W - 1.0, H), (1.0, H), (0, H - 1.0)]]),
    "6": G([[(W - 0.2, 0.8), (W - 1.0, 0), (1.0, 0), (0, 1.0), (0, H - 1.0), (1.0, H), (W - 1.0, H), (W, H - 1.0), (W, M + 0.9), (W - 0.9, M), (1.0, M), (0, M + 0.9)]]),
    "7": G([[(0, 0), (W, 0), (1.2, H)]]),
    "8": G([[(1.0, 0), (W - 1.0, 0), (W, 0.9), (W, M - 0.9), (W - 0.9, M), (0.9, M), (0, M - 0.9), (0, 0.9), (1.0, 0)],
            [(0.9, M), (W - 0.9, M), (W, M + 0.9), (W, H - 1.0), (W - 1.0, H), (1.0, H), (0, H - 1.0), (0, M + 0.9), (0.9, M)]]),
    "9": G([[(0.2, H - 0.8), (1.0, H), (W - 1.0, H), (W, H - 1.0), (W, 1.0), (W - 1.0, 0), (1.0, 0), (0, 1.0), (0, M - 0.9), (0.9, M), (W - 1.0, M), (W, M - 0.9)]]),
    # punctuation
    ".": G([], w=0.0, dots=[(0, H)]),
    ",": G([[(0, H), (-0.5, H + 1.2)]], w=0.0, dots=[(0, H - 0.05)]),
    ":": G([], w=0.0, dots=[(0, 1.6), (0, H)]),
    ";": G([[(0, H), (-0.5, H + 1.2)]], w=0.0, dots=[(0, 1.6), (0, H - 0.05)]),
    "!": G([[(0, 0), (0, 3.4)]], w=0.0, dots=[(0, H)]),
    "?": G([[(0, 1.0), (1.0, 0), (W - 1.0, 0), (W, 1.0), (W, 1.9), (W / 2, M + 0.3), (W / 2, 3.4)]], dots=[(W / 2, H)]),
    "'": G([[(0, 0), (0, 1.5)]], w=0.0),
    '"': G([[(0, 0), (0, 1.5)], [(1.3, 0), (1.3, 1.5)]], w=1.3),
    "-": G([[(0, M), (W - 1.0, M)]], w=W - 1.0),
    "+": G([[(0, M), (W - 0.6, M)], [(1.5, M - 1.5), (1.5, M + 1.5)]], w=W - 0.6),
    "=": G([[(0, M - 0.85), (W - 0.6, M - 0.85)], [(0, M + 0.85), (W - 0.6, M + 0.85)]], w=W - 0.6),
    "/": G([[(0, H), (W - 0.4, 0)]], w=W - 0.4),
    "\\": G([[(0, 0), (W - 0.4, H)]], w=W - 0.4),
    "%": G([ring(0.7, 0.9, 0.7, 0.9, 12), ring(W - 0.7, H - 0.9, 0.7, 0.9, 12), [(0.2, H), (W - 0.2, 0)]]),
    "#": G([[(1.0, 0.2), (0.6, H - 0.2)], [(2.6, 0.2), (2.2, H - 0.2)], [(0, 1.7), (W, 1.7)], [(-0.2, 3.4), (W - 0.2, 3.4)]]),
    "(": G([[(1.0, -0.1), (0, 1.2), (0, H - 1.2), (1.0, H + 0.1)]], w=1.0),
    ")": G([[(0, -0.1), (1.0, 1.2), (1.0, H - 1.2), (0, H + 0.1)]], w=1.0),
    "[": G([[(1.0, 0), (0, 0), (0, H), (1.0, H)]], w=1.0),
    "]": G([[(0, 0), (1.0, 0), (1.0, H), (0, H)]], w=1.0),
    "<": G([[(W - 1.0, 0.4), (0, M), (W - 1.0, H - 0.4)]], w=W - 1.0),
    ">": G([[(0, 0.4), (W - 1.0, M), (0, H - 0.4)]], w=W - 1.0),
    "*": G([[(0, M - 1.0), (1.8, M + 1.0)], [(1.8, M - 1.0), (0, M + 1.0)], [(0.9, M - 1.4), (0.9, M + 1.4)]], w=1.8),
    "_": G([[(0, H + 0.6), (W, H + 0.6)]]),
    "|": G([[(0, -0.3), (0, H + 0.3)]], w=0.0),
    "~": G([[(0, M + 0.2), (0.9, M - 0.5), (1.9, M + 0.5), (2.8, M - 0.2)]], w=2.8),
    "×": G([[(0.2, M - 1.3), (2.8, M + 1.3)], [(2.8, M - 1.3), (0.2, M + 1.3)]], w=3.0),
    "°": G([ring(0.9, 0.9, 0.9, 0.9, 14)], w=1.8),
    "·": G([], w=0.0, dots=[(0, M)]),
    "–": G([[(0, M), (W, M)]]),
    "—": G([[(0, M), (W + 1.4, M)]], w=W + 1.4),
    "…": G([], w=2.4, dots=[(0, H), (1.2, H), (2.4, H)]),
    "’": G([[(0, 0), (0, 1.5)]], w=0.0),
}
ALIASES = {"‘": "’", "“": '"', "”": '"'}


def glyph_polygon(g):
    """Thickens a glyph definition into a merged polygon in font units (y up, baseline 0)."""
    shapes = []
    r = STROKE / 2.0
    for path in g["paths"]:
        if len(path) < 2:
            continue
        shapes.append(LineString(path).buffer(r, quad_segs=8, cap_style=1, join_style=1))
    for (x, y) in g["dots"]:
        shapes.append(Point(x, y).buffer(r * 1.22, quad_segs=8))
    if not shapes:
        return None
    poly = unary_union(shapes)
    # grid (y down, centre-line box starting at 0,0)  ->  font units (y up, baseline at outer bottom)
    def to_font(x, y):
        return ((x + SIDE + r) * S, (H + r - y) * S)
    out = []
    geoms = list(poly.geoms) if isinstance(poly, MultiPolygon) else [poly]
    for p in geoms:
        ext = [to_font(x, y) for x, y in p.exterior.coords]
        holes = [[to_font(x, y) for x, y in h.coords] for h in p.interiors]
        out.append(orient(Polygon(ext, holes), sign=-1.0))
    return out


def polygon_to_glyph(polys):
    pen = TTGlyphPen(None)
    xs = []
    for p in polys:
        for ringpts in [list(p.exterior.coords)] + [list(h.coords) for h in p.interiors]:
            pts = []
            for (x, y) in ringpts[:-1]:
                q = (int(round(x)), int(round(y)))
                if not pts or pts[-1] != q:
                    pts.append(q)
            if len(pts) > 1 and pts[0] == pts[-1]:
                pts.pop()
            if len(pts) < 3:
                continue
            pen.moveTo(pts[0])
            for q in pts[1:]:
                pen.lineTo(q)
            pen.closePath()
            xs.extend(q[0] for q in pts)
    return pen.glyph(), (min(xs) if xs else 0), (max(xs) if xs else 0)


def build(path):
    names = [".notdef", "space"]
    glyphs = {}
    metrics = {}
    cmap = {32: "space"}
    # .notdef: an outlined box
    box = Polygon([(60, 0), (60, 700), (540, 700), (540, 0)], [[(120, 60), (480, 60), (480, 640), (120, 640)]])
    box = orient(box, sign=-1.0)
    g, x0, x1 = polygon_to_glyph([box])
    glyphs[".notdef"] = g
    metrics[".notdef"] = (600, 60)
    glyphs["space"] = TTGlyphPen(None).glyph()
    metrics["space"] = (int(0.9 * S * 1.6), 0)

    def add(ch, definition, target_name):
        polys = glyph_polygon(definition)
        if polys is None:
            return
        glyph, xmin, xmax = polygon_to_glyph(polys)
        adv = int(round((definition["w"] + STROKE + 2 * SIDE) * S))
        if target_name not in glyphs:
            names.append(target_name)
            glyphs[target_name] = glyph
            metrics[target_name] = (adv, xmin)

    for ch, definition in GLYPHS.items():
        name = "uni%04X" % ord(ch)
        add(ch, definition, name)
        cmap[ord(ch)] = name
        if ch.isupper():
            cmap[ord(ch.lower())] = name          # small letters share the capital forms
    for alias, source in ALIASES.items():
        cmap[ord(alias)] = "uni%04X" % ord(source)

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({n: glyphs[n] for n in names})
    fb.setupHorizontalMetrics({n: metrics[n] for n in names})
    fb.setupHorizontalHeader(ascent=820, descent=-220)
    fb.setupNameTable({
        "familyName": "Spire Display",
        "styleName": "Regular",
        "uniqueFontIdentifier": "SpireDisplay-Regular-1.0",
        "fullName": "Spire Display Regular",
        "psName": "SpireDisplay-Regular",
        "version": "Version 1.0",
        "copyright": "Created for Spire Sprint (generated by tools/gen_font.py).",
        "licenseDescription": "Original artwork made for the Spire Sprint project.",
    })
    fb.setupOS2(sTypoAscender=820, sTypoDescender=-220, sTypoLineGap=0, usWinAscent=920, usWinDescent=260,
                sxHeight=int(6.0 * S), sCapHeight=int(6.0 * S), achVendID="SPIR", fsType=0)
    fb.setupPost(keepGlyphNames=False)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fb.save(path)
    return len(names)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    ap.add_argument("--out", default=os.path.join(root, "assets", "fonts", "spire_display.ttf"))
    a = ap.parse_args()
    n = build(a.out)
    print("wrote %s (%d glyphs, %d bytes)" % (a.out, n, os.path.getsize(a.out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
