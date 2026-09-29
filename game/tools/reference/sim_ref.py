#!/usr/bin/env python3
"""
Spire Sprint - reference implementation of the deterministic core simulation.

WHY THIS FILE EXISTS
--------------------
The game logic in `game/src/core/*.gd` is a line-by-line port of this file.
Keeping a second implementation in Python lets us

  * tune the feel numerically (jump heights, run-up distances, scroll curves),
  * prove with "planner bots" that the procedural tower is always reachable,
  * generate *golden vectors* (tests/golden/*.json) that the GDScript unit
    tests compare against, so any porting mistake shows up immediately.

Rules that keep the two implementations bit-identical
  * only + - * / , sqrt, abs, min, max and comparisons on doubles
    (no pow/sin/cos/exp/log: libm results may differ per platform),
  * xorshift128 PRNG built from shifts/xors only,
  * no rounding helpers with different tie rules (int(x + 0.5) instead),
  * every division has at least one float operand.
"""
from math import sqrt
import copy
import json
import sys

SIM_VERSION = 1
TICK_RATE = 120
DT = 1.0 / 120.0
M32 = 0xFFFFFFFF

KIND_NORMAL = 0
KIND_LANDMARK = 1
KIND_GROUND = 2

PATTERN_FREE = 0
PATTERN_STAIRS = 1
PATTERN_ZIGZAG = 2

END_NONE = 0
END_LOWER = 1   # landed on same/one/lower floor
END_TIMEOUT = 2
END_DEATH = 3


# ---------------------------------------------------------------------------
# Tuning (mirrors game/src/data/game_tuning.gd; keep names identical)
# ---------------------------------------------------------------------------
class Tuning:
    def __init__(self):
        # world
        self.tower_width = 640.0
        self.view_height = 720.0
        # player body
        self.player_half_width = 20.0
        self.player_height = 62.0
        self.foot_half_width = 14.0
        # horizontal movement
        self.max_speed = 720.0
        self.accel_ground = 1650.0
        self.accel_at_max_ratio = 0.30
        self.brake_decel = 3000.0
        self.ground_friction = 1800.0
        self.air_accel = 900.0
        self.air_brake = 1500.0
        self.air_friction = 40.0
        # vertical
        self.gravity = 2500.0
        self.max_fall_speed = 1900.0
        self.base_jump_velocity = 870.0
        self.jump_min_multiplier = 1.0
        self.jump_max_multiplier = 2.2
        self.jump_curve_bias = 0.5
        # walls
        self.wall_rebound_multiplier = 0.92
        self.wall_rebound_vertical_influence = 0.06
        self.wall_rebound_min_speed = 60.0
        # input forgiveness
        self.coyote_time = 0.06
        self.jump_buffer_time = 0.09
        # platforms
        self.platform_spacing_start = 104.0
        self.platform_spacing_end = 124.0
        self.platform_spacing_jitter = 6.0
        self.platform_spacing_min = 84.0
        self.platform_clearance = 14.0
        self.platform_width_start_min = 300.0
        self.platform_width_start_max = 420.0
        self.platform_width_end_min = 96.0
        self.platform_width_end_max = 190.0
        self.difficulty_ramp_floors = 700
        self.reach_factor_start = 0.32
        self.reach_factor_end = 0.85
        self.landmark_interval = 10
        self.landmark_min_width = 400.0
        self.pattern_stairs_chance = 0.28
        self.pattern_zigzag_chance = 0.24
        self.pattern_min_run = 3
        self.pattern_max_run = 6
        self.generate_ahead = 900.0
        # scrolling
        self.scroll_start_floor = 5
        self.scroll_speed_start = 36.0
        self.scroll_speed_max = 480.0
        self.scroll_stage_seconds = 30.0
        self.scroll_stage_halfpoint = 14.0
        self.scroll_ramp_seconds = 2.0
        self.scroll_stage_blend_seconds = 1.5
        self.camera_follow_line = 0.60
        self.camera_follow_gain = 0.30
        self.camera_start_bottom = -64.0
        self.death_margin = 0.0
        # combo
        self.combo_min_floors = 2
        self.combo_timeout = 3.0
        self.combo_min_jumps_for_bonus = 2
        self.combo_min_total_floors_for_bonus = 4
        self.combo_bonus_exponent = 2
        self.combo_bonus_multiplier = 1
        self.combo_only_new_floors = False
        # score
        self.points_per_floor = 10

    # derived helpers -------------------------------------------------------
    def coyote_ticks(self):
        return int(self.coyote_time * TICK_RATE + 0.5)

    def buffer_ticks(self):
        return int(self.jump_buffer_time * TICK_RATE + 0.5)

    def combo_ticks(self):
        return int(self.combo_timeout * TICK_RATE + 0.5)

    def stage_ticks(self):
        return int(self.scroll_stage_seconds * TICK_RATE + 0.5)

    def base_apex(self):
        v = self.base_jump_velocity
        return v * v / (2.0 * self.gravity)


