"""Mock screenshots of the theme textures (what BackdropView composes in the game)."""
import numpy as np
from PIL import Image, ImageDraw

from .tile import lighten


def compose_theme(pal, far, near, wall, width=1280, height=720, tower_w=640, cam=0.0):
    """Approximates BackdropView: gradient, far layer, near layer, tower panel, walls."""
    top = np.array(pal.bg_top) * 255.0
    bottom = np.array(pal.bg_bottom) * 255.0
    t = np.linspace(0.0, 1.0, height)[:, None, None]
    canvas = Image.fromarray((top * (1 - t) + bottom * t).astype(np.uint8).repeat(width, axis=1), "RGB").convert("RGBA")

    def tiled(img, factor, x, w, alpha):
        layer = Image.new("RGBA", (w, height), (0, 0, 0, 0))
        th = img.height
        off = int((height + cam * factor) % th) - th
        y = off
        while y < height:
            xx = 0
            while xx < w:
                layer.alpha_composite(img, (xx, y))
                xx += img.width
            y += th
        if alpha < 1.0:
            a = layer.getchannel("A").point(lambda v: int(v * alpha))
            layer.putalpha(a)
        canvas.alpha_composite(layer, (x, 0))

    left = (width - tower_w) // 2
    tiled(far, 0.22, 0, width, 0.9)
    tiled(near, 0.5, 0, width, 1.0)
    panel = Image.new("RGBA", (tower_w, height), (0, 0, 0, int(255 * pal.panel_alpha)))
    canvas.alpha_composite(panel, (left, 0))
    tiled(wall, 1.0, left - 64, 64, 1.0)
    right_wall = wall.transpose(Image.FLIP_LEFT_RIGHT)
    tiled(right_wall, 1.0, left + tower_w, 64, 1.0)
    # a few platforms drawn like PlatformView's default style, only to judge contrast
    d = ImageDraw.Draw(canvas)
    for i, (px, py, pw) in enumerate(((left + 40, 600, 220), (left + 300, 470, 180), (left + 120, 340, 200), (left + 380, 210, 190), (left + 60, 100, 160))):
        d.rounded_rectangle([px, py, px + pw, py + 24], 6, fill=tuple(int(c * 255) for c in pal.plat_body) + (255,))
        d.rounded_rectangle([px, py, px + pw, py + 9], 6, fill=tuple(int(c * 255) for c in pal.plat_top) + (255,))
    # the character-sized reference block (40 x 62 units)
    d.rounded_rectangle([left + 340, 408, left + 380, 470], 8, fill=tuple(int(c * 255) for c in pal.accent) + (255,))
    return canvas.convert("RGB")
