"""The other six characters (Pip lives in characters.py next to the shared pipeline)."""
import math

from .characters import Character, Pip, rrect_pts, rot_pt, spine_poly, WHITE
from .poses import HIP
from .rig import bezier
from .tile import darken, hex_color, lighten, mix


# =========================================================================================
# Bolt - a clockwork robot running on spare parts and optimism
# =========================================================================================
class Bolt(Character):
    id = "bolt"
    main = hex_color("5aa9ff")
    light = hex_color("cfe6ff")
    dark = hex_color("2f6fc0")
    accent = hex_color("ff5252")
    accent2 = hex_color("ffd54a")
    eye_c = hex_color("ffe45a")
    glove = hex_color("39435c")
    shoe = hex_color("39435c")
    limb_front = hex_color("b4c2da")
    limb_back = hex_color("8291ac")
    head_r = (21.0, 17.0)
    torso = (64.0, 86.0, 16.0, 18.0)
    thigh = (5.0, 4.4)
    arm_r = (4.0, 3.4)

    def head_polys(self, R, hc):
        return [R.poly(rrect_pts(hc[0], hc[1], 21.0, 17.0, 8.0))]

    def torso_polys(self, R):
        return [R.poly(rrect_pts(64.0, 86.0, 16.0, 18.0, 6.0))]

    def draw_back(self, F, R, pose, hc):
        # wind-up key on the back
        anim, idx = self.cur
        ang = {"idle": 25.0 * idx, "run": 60.0 * idx, "accel": 90.0 * idx}.get(anim, 20.0)
        c = (46.0, 84.0)
        F.part([R.poly(rrect_pts(52.0, 84.0, 6.0, 2.4, 1.0))], self.accent2, self.outline, 1.2, shade=0.3)
        for s in (-1, 1):
            p = rot_pt((c[0] - 2.0, c[1] + s * 7.0), c, ang)
            F.part([R.circle(p[0], p[1], 5.0)], self.accent2, self.outline, 1.2, shade=0.3)
        F.part([R.poly(rrect_pts(c[0] + 1.0, c[1], 2.4, 7.5, 1.0))], darken(self.accent2, 0.1), self.outline, 1.0, shade=0.0, light=0.0)

    def draw_head_behind(self, F, R, pose, hc):
        # antenna
        tilt = pose["ears"] * 1.5
        top = (hc[0] + 2.0 + tilt, hc[1] - 30.0)
        F.stroke([R.T((hc[0] + 2.0, hc[1] - 14.0)), R.T(top)], 2.4, self.outline)
        F.stroke([R.T((hc[0] + 2.0, hc[1] - 14.0)), R.T(top)], 1.2, self.limb_front)
        F.part([R.circle(top[0], top[1], 4.0)], self.accent, self.outline, 1.2, shade=0.4)
        F.detail([R.circle(top[0] - 1.2, top[1] - 1.4, 1.1)], WHITE, 0.9)

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        for sx in (-19.5, 19.0):
            F.part([R.circle(hc[0] + sx, hc[1] + 2.0, 4.2)], self.glove, self.outline, 1.2, shade=0.3)
        F.detail([R.poly(rrect_pts(hc[0] + 1.0, hc[1] - 12.5, 11.0, 2.2, 1.0))], self.light, 0.6, clip=head_mask)
        for rx in (-13.0, 15.0):
            F.detail([R.circle(hc[0] + rx, hc[1] - 12.5, 1.1)], self.dark, 0.9, clip=head_mask)

    def draw_torso_extras(self, F, R, m):
        F.detail([R.poly(rrect_pts(68.0, 86.0, 9.5, 10.5, 3.0))], self.light, 0.95, clip=m)
        F.detail([R.poly(rrect_pts(68.0, 86.0, 7.0, 8.0, 2.0))], self.dark, 0.55, clip=m)
        # lightning bolt emblem
        F.detail([R.poly([(70.0, 79.0), (65.0, 87.0), (68.5, 87.0), (66.0, 94.0), (73.0, 84.5), (69.5, 84.5)])], self.accent2, 1.0, clip=m)
        F.detail([R.poly(rrect_pts(64.0, 100.0, 16.0, 2.6, 1.0))], self.dark, 0.8, clip=m)
        for rx in (52.5, 75.5):
            F.detail([R.circle(rx, 72.0, 1.1)], self.light, 0.9, clip=m)

    def draw_shoe(self, F, R, foot, back):
        col = darken(self.shoe, 0.12) if back else self.shoe
        m = F.part([R.poly(rrect_pts(foot[0] + 3.0, foot[1] - 4.5, 9.5, 4.5, 2.5))], col, self.outline, self.ow, shade=0.4)
        F.detail([R.poly(rrect_pts(foot[0] + 3.0, foot[1] - 7.0, 8.0, 1.3, 0.6))], self.accent, 0.9, clip=m)

    def draw_hand(self, F, R, hand, back):
        col = darken(self.glove, 0.12) if back else self.glove
        F.part([R.circle(hand[0], hand[1], 4.6)], col, self.outline, self.ow, shade=0.4)
        F.detail([R.circle(hand[0] - 1.0, hand[1] - 1.2, 1.2)], self.light, 0.6)

    def draw_face(self, F, R, pose, hc):
        F.part([R.poly(rrect_pts(hc[0] + 3.5, hc[1] - 1.0, 18.5, 8.2, 4.5))], hex_color("1b2340"), self.outline, 1.2, shade=0.0, light=0.0)
        glow = self.eye_c
        kind = pose["eye"]
        for (ex, ey, s) in ((hc[0] + 5.0, hc[1] - 1.0, 1.0), (hc[0] + 16.0, hc[1] - 1.0, 0.9)):
            if kind in ("open", "determined"):
                F.detail([R.ell(ex, ey, 3.8 * s, 4.6 * s)], glow)
                F.detail([R.circle(ex - 0.8, ey - 1.6, 1.0 * s)], WHITE, 0.9)
                if kind == "determined":
                    F.detail([R.poly([(ex - 6.0, ey - 7.0), (ex + 6.0, ey - 2.4), (ex + 6.0, ey - 8.0)])], hex_color("1b2340"))
            elif kind == "wide":
                F.detail([R.ell(ex, ey, 4.8 * s, 5.8 * s)], glow)
                F.detail([R.circle(ex, ey, 1.4 * s)], hex_color("1b2340"))
            elif kind == "blink":
                F.stroke([R.T((ex - 3.8 * s, ey)), R.T((ex + 3.8 * s, ey))], 1.5, glow)
            elif kind == "happy":
                F.stroke([R.T((ex - 3.8 * s, ey + 1.6)), R.T((ex, ey - 2.2)), R.T((ex + 3.8 * s, ey + 1.6))], 1.7, glow)
            elif kind == "x":
                F.stroke([R.T((ex - 3.2, ey - 3.2)), R.T((ex + 3.2, ey + 3.2))], 1.6, glow)
                F.stroke([R.T((ex + 3.2, ey - 3.2)), R.T((ex - 3.2, ey + 3.2))], 1.6, glow)
        mx, my = hc[0] + 11.0, hc[1] + 12.0
        kind = pose["mouth"]
        if kind == "smile":
            F.stroke([R.T((mx - 5.0, my - 1.0)), R.T((mx - 2.0, my + 1.4)), R.T((mx + 2.0, my + 1.4)), R.T((mx + 5.0, my - 1.0))], 1.3, self.outline)
        elif kind in ("open", "o", "tongue"):
            F.detail([R.poly(rrect_pts(mx, my + 1.0, 4.4 if kind != "o" else 3.0, 3.4, 1.5))], hex_color("1b2340"))
            F.detail([R.poly(rrect_pts(mx, my + 2.4, 3.0 if kind != "o" else 1.8, 1.2, 0.6))], self.accent, 0.9)
        elif kind == "grit":
            F.detail([R.poly(rrect_pts(mx, my + 0.8, 5.5, 3.2, 1.2))], WHITE)
            for k in (-2.0, 0.0, 2.0):
                F.stroke([R.T((mx + k, my - 2.0)), R.T((mx + k, my + 3.6))], 0.6, self.outline, 0.8)
            F.stroke([R.T((mx - 5.5, my + 0.8)), R.T((mx + 5.5, my + 0.8))], 0.6, self.outline, 0.8)
        else:
            F.stroke([R.T((mx - 4.0, my + 0.5)), R.T((mx + 4.0, my + 0.5))], 1.3, self.outline)