# ---------------------------------------------------------------------------
# Deterministic PRNG: xorshift128 seeded through xorshift32 (shifts/xors only)
# ---------------------------------------------------------------------------
class SimRng:
    def __init__(self, seed):
        self.x = 0
        self.y = 0
        self.z = 0
        self.w = 0
        self.seed(seed)

    @staticmethod
    def _step32(v):
        v = v ^ ((v << 13) & M32)
        v = v ^ (v >> 17)
        v = v ^ ((v << 5) & M32)
        return v

    def seed(self, s):
        v = (s & M32) ^ 0x9E3779B9
        if v == 0:
            v = 0x1234567
        v = self._step32(v)
        self.x = v
        v = self._step32(v)
        self.y = v
        v = self._step32(v)
        self.z = v
        v = self._step32(v)
        self.w = v
        if (self.x | self.y | self.z | self.w) == 0:
            self.w = 1
        for _i in range(16):
            self.next_u32()

    def next_u32(self):
        t = self.x ^ ((self.x << 11) & M32)
        self.x = self.y
        self.y = self.z
        self.z = self.w
        self.w = (self.w ^ (self.w >> 19)) ^ (t ^ (t >> 8))
        return self.w

    def next_float(self):
        return float(self.next_u32() >> 8) * (1.0 / 16777216.0)

    def range_f(self, a, b):
        return a + (b - a) * self.next_float()

    def range_i(self, a, b):
        n = b - a + 1
        return a + int((self.next_u32() >> 8) % n)


# ---------------------------------------------------------------------------
# Platforms and the tower generator
# ---------------------------------------------------------------------------
class Platform:
    __slots__ = ("floor", "x", "y", "w", "kind", "variant")

    def __init__(self, floor, x, y, w, kind, variant):
        self.floor = floor
        self.x = x          # centre
        self.y = y          # altitude of the walkable top surface
        self.w = w
        self.kind = kind
        self.variant = variant

    def left(self):
        return self.x - self.w * 0.5

    def right(self):
        return self.x + self.w * 0.5


