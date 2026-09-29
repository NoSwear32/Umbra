"""
A small 2D character rig for the 128x128 sprite-sheet frames.

  * `Frame`  - a supersampled premultiplied-alpha canvas with outlined, cel-shaded "parts".
  * `Rig`    - the pose transform (squash / stretch about the feet, lean, offset) and 2-bone
               limb solving, so every animation is described by a handful of numbers.

All coordinates are in frame units (0..128, y down, feet on y = 120, character faces RIGHT).
The character's centre line is x = 64, which is also the sprite anchor used by the game, so
mirroring the sprite for left-facing movement stays centred.
"""
import math

import numpy as np
from PIL import Image, ImageDraw

from .tile import darken, lighten, mix

FRAME = 128
SS = 4
PIVOT = (64.0, 120.0)


def _circle_pts(cx, cy, r, n=24):
    return [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


class Frame:
    def __init__(self, ss=SS):
        self.ss = ss
        self.S = FRAME * ss
        self.rgb = np.zeros((self.S, self.S, 3), np.float32)
        self.a = np.zeros((self.S, self.S), np.float32)

    # ------------------------------------------------------------------ masks
    def mask(self, polys):
        img = Image.new("L", (self.S, self.S), 0)
        d = ImageDraw.Draw(img)
        for pts in polys:
            d.polygon([(x * self.ss, y * self.ss) for x, y in pts], fill=255)
        return np.asarray(img, np.float32) / 255.0

    def shift(self, m, dx, dy):
        sx, sy = int(round(dx * self.ss)), int(round(dy * self.ss))
        out = np.zeros_like(m)
        h, w = m.shape
        ys, yd = (slice(max(0, sy), h), slice(0, h - max(0, sy))) if sy >= 0 else (slice(0, h + sy), slice(-sy, h))
        xs, xd = (slice(max(0, sx), w), slice(0, w - max(0, sx))) if sx >= 0 else (slice(0, w + sx), slice(-sx, w))
        out[ys, xs] = m[yd, xd]
        return out

    def dilate(self, m, r):
        out = m.copy()
        for ring, n in ((1.0, 14), (0.55, 8)):
            rr = r * ring
            for i in range(n):
                a = 2 * math.pi * i / n
                out = np.maximum(out, self.shift(m, rr * math.cos(a), rr * math.sin(a)))
        return out

    # ------------------------------------------------------------------ compositing
    def over(self, m, color, alpha=1.0):
        a = (m * alpha).astype(np.float32)
        self.rgb = np.asarray(color, np.float32)[None, None, :] * a[..., None] + self.rgb * (1.0 - a[..., None])
        self.a = a + self.a * (1.0 - a)

    def part(self, polys, fill, outline=None, ow=1.5, shade=0.5, light=0.35, clip=None):
        """Outlined, cel-shaded shape. Returns its mask (for clipping details into it)."""
        m = self.mask(polys)
        if clip is not None:
            m = m * clip
        if outline is not None:
            self.over(self.dilate(m, ow), outline)
        self.over(m, fill)
        if shade:
            lit = self.shift(m, -2.2, -2.2)
            self.over(np.clip(m - lit, 0, 1), darken(fill, 0.32), shade)
        if light:
            low = self.shift(m, 2.0, 2.6)
            self.over(np.clip(m - low, 0, 1), lighten(fill, 0.4), light)
        return m

    def detail(self, polys, color, alpha=1.0, clip=None):
        m = self.mask(polys)
        if clip is not None:
            m = m * clip
        self.over(m, color, alpha)
        return m

    def stroke(self, pts, width, color, alpha=1.0, clip=None):
        """A polyline as a thick smooth line."""
        img = Image.new("L", (self.S, self.S), 0)
        d = ImageDraw.Draw(img)
        p = [(x * self.ss, y * self.ss) for x, y in pts]
        w = max(1, int(round(width * self.ss)))
        d.line(p, fill=255, width=w, joint="curve")
        r = width * self.ss / 2.0
        for (x, y) in (p[0], p[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
        m = np.asarray(img, np.float32) / 255.0
        if clip is not None:
            m = m * clip
        self.over(m, color, alpha)
        return m

    def glow(self, cx, cy, r, color, alpha=1.0):
        yy, xx = np.mgrid[0:self.S, 0:self.S]
        d = np.sqrt((xx / self.ss - cx) ** 2 + (yy / self.ss - cy) ** 2) / max(r, 1e-6)
        self.over((np.clip(1.0 - d, 0.0, 1.0) ** 2).astype(np.float32), color, alpha)

    # ------------------------------------------------------------------ output
    def to_image(self):
        p = self.rgb.reshape(FRAME, self.ss, FRAME, self.ss, 3).mean(axis=(1, 3))
        a = self.a.reshape(FRAME, self.ss, FRAME, self.ss).mean(axis=(1, 3))
        rgb = np.where(a[..., None] > 1e-5, p / np.maximum(a[..., None], 1e-5), 0.0)
        # colour bleed under transparent pixels so bilinear filtering never shows dark fringes
        out = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], axis=2)
        img = Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")
        return img


class Rig:
    """Pose transform: squash/stretch about the feet, lean, offset."""

    def __init__(self, pose):
        self.sx = pose.get("sx", 1.0)
        self.sy = pose.get("sy", 1.0)
        r = math.radians(pose.get("rot", 0.0))
        self.c, self.s = math.cos(r), math.sin(r)
        self.dx = pose.get("dx", 0.0)
        self.dy = pose.get("dy", 0.0)
        self.scale = (self.sx + self.sy) * 0.5

    def T(self, p):
        x = (p[0] - PIVOT[0]) * self.sx
        y = (p[1] - PIVOT[1]) * self.sy
        return (PIVOT[0] + x * self.c - y * self.s + self.dx, PIVOT[1] + x * self.s + y * self.c + self.dy)

    def poly(self, pts):
        return [self.T(p) for p in pts]

    def ell(self, cx, cy, rx, ry, rot=0.0, n=32):
        c, s = math.cos(rot), math.sin(rot)
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            x, y = rx * math.cos(a), ry * math.sin(a)
            pts.append(self.T((cx + x * c - y * s, cy + x * s + y * c)))
        return pts

    def circle(self, cx, cy, r, n=24):
        return self.ell(cx, cy, r, r, 0.0, n)

    def capsule(self, p0, r0, p1, r1):
        """A tapered limb segment (list of polygons in frame space)."""
        (x0, y0), (x1, y1) = p0, p1
        dx, dy = x1 - x0, y1 - y0
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        quad = [(x0 + nx * r0, y0 + ny * r0), (x1 + nx * r1, y1 + ny * r1), (x1 - nx * r1, y1 - ny * r1), (x0 - nx * r0, y0 - ny * r0)]
        return [self.poly(quad), self.ell(x0, y0, r0, r0), self.ell(x1, y1, r1, r1)]

    def tri(self, a, b, c):
        return [self.poly([a, b, c])]


def ik2(hip, foot, l1, l2, side=1.0):
    """Two-bone IK: returns the knee/elbow position. side=+1 bends towards +x."""
    dx, dy = foot[0] - hip[0], foot[1] - hip[1]
    d = math.hypot(dx, dy)
    d = max(min(d, l1 + l2 - 0.05), abs(l1 - l2) + 0.05)
    a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    ux, uy = dx / (math.hypot(dx, dy) or 1.0), dy / (math.hypot(dx, dy) or 1.0)
    mx, my = hip[0] + ux * a, hip[1] + uy * a
    return (mx + side * uy * h, my - side * ux * h)


def bezier(p0, p1, p2, p3, n=12):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def ribbon(spine, w0, w1):
    """Polygon around a polyline with tapering width (for tails, wisps, flames)."""
    n = len(spine)
    left, right = [], []
    for i, (x, y) in enumerate(spine):
        a = spine[max(i - 1, 0)]
        b = spine[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        w = w0 + (w1 - w0) * i / max(n - 1, 1)
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]