# =========================================================================================
# Moss - a leaf-hatted frog from the overgrown ruins
# =========================================================================================
class Moss(Character):
    id = "moss"
    main = hex_color("6fd06f")
    light = hex_color("eefbd2")
    dark = hex_color("3f9a4a")
    accent = hex_color("f2e05c")
    accent2 = hex_color("ffffff")
    eye_c = hex_color("1d2b1d")
    glove = hex_color("5cbc5f")
    shoe = hex_color("5cbc5f")
    head_c0 = (66.0, 56.0)
    head_r = (25.0, 16.0)
    torso = (64.0, 89.0, 18.0, 16.0)
    thigh = (6.2, 5.0)
    arm_r = (4.4, 3.6)
    leg_len = 12.0

    def eye_center(self, hc, near=True):
        return (hc[0] + (9.0 if near else -7.0), hc[1] - 15.0 - (0.0 if near else 1.0))

    def draw_head_behind(self, F, R, pose, hc):
        for near in (False, True):
            ex, ey = self.eye_center(hc, near)
            F.part([R.circle(ex, ey + 1.5, 9.5)], self.main, self.outline, self.ow, shade=0.4)
        # leaf hat (behind the head, tilted back)
        e = pose["ears"]
        base = (hc[0] - 4.0, hc[1] - 19.0)
        tip = (hc[0] - 34.0 + 1.5 * max(e, 0.0), hc[1] - 28.0 - 2.0 * max(e, 0.0) + 2.5 * max(-e, 0.0))
        spine = bezier(base, (base[0] - 8.0, base[1] - 14.0), (tip[0] + 10.0, tip[1] + 2.0), tip, 10)
        widths = [1.0 + 8.0 * math.sin(math.pi * i / 10.0) ** 0.8 for i in range(11)]
        outline, left, right = spine_poly(spine, widths)
        m = F.part([R.poly(outline)], hex_color("4cae55"), self.outline, self.ow, shade=0.4)
        F.stroke([R.T(p) for p in spine[1:9]], 1.0, hex_color("2f7d3a"), 0.9, clip=m)

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        F.detail([R.ell(hc[0] + 6.0, hc[1] + 9.0, 17.0, 8.0)], self.light, 1.0, clip=head_mask)
        for (cx, cy) in ((hc[0] - 12.0, hc[1] + 3.0), (hc[0] + 19.0, hc[1] + 2.0)):
            F.detail([R.ell(cx, cy, 4.2, 2.6)], hex_color("ff9aa8"), 0.55, clip=head_mask)

    def draw_torso_extras(self, F, R, m):
        F.detail([R.ell(69.0, 92.0, 11.0, 12.5)], self.light, 1.0, clip=m)

    def draw_scarf_knot(self, F, R, pose, hc):
        c = (hc[0] - 9.0, hc[1] + 13.5)
        F.part([R.ell(c[0], c[1], 8.5, 5.8, -0.25)], self.accent, self.outline, 1.2, shade=0.4)
        F.detail([R.ell(c[0] - 1.0, c[1] + 0.5, 6.0, 1.6, -0.25)], self.accent2, 0.9)

    def draw_face(self, F, R, pose, hc):
        kind = pose["eye"]
        for near in (False, True):
            ex, ey = self.eye_center(hc, near)
            # a big glossy eye: white, dark pupil, highlight (kinds reuse the base implementation)
            if kind in ("open", "wide", "determined"):
                s = 1.45 if near else 1.3
                self.draw_eye(F, R, ex, ey + 1.0, s, kind)
            else:
                self.draw_eye(F, R, ex, ey + 1.0, 1.4, kind)
        self.draw_mouth(F, R, hc, pose["mouth"])

    def mouth_center(self, hc):
        return (hc[0] + 12.0, hc[1] + 6.5)

    def draw_mouth(self, F, R, hc, kind):
        mx, my = self.mouth_center(hc)
        ink = self.outline
        if kind == "smile":
            F.stroke([R.T((mx - 18.0, my - 3.0)), R.T((mx - 8.0, my + 2.0)), R.T((mx + 5.0, my + 2.4)), R.T((mx + 13.0, my - 2.0))], 1.5, ink)
        elif kind in ("open", "o", "tongue"):
            w = 8.0 if kind == "open" else 5.0
            F.detail([R.ell(mx, my + 1.5, w, 4.4 if kind != "o" else 5.0)], darken(ink, 0.2))
            F.detail([R.ell(mx, my + 3.4, w * 0.6, 2.0)], hex_color("ff7a8a"), 0.95)
        elif kind == "grit":
            F.stroke([R.T((mx - 16.0, my - 2.0)), R.T((mx - 6.0, my + 3.0)), R.T((mx + 6.0, my + 3.0)), R.T((mx + 14.0, my - 2.0))], 3.0, ink)
            F.stroke([R.T((mx - 14.0, my - 1.4)), R.T((mx - 6.0, my + 2.6)), R.T((mx + 6.0, my + 2.6)), R.T((mx + 12.0, my - 1.4))], 1.4, WHITE, 0.9)
        else:
            F.stroke([R.T((mx - 12.0, my + 1.0)), R.T((mx + 12.0, my + 1.0))], 1.4, ink)
        if kind == "tongue":
            F.detail([R.ell(mx + 3.0, my + 6.5, 3.0, 4.0)], hex_color("ff7a8a"), 1.0)

    def draw_hand(self, F, R, hand, back):
        col = darken(self.glove, 0.1) if back else self.glove
        polys = [R.circle(hand[0], hand[1], 4.8)]
        for a in (-0.7, 0.0, 0.7):
            polys.append(R.circle(hand[0] + 5.2 * math.cos(a), hand[1] + 5.2 * math.sin(a) + 0.5, 2.3))
        F.part(polys, col, self.outline, self.ow, shade=0.4)

    def draw_shoe(self, F, R, foot, back):
        col = darken(self.shoe, 0.1) if back else self.shoe
        polys = [R.ell(foot[0] + 4.0, foot[1] - 4.8, 11.0, 4.8)]
        for k in (-1, 0, 1):
            polys.append(R.circle(foot[0] + 12.0, foot[1] - 4.8 + k * 3.2, 2.3))
        F.part(polys, col, self.outline, self.ow, shade=0.4)