class PlatformGenerator:
    def __init__(self, t, seed):
        self.t = t
        self.seed_value = seed
        self.rng = SimRng(seed)
        self.platforms = []
        self.pattern = PATTERN_FREE
        self.pattern_left = 0
        self.dir = 1.0
        self.platforms.append(Platform(0, t.tower_width * 0.5, 0.0, t.tower_width, KIND_GROUND, 0))

    def ensure_up_to(self, altitude):
        while self.platforms[len(self.platforms) - 1].y < altitude:
            self._generate_next()

    def difficulty(self, floor):
        d = float(floor) / float(self.t.difficulty_ramp_floors)
        if d > 1.0:
            d = 1.0
        return d

    def max_gap(self, prev_w, spacing, d):
        """Largest edge-to-edge horizontal gap that is guaranteed jumpable."""
        t = self.t
        run = prev_w - 2.0 * t.foot_half_width
        if run < 0.0:
            run = 0.0
        v = sqrt(t.accel_ground * run)          # conservative run-up (half the accel)
        if v > t.max_speed:
            v = t.max_speed
        v0 = t.base_jump_velocity
        disc = v0 * v0 - 2.0 * t.gravity * spacing
        if disc < 0.0:
            disc = 0.0
        tair = (v0 + sqrt(disc)) / t.gravity
        ratio = v / t.max_speed
        a_eff = t.air_accel * (1.0 + (t.accel_at_max_ratio - 1.0) * ratio)
        reach = v * tair + 0.5 * a_eff * tair * tair
        factor = t.reach_factor_start + (t.reach_factor_end - t.reach_factor_start) * d
        return factor * reach

    def _choose_pattern(self):
        t = self.t
        r = self.rng.next_float()
        if r < t.pattern_stairs_chance:
            self.pattern = PATTERN_STAIRS
        elif r < t.pattern_stairs_chance + t.pattern_zigzag_chance:
            self.pattern = PATTERN_ZIGZAG
        else:
            self.pattern = PATTERN_FREE
        if self.rng.next_float() < 0.5:
            self.dir = -1.0
        else:
            self.dir = 1.0
        self.pattern_left = self.rng.range_i(t.pattern_min_run, t.pattern_max_run)

    def _generate_next(self):
        t = self.t
        rng = self.rng
        k = len(self.platforms)
        prev = self.platforms[k - 1]
        d = self.difficulty(k)

        # vertical spacing
        sp = t.platform_spacing_start + (t.platform_spacing_end - t.platform_spacing_start) * d
        sp = sp + rng.range_f(-t.platform_spacing_jitter, t.platform_spacing_jitter)
        max_sp = t.base_apex() - t.platform_clearance
        if sp > max_sp:
            sp = max_sp
        if sp < t.platform_spacing_min:
            sp = t.platform_spacing_min

        # width
        wmin = t.platform_width_start_min + (t.platform_width_end_min - t.platform_width_start_min) * d
        wmax = t.platform_width_start_max + (t.platform_width_end_max - t.platform_width_start_max) * d
        w = rng.range_f(wmin, wmax)
        kind = KIND_NORMAL
        if t.landmark_interval > 0 and (k % t.landmark_interval) == 0:
            kind = KIND_LANDMARK
            if w < t.landmark_min_width:
                w = t.landmark_min_width
        if w > t.tower_width:
            w = t.tower_width

        # horizontal placement
        if self.pattern_left <= 0:
            self._choose_pattern()
        self.pattern_left -= 1

        reach = self.max_gap(prev.w, sp, d)
        max_dx = (w + prev.w) * 0.5 + reach
        lo = prev.x - max_dx
        if lo < w * 0.5:
            lo = w * 0.5
        hi = prev.x + max_dx
        if hi > t.tower_width - w * 0.5:
            hi = t.tower_width - w * 0.5

        if self.pattern == PATTERN_FREE:
            x = rng.range_f(lo, hi)
        elif self.pattern == PATTERN_STAIRS:
            m = rng.range_f(0.5, 0.9)
            x = prev.x + self.dir * m * max_dx
            if x < lo or x > hi:
                self.dir = -self.dir
                x = prev.x + self.dir * m * max_dx
            if x < lo:
                x = lo
            if x > hi:
                x = hi
        else:
            self.dir = -self.dir
            m = rng.range_f(0.6, 1.0)
            x = prev.x + self.dir * m * max_dx
            if x < lo:
                x = lo
            if x > hi:
                x = hi

        variant = rng.next_u32() & 0xFFFF
        self.platforms.append(Platform(k, x, prev.y + sp, w, kind, variant))


# ---------------------------------------------------------------------------
# Player kinematics
# ---------------------------------------------------------------------------
EV_JUMP = "jump"
EV_LAND = "land"
EV_WALL = "wall"
EV_LEFT_GROUND = "left_ground"


