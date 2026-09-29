#!/usr/bin/env python3
"""
Planner bots that play the reference simulation.

  reach   - checks the generator's guarantee: from a standstill, every platform k
            is reachable from platform k-1 (exact simulation, no shortcuts).
  play    - a look-ahead "player" (tries run-ups and jump targets, picks the best
            landing) used to sanity-check scroll pacing, combos and score curves.

Usage:
  python3 bots.py reach [seeds] [floors]
  python3 bots.py play  [seed]  [max_seconds]
"""
import copy
import sys
import time
from sim_ref import *


# ---------------------------------------------------------------------------
def simulate_jump(player, tower, t, direction, run_ticks, target, max_air_ticks=420):
    """Run `run_ticks` toward `direction`, jump, steer toward target.x. Returns (landing_platform, ticks, path_ok)."""
    p = copy.copy(player)
    ev = []
    ticks = 0
    # run phase
    for _ in range(run_ticks):
        ev.clear()
        p.step(direction, False, tower, ev)
        ticks += 1
        for e in ev:
            if e[0] == EV_LEFT_GROUND:
                return (None, ticks)          # ran off the edge before jumping
    # jump tick
    ev.clear()
    p.step(direction, True, tower, ev)
    ticks += 1
    airborne_ticks = 0
    took_off = False
    for e in ev:
        if e[0] == EV_JUMP:
            took_off = True
    if not took_off:
        return (None, ticks)
    while airborne_ticks < max_air_ticks:
        # steering: aim so that we end above the target
        dx = target.x - p.x
        # predicted drift if we stop accelerating now
        if p.vy > 0:
            steer = 0.0
            if dx > 6.0:
                steer = 1.0
            elif dx < -6.0:
                steer = -1.0
        else:
            steer = 0.0
            if dx > 8.0:
                steer = 1.0
            elif dx < -8.0:
                steer = -1.0
            # slow down if we would overshoot: braking is stronger than accel
            if p.vx * dx > 0 and abs(p.vx) * 0.25 > abs(dx):
                steer = -steer if steer != 0 else (-1.0 if p.vx > 0 else 1.0)
        ev.clear()
        p.step(steer, False, tower, ev)
        ticks += 1
        airborne_ticks += 1
        for e in ev:
            if e[0] == EV_LAND:
                return (e[1], ticks)
    return (None, ticks)


def best_plan(player, tower, t, cur_floor, target_floors, run_options, dirs=(1.0, -1.0)):
    best = None
    for tf in target_floors:
        if tf >= len(tower.platforms):
            continue
        target = tower.platforms[tf]
        for d in dirs:
            for rt in run_options:
                landed, ticks = simulate_jump(player, tower, t, d, rt, target)
                if landed is None:
                    continue
                adv = landed.floor - cur_floor
                if adv <= 0:
                    continue
                score = adv * 1000 - ticks
                if best is None or score > best[0]:
                    best = (score, d, rt, tf, landed.floor)
    return best


# ---------------------------------------------------------------------------
def reach_test(seeds, floors, verbose=False):
    t = Tuning()
    fails = 0
    total = 0
    worst = []
    for seed in seeds:
        tower = TowerGenerator(t, seed)
        tower.ensure_up_to(floors * 130.0)
        for k in range(1, min(floors, len(tower.platforms) - 1) + 1):
            prev = tower.platforms[k - 1]
            nxt = tower.platforms[k]
            # standstill on the far edge of prev, facing the target
            direction = 1.0 if nxt.x >= prev.x else -1.0
            player = Player(t)
            # start position: far edge, or beside the target if platforms overlap
            far = prev.left() + 1.0 if direction > 0 else prev.right() - 1.0
            player.x = far
            player.y = prev.y
            player.support = prev
            player.grounded = True
            player.takeoff_floor = prev.floor
            player.prev_x = player.x
            player.prev_y = player.y
            ok = False
            run_options = list(range(0, 160, 5))
            for rt in run_options:
                landed, ticks = simulate_jump(player, tower, t, direction, rt, nxt)
                if landed is not None and landed.floor >= k:
                    ok = True
                    break
            if not ok:
                # also try the opposite direction / steering variants (bot is simple)
                for rt in run_options:
                    landed, ticks = simulate_jump(player, tower, t, -direction, rt, nxt)
                    if landed is not None and landed.floor >= k:
                        ok = True
                        break
            total += 1
            if not ok:
                fails += 1
                gap = max(0.0, abs(nxt.x - prev.x) - (nxt.w + prev.w) * 0.5)
                worst.append((seed, k, round(gap, 1), round(prev.w), round(nxt.w), round(nxt.y - prev.y, 1)))
    print("pairs tested: %d  unreachable (by simple bot): %d" % (total, fails))
    for w in worst[:20]:
        print("  seed=%d floor=%d gap=%.1f prev_w=%d next_w=%d spacing=%.1f" % w)
    return fails