# =========================================================================================
# Nova - a star-child who tumbled down from the upper terraces
# =========================================================================================
class Nova(Character):
    id = "nova"
    main = hex_color("ffd84a")
    light = hex_color("fff6c2")
    dark = hex_color("e0a800")
    accent = hex_color("ff6bd6")
    accent2 = hex_color("6be6ff")
    eye_c = hex_color("3a1f6b")
    glove = hex_color("ffffff")
    shoe = hex_color("ff6bd6")
    limb_front = hex_color("ffe27a")
    limb_back = hex_color("e6b52e")
    torso = (64.0, 86.0, 15.0, 18.0)

    def draw_back(self, F, R, pose, hc):
        # star-spangled cape
        a = pose["tail"]
        base = (54.0, 74.0)
        tip = rot_pt((22.0, 108.0), base, a * 0.8)
        mid = rot_pt((26.0, 86.0), base, a * 0.6)
        spine = bezier(base, (40.0, 76.0), mid, tip, 10)
        widths = [3.0 + 10.0 * math.sin(math.pi * (i / 10.0) ** 0.9) + 2.0 * (i / 10.0) for i in range(11)]
        outline, left, right = spine_poly(spine, widths)
        m = F.part([R.poly(outline)], hex_color("d94fb4"), self.outline, self.ow, shade=0.45)
        F.detail([R.poly(spine_poly(spine[3:], widths[3:])[0])], hex_color("ff8ae6"), 0.55, clip=m)
        for k in (3, 6, 8):
            x, y = spine[k]
            self.sparkle_at(F, R, x, y, 3.6, self.accent2)
        # spiky hair behind the head
        for k, (dx, dy) in enumerate(((-16.0, -12.0), (-10.0, -19.0), (-2.0, -22.0), (8.0, -20.0), (15.0, -13.0))):
            e = pose["ears"]
            tip_h = (hc[0] + dx * 1.45 + 0.5 * e, hc[1] + dy * 1.45 - 1.4 * e)
            b0 = (hc[0] + dx * 0.55 - 5.0, hc[1] + dy * 0.55 + 3.0)
            b1 = (hc[0] + dx * 0.55 + 5.0, hc[1] + dy * 0.55 + 3.0)
            F.part([R.poly([b0, tip_h, b1])], hex_color("ff9b3c") if k % 2 == 0 else hex_color("ffb64a"), self.outline, self.ow, shade=0.4)

    def sparkle_at(self, F, R, x, y, r, color):
        pts = []
        for i in range(8):
            rr = r if i % 2 == 0 else r * 0.3
            a = -math.pi / 2 + math.pi * i / 4
            pts.append(R.T((x + rr * math.cos(a), y + rr * math.sin(a))))
        F.detail([pts], color, 0.95)

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        # bangs and a forehead star
        for (dx, w) in ((-10.0, 6.0), (-2.0, 6.0), (7.0, 6.0)):
            F.detail([R.poly([(hc[0] + dx - w, hc[1] - 18.0), (hc[0] + dx + 1.0, hc[1] - 6.0), (hc[0] + dx + w, hc[1] - 18.0)])], hex_color("ff9b3c"), 1.0, clip=head_mask)
        self.sparkle_at(F, R, hc[0] + 4.0, hc[1] - 9.0, 4.6, self.accent)
        for (cx, cy) in ((hc[0] - 1.0, hc[1] + 8.0), (hc[0] + 19.0, hc[1] + 6.0)):
            F.detail([R.ell(cx, cy, 3.6, 2.3)], hex_color("ff8ab8"), 0.55, clip=head_mask)

    def draw_torso_extras(self, F, R, m):
        pts = []
        for i in range(10):
            rr = 8.5 if i % 2 == 0 else 3.6
            a = -math.pi / 2 + math.pi * i / 5
            pts.append((69.0 + rr * math.cos(a), 86.0 + rr * math.sin(a)))
        F.detail([R.poly(pts)], self.accent2, 1.0, clip=m)
        F.detail([R.poly(pts)], WHITE, 0.4, clip=m)
        F.detail([R.ell(64.0, 102.0, 17.0, 2.6)], self.accent, 0.95, clip=m)


