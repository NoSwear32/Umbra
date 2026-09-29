#!/usr/bin/env python3
"""
Generate golden test vectors from the Python reference simulation.

Output: game/tests/golden/*.json  (consumed by game/tests/test_golden.gd)

Run:  python3 gen_golden.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim_ref import *
from bots import PlanBot

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tests", "golden"))


def dump(name, obj):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        json.dump(obj, f, separators=(",", ":"))
    print("wrote", path, os.path.getsize(path), "bytes")


# ---------------------------------------------------------------------------
def gen_rng():
    cases = []
    for seed in (0, 1, 42, 123456789, 2147483647, 4294967295):
        r = SimRng(seed)
        u = [r.next_u32() for _ in range(8)]
        r = SimRng(seed)
        fl = [r.next_float() for _ in range(4)]
        rf = [r.range_f(-5.0, 5.0) for _ in range(4)]
        ri = [r.range_i(3, 9) for _ in range(6)]
        cases.append({"seed": seed, "u32": u, "floats": fl, "range_f": rf, "range_i": ri})
    dump("rng.json", {"cases": cases})


def plat_row(p):
    return [p.floor, p.x, p.y, p.w, p.kind, p.variant]


def gen_tower():
    t = Tuning()
    out = []
    for seed in (1, 7, 2024, 4294967295):
        tw = PlatformGenerator(t, seed)
        tw.ensure_up_to(1010 * 125.0)
        rows = [plat_row(p) for p in tw.platforms[0:60]]
        rows += [plat_row(p) for p in tw.platforms[300:306]]
        rows += [plat_row(p) for p in tw.platforms[1000:1005]]
        out.append({"seed": seed, "platforms": rows})
    dump("tower.json", {"cases": out})


# ---------------------------------------------------------------------------
def trace_row(run):
    p = run.player
    return [run.tick_count, p.x, p.y, p.vx, p.vy, 1 if p.grounded else 0,
            run.highest_floor, run.score, run.scroll.cam_bottom,
            1 if run.combo.active else 0, run.combo.jumps, run.combo.floors,
            1 if run.dead else 0]


def run_segments(seed, segments, sample_every, tuning=None):
    t = tuning if tuning is not None else Tuning()
    run = Run(t, seed)
    trace = []
    apex = 0.0
    events_summary = []
    for seg in segments:
        n, axis, jump_first = seg
        for i in range(n):
            if run.dead:
                break
            ev = run.tick(float(axis), bool(jump_first and i == 0))
            for e in ev:
                if e[0] in ("combo_ended", "speed_up", "scroll_started", "game_over", "new_floor"):
                    events_summary.append([run.tick_count] + [x if not isinstance(x, bool) else int(x) for x in e])
            if run.player.y > apex:
                apex = run.player.y
            if run.tick_count % sample_every == 0:
                trace.append(trace_row(run))
    trace.append(trace_row(run))
    return {
        "seed": seed,
        "segments": [list(map(lambda v: v if not isinstance(v, bool) else int(v), s)) for s in segments],
        "sample_every": sample_every,
        "trace": trace,
        "apex": apex,
        "events": events_summary,
        "final": {"score": run.score, "highest": run.highest_floor, "dead": run.dead, "ticks": run.tick_count,
                  "jumps": run.total_jumps, "walls": run.wall_rebounds},
    }


def gen_physics():
    scenarios = []
    # A: standing jump
    a = run_segments(1, [(30, 0, 0), (1, 0, 1), (120, 0, 0)], 6)
    a["name"] = "stand_jump"
    scenarios.append(a)
    # B: run right then coast
    b = run_segments(1, [(100, 1, 0), (60, 0, 0)], 10)
    b["name"] = "run_right_coast"
    scenarios.append(b)
    # C: run-up then jump at increasing speeds
    for n in (0, 20, 45, 80, 140):
        c = run_segments(2, [(n, 1, 0), (1, 1, 1), (170, 0, 0)], 10)
        c["name"] = "run_jump_%d" % n
        scenarios.append(c)
    # D: wall rebound on the ground floor (keep pushing left)
    d = run_segments(3, [(220, -1, 0)], 5)
    d["name"] = "wall_rebound_left"
    scenarios.append(d)
    # D2: run right, jump at speed, bounce in the air, coast
    d2 = run_segments(3, [(70, 1, 0), (1, 1, 1), (200, 1, 0), (120, 0, 0)], 10)
    d2["name"] = "air_wall_bounce"
    scenarios.append(d2)
    # jump-through / land-on-top: jump straight up from ground next to platform 1 (may or may not overlap)
    e = run_segments(5, [(20, 0, 0), (1, 0, 1), (200, 0, 0)], 10)
    e["name"] = "vertical_jump_seed5"
    scenarios.append(e)
    dump("physics.json", {"scenarios": scenarios})


# ---------------------------------------------------------------------------
def chaos_segments(seed, ticks):
    """Portable random driver: identical algorithm is implemented in the GDScript test."""
    drv = SimRng((seed ^ 0x5EED) & 0xFFFFFFFF)
    segs = []
    left = 0
    axis = 0
    jump_now = False
    inputs = []
    for i in range(ticks):
        jump = False
        if left <= 0:
            r = drv.next_float()
            if r < 0.4:
                axis = -1
            elif r < 0.8:
                axis = 1
            else:
                axis = 0
            left = drv.range_i(6, 60)
            if drv.next_float() < 0.5:
                jump = True
        left -= 1
        if drv.next_float() < 0.02:
            jump = True
        inputs.append((axis, jump))
    return inputs


def compress_inputs(inputs):
    """[(axis, jump)] -> [[ticks, axis, jump_on_first_tick]] (jump ticks always start a new segment)."""
    segs = []
    cur_axis = None
    count = 0
    for axis, jump in inputs:
        if jump or axis != cur_axis:
            if count > 0:
                segs.append([count, cur_axis, first_jump])
            cur_axis = axis
            count = 1
            first_jump = 1 if jump else 0
        else:
            count += 1
    if count > 0:
        segs.append([count, cur_axis, first_jump])
    return segs


def gen_chaos():
    out = []
    for seed in (11, 12, 13):
        inputs = chaos_segments(seed, 9000)
        segs = compress_inputs(inputs)
        r = run_segments(seed, segs, 300)
        r["name"] = "chaos_%d" % seed
        r["driver_ticks"] = 9000
        out.append(r)
    dump("chaos.json", {"scenarios": out})


# ---------------------------------------------------------------------------
def gen_bot_run():
    t = Tuning()
    seed = 1
    run = Run(t, seed)
    bot = PlanBot(run, 1)
    inputs = []
    max_ticks = 100 * TICK_RATE
    while not run.dead and run.tick_count < max_ticks:
        axis, jump = bot.act()
        inputs.append((axis, jump))
        run.tick(axis, jump)
    segs = compress_inputs(inputs)
    r = run_segments(seed, segs, 600)
    r["name"] = "bot_run"
    dump("bot_run.json", {"scenarios": [r]})
    print("  bot run: ticks=%d floor=%d score=%d dead=%s segments=%d" % (run.tick_count, run.highest_floor, run.score, run.dead, len(segs)))


# ---------------------------------------------------------------------------
class _Sink:
    def __init__(self):
        self.total = 0

    def combo_ended(self, jumps, floors, bonus, reason, valid):
        self.total += bonus


def gen_combo():
    t = Tuning()
    cases = []
    scripts = [
        # name, ops
        ("basic_chain_then_one_floor", [["land", 3, 1], ["tick", 100], ["land", 2, 1], ["tick", 60], ["land", 4, 1], ["land", 1, 1]]),
        ("single_jump_no_bonus", [["land", 2, 1], ["land", 1, 1]]),
        ("timeout", [["land", 2, 1], ["land", 3, 1], ["tick", 361], ["land", 1, 1]]),
        ("timeout_boundary", [["land", 2, 1], ["land", 2, 1], ["tick", 359], ["land", 2, 1], ["tick", 360]]),
        ("lower_floor_breaks", [["land", 3, 1], ["land", 3, 1], ["land", -2, 0], ["land", 2, 1]]),
        ("same_floor_breaks", [["land", 2, 1], ["land", 2, 1], ["land", 0, 0]]),
        ("small_total_no_bonus", [["land", 2, 1], ["land", 1, 1]]),
        ("min_total_exactly", [["land", 2, 1], ["land", 2, 1], ["land", 1, 1]]),
        ("long_chain", [["land", 5, 1]] * 12 + [["land", 1, 1]]),
        ("death_ends", [["land", 4, 1], ["land", 4, 1], ["end", END_DEATH]]),
    ]
    for name, ops in scripts:
        sink = _Sink()
        c = Combo(t, sink)
        evs = []
        log = []
        for op in ops:
            ev = []
            if op[0] == "land":
                c.on_landing(op[1], bool(op[2]), ev)
            elif op[0] == "tick":
                for _ in range(op[1]):
                    c.tick(ev)
            elif op[0] == "end":
                c.end_now(op[1], ev)
            for e in ev:
                if e[0] == "combo_started":
                    log.append("started")
                elif e[0] == "combo_progress":
                    log.append("progress:%d:%d" % (e[1], e[2]))
                elif e[0] == "combo_ended":
                    log.append("ended:%d:%d:%d:%d:%d" % (e[1], e[2], e[3], e[4], 1 if e[5] else 0))
        cases.append({"name": name, "ops": ops, "log": log, "bonus_total": sink.total,
                      "best_floors": c.best_floors_run, "best_jumps": c.best_jumps_run})
    dump("combo.json", {"cases": cases})


def gen_curves():
    t = Tuning()
    rows = []
    for pct in range(0, 101, 5):
        p = Player(t)
        p.vx = t.max_speed * pct / 100.0
        rows.append([pct, p.jump_velocity()])
    stage = Scroll(t)
    speeds = [[s, stage.stage_speed(s)] for s in (0, 1, 2, 3, 5, 8, 13, 21, 55)]
    dump("curves.json", {"jump": rows, "stage_speed": speeds,
                         "run_up": {str(k): v for k, v in run_up_profile(t).items()},
                         "base_apex": t.base_apex()})


if __name__ == "__main__":
    gen_rng()
    gen_tower()
    gen_physics()
    gen_chaos()
    gen_bot_run()
    gen_combo()
    gen_curves()
