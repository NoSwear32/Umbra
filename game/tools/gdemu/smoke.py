"""
Whole-app smoke test ("monkey run") on the engine stubs.

Boots every autoload from its real script, adds the Main scene, then repeatedly presses visible buttons,
flips toggles, moves sliders, sends touch input, pauses, backgrounds the app and steps frames. The
game's own code runs for real; the engine is stubbed (see engine.py), so this finds Python-level failures
in the project's UI / view / manager code (missing keys, null dereferences, wrong arguments, broken state
transitions). It says nothing about how anything looks or feels.

    cd game && python3 -m tools.gdemu smoke [--actions N] [--seed S]
"""
import collections
import math
import random
import re
import sys

from . import engine
from . import runtime as rt

CLICK_SIGNALS = ("pressed", "toggled", "value_changed", "item_selected", "text_submitted", "button_down", "button_up", "gui_input")


def seed_profile(loader, n_runs=26, seed=5):
    """Fills the profile with records, replays, unlocks and a custom character (through the real
    end-of-run pipeline, using the helpers of tests/test_flow.gd) so screens render real data."""
    rng = random.Random(seed)
    ns = loader.ns
    flow = loader.instantiate("res://tests/test_flow.gd")
    ns["GameManager"].replay_save_delay = 0.0
    bot = flow._bot()
    for i in range(n_runs):
        if i % 6 == 0:
            live = flow._live(bot["plan"], int(bot["seed"]) + i, rng.choice([1500, 4000, 0]))
            result = live["run"].abandon()
            replay = live["rec"].finish(result, True)
        else:
            result = flow._result(rng.randint(50, 90000), rng.randint(1, 320), rng.choice([0, 3, 8, 21, 35]), rng.randint(3, 200))
            replay = flow._replay(1700000000 + i * 3600, rng.randint(1, 300), rng.randint(50, 90000))
        ns["GameManager"].finish_run(result, replay)
    for meta in list(ns["ReplayManager"].list_meta())[:3]:
        ns["ReplayManager"].rename_replay(meta["id"], "Keep " + str(meta["id"])[-4:])
    ns["CharacterManager"].import_pack_text(make_pack_text(loader, "seed_fox"))
    ns["SettingsManager"].set_value("control_chosen", True)
    ns["SettingsManager"].set_value("tutorial_done", True)
    ns["SettingsManager"].set_value("player_name", "Ada")
    ns["SaveManager"].flush()