# =========================================================================================
# Wraith - a very polite ghost. Not haunted. Probably.
# =========================================================================================
class Wraith(Character):
    id = "wraith"
    main = hex_color("b9a4ff")
    light = hex_color("f0e8ff")
    dark = hex_color("7a5cff")
    accent = hex_color("7a5cff")
    accent2 = hex_color("ffffff")
    eye_c = hex_color("1b1233")
    glove = hex_color("cdbfff")
    shoe = hex_color("cdbfff")
    limb_front = hex_color("b9a4ff")
    limb_back = hex_color("9a84ee")
    head_c0 = (66.0, 51.0)
    head_r = (22.0, 20.0)
    arm_len = 8.5
    has_legs = False

    def body_polys(self, R):
        pose = self.pose
        sway = ((pose["foot_f"][0] - 75.0) + (pose["foot_b"][0] - 54.0)) * 0.22
        lift = max(0.0, 120.0 - max(pose["foot_f"][1], pose["foot_b"][1])) * 0.9
        bottom = 119.0 - lift
        left, right = 44.0 + sway, 86.0 + sway
        pts = [(46.0, 70.0), (82.0, 70.0), (85.0 + sway * 0.5, 96.0), (right, bottom - 6.0)]
        n = 4
        step = (right - left) / n
        for k in range(n):
            x1 = right - k * step
            depth = 6.0 + 1.6 * math.sin(k * 1.7 + self.cur[1] * 1.1)
            notch = bottom - depth
            for j in range(1, 9):
                t = j / 8.0
                pts.append((x1 - step * t, notch + depth * math.sin(math.pi * t)))
        pts.append((44.0 + sway * 0.5, 96.0))
        return [R.poly(pts)]

    def draw_back(self, F, R, pose, hc):
        # wisp of tail
        a = pose["tail"]
        base = (50.0, 108.0)
        tip = rot_pt((28.0, 100.0), base, a * 0.7)
        spine = bezier(base, (42.0, 116.0), (34.0, 104.0), tip, 10)
        widths = [4.2 * (1.0 - i / 10.0) ** 0.8 + 0.5 for i in range(11)]
        outline, left, right = spine_poly(spine, widths)
        F.part([R.poly(outline)], self.limb_back, self.outline, self.ow, shade=0.4)

    def draw_torso(self, F, R, pose):
        m = F.part(self.body_polys(R), self.main, self.outline, self.ow, shade=0.5)
        F.detail([R.ell(68.0, 92.0, 12.0, 14.0)], self.light, 0.9, clip=m)
        # scallop shading
        F.detail([R.ell(64.0, 112.0, 26.0, 5.0)], self.dark, 0.25, clip=m)
        return m

    def draw_head_behind(self, F, R, pose, hc):
        pass

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        F.detail([R.ell(hc[0] + 8.0, hc[1] + 8.0, 14.0, 8.0)], self.light, 0.9, clip=head_mask)
        # a tiny top hat, tilted by the "ears" parameter
        tilt = 4.0 * pose["ears"]
        pivot = (hc[0] - 2.0, hc[1] - 19.0)
        def T2(p):
            q = rot_pt(p, pivot, tilt)
            return q
        brim = [T2((hc[0] - 14.0, hc[1] - 19.0)), T2((hc[0] + 12.0, hc[1] - 19.0)), T2((hc[0] + 12.0, hc[1] - 16.0)), T2((hc[0] - 14.0, hc[1] - 16.0))]
        crown = [T2((hc[0] - 8.0, hc[1] - 19.0)), T2((hc[0] - 7.0, hc[1] - 34.0)), T2((hc[0] + 6.0, hc[1] - 34.0)), T2((hc[0] + 6.5, hc[1] - 19.0))]
        hat = hex_color("2b2540")
        mh = F.part([R.poly(crown)], hat, self.outline, self.ow, shade=0.3)
        F.detail([R.poly([T2((hc[0] - 7.5, hc[1] - 23.5)), T2((hc[0] + 6.3, hc[1] - 23.5)), T2((hc[0] + 6.4, hc[1] - 20.0)), T2((hc[0] - 7.7, hc[1] - 20.0))])], self.accent, 1.0, clip=mh)
        F.part([R.poly(brim)], hat, self.outline, self.ow, shade=0.3)

    def draw_face(self, F, R, pose, hc):
        super().draw_face(F, R, pose, hc)
        # monocle on the far eye
        ex, ey = self.eye_center(hc, False)
        pts = R.circle(ex, ey, 7.0, 28)
        F.stroke(pts + [pts[0]], 1.4, hex_color("ffd54a"), 1.0)
        F.stroke([R.T((ex + 3.0, ey + 6.5)), R.T((ex + 6.0, ey + 16.0))], 0.8, hex_color("ffd54a"), 0.8)

    def draw_hand(self, F, R, hand, back):
        col = darken(self.glove, 0.08) if back else self.glove
        F.part([R.circle(hand[0], hand[1], 4.4)], col, self.outline, self.ow, shade=0.4)

    def draw_scarf_knot(self, F, R, pose, hc):
        c = (hc[0] - 7.0, hc[1] + 17.5)
        F.part([R.ell(c[0], c[1], 8.5, 6.0, -0.35)], self.accent, self.outline, 1.2, shade=0.4)
        F.detail([R.ell(c[0] - 1.0, c[1] + 0.5, 6.0, 1.8, -0.35)], self.accent2, 0.9)