class Player:
    def __init__(self, t):
        self.t = t
        self.x = t.tower_width * 0.5
        self.y = 0.0
        self.vx = 0.0
        self.vy = 0.0
        self.grounded = True
        self.support = None
        self.takeoff_floor = 0
        self.coyote = 0
        self.jump_buf = 0
        self.prev_x = self.x
        self.prev_y = self.y
        self.facing = 1

    def jump_velocity(self):
        t = self.t
        r = abs(self.vx) / t.max_speed
        if r > 1.0:
            r = 1.0
        f = r + (r * r - r) * t.jump_curve_bias
        m = t.jump_min_multiplier + (t.jump_max_multiplier - t.jump_min_multiplier) * f
        return t.base_jump_velocity * m

    def _horizontal(self, axis):
        t = self.t
        vx = self.vx
        if self.grounded:
            acc0 = t.accel_ground
            brake = t.brake_decel
            fric = t.ground_friction
        else:
            acc0 = t.air_accel
            brake = t.air_brake
            fric = t.air_friction
        if axis != 0.0:
            if axis > 0.0:
                sa = 1.0
            else:
                sa = -1.0
            target = axis * t.max_speed
            at = abs(target)
            if vx == 0.0 or ((vx > 0.0) == (axis > 0.0)):
                av = abs(vx)
                if av < at:
                    ratio = av / t.max_speed
                    acc = acc0 * (1.0 + (t.accel_at_max_ratio - 1.0) * ratio)
                    dv = acc * DT
                    gap = at - av
                    if dv > gap:
                        dv = gap
                    vx = vx + sa * dv
                elif av > at:
                    dv = fric * DT
                    gap = av - at
                    if dv > gap:
                        dv = gap
                    vx = vx - sa * dv
            else:
                vx = vx + sa * brake * DT
        else:
            av = abs(vx)
            dv = fric * DT
            if dv >= av:
                vx = 0.0
            elif vx > 0.0:
                vx = vx - dv
            else:
                vx = vx + dv
        return vx

    def step(self, axis, jump, tower, events):
        t = self.t
        self.prev_x = self.x
        self.prev_y = self.y

        if jump:
            self.jump_buf = t.buffer_ticks()

        # ---- jump (uses the speed built up before this tick's input)
        if self.jump_buf > 0 and (self.grounded or self.coyote > 0):
            jv = self.jump_velocity()
            if self.grounded and self.support is not None:
                self.takeoff_floor = self.support.floor
            self.vy = jv
            self.grounded = False
            self.support = None
            self.coyote = 0
            self.jump_buf = 0
            events.append((EV_JUMP, jv, abs(self.vx) / t.max_speed))

        # ---- horizontal
        vx_old = self.vx
        self.vx = self._horizontal(axis)
        self.x = self.x + (vx_old + self.vx) * 0.5 * DT
        if self.vx > 0.0:
            self.facing = 1
        elif self.vx < 0.0:
            self.facing = -1

        # ---- walls
        left_lim = t.player_half_width
        right_lim = t.tower_width - t.player_half_width
        if self.x < left_lim:
            self.x = left_lim
            if self.vx < 0.0:
                self._rebound(1, events)
        elif self.x > right_lim:
            self.x = right_lim
            if self.vx > 0.0:
                self._rebound(-1, events)

        # ---- vertical / support
        if self.grounded:
            sp = self.support
            fhw = t.foot_half_width
            if not (self.x + fhw > sp.left() and self.x - fhw < sp.right()):
                self.grounded = False
                self.takeoff_floor = sp.floor
                self.support = None
                self.coyote = t.coyote_ticks()
                self.vy = 0.0
                events.append((EV_LEFT_GROUND, sp.floor))
        if not self.grounded:
            vy_old = self.vy
            vy_new = vy_old - t.gravity * DT
            if vy_new < -t.max_fall_speed:
                vy_new = -t.max_fall_speed
            y_new = self.y + (vy_old + vy_new) * 0.5 * DT
            landed = None
            if y_new <= self.y:
                fhw = t.foot_half_width
                plats = tower.platforms
                i = self.floor_index_below(tower, self.y)
                # scan a small window of floors around the crossing range
                lo_i = i - 3
                if lo_i < 0:
                    lo_i = 0
                hi_i = i + 3
                if hi_i > len(plats) - 1:
                    hi_i = len(plats) - 1
                j = lo_i
                while j <= hi_i:
                    p = plats[j]
                    top = p.y
                    if self.y >= top - 0.01 and y_new <= top:
                        if self.x + fhw > p.left() and self.x - fhw < p.right():
                            if landed is None or top > landed.y:
                                landed = p
                    j += 1
            if landed is not None:
                impact = vy_new
                self.y = landed.y
                self.vy = 0.0
                self.grounded = True
                self.support = landed
                self.coyote = 0
                events.append((EV_LAND, landed, impact))
            else:
                self.y = y_new
                self.vy = vy_new
                if self.coyote > 0:
                    self.coyote -= 1

        if self.jump_buf > 0:
            self.jump_buf -= 1

    @staticmethod
    def floor_index_below(tower, altitude):
        """Highest platform index whose top is <= altitude + small slack (binary search)."""
        plats = tower.platforms
        lo = 0
        hi = len(plats) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if plats[mid].y <= altitude + 0.01:
                lo = mid
            else:
                hi = mid - 1
        return lo

    def _rebound(self, direction, events):
        t = self.t
        speed = abs(self.vx)
        if speed >= t.wall_rebound_min_speed:
            self.vx = direction * speed * t.wall_rebound_multiplier
            if not self.grounded:
                self.vy = self.vy + speed * t.wall_rebound_vertical_influence
            events.append((EV_WALL, direction, speed))
        else:
            self.vx = 0.0