def make_pack_text(loader, pack_id="monkey_fox"):
    """A valid .spirechar document (solid-colour sheet) built the same way the tests do."""
    import base64
    import io
    import json
    from PIL import Image as PILImage
    frame = 32
    img = PILImage.new("RGBA", (6 * frame, 4 * frame), (60, 180, 220, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    pack = loader.ns["CharacterPack"]
    return json.dumps({
        "format": pack.FORMAT_ID, "format_version": pack.FORMAT_VERSION, "id": pack_id, "name": "Monkey Fox", "author": "QA",
        "frame_size": [frame, frame], "anchor": [16, 30], "scale": 0.8, "scarf": ["#ff5a3c", "#ffd23c"],
        "animations": {
            "idle": {"row": 0, "frames": 4, "fps": 5, "loop": True}, "run": {"row": 1, "frames": 6, "fps": 14, "loop": True},
            "jump_up": {"row": 2, "frames": 2, "fps": 10, "loop": False}, "fall": {"row": 3, "frames": 2, "fps": 8, "loop": True}},
        "sheet_png_base64": base64.b64encode(buf.getvalue()).decode("ascii")})


class Invariants:
    """Consistency rules that must hold after every action, and the replay contract for every finished run:
    re-simulating the recorded inputs reproduces the live result."""

    RESULT_KEYS = ("score", "highest_floor", "best_combo_floors", "best_combo_jumps", "duration_ticks", "jumps",
                   "wall_rebounds", "combos_completed", "combo_jumps")

    def __init__(self, monkey):
        self.m = monkey
        self.replays_checked = 0
        self._finished = set()

    def fail(self, message):
        sig = "INVARIANT: " + message.split(":")[0]
        if sig not in self.m.errors:
            self.m.errors[sig] = [0, "INVARIANT VIOLATED: " + message, "after %d actions" % self.m.actions]
        self.m.errors[sig][0] += 1

    def hook_finish_run(self):
        gm = self.m.loader.ns["GameManager"]
        original = gm.finish_run

        def wrapped(result, replay):
            key = (result["seed"], result["duration_ticks"], result["score"], result["highest_floor"])
            if replay is not None and not result.get("debug_used", False) and not result.get("practice", False):
                if key in self._finished:
                    self.fail("run finished twice: seed %s, %s ticks, score %s was submitted again" % key[:3])
                self._finished.add(key)
            out = original(result, replay)
            if replay is not None and not result.get("debug_used", False):     # debug teleports are not recorded
                self.check_replay(result, replay)
            return out
        gm.finish_run = wrapped

    def check_replay(self, result, replay):
        ns = self.m.loader.ns
        player = ns["ReplayPlayer"](replay)
        if player.incompatible or player.tuning_mismatch:
            self.fail("replay contract: recorded replay is incompatible (%s / %s)" % (player.incompatible, player.tuning_mismatch))
            return
        again = player.simulate_all()
        self.replays_checked += 1
        for key in self.RESULT_KEYS:
            if again[key] != result[key]:
                self.fail("replay contract: '%s' differs between the live run (%s) and its replay (%s), seed %s, %d ticks" % (
                    key, result[key], again[key], result["seed"], result["duration_ticks"]))
                return

    def check_all(self):
        ns = self.m.loader.ns
        sm = ns["SaveManager"]
        for cat in ("score", "floor", "combo"):
            entries = sm.section("leaderboards").get(cat, [])
            if len(entries) > 20:
                self.fail("leaderboard size: '%s' holds %d entries" % (cat, len(entries)))
            values = []
            for e in entries:
                v = e.get(cat)
                if type(v) is not int:
                    self.fail("leaderboard types: '%s' entry value is %r" % (cat, v))
                else:
                    values.append(v)
            if values != sorted(values, reverse=True):
                self.fail("leaderboard order: '%s' is not sorted best-first" % cat)
        settings = ns["SettingsManager"]
        cls = type(settings)
        for key, default in cls.DEFAULTS.items():
            v = settings.get_value(key)
            if type(v) is not type(default):
                self.fail("setting type: %s is %r (default %r)" % (key, v, default))
                continue
            rng = cls.RANGES.get(key)
            if rng is not None and not (rng[0] <= v <= rng[1]):
                self.fail("setting range: %s = %r outside %r" % (key, v, list(rng)))
        cm = ns["CharacterManager"]
        if not cm.is_unlocked(cm.selected_id):
            self.fail("character: '%s' is selected but locked" % cm.selected_id)
        for k, v in sm.section("stats").items():
            if isinstance(v, (int, float)) and v < 0:
                self.fail("statistics: %s is negative (%r)" % (k, v))
        ids = [str(mm.get("id")) for mm in sm.array_section("replays") if isinstance(mm, dict)]
        if len(ids) != len(set(ids)):
            self.fail("replay index: duplicate ids")
        im = ns["InputManager"]
        axis = im.sample_axis()
        if not (-1.0 <= axis <= 1.0):
            self.fail("input: axis %r out of range" % axis)
        if not im.gameplay_enabled and axis != 0.0:
            self.fail("input: axis %r while gameplay input is disabled" % axis)
        tilt = ns["SensorManager"].tilt.axis
        if not (-1.0 <= tilt <= 1.0):
            self.fail("tilt: axis %r out of range" % tilt)
        game = self.m.game()
        if game is not None and game.run is not None:
            p = game.run.player
            for name in ("x", "y", "vx", "vy"):
                v = getattr(p, name)
                if v != v or v in (float("inf"), float("-inf")):
                    self.fail("player state: %s is %r" % (name, v))
            if not (0.0 <= p.x <= game.run.tuning.tower_width):
                self.fail("player state: x = %r outside the tower" % p.x)


class Monkey:
    def __init__(self, loader, seed=1):
        self.loader = loader
        self.rng = random.Random(seed)
        self.errors = collections.OrderedDict()      # signature -> [count, formatted trace, action]
        self.actions = 0
        self.screens_seen = set()
        self.runs_started = 0
        self.log = []
        self.pressed = collections.Counter()
        self.modes = collections.Counter()
        self.invariants = Invariants(self)

    # ---- safe execution
    def guard(self, label, fn, *args):
        try:
            return fn(*args)
        except Exception as e:                      # noqa: BLE001 - collect everything
            trace = self.loader.format_exception(e)
            sig = trace.splitlines()[0] + " | " + " / ".join(ln.strip().split(" py:")[0] for ln in trace.splitlines()[1:][-3:])
            if sig not in self.errors:
                self.errors[sig] = [0, trace, label]
            self.errors[sig][0] += 1
            return None

    def frames(self, n, dt=1.0 / 60.0):
        for _ in range(n):
            self.guard("frame", rt.TREE.step, dt)

    # ---- inspection
    def nodes(self):
        return [n for n in rt.TREE.root._gd_walk() if n._gd_in_tree and not getattr(n, "_gd_freed", False)]

    def interactive(self):
        out = []
        for n in self.nodes():
            if not getattr(n, "_gd_opaque", False):
                continue
            if hasattr(n, "is_visible_in_tree") and not n.is_visible_in_tree():
                continue
            for name, v in list(n.__dict__.items()):
                if name in CLICK_SIGNALS and isinstance(v, engine.Opaque) and v._conns:
                    out.append((n, name))
        return out

    def texts(self):
        return [str(getattr(n, "text", "")) for n in self.nodes() if isinstance(getattr(n, "text", None), str) and getattr(n, "text", "")]

    # ---- actions
    def press_random(self):
        items = self.interactive()
        if not items:
            return False
        # prefer controls that were pressed the least: the monkey explores instead of hammering one button
        weights = [1.0 / (1 + self.pressed["%s '%s'" % (sig, getattr(n, "text", ""))]) ** 2 for n, sig in items]
        node, sig = self.rng.choices(items, weights)[0]
        args = ()
        if sig == "toggled":
            args = (self.rng.random() < 0.5,)
        elif sig == "value_changed":
            lo = node.__dict__.get("min_value", 0.0)
            hi = node.__dict__.get("max_value", 1.0)
            lo = lo if isinstance(lo, (int, float)) else 0.0
            hi = hi if isinstance(hi, (int, float)) else 1.0
            args = (lo + (hi - lo) * self.rng.random(),)
        elif sig == "item_selected":
            args = (self.rng.randrange(0, 3),)
        elif sig == "text_submitted":
            args = (self.rng.choice(["", "Ada", "x" * 40, "{\"format\": 1}"]),)
        label = "%s.%s on %s '%s'" % (type(node).__name__, sig, node.name, getattr(node, "text", ""))
        self.log.append(label)
        self.pressed["%s '%s'" % (sig, getattr(node, "text", ""))] += 1
        if sig == "gui_input":
            for down in (True, False):
                ev = rt.InputEventMouseButton()
                ev.button_index = 1
                ev.pressed = down
                ev.position = rt.Vector2(self.rng.uniform(0, 1600), self.rng.uniform(0, 720))
                self.guard(label, node.gui_input.emit, ev)
            return True
        self.guard(label, getattr(node, sig).emit, *args)
        return True

    def touch(self, x, y, pressed, index=0):
        ev = rt.InputEventScreenTouch()
        ev.index = index
        ev.position = rt.Vector2(x, y)
        ev.pressed = pressed
        self.guard("touch", rt.TREE.input, ev)

    def play_burst_tilt(self, seconds):
        """Tilt mode: sweep the device angle, tap anywhere to jump."""
        inp = self.loader.ns["Input"]
        t = 0.0
        while t < seconds:
            ang = math.radians(self.rng.uniform(-28.0, 28.0))
            inp.gravity_value = rt.Vector3(9.81 * math.sin(ang), 9.81 * math.cos(ang) * 0.5, 9.81 * math.cos(ang) * 0.866)
            dur = self.rng.uniform(0.1, 0.6)
            self.frames(max(1, int(dur * 60)))
            if self.rng.random() < 0.5:
                self.touch(800.0, 300.0, True)
                self.frames(2)
                self.touch(800.0, 300.0, False)
            t += dur

    def tilt_run(self):
        """A whole run in tilt mode (analog axis: exercises the replay quantisation), then back to touch."""
        sm = self.loader.ns["SettingsManager"]
        self.guard("calibrated", sm.set_value, "tilt_calibrated", True)
        self.guard("tilt mode", sm.set_value, "control_mode", "tilt")
        self.full_run(force_quit=self.rng.random() < 0.5)
        self.guard("touch mode", sm.set_value, "control_mode", "touch")

    def play_burst(self, seconds):
        """Hold left / right with a finger, release to jump, for a while."""
        if self.loader.ns["SettingsManager"].is_tilt_mode():
            return self.play_burst_tilt(seconds)
        t = 0.0
        while t < seconds:
            side = self.rng.choice([130.0, 1470.0])
            self.touch(side, 600.0, True)
            hold = self.rng.uniform(0.05, 0.9)
            self.frames(max(1, int(hold * 60)))
            self.touch(side, 600.0, False)
            self.frames(self.rng.randint(1, 30))
            t += hold + 0.3

    def app_cycle(self):
        ev = self.loader.ns["Events"]
        self.guard("background", ev.app_backgrounded.emit)
        self.guard("notify paused", rt.TREE.notify_all, rt.NOTIFICATION_APPLICATION_PAUSED)
        self.frames(5)
        self.guard("notify focus out", rt.TREE.notify_all, rt.NOTIFICATION_APPLICATION_FOCUS_OUT)
        self.frames(3)
        self.guard("notify resumed", rt.TREE.notify_all, rt.NOTIFICATION_APPLICATION_RESUMED)
        self.guard("foreground", ev.app_foregrounded.emit)

    def key(self, keycode):
        for down in (True, False):
            ev = rt.InputEventKey()
            ev.physical_keycode = keycode
            ev.pressed = down
            self.guard("key %s" % keycode, rt.TREE.input, ev)
            self.frames(1)

    def clipboard(self):
        ds = self.loader.ns["DisplayServer"]
        ids = [str(mm["id"]) for mm in self.guard("list", self.loader.ns["ReplayManager"].list_meta) or []]
        choices = [make_pack_text(self.loader, "monkey_%d" % self.rng.randrange(1000)), "", "not json", "x" * 5000, "{\"format\": \"nope\"}"]
        if ids:
            choices.append(self.guard("export", self.loader.ns["ReplayManager"].export_text, self.rng.choice(ids)))
        ds.clipboard_set(self.rng.choice(choices))

    def game(self):
        scene = rt.TREE.current_scene
        return getattr(scene, "game", None) if scene is not None else None

    def theme_tour(self):
        """Live run teleported through every theme (draws every platform style and background)."""
        g = self.game()
        if g is None:
            return
        self.guard("start run", g.start_run)
        self.frames(5)
        for floor_index in (0, 60, 130, 250, 350, 480, 560, 700, 830, 960, 1100, 1500):
            if g.run is None or g.run.dead:
                break
            self.guard("teleport", g.run.debug_teleport_to_floor, floor_index)
            self.frames(12)
        self.guard("quit", g.quit_to_menu)
        self.frames(20)

    def full_run(self, force_quit=False):
        """A normal live run played with random holds until it ends (or a time limit), then the game-over screen."""
        g = self.game()
        if g is None:
            return
        self.guard("start run", g.start_run)
        self.frames(5)
        for _ in range(45):                                   # at most a few minutes of game time
            if g.run is None or g.run.dead or g.mode == 0:
                break
            self.play_burst(self.rng.uniform(2.0, 6.0))
        if g.run is not None and g.mode != 0 and (force_quit or self.rng.random() < 0.7):
            self.frames(30)
            self.guard("quit to menu", g.quit_to_menu)        # an abandoned run is saved like a finished one;
            #                                                   a run that already ended must not be saved twice
        self.frames(120)

    def warmup(self):
        """Fixed opening sequence, whatever the seed: one played run (checked against its replay), a replay watched
        and left through Back, and hostile settings values (which must be sanitised)."""
        self.full_run(force_quit=True)
        self.tilt_run()
        self.watch_replay(leave_with_back=True)
        sm = self.loader.ns["SettingsManager"]
        for key, val in (("vol_master", 9.0), ("touch_scale", -4.0), ("fps_limit", 999999), ("particles", 40),
                         ("tilt_custom_deg", 1000.0), ("player_name", "x" * 60), ("control_mode", "banana"), ("touch_min_hold_ms", -5)):
            self.guard("setting %s" % key, sm.set_value, key, val)
            self.guard("invariants", self.invariants.check_all)

    def watch_replay(self, leave_with_back=False):
        rm = self.loader.ns["ReplayManager"]
        g = self.game()
        metas = self.guard("list", rm.list_meta) or []
        if g is None or not metas:
            return
        meta = self.rng.choice(list(metas))
        loaded = self.guard("load", rm.load_replay, meta["id"])
        if not loaded or not loaded["ok"]:
            return
        self.guard("start replay", g.start_replay, loaded["replay"], self.rng.random() < 0.5)
        if leave_with_back:
            self.frames(90)
            self.back()
            self.frames(30)
            return
        for _ in range(self.rng.randint(3, 12)):
            self.frames(self.rng.randint(5, 240))
            if self.rng.random() < 0.6:
                self.press_random()

    def multitouch(self):
        """Several fingers at once: sliding, cancelled, released out of order."""
        pts = [(130.0, 590.0), (1470.0, 590.0), (800.0, 300.0)]
        for i, (x, y) in enumerate(pts):
            self.touch(x, y, True, index=i)
        for _ in range(self.rng.randint(1, 20)):
            i = self.rng.randrange(3)
            ev = rt.InputEventScreenDrag()
            ev.index = i
            ev.position = rt.Vector2(self.rng.uniform(0, 1600), self.rng.uniform(0, 720))
            self.guard("drag", rt.TREE.input, ev)
            self.frames(self.rng.randint(1, 6))
        order = list(range(3))
        self.rng.shuffle(order)
        for i in order:
            if self.rng.random() < 0.3:
                ev = rt.InputEventScreenTouch()
                ev.index = i
                ev.pressed = False
                ev.canceled = True
                self.guard("cancel", rt.TREE.input, ev)
            else:
                self.touch(pts[i][0], pts[i][1], False, index=i)
            self.frames(self.rng.randint(1, 8))

    def tilt(self):
        inp = self.loader.ns["Input"]
        inp.gravity_value = rt.Vector3(self.rng.uniform(-6.0, 6.0), 9.0, self.rng.uniform(-3.0, 3.0))

    def resize(self):
        ds = self.loader.ns["DisplayServer"]
        w, h = self.rng.choice([(2400, 1080), (1920, 1080), (2560, 1600), (1280, 720), (2340, 1080)])
        ds.window_size = rt.Vector2i(w, h)
        ds.safe_area = rt.Rect2i(self.rng.choice([0, 84, 120]), 0, w - self.rng.choice([0, 168, 240]), h - self.rng.choice([0, 40]))
        self.guard("layout", self.loader.ns["Events"].layout_changed.emit)
        self.guard("size_changed", rt.TREE.viewport.size_changed.emit)

    def settings_tweak(self):
        sm = self.loader.ns["SettingsManager"]
        key, val = self.rng.choice([
            ("control_mode", "tilt"), ("control_mode", "touch"), ("tilt_calibrated", True), ("tilt_preset", "high"),
            ("tilt_preset", "custom"), ("tilt_invert", True), ("touch_swap", True), ("touch_swap", False),
            ("touch_scale", 1.5), ("touch_opacity", 0.2), ("haptics", False), ("mute", True), ("mute", False),
            ("reduced_effects", True), ("screen_shake", False), ("particles", 0), ("show_fps", True), ("fps_limit", 60),
            ("vol_master", 9.0), ("touch_scale", -4.0), ("fps_limit", 999999), ("particles", 40), ("tilt_custom_deg", 1000.0),
            ("player_name", "x" * 60), ("control_mode", "banana"), ("touch_min_hold_ms", -5)])
        self.guard("setting %s" % key, sm.set_value, key, val)

    def back(self):
        self.guard("back", self.loader.ns["Events"].back_requested.emit)

    def step(self):
        self.actions += 1
        r = self.rng.random()
        if r < 0.50:
            if self.rng.random() < 0.08:
                self.clipboard()
            if not self.press_random():
                self.back()
        elif r < 0.58:
            self.back()
        elif r < 0.72:
            if self.rng.random() < 0.5:
                self.tilt()
            self.play_burst(self.rng.uniform(1.0, 6.0))
        elif r < 0.76:
            self.app_cycle()
        elif r < 0.80:
            self.key(self.rng.choice([rt.KEY_F3, rt.KEY_ESCAPE, rt.KEY_P, rt.KEY_LEFT, rt.KEY_SPACE, rt.KEY_A]))
        elif r < 0.83:
            self.resize()
        elif r < 0.86:
            self.settings_tweak()
        elif r < 0.88:
            self.theme_tour()
        elif r < 0.885:
            self.full_run()
        elif r < 0.895:
            self.tilt_run()
        elif r < 0.93:
            self.watch_replay()
        elif r < 0.94:
            self.multitouch()
        else:
            self.frames(self.rng.randint(1, 120))
        self.frames(self.rng.randint(1, 4))
        self.guard("invariants", self.invariants.check_all)
        cur = self.guard("id", self.loader.ns["UIManager"].current_id)
        if cur:
            self.screens_seen.add(cur)
        scene = rt.TREE.current_scene
        game = getattr(scene, "game", None) if scene is not None else None
        if game is not None:
            self.modes["mode=%s paused=%s dead=%s" % (game.mode, game.paused, getattr(game.run, "dead", None))] += 1


def run(loader, actions=400, seed=1, verbose=False, coverage=None, seeded=False):
    m = Monkey(loader, seed)
    m.coverage = coverage
    if coverage is not None:
        coverage.start()
    loader.boot("all")
    if seeded:
        m.guard("seed profile", seed_profile, loader)      # synthetic results: not part of the replay contract
    m.invariants.hook_finish_run()
    main = loader.instantiate("res://src/main.gd")
    m.guard("main", rt.TREE.root.add_child, main)
    rt.TREE.current_scene = main
    m.frames(90)
    if seeded:
        m.warmup()
    for _ in range(actions):
        m.step()
    if coverage is not None:
        coverage.stop()
    return m


# ---------------------------------------------------------------------------------------- coverage
class LineCoverage:
    """Records which GDScript lines ran (via sys.settrace on the generated Python)."""

    def __init__(self, loader):
        self.loader = loader
        self.executed = collections.defaultdict(set)      # generated filename -> gd lines

    def _tracer(self, frame, event, arg):
        fn = frame.f_code.co_filename
        if not fn.startswith("<gd:"):
            return None
        entry = self.loader.sources.get(fn)
        if entry is None:
            return None
        lmap = entry[1]
        hit = self.executed[fn]

        def local(frame, event, arg):
            if event == "line":
                i = frame.f_lineno - 1
                if 0 <= i < len(lmap) and lmap[i]:
                    hit.add(lmap[i])
            return local
        i = frame.f_lineno - 1
        if 0 <= i < len(lmap) and lmap[i]:
            hit.add(lmap[i])
        return local

    def start(self):
        sys.settrace(self._tracer)

    def stop(self):
        sys.settrace(None)

    def report(self, top=25, detail=None):
        rows = []
        for fn, (src, lmap) in self.loader.sources.items():
            path = fn[4:-1]
            if not path.startswith("res://src/"):
                continue
            universe = {g for g in lmap if g}
            hit = self.executed.get(fn, set()) & universe
            rows.append((path, len(hit), len(universe), sorted(universe - hit), src, lmap))
        total_hit = sum(r[1] for r in rows)
        total = sum(r[2] for r in rows)
        out = ["line coverage of loaded src/ scripts: %d / %d lines (%.1f%%)" % (total_hit, total, 100.0 * total_hit / max(1, total))]
        for path, h, n, missed, src, lmap in sorted(rows, key=lambda r: -(r[2] - r[1]))[:top]:
            out.append("  %-52s %4d / %4d  (%3.0f%%)" % (path, h, n, 100.0 * h / max(1, n)))
            if detail and path.endswith(detail):
                out.append("      missed lines: " + _ranges(missed))
        return "\n".join(out)


def _ranges(lines):
    out = []
    i = 0
    while i < len(lines):
        j = i
        while j + 1 < len(lines) and lines[j + 1] <= lines[j] + 2:
            j += 1
        out.append(str(lines[i]) if i == j else "%d-%d" % (lines[i], lines[j]))
        i = j + 1
    return ", ".join(out)