# =========================================================================================
# Ember - a flame-tailed lizard who hates falling behind
# =========================================================================================
class Ember(Character):
    id = "ember"
    main = hex_color("ff5a3c")
    light = hex_color("ffd27a")
    dark = hex_color("c23a1e")
    accent = hex_color("ff9b3c")
    accent2 = hex_color("ffee7a")
    eye_c = hex_color("2a1400")
    glove = hex_color("a8321b")
    shoe = hex_color("a8321b")
    head_c0 = (66.0, 51.0)
    head_r = (20.0, 17.0)

    def head_polys(self, R, hc):
        return [R.ell(hc[0], hc[1], 20.0, 17.0), R.ell(hc[0] + 15.0, hc[1] + 5.0, 12.0, 8.5)]

    def draw_back(self, F, R, pose, hc):
        # tail with a flame at its tip
        a = pose["tail"]
        base = (52.0, 96.0)
        spine0 = bezier(base, (38.0, 104.0), (24.0, 96.0), (18.0, 80.0), 12)
        spine = [rot_pt(p, base, a) for p in spine0]
        widths = [7.0 * (1.0 - i / 12.0) ** 0.9 + 1.4 for i in range(13)]
        outline, left, right = spine_poly(spine, widths)
        m = F.part([R.poly(outline)], self.main, self.outline, self.ow)
        tipx, tipy = spine[-1]
        idx = self.cur[1] + {"idle": 0, "run": 2, "accel": 4}.get(self.cur[0], 1)
        flick = [1.0, 0.75, 1.15, 0.85, 1.05, 0.7][idx % 6]
        F.glow(tipx, tipy - 4.0, 16.0, self.accent, 0.42)
        outer = [(tipx - 6.0, tipy + 2.0), (tipx - 7.5, tipy - 8.0 * flick), (tipx - 3.0, tipy - 6.0 * flick), (tipx - 3.5, tipy - 17.0 * flick),
                 (tipx + 1.5, tipy - 8.0 * flick), (tipx + 4.0, tipy - 13.0 * flick), (tipx + 6.5, tipy - 3.0), (tipx + 5.5, tipy + 3.0)]
        F.part([R.poly(outer)], self.accent, self.outline, 1.2, shade=0.2, light=0.0)
        inner = [(tipx - 3.0, tipy + 2.0), (tipx - 3.5, tipy - 4.0 * flick), (tipx, tipy - 9.0 * flick), (tipx + 3.0, tipy - 3.0), (tipx + 2.5, tipy + 2.5)]
        F.detail([R.poly(inner)], self.accent2, 1.0)
        # dorsal spikes
        for k in range(6):
            t = k / 5.0
            x = hc[0] - 12.0 - 12.0 * t
            y = hc[1] - 6.0 + 40.0 * t
            F.part([R.poly([(x - 3.2, y + 2.0), (x - 9.0 - 1.5 * t, y - 5.0), (x + 1.5, y - 1.0)])], self.dark, self.outline, 1.1, shade=0.2, light=0.0)

    def draw_torso_extras(self, F, R, m):
        F.detail([R.ell(69.0, 91.0, 9.0, 15.0)], self.light, 1.0, clip=m)
        for k in range(4):
            F.stroke([R.T((61.0, 78.0 + k * 7.0)), R.T((77.0, 78.0 + k * 7.0))], 0.8, darken(self.light, 0.25), 0.8, clip=m)

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        # brow ridge and nostril
        F.detail([R.ell(hc[0] + 8.0, hc[1] + 9.5, 17.0, 6.5)], self.light, 1.0, clip=head_mask)
        F.detail([R.circle(hc[0] + 25.0, hc[1] + 3.5, 1.1)], self.outline, 0.9)
        for k in range(3):
            hx = hc[0] - 6.0 + k * 7.0
            F.part([R.poly([(hx - 3.0, hc[1] - 14.0), (hx + 0.5, hc[1] - 21.0 + (1 if k == 1 else 0) - pose["ears"] * 0.6), (hx + 3.0, hc[1] - 14.0)])], self.accent, self.outline, 1.0, shade=0.2, light=0.0)

    def eye_center(self, hc, near=True):
        return (hc[0] + (7.0 if near else 18.0), hc[1] - 3.5)

    def draw_eye(self, F, R, ex, ey, s, kind):
        if kind in ("open", "wide", "determined"):
            big = 1.15 if kind == "wide" else 1.0
            sclera = F.detail([R.ell(ex, ey, 4.6 * s * big, 5.2 * s * big)], hex_color("ffe97a"))
            F.detail([R.ell(ex + 0.6, ey, 1.4 * s, 4.4 * s * big)], self.eye_c)
            F.detail([R.circle(ex - 1.0, ey - 2.0, 1.1 * s)], WHITE, 0.9)
            F.stroke([R.T((ex - 4.8 * s, ey - 0.5)), R.T((ex - 3.0 * s, ey - 4.4 * s)), R.T((ex + 3.0 * s, ey - 4.6 * s)), R.T((ex + 4.8 * s, ey - 0.5))], 0.9, self.outline, 0.9)
            if kind == "determined":
                F.detail([R.poly([(ex - 6.0 * s, ey - 8.0 * s), (ex + 6.0 * s, ey - 3.0 * s), (ex + 6.0 * s, ey - 9.0 * s)])], self.main, 1.0, clip=sclera)
                F.stroke([R.T((ex - 5.0 * s, ey - 6.0 * s)), R.T((ex + 5.0 * s, ey - 2.6 * s))], 1.4, self.outline, 0.95)
        else:
            super().draw_eye(F, R, ex, ey, s, kind)

    def mouth_center(self, hc):
        return (hc[0] + 19.0, hc[1] + 11.0)

    def draw_shoe(self, F, R, foot, back):
        col = darken(self.shoe, 0.12) if back else self.shoe
        polys = [R.ell(foot[0] + 3.0, foot[1] - 5.0, 9.0, 5.0)]
        for k in (-1, 0, 1):
            polys.append(R.poly([(foot[0] + 10.0, foot[1] - 5.0 + k * 3.0 - 1.6), (foot[0] + 15.0, foot[1] - 5.0 + k * 3.0), (foot[0] + 10.0, foot[1] - 5.0 + k * 3.0 + 1.6)]))
        F.part(polys, col, self.outline, self.ow, shade=0.4)


