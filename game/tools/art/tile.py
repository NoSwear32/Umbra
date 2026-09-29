"""
A tiny 2D vector-art engine on top of numpy + Pillow.

* Everything is composited in linear float space with PREMULTIPLIED alpha, so semi-transparent
  shapes over transparent pixels never leave dark fringes.
* Layers are rendered at `ss` times the final resolution and box-filtered down (anti-aliasing).
* `Tile` layers wrap around their borders: a shape that leaves on the right re-enters on the
  left, so backgrounds and wall strips tile seamlessly in both directions.
"""
import math

import numpy as np
from PIL import Image, ImageDraw


def hex_color(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def lighten(c, t):
    return mix(c, (1.0, 1.0, 1.0), t)


def darken(c, t):
    return mix(c, (0.0, 0.0, 0.0), t)


def blur_wrap(arr, sigma):
    """Circular gaussian blur (FFT). `arr` is HxW or HxWxC."""
    if sigma <= 0.05:
        return arr
    h, w = arr.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    kernel = np.exp(-2.0 * (np.pi ** 2) * (sigma ** 2) * (fx * fx + fy * fy))
    if arr.ndim == 2:
        return np.fft.irfft2(np.fft.rfft2(arr) * kernel, s=(h, w)).astype(np.float32)
    out = np.empty_like(arr)
    for c in range(arr.shape[2]):
        out[..., c] = np.fft.irfft2(np.fft.rfft2(arr[..., c]) * kernel, s=(h, w))
    return out


# ------------------------------------------------------------------------- primitive builders
# A "drawer" is f(draw, ox, oy, s): draw a shape into an 'L' mask with pixel offset (ox, oy)
# and scale s (design units -> pixels). Wrapping is done by calling it with 9 offsets.
def poly(pts):
    def f(d, ox, oy, s):
        d.polygon([(x * s + ox, y * s + oy) for x, y in pts], fill=255)
    return f


def ellipse(cx, cy, rx, ry, rot=0.0, n=40):
    pts = []
    c, sn = math.cos(rot), math.sin(rot)
    for i in range(n):
        a = 2.0 * math.pi * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        pts.append((cx + x * c - y * sn, cy + x * sn + y * c))
    return poly(pts)


def circle(cx, cy, r):
    def f(d, ox, oy, s):
        d.ellipse([(cx - r) * s + ox, (cy - r) * s + oy, (cx + r) * s + ox, (cy + r) * s + oy], fill=255)
    return f


def rect(x0, y0, x1, y1):
    def f(d, ox, oy, s):
        d.rectangle([x0 * s + ox, y0 * s + oy, x1 * s + ox, y1 * s + oy], fill=255)
    return f


def rrect(x0, y0, x1, y1, r):
    def f(d, ox, oy, s):
        d.rounded_rectangle([x0 * s + ox, y0 * s + oy, x1 * s + ox, y1 * s + oy], radius=r * s, fill=255)
    return f


def line(pts, width, round_caps=True):
    def f(d, ox, oy, s):
        p = [(x * s + ox, y * s + oy) for x, y in pts]
        d.line(p, fill=255, width=max(1, int(round(width * s))), joint="curve")
        if round_caps:
            r = width * s / 2.0
            for (x, y) in (p[0], p[-1]):
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return f


def union(*fs):
    def f(d, ox, oy, s):
        for g in fs:
            g(d, ox, oy, s)
    return f


def star(cx, cy, r_out, r_in, points=5, rot=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = rot + math.pi * i / points
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return poly(pts)


def sparkle(cx, cy, r, thin=0.18):
    """Four-point sparkle."""
    pts = []
    for i in range(8):
        rr = r if i % 2 == 0 else r * thin
        a = -math.pi / 2 + math.pi * i / 4
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return poly(pts)


def gear(cx, cy, r, teeth, tooth_h, hole=0.0):
    pts = []
    n = teeth * 4
    for i in range(n):
        a = 2.0 * math.pi * i / n
        k = i % 4
        rr = r + tooth_h if k in (1, 2) else r
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    body = poly(pts)
    if hole <= 0:
        return body

    def f(d, ox, oy, s):
        body(d, ox, oy, s)
        d.ellipse([(cx - hole) * s + ox, (cy - hole) * s + oy, (cx + hole) * s + ox, (cy + hole) * s + oy], fill=0)
    return f


# --------------------------------------------------------------------------------- the layer
class Tile:
    def __init__(self, w, h, ss=2, wrap=True):
        self.w, self.h, self.ss, self.wrap = w, h, ss, wrap
        self.W, self.H = w * ss, h * ss
        self.p = np.zeros((self.H, self.W, 4), np.float32)   # premultiplied RGBA
        yy, xx = np.mgrid[0:self.H, 0:self.W]
        self._xx = (xx.astype(np.float32) + 0.5) / ss
        self._yy = (yy.astype(np.float32) + 0.5) / ss

    # -- compositing
    def over(self, mask, color, alpha=1.0):
        a = (mask * alpha).astype(np.float32)
        rgb = np.asarray(color, np.float32)[None, None, :] * a[..., None]
        self.p[..., :3] = rgb + self.p[..., :3] * (1.0 - a[..., None])
        self.p[..., 3] = a + self.p[..., 3] * (1.0 - a)

    def mask(self, drawer):
        m = Image.new("L", (self.W, self.H), 0)
        d = ImageDraw.Draw(m)
        offs = (-1, 0, 1) if self.wrap else (0,)
        for ix in offs:
            for iy in offs:
                drawer(d, ix * self.W, iy * self.H, self.ss)
        return np.asarray(m, np.float32) / 255.0

    def fill(self, drawer, color, alpha=1.0, blur=0.0, cut=None):
        m = self.mask(drawer)
        if cut is not None:
            m = m * (1.0 - self.mask(cut))
        if blur > 0:
            m = blur_wrap(m, blur * self.ss)
        self.over(m, color, alpha)
        return m

    def fill_masked(self, drawer, color, clip, alpha=1.0):
        """Fills `drawer` only where `clip` (a mask array) is set."""
        self.over(self.mask(drawer) * clip, color, alpha)

    def glow(self, cx, cy, r, color, alpha=1.0, power=2.0):
        dx = np.abs(self._xx - cx)
        dy = np.abs(self._yy - cy)
        if self.wrap:
            dx = np.minimum(dx, self.w - dx)
            dy = np.minimum(dy, self.h - dy)
        d = np.sqrt(dx * dx + dy * dy) / max(r, 1e-6)
        m = np.clip(1.0 - d, 0.0, 1.0) ** power
        self.over(m.astype(np.float32), color, alpha)

    def gradient_v(self, top, bottom, alpha=1.0, y0=0.0, y1=None):
        y1 = self.h if y1 is None else y1
        t = np.clip((self._yy - y0) / max(y1 - y0, 1e-6), 0.0, 1.0)[..., None]
        col = np.asarray(top, np.float32)[None, None, :] * (1 - t) + np.asarray(bottom, np.float32)[None, None, :] * t
        a = np.full((self.H, self.W), alpha, np.float32)
        self.p[..., :3] = col * a[..., None] + self.p[..., :3] * (1 - a[..., None])
        self.p[..., 3] = a + self.p[..., 3] * (1 - a)

    def stripe_shade(self, clip, color, alpha, fn):
        """Multiplies `fn(x, y)` (0..1) into a colour overlay clipped to `clip`."""
        m = fn(self._xx, self._yy).astype(np.float32) * clip
        self.over(m, color, alpha)

    # -- output
    def to_image(self):
        p = self.p.reshape(self.h, self.ss, self.w, self.ss, 4).mean(axis=(1, 3))
        a = p[..., 3]
        rgb = np.where(a[..., None] > 1e-5, p[..., :3] / np.maximum(a[..., None], 1e-5), 0.0)
        # bleed colours into transparent pixels (avoids dark fringes with texture filtering)
        if self.wrap:
            wa = blur_wrap(a, 2.0)
            wc = blur_wrap(p[..., :3], 2.0)
            bleed = wc / np.maximum(wa[..., None], 1e-4)
            rgb = np.where(a[..., None] > 0.02, rgb, np.where(wa[..., None] > 1e-4, bleed, 0.0))
        out = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], axis=2)
        return Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGBA")