# ---------------------------------------------------------------------------
# Scroll / camera / difficulty
# ---------------------------------------------------------------------------
class Scroll:
    def __init__(self, t):
        self.t = t
        self.cam_bottom = t.camera_start_bottom
        self.prev_cam_bottom = self.cam_bottom
        self.active = False
        self.ticks_since_start = 0
        self.stage = 0
        self.speed = 0.0

    def stage_speed(self, stage):
        t = self.t
        s = float(stage)
        return t.scroll_speed_start + (t.scroll_speed_max - t.scroll_speed_start) * (s / (s + t.scroll_stage_halfpoint))

    def step(self, head_y, highest_floor, events):
        t = self.t
        self.prev_cam_bottom = self.cam_bottom
        if not self.active and highest_floor >= t.scroll_start_floor:
            self.active = True
            events.append(("scroll_started",))
        if self.active:
            self.ticks_since_start += 1
            st = self.ticks_since_start // t.stage_ticks()
            if st != self.stage:
                self.stage = st
                events.append(("speed_up", st))
            cur = self.stage_speed(self.stage)
            local = self.ticks_since_start - self.stage * t.stage_ticks()
            blend_ticks = int(t.scroll_stage_blend_seconds * TICK_RATE + 0.5)
            speed = cur
            if self.stage > 0 and local < blend_ticks:
                prev = self.stage_speed(self.stage - 1)
                speed = prev + (cur - prev) * (float(local) / float(blend_ticks))
            ramp_ticks = int(t.scroll_ramp_seconds * TICK_RATE + 0.5)
            if self.ticks_since_start < ramp_ticks:
                speed = speed * (float(self.ticks_since_start) / float(ramp_ticks))
            self.speed = speed
            self.cam_bottom = self.cam_bottom + speed * DT
        target = head_y - t.camera_follow_line * t.view_height
        if target > self.cam_bottom:
            self.cam_bottom = self.cam_bottom + (target - self.cam_bottom) * t.camera_follow_gain