# =========================================================================================
# Zenith - crowned by the storm. Reserved for tower legends.
# =========================================================================================
class Zenith(Character):
    id = "zenith"
    main = hex_color("f5f0dc")
    light = hex_color("ffffff")
    dark = hex_color("c9c2a8")
    accent = hex_color("ffd45a")
    accent2 = hex_color("ffffff")
    eye_c = hex_color("2a6fb8")
    glove = hex_color("ffd45a")
    shoe = hex_color("ffd45a")
    limb_front = hex_color("efe6c4")
    limb_back = hex_color("cfc6a4")
    torso = (64.0, 86.0, 16.0, 18.0)
    gold = hex_color("ffd45a")

    def draw_back(self, F, R, pose, hc):
        # long white cloak
        a = pose["tail"]
        base = (54.0, 72.0)
        tip = rot_pt((18.0, 112.0), base, a * 0.7)
        mid = rot_pt((24.0, 88.0), base, a * 0.5)
        spine = bezier(base, (40.0, 74.0), mid, tip, 10)
        widths = [3.0 + 8.0 * math.sin(math.pi * (i / 10.0) ** 0.9) + 3.0 * (i / 10.0) for i in range(11)]
        outline, left, right = spine_poly(spine, widths)
        m = F.part([R.poly(outline)], hex_color("3d4f8f"), self.outline, self.ow, shade=0.5)
        F.detail([R.poly(spine_poly(spine[2:], [w * 0.62 for w in widths[2:]])[0])], hex_color("6f86c9"), 0.8, clip=m)
        F.stroke([R.T(p) for p in left[1:]], 1.6, self.gold, 0.95, clip=m)
        F.stroke([R.T(p) for p in right[1:]], 1.6, self.gold, 0.95, clip=m)
        # halo behind the head
        pts = R.ell(hc[0] + 1.0, hc[1] - 28.0, 15.0, 4.6)
        F.stroke(pts + [pts[0]], 2.6, self.outline, 1.0)
        F.stroke(pts + [pts[0]], 1.5, self.gold, 1.0)
        F.glow(hc[0] + 1.0, hc[1] - 28.0, 22.0, self.gold, 0.25)

    def draw_head_extras(self, F, R, pose, hc, head_mask):
        # helmet visor line and crown of lightning spikes
        F.detail([R.ell(hc[0] + 9.0, hc[1] + 8.0, 15.0, 8.0)], self.light, 0.8, clip=head_mask)
        e = pose["ears"]
        for k, (dx, h) in enumerate(((-13.0, 13.0), (-6.0, 17.0), (1.0, 20.0), (8.0, 17.0), (14.0, 12.0))):
            x = hc[0] + dx
            F.part([R.poly([(x - 3.5, hc[1] - 15.0), (x - 1.0, hc[1] - 15.0 - h * 0.55 - e * 0.5), (x + 1.2, hc[1] - 15.0 - h * 0.5), (x + 0.5, hc[1] - 15.0 - h - e), (x + 4.0, hc[1] - 15.0)])], self.gold, self.outline, 1.0, shade=0.3, light=0.4)
        F.detail([R.poly(rrect_pts(hc[0] + 1.0, hc[1] - 12.5, 16.0, 2.3, 1.0))], self.gold, 1.0, clip=head_mask)

    def draw_torso_extras(self, F, R, m):
        F.detail([R.poly([(70.0, 76.0), (64.0, 87.0), (68.5, 87.0), (65.5, 97.0), (74.0, 84.0), (69.5, 84.0)])], self.gold, 1.0, clip=m)
        F.detail([R.poly(rrect_pts(64.0, 101.0, 16.0, 2.6, 1.0))], self.gold, 1.0, clip=m)

    def draw_extras(self, F, R, pose, hc, torso_mask):
        # golden pauldron
        F.part([R.ell(64.0, 74.5, 8.5, 5.5)], self.gold, self.outline, 1.2, shade=0.4)
        anim, idx = self.cur
        if anim in ("idle", "wall", "near_fall", "gameover", "fast_jump"):
            k = idx % 2
            x0, y0 = pose["hand_f"]
            pts = [(x0 + 4.0, y0 - 2.0), (x0 + 8.0 + 2 * k, y0 - 5.0), (x0 + 7.0, y0 - 9.0 + k), (x0 + 12.0, y0 - 11.0)]
            F.stroke([R.T(p) for p in pts], 1.4, hex_color("bfe6ff"), 0.9)


ALL = [Pip, Bolt, Moss, Nova, Wraith, Ember, Zenith]