# ---------------------------------------------------------------------------
class PlanBot:
    """Chooses (direction, run ticks, target) by look-ahead, executes the plan on the real run."""

    def __init__(self, run, aggressiveness=1):
        self.run = run
        self.plan = None       # list of (axis, jump)
        self.aggr = aggressiveness

    def decide(self):
        run = self.run
        t = run.t
        p = run.player
        cur = p.support.floor
        max_up = 2 + 2 * self.aggr
        targets = list(range(cur + 1, cur + 1 + max_up))
        # if already standing well beyond the camera, hurry
        best = best_plan(p, run.tower, t, cur, targets, list(range(0, 100, 6)))
        if best is None:
            # nothing found: try walking toward the platform above and retry
            return None
        _, d, rt, tf, lf = best
        target = run.tower.platforms[tf]
        seq = []
        for _ in range(rt):
            seq.append((d, False))
        seq.append((d, True))
        return ("go", seq, target, d)

    def act(self):
        """Return (axis, jump) for the next tick."""
        run = self.run
        p = run.player
        if self.plan is None and p.grounded:
            dec = self.decide()
            if dec is None:
                # fallback: shuffle toward nearest higher platform
                nxt = run.tower.platforms[min(p.support.floor + 1, len(run.tower.platforms) - 1)]
                return (1.0 if nxt.x > p.x else -1.0, False)
            self.plan = list(dec[1])
            self.target = dec[2]
            self.dir = dec[3]
        if self.plan:
            return self.plan.pop(0)
        # airborne steering
        tx = self.target.x if getattr(self, "target", None) is not None else p.x
        dx = tx - p.x
        steer = 0.0
        if dx > 8.0:
            steer = 1.0
        elif dx < -8.0:
            steer = -1.0
        if p.vx * dx > 0 and abs(p.vx) * 0.25 > abs(dx):
            steer = -steer if steer != 0 else (-1.0 if p.vx > 0 else 1.0)
        if p.grounded:
            self.plan = None
        return (steer, False)


def play(seed, max_seconds=180, aggressiveness=1, verbose=True):
    t = Tuning()
    run = Run(t, seed)
    bot = PlanBot(run, aggressiveness)
    combos = []
    t0 = time.time()
    last_report = 0
    while not run.dead and run.tick_count < max_seconds * TICK_RATE:
        axis, jump = bot.act()
        ev = run.tick(axis, jump)
        for e in ev:
            if e[0] == "combo_ended" and e[5]:
                combos.append((e[1], e[2], e[3]))
            if e[0] == "speed_up" and verbose:
                print("  t=%5.1fs speed stage %d  floor=%d score=%d" % (run.tick_count * DT, e[1], run.highest_floor, run.score))
    secs = run.tick_count * DT
    print("seed %d: dead=%s time=%.1fs floor=%d score=%d jumps=%d walls=%d combos=%d best_combo_floors=%d (wall %.1fs)" % (
        seed, run.dead, secs, run.highest_floor, run.score, run.total_jumps, run.wall_rebounds, len(combos),
        max([c[1] for c in combos] or [0]), time.time() - t0))
    return run, combos


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "reach"
    if mode == "reach":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
        fl = int(sys.argv[3]) if len(sys.argv) > 3 else 900
        reach_test(list(range(1, n + 1)), fl)
    elif mode == "play":
        seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        secs = float(sys.argv[3]) if len(sys.argv) > 3 else 180
        aggr = int(sys.argv[4]) if len(sys.argv) > 4 else 1
        play(seed, secs, aggr)
