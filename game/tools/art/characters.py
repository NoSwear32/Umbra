"""
The seven playable characters. All of them are drawn by the same rig (rig.py) with the same
poses (poses.py); a character is just a palette plus a few overrides for the parts that make
it unique (tail, ears, hat, eyes ...).

Sheet layout (must match CharacterDef in the game): 768 x 1280 px, 128 x 128 frames,
one ROW per animation in the order of poses.ANIMS, one COLUMN per frame.
"""
import math
import os

import numpy as np
from PIL import Image

from .poses import ANIMS, HIP, SHOULDER, pose_for
from .rig import FRAME, Frame, Rig, bezier, ik2, ribbon
from .tile import darken, hex_color, lighten, mix

OUTLINE = hex_color("2a1a26")
# The whole figure is drawn this much higher than the pose numbers say, so that the outer edge
# of the soles ends up exactly on y = 120 (the sprite anchor = the platform surface).
BASE_DY = -1.5
WHITE = (1.0, 1.0, 1.0)


def rrect_pts(cx, cy, hw, hh, r, n=6):
    """Rounded rectangle as a polygon (centre, half sizes, corner radius)."""
    pts = []
    for (ox, oy, a0) in ((cx + hw - r, cy - hh + r, -90.0), (cx + hw - r, cy + hh - r, 0.0),
                         (cx - hw + r, cy + hh - r, 90.0), (cx - hw + r, cy - hh + r, 180.0)):
        for i in range(n + 1):
            a = math.radians(a0 + 90.0 * i / n)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def spine_poly(spine, widths):
    """Outline polygon around a polyline with per-point half widths."""
    n = len(spine)
    left, right = [], []
    for i, (x, y) in enumerate(spine):
        a = spine[max(i - 1, 0)]
        b = spine[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        left.append((x + nx * widths[i], y + ny * widths[i]))
        right.append((x - nx * widths[i], y - ny * widths[i]))
    return left + right[::-1], left, right


def rot_pt(p, o, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    x, y = p[0] - o[0], p[1] - o[1]
    return (o[0] + x * c - y * s, o[1] + x * s + y * c)


class Character:
    """Shared drawing pipeline. Subclasses override the hooks marked (hook)."""

    id = "base"
    # palette
    main = hex_color("ff8c42")
    light = hex_color("ffe2b8")
    dark = hex_color("c95a1e")
    outline = OUTLINE
    accent = hex_color("21c4c4")
    accent2 = hex_color("ffd54a")
    eye_c = hex_color("2b1b12")
    limb_front = None          # defaults to `main`
    limb_back = None           # defaults to a darker `main`
    glove = hex_color("5b2a17")
    shoe = hex_color("5b2a17")
    # geometry
    head_c0 = (66.0, 50.0)
    head_r = (22.0, 19.0)
    torso = (64.0, 86.0, 17.0, 19.0)
    thigh = (5.4, 4.6)
    arm_r = (4.2, 3.4)
    leg_len = 12.5
    arm_len = 10.5
    has_legs = True
    ow = 1.5

    def __init__(self):
        self.limb_front = self.limb_front or self.main
        self.limb_back = self.limb_back or darken(self.main, 0.18)

    # ------------------------------------------------------------------ pipeline
    GROUNDED = ("idle", "run", "accel", "wall", "land", "near_fall", "gameover")

    def render(self, anim, index):
        """Renders one frame: pose -> ground contact fix -> draw -> keep inside the frame."""
        pose = pose_for(anim, index)
        pose["dy"] += BASE_DY
        if anim in self.GROUNDED:
            # rotation / lean must never push a foot through the floor
            R = Rig(pose)
            lowest = max(R.T(pose["foot_f"])[1], R.T(pose["foot_b"])[1]) if self.has_legs else 118.5
            if lowest > 118.5:
                pose["dy"] -= lowest - 118.5
        img = self._draw_pose(anim, index, pose)
        for _ in range(3):
            alpha = img.getchannel("A").point(lambda v: 255 if v > 40 else 0)
            x0, y0, x1, y1 = alpha.getbbox()
            ddx = ddy = 0.0
            if y0 < 2:
                ddy += 2 - y0
            if x1 > 126:
                ddx -= x1 - 126
            if x0 < 1:
                ddx += 1 - x0
            if y1 > 126 and anim not in self.GROUNDED:
                ddy -= y1 - 126
            if ddx == 0.0 and ddy == 0.0:
                break
            pose["dx"] += ddx
            pose["dy"] += ddy
            img = self._draw_pose(anim, index, pose)
        return img

    def _draw_pose(self, anim, index, pose):
        self.cur = (anim, index)
        self.pose = pose
        F = Frame()
        R = Rig(pose)
        hc = self.head_center(pose)
        self.draw_back(F, R, pose, hc)
        self.draw_arm(F, R, pose, back=True)
        if self.has_legs:
            self.draw_leg(F, R, pose, back=True)
        torso_mask = self.draw_torso(F, R, pose)
        self.draw_head(F, R, pose, hc)
        self.draw_face(F, R, pose, hc)
        if self.has_legs:
            self.draw_leg(F, R, pose, back=False)
        self.draw_scarf_knot(F, R, pose, hc)
        self.draw_extras(F, R, pose, hc, torso_mask)
        self.draw_arm(F, R, pose, back=False)
        self.draw_fx(F, R, pose, hc)
        return F.to_image()

    def head_center(self, pose):
        hx, hy, _ = pose["head"]
        return (self.head_c0[0] + hx, self.head_c0[1] + hy)

    # ------------------------------------------------------------------ hooks
    def draw_back(self, F, R, pose, hc):
        pass

    def draw_extras(self, F, R, pose, hc, torso_mask):
        pass

    def head_polys(self, R, hc):
        return [R.ell(hc[0], hc[1], self.head_r[0], self.head_r[1])]

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        pass

    def draw_head_behind(self, F, R, pose, hc):
        pass

    def torso_polys(self, R):
        cx, cy, rx, ry = self.torso
        return [R.ell(cx, cy, rx, ry)]

    def draw_torso_extras(self, F, R, torso_mask):
        pass

    def draw_muzzle(self, F, R, pose, hc):
        pass

    # ------------------------------------------------------------------ parts
    def draw_torso(self, F, R, pose):
        m = F.part(self.torso_polys(R), self.main, self.outline, self.ow)
        self.draw_torso_extras(F, R, m)
        return m

    def draw_head(self, F, R, pose, hc):
        self.draw_head_behind(F, R, pose, hc)
        m = F.part(self.head_polys(R, hc), self.main, self.outline, self.ow)
        self.draw_head_extras(F, R, pose, hc, m)

    def leg_points(self, pose, back):
        foot = pose["foot_b"] if back else pose["foot_f"]
        hip = (HIP[0] - 3.0, HIP[1]) if back else (HIP[0] + 3.0, HIP[1])
        knee = ik2(hip, foot, self.leg_len, self.leg_len, side=1.0)
        return hip, knee, foot

    def draw_leg(self, F, R, pose, back):
        hip, knee, foot = self.leg_points(pose, back)
        col = self.limb_back if back else self.limb_front
        polys = R.capsule(hip, self.thigh[0], knee, self.thigh[1]) + R.capsule(knee, self.thigh[1], foot, self.thigh[1] - 0.8)
        F.part(polys, col, self.outline, self.ow)
        self.draw_shoe(F, R, foot, back)

    def draw_shoe(self, F, R, foot, back):
        col = darken(self.shoe, 0.12) if back else self.shoe
        F.part([R.ell(foot[0] + 3.0, foot[1] - 5.4, 9.0, 5.4)], col, self.outline, self.ow, shade=0.4)

    def arm_points(self, pose, back):
        hand = pose["hand_b"] if back else pose["hand_f"]
        sh = (SHOULDER[0] - 3.0, SHOULDER[1] + 1.0) if back else (SHOULDER[0] + 2.0, SHOULDER[1])
        elbow = ik2(sh, hand, self.arm_len, self.arm_len, side=-1.0)
        return sh, elbow, hand

    def draw_arm(self, F, R, pose, back):
        sh, elbow, hand = self.arm_points(pose, back)
        col = self.limb_back if back else self.limb_front
        polys = R.capsule(sh, self.arm_r[0], elbow, self.arm_r[1]) + R.capsule(elbow, self.arm_r[1], hand, self.arm_r[1] - 0.3)
        F.part(polys, col, self.outline, self.ow, shade=0.4)
        self.draw_hand(F, R, hand, back)

    def draw_hand(self, F, R, hand, back):
        col = darken(self.glove, 0.12) if back else self.glove
        F.part([R.circle(hand[0], hand[1], 4.6)], col, self.outline, self.ow, shade=0.4)

    def draw_scarf_knot(self, F, R, pose, hc):
        """The scarf itself is animated by the game; this is only the knot at the neck."""
        c = (hc[0] - 7.0, hc[1] + 17.0)
        F.part([R.ell(c[0], c[1], 8.5, 6.0, -0.35)], self.accent, self.outline, 1.2, shade=0.4)
        F.detail([R.ell(c[0] - 1.0, c[1] + 0.5, 6.0, 1.8, -0.35)], self.accent2, 0.9)

    # ------------------------------------------------------------------ face
    def eye_center(self, hc, near=True):
        return (hc[0] + (6.0 if near else 18.0), hc[1] - 3.0 + (0.0 if near else -0.5))

    def draw_face(self, F, R, pose, hc):
        self.draw_muzzle(F, R, pose, hc)
        kind = pose["eye"]
        for near in (False, True):
            ex, ey = self.eye_center(hc, near)
            r = 1.0 if near else 0.86
            self.draw_eye(F, R, ex, ey, r, kind)
        self.draw_mouth(F, R, hc, pose["mouth"])

    def draw_eye(self, F, R, ex, ey, s, kind):
        ink = self.eye_c
        if kind in ("open", "wide", "determined"):
            big = 1.18 if kind == "wide" else 1.0
            sclera = F.detail([R.ell(ex, ey, 4.6 * s * big, 5.6 * s * big)], WHITE)
            F.detail([R.ell(ex + 0.9, ey + 0.4, 3.3 * s * (0.62 if kind == "wide" else 1.0) * big, 4.4 * s * (0.62 if kind == "wide" else 1.0) * big)], ink)
            F.detail([R.circle(ex + 0.2, ey - 1.6, 1.25 * s)], WHITE)
            F.stroke([R.T((ex - 4.6 * s, ey - 0.5)), R.T((ex - 3.0 * s, ey - 4.6 * s)), R.T((ex, ey - 5.7 * s)), R.T((ex + 3.0 * s, ey - 4.6 * s)), R.T((ex + 4.6 * s, ey - 0.5))], 0.9, self.outline, 0.85)
            if kind == "determined":
                # a heavy lid slanting down towards the nose, clipped to the eye itself
                F.detail([R.poly([(ex - 6.0 * s, ey - 8.0 * s), (ex + 6.0 * s, ey - 3.2 * s), (ex + 6.0 * s, ey - 9.0 * s)])], self.main, 1.0, clip=sclera)
                F.stroke([R.T((ex - 5.0 * s, ey - 6.0 * s)), R.T((ex + 5.0 * s, ey - 2.6 * s))], 1.4, self.outline, 0.95)
        elif kind == "blink":
            F.stroke([R.T((ex - 4.2 * s, ey)), R.T((ex, ey + 1.6 * s)), R.T((ex + 4.2 * s, ey))], 1.5, self.outline)
        elif kind == "happy":
            F.stroke([R.T((ex - 4.2 * s, ey + 1.6 * s)), R.T((ex, ey - 2.2 * s)), R.T((ex + 4.2 * s, ey + 1.6 * s))], 1.7, self.outline)
        elif kind == "x":
            F.stroke([R.T((ex - 3.6 * s, ey - 3.6 * s)), R.T((ex + 3.6 * s, ey + 3.6 * s))], 1.6, self.outline)
            F.stroke([R.T((ex + 3.6 * s, ey - 3.6 * s)), R.T((ex - 3.6 * s, ey + 3.6 * s))], 1.6, self.outline)

    def mouth_center(self, hc):
        return (hc[0] + 16.0, hc[1] + 10.0)

    def draw_mouth(self, F, R, hc, kind):
        mx, my = self.mouth_center(hc)
        ink = self.outline
        if kind == "smile":
            F.stroke([R.T((mx - 4.0, my - 0.5)), R.T((mx - 1.0, my + 2.0)), R.T((mx + 3.5, my + 0.6)), R.T((mx + 5.0, my - 1.2))], 1.3, ink)
        elif kind == "open":
            F.detail([R.ell(mx + 0.5, my + 1.0, 3.8, 3.2)], darken(ink, 0.2))
            F.detail([R.ell(mx + 0.5, my + 2.6, 2.4, 1.3)], hex_color("ff7a8a"), 0.95)
        elif kind == "o":
            F.detail([R.ell(mx + 0.5, my + 1.5, 2.5, 3.4)], darken(ink, 0.2))
            F.detail([R.ell(mx + 0.5, my + 3.0, 1.5, 1.2)], hex_color("ff7a8a"), 0.9)
        elif kind == "grit":
            F.detail([R.poly([(mx - 4.5, my - 1.0), (mx + 5.0, my - 1.6), (mx + 4.6, my + 3.2), (mx - 4.0, my + 3.4)])], darken(ink, 0.2))
            F.detail([R.poly([(mx - 3.6, my - 0.4), (mx + 4.2, my - 0.9), (mx + 4.0, my + 1.5), (mx - 3.2, my + 1.6)])], WHITE, 0.95)
            F.stroke([R.T((mx - 0.2, my - 0.8)), R.T((mx - 0.2, my + 1.6))], 0.6, ink, 0.7)
        elif kind == "flat":
            F.stroke([R.T((mx - 3.5, my + 0.5)), R.T((mx + 4.0, my))], 1.3, ink)
        elif kind == "tongue":
            F.detail([R.ell(mx + 0.5, my + 1.5, 3.6, 3.0)], darken(ink, 0.2))
            F.detail([R.ell(mx + 1.5, my + 5.0, 2.4, 3.4)], hex_color("ff7a8a"), 1.0)
            F.stroke([R.T((mx + 1.5, my + 3.0)), R.T((mx + 1.5, my + 6.0))], 0.6, darken(hex_color("ff7a8a"), 0.3), 0.8)

    # ------------------------------------------------------------------ effects
    def draw_fx(self, F, R, pose, hc):
        for fx in pose["fx"]:
            if fx == "dust_back":
                for k, (dx, dy, r) in enumerate(((-2.0, 0.0, 5.0), (-9.0, -3.0, 4.0), (-15.0, -8.0, 3.0))):
                    F.detail([R.circle(40.0 + dx, 117.0 + dy, r)], (1, 1, 1), 0.5 - 0.1 * k)
            elif fx == "dust_both":
                for sgn in (-1, 1):
                    for k, (dx, r) in enumerate(((10.0, 5.5), (18.0, 4.2), (25.0, 3.0))):
                        F.detail([R.circle(64.0 + sgn * (dx + 12.0), 117.0 - k * 2.0, r)], (1, 1, 1), 0.55 - 0.12 * k)
            elif fx == "speed":
                for (x0, y0, ln) in ((10.0, 60.0, 26.0), (6.0, 84.0, 34.0), (16.0, 104.0, 22.0), (14.0, 36.0, 20.0)):
                    F.stroke([(x0, y0), (x0 + ln, y0)], 1.8, (1, 1, 1), 0.6)
            elif fx == "impact":
                cx, cy = 99.0, 80.0
                for a in (-50.0, -20.0, 10.0, 40.0):
                    p0 = (cx + 4.0 * math.cos(math.radians(a)), cy + 4.0 * math.sin(math.radians(a)))
                    p1 = (cx + 14.0 * math.cos(math.radians(a)), cy + 14.0 * math.sin(math.radians(a)))
                    F.stroke([p0, p1], 2.0, hex_color("fff2a6"), 0.95)
            elif fx == "sweat":
                for (x, y) in ((hc[0] - 20.0, hc[1] - 6.0), (hc[0] + 24.0, hc[1] - 14.0)):
                    F.detail([R.ell(x, y, 2.4, 3.6)], hex_color("9ad1ff"), 0.95)
                    F.detail([R.poly([(x - 2.2, y - 1.0), (x + 2.2, y - 1.0), (x, y - 6.0)])], hex_color("9ad1ff"), 0.95)
            elif fx == "stars":
                for k in range(3):
                    a = k * 2.1 + 0.6
                    x = hc[0] + 2.0 + 20.0 * math.cos(a)
                    y = hc[1] - 21.0 + 5.0 * math.sin(a)
                    self.sparkle(F, x, y, 5.0, hex_color("fff2a6"))

    def sparkle(self, F, cx, cy, r, color):
        pts = []
        for i in range(8):
            rr = r if i % 2 == 0 else r * 0.3
            a = -math.pi / 2 + math.pi * i / 4
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        F.detail([pts], color)


# =========================================================================================
# Pip - a scrappy fox-kit courier
# =========================================================================================
class Pip(Character):
    id = "pip"
    main = hex_color("ff8c42")
    light = hex_color("ffe6c4")
    dark = hex_color("c95a1e")
    accent = hex_color("21c4c4")
    accent2 = hex_color("ffd54a")

    def draw_back(self, F, R, pose, hc):
        # bushy tail
        base = (52.0, 95.0)
        spine0 = bezier(base, (40.0, 101.0), (27.0, 92.0), (23.0, 70.0), 12)
        spine = [rot_pt(p, base, pose["tail"]) for p in spine0]
        widths = [4.0 + 7.5 * math.sin(math.pi * (i / 12.0) ** 0.85) for i in range(13)]
        outline, left, right = spine_poly(spine, widths)
        m = F.part([R.poly(outline)], self.main, self.outline, self.ow)
        tip = left[8:] + right[8:][::-1]
        F.detail([R.poly(tip)], self.light, 1.0, clip=m)
        # back ear
        self.draw_ear(F, R, pose, hc, back=True)

    def ear_tip(self, hc, pose, back):
        e = pose["ears"]
        tx = (-15.0 if back else 15.0) + hc[0]
        ty = hc[1] - 33.0
        tx += -2.2 * max(-e, 0.0) + 0.6 * max(e, 0.0) * (1 if not back else -1)
        ty += -1.6 * max(e, 0.0) + 2.6 * max(-e, 0.0)
        return (tx, ty)

    def draw_ear(self, F, R, pose, hc, back):
        tip = self.ear_tip(hc, pose, back)
        if back:
            a, b = (hc[0] - 15.0, hc[1] - 8.0), (hc[0] - 2.0, hc[1] - 16.0)
        else:
            a, b = (hc[0] + 2.0, hc[1] - 16.0), (hc[0] + 17.0, hc[1] - 7.0)
        col = darken(self.main, 0.12) if back else self.main
        m = F.part([R.poly([a, tip, b])], col, self.outline, self.ow)
        inner_tip = ((a[0] + b[0]) / 2 * 0.45 + tip[0] * 0.55, (a[1] + b[1]) / 2 * 0.45 + tip[1] * 0.55 + 1.0)
        ia = (a[0] * 0.7 + b[0] * 0.3, a[1] * 0.7 + b[1] * 0.3 + 1.0)
        ib = (a[0] * 0.3 + b[0] * 0.7, a[1] * 0.3 + b[1] * 0.7 + 1.0)
        F.detail([R.poly([ia, inner_tip, ib])], hex_color("ffb0a0") if not back else darken(hex_color("ffb0a0"), 0.2), 0.95, clip=m)
        # dark tip
        d = (tip[0] * 0.75 + (a[0] + b[0]) / 2 * 0.25, tip[1] * 0.75 + (a[1] + b[1]) / 2 * 0.25)
        F.detail([R.poly([((a[0] + tip[0]) / 2 * 0.5 + d[0] * 0.5, (a[1] + tip[1]) / 2 * 0.5 + d[1] * 0.5), tip, ((b[0] + tip[0]) / 2 * 0.5 + d[0] * 0.5, (b[1] + tip[1]) / 2 * 0.5 + d[1] * 0.5)])], self.glove, 0.95, clip=m)

    def draw_torso_extras(self, F, R, m):
        F.detail([R.ell(69.0, 90.0, 10.5, 14.0)], self.light, 1.0, clip=m)

    def draw_head_behind(self, F, R, pose, hc):
        pass

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        # cream cheeks / lower face
        F.detail([R.ell(hc[0] + 9.0, hc[1] + 9.0, 15.0, 10.0)], self.light, 1.0, clip=head_mask)
        # front ear
        self.draw_ear(F, R, pose, hc, back=False)

    def draw_muzzle(self, F, R, pose, hc):
        # snout in front of the cheeks, then the nose
        F.part([R.ell(hc[0] + 20.0, hc[1] + 6.0, 8.5, 6.4)], self.light, self.outline, 1.2, shade=0.3)
        F.part([R.ell(hc[0] + 26.5, hc[1] + 2.8, 3.4, 2.7)], self.glove, self.outline, 0.9, shade=0.0, light=0.0)
        F.detail([R.circle(hc[0] + 25.8, hc[1] + 1.8, 0.9)], (1, 1, 1), 0.9)
        # blush
        F.detail([R.ell(hc[0] - 1.0, hc[1] + 8.0, 4.2, 2.6)], hex_color("ff8a8a"), 0.5)

    def mouth_center(self, hc):
        return (hc[0] + 19.0, hc[1] + 11.5)


# =========================================================================================
# Sheets
# =========================================================================================
def render_sheet(char):
    sheet = Image.new("RGBA", (FRAME * 6, FRAME * len(ANIMS)), (0, 0, 0, 0))
    for row, (name, frames, fps, loop) in enumerate(ANIMS):
        for i in range(frames):
            sheet.paste(char.render(name, i), (i * FRAME, row * FRAME))
    return sheet


def contact_sheet(sheet, bg=(58, 64, 92)):
    """Sheet on a solid colour with a foot line, for reviewing."""
    from PIL import ImageDraw
    canvas = Image.new("RGBA", sheet.size, bg + (255,))
    d = ImageDraw.Draw(canvas)
    for row in range(len(ANIMS)):
        d.line([(0, row * FRAME + 120), (sheet.width, row * FRAME + 120)], fill=(255, 255, 255, 60))
        for col in range(6):
            d.rectangle([col * FRAME, row * FRAME, (col + 1) * FRAME - 1, (row + 1) * FRAME - 1], outline=(255, 255, 255, 25))
    canvas.alpha_composite(sheet)
    return canvas.convert("RGB")


def render_all(out_dir, preview_dir=None, only=None):
    from .cast import ALL
    for cls in ALL:
        if only and cls.id not in only:
            continue
        char = cls()
        sheet = render_sheet(char)
        assert sheet.size == (768, 1280)
        sheet.save(os.path.join(out_dir, char.id + ".png"), optimize=True)
        print("character %-8s done" % char.id)
        if preview_dir:
            contact_sheet(sheet).save(os.path.join(preview_dir, "char_%s.png" % char.id))