# ---------------------------------------------------------------------------
# Combo + score
# ---------------------------------------------------------------------------
class Combo:
    def __init__(self, t, sink):
        self.t = t
        self.sink = sink            # object with combo_ended(jumps, floors, bonus, reason, valid)
        self.active = False
        self.jumps = 0
        self.floors = 0
        self.timer = 0
        self.best_floors_run = 0
        self.best_jumps_run = 0
        self.total_combo_jumps = 0

    def timer_ratio(self):
        n = self.t.combo_ticks()
        if n <= 0:
            return 0.0
        return float(self.timer) / float(n)

    def bonus_for(self, jumps, floors):
        t = self.t
        if jumps < t.combo_min_jumps_for_bonus or floors < t.combo_min_total_floors_for_bonus:
            return 0
        v = 1
        i = 0
        while i < t.combo_bonus_exponent:
            v = v * floors
            i += 1
        return v * t.combo_bonus_multiplier

    def on_landing(self, floors_advanced, is_new_floor, events):
        t = self.t
        qualifies = floors_advanced >= t.combo_min_floors
        if t.combo_only_new_floors and not is_new_floor:
            qualifies = False
        if qualifies:
            if not self.active:
                self.active = True
                self.jumps = 0
                self.floors = 0
                events.append(("combo_started",))
            self.jumps += 1
            self.floors += floors_advanced
            self.timer = t.combo_ticks()
            self.total_combo_jumps += 1
            events.append(("combo_progress", self.jumps, self.floors))
        elif self.active:
            self._end(END_LOWER, events)
        return 0

    def tick(self, events):
        if self.active:
            self.timer -= 1
            if self.timer <= 0:
                self._end(END_TIMEOUT, events)

    def end_now(self, reason, events):
        if self.active:
            self._end(reason, events)

    def _end(self, reason, events):
        bonus = self.bonus_for(self.jumps, self.floors)
        valid = bonus > 0
        if valid:
            if self.floors > self.best_floors_run:
                self.best_floors_run = self.floors
            if self.jumps > self.best_jumps_run:
                self.best_jumps_run = self.jumps
        jumps = self.jumps
        floors = self.floors
        self.active = False
        self.jumps = 0
        self.floors = 0
        self.timer = 0
        events.append(("combo_ended", jumps, floors, bonus, reason, valid))
        self.sink.combo_ended(jumps, floors, bonus, reason, valid)


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
class Run:
    def __init__(self, t, seed):
        self.t = t
        self.seed = seed
        self.tick_count = 0
        self.dead = False
        self.tower = PlatformGenerator(t, seed)
        self.player = Player(t)
        self.scroll = Scroll(t)
        self.combo = Combo(t, self)
        self.score = 0
        self.combo_bonus_total = 0
        self.highest_floor = 0
        self.current_floor = 0
        self.total_jumps = 0
        self.wall_rebounds = 0
        self.tower.ensure_up_to(self.scroll.cam_bottom + t.view_height + t.generate_ahead)
        self.player.support = self.tower.platforms[0]
        self.events = []

    # combo sink -----------------------------------------------------------
    def combo_ended(self, jumps, floors, bonus, reason, valid):
        self.score += bonus
        self.combo_bonus_total += bonus

    def tick(self, axis, jump):
        """Advance one 1/120 s tick. Returns the list of events produced."""
        if self.dead:
            return []
        t = self.t
        self.tick_count += 1
        ev = []
        self.tower.ensure_up_to(self.scroll.cam_bottom + t.view_height + t.generate_ahead + 400.0)
        p = self.player
        p.step(axis, jump, self.tower, ev)

        i = 0
        while i < len(ev):
            e = ev[i]
            if e[0] == EV_JUMP:
                self.total_jumps += 1
            elif e[0] == EV_WALL:
                self.wall_rebounds += 1
            elif e[0] == EV_LAND:
                self._on_land(e[1], ev)
            i += 1

        self.scroll.step(p.y + t.player_height, self.highest_floor, ev)
        self.combo.tick(ev)

        if p.y + t.player_height < self.scroll.cam_bottom - t.death_margin:
            self.combo.end_now(END_DEATH, ev)
            self.dead = True
            ev.append(("game_over",))
        self.events = ev
        return ev

    def _on_land(self, plat, ev):
        adv = plat.floor - self.player.takeoff_floor
        is_new = plat.floor > self.highest_floor
        self.current_floor = plat.floor
        if is_new:
            gained = plat.floor - self.highest_floor
            self.score += gained * self.t.points_per_floor
            self.highest_floor = plat.floor
            ev.append(("new_floor", plat.floor))
        self.combo.on_landing(adv, is_new, ev)
        ev.append(("landed", plat.floor, adv))


def run_ticks(run, script, n):
    """Drive `run` for n ticks with script(tick_index) -> (axis, jump). Returns all events."""
    out = []
    for i in range(n):
        if run.dead:
            break
        axis, jump = script(i)
        out.extend(run.tick(axis, jump))
    return out


# ---------------------------------------------------------------------------
# Analysis helpers used while tuning
# ---------------------------------------------------------------------------
def jump_table(t):
    rows = []
    for pct in (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100):
        p = Player(t)
        p.vx = t.max_speed * pct / 100.0
        jv = p.jump_velocity()
        apex = jv * jv / (2.0 * t.gravity)
        air = 2.0 * jv / t.gravity
        rows.append((pct, jv, apex, apex / t.platform_spacing_start, air))
    return rows


def run_up_profile(t, seconds=1.4):
    """time/distance to reach fractions of max speed from standstill on flat ground."""
    p = Player(t)
    dist = 0.0
    out = {}
    marks = [0.25, 0.5, 0.75, 0.9, 0.95]
    for i in range(int(seconds * TICK_RATE)):
        x0 = p.x
        p.vx = p._horizontal(1.0)
        dist += p.vx * DT
        r = p.vx / t.max_speed
        for m in list(marks):
            if r >= m:
                out[m] = (round((i + 1) * DT, 3), round(dist, 1))
                marks.remove(m)
    return out


if __name__ == "__main__":
    t = Tuning()
    print("base apex", round(t.base_apex(), 1), "px  (spacing", t.platform_spacing_start, "-", t.platform_spacing_end, ")")
    print("pct  jump_v  apex   floors  airtime")
    for r in jump_table(t):
        print("%3d%%  %6.0f  %6.1f  %5.2f  %5.2fs" % r)
    print("run-up:", run_up_profile(t))
