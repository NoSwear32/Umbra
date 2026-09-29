"""
Mutation check for the gdemu harness: every injected fault must make at least one suite fail or crash.

    cd game && python3 -m tools.gdemu.mutation_check

Each mutation edits a copy of the project (never the working tree) and runs `python3 -m tools.gdemu test`
in it. A "survivor" means the tests would not notice that defect.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.getcwd()

# (description, file, old text, new text). "DELETE" removes the file named in `old`.
MUTATIONS = [
    ("rebound keeps less momentum", "src/core/player_controller.gd",
     "vx = float(direction) * speed * t.wall_rebound_multiplier", "vx = float(direction) * speed * t.wall_rebound_multiplier * 0.9"),
    ("combo timeout off by one", "src/core/combo_manager.gd",
     "\t\tif timer <= 0:\n\t\t\t_end(SimConst.COMBO_END_TIMEOUT)", "\t\tif timer < 0:\n\t\t\t_end(SimConst.COMBO_END_TIMEOUT)"),
    ("combo needs 3 floors", "src/core/combo_manager.gd", "floors_advanced >= t.combo_min_floors", "floors_advanced > t.combo_min_floors"),
    ("touch min-hold exclusive", "src/input/touch_input_controller.gd", "held >= min_hold", "held > min_hold"),
    ("tilt dead zone ignored", "src/input/tilt_input_controller.gd",
     "var m: float = absf(rel_deg) - dead_zone", "var m: float = absf(rel_deg)"),
    ("rng shift constant", "src/core/sim_rng.gd", "v = v ^ (v >> 17)", "v = v ^ (v >> 16)"),
    ("scroll stage boundary", "src/core/scroll_difficulty_manager.gd",
     "if _local_ticks >= _stage_ticks:", "if _local_ticks > _stage_ticks:"),
    ("swept landing tolerance", "src/core/player_controller.gd",
     "if y >= top - 0.01 and y_new <= top:", "if y >= top and y_new < top:"),
    ("jump buffer never consumed", "src/core/player_controller.gd",
     "\tif jump_buf > 0:\n\t\tjump_buf -= 1", "\tif jump_buf > 1:\n\t\tjump_buf -= 1"),
    ("stats count practice runs", "src/data/stats_data.gd",
     'if bool(result.get("practice", false)) or bool(result.get("debug_used", false)):', 'if bool(result.get("debug_used", false)):'),
    ("leaderboard never trims", "src/data/local_leaderboard_provider.gd",
     "while list.size() > MAX_ENTRIES:", "while list.size() > MAX_ENTRIES + 5:"),
    ("replay version unchecked", "src/core/replay_data.gd",
     'if int(d.get("format_version", 0)) != FORMAT_VERSION:', 'if int(d.get("format_version", 0)) < 0:'),
    ("PNG signature unchecked", "src/data/character_pack.gd",
     "if png[i] != int(PNG_SIGNATURE[i]):", "if png[i] < 0:"),
    ("scroll starts at floor 6", "src/data/game_tuning.gd",
     "@export var scroll_start_floor: int = 5", "@export var scroll_start_floor: int = 6"),
    ("combo exponent 3", "src/data/game_tuning.gd", "var combo_bonus_exponent: int = 2", "var combo_bonus_exponent: int = 3"),
    ("theme every 90 floors", "src/autoload/theme_manager.gd", "const FLOORS_PER_THEME: int = 100", "const FLOORS_PER_THEME: int = 90"),
    ("safe area swaps scale", "src/util/safe_area.gd",
     "var sx: float = vp_size.x / float(win_size.x)", "var sx: float = vp_size.y / float(win_size.y)"),
    ("landscape lock removed", "project.godot", "window/handheld/orientation=4", "window/handheld/orientation=0"),
    ("internet permission added", "export_presets.cfg", "permissions/internet=false", "permissions/internet=true"),
    ("theme art missing", "DELETE", "assets/art/themes/wall_03.png", None),
    ("music loop chunk lost", "DELETE", "assets/audio/music_game.wav", None),
    ("font missing", "DELETE", "assets/fonts/spire_display.ttf", None),
    # flows across the autoloads
    ("unlock threshold off by one", "src/autoload/character_manager.gd",
     "if float(StatisticsManager.get_stat(d.unlock_stat)) >= float(d.unlock_target):",
     "if float(StatisticsManager.get_stat(d.unlock_stat)) > float(d.unlock_target):"),
    ("finished runs are not flushed", "src/autoload/game_manager.gd", "\tSaveManager.flush()\n\tlast_summary = summary", "\tlast_summary = summary"),
    ("replays are never pruned", "src/autoload/replay_manager.gd", "\tif over <= 0:\n\t\treturn", "\treturn"),
    ("deleted replays stay linked", "src/autoload/replay_manager.gd", "\tLeaderboardManager.forget_replay(id)\n", ""),
    ("recovery keeps the autosave", "src/autoload/game_manager.gd",
     "\tclear_active_run()\n\tif bool(result.get(\"practice\", false))", "\tif bool(result.get(\"practice\", false))"),
    ("setting names are not limited", "src/autoload/settings_manager.gd",
     "out = String(out).strip_edges().substr(0, PLAYER_NAME_MAX)", "out = String(out).strip_edges()"),
]


# faults in code that only the smoke run executes (game loop, replay exit, settings sliders)
SMOKE_MUTATIONS = [
    ("live loop forgets to record the axis", "src/view/game_scene.gd",
     "recorder.record(n, q, jump)", "recorder.record(n, 0, jump)"),
    ("a run can be finished twice", "src/view/game_scene.gd",
     "if run == null or mode == Mode.REPLAY or _run_ended_handled:\n\t\treturn\n\t_run_ended_handled = true\n\tvar result: Dictionary = run.abandon()",
     "if run == null or mode == Mode.REPLAY:\n\t\treturn\n\t_run_ended_handled = true\n\tvar result: Dictionary = run.abandon()"),
    ("settings are not clamped", "src/autoload/settings_manager.gd",
     "\t\t\tout = clampf(float(out), float(r[0]), float(r[1]))", "\t\t\tout = float(out)"),
    ("leaderboard is not kept sorted", "src/data/local_leaderboard_provider.gd",
     "list.insert(rank - 1, e.duplicate())", "list.append(e.duplicate())"),
]


def run_one(name, rel, old, new, smoke=False):
    tmp = tempfile.mkdtemp()
    try:
        for d in ("src", "tests", "tools", "resources", "assets"):
            shutil.copytree(os.path.join(ROOT, d), os.path.join(tmp, d), ignore=shutil.ignore_patterns("__pycache__"))
        for f in ("project.godot", "export_presets.cfg", "icon.svg"):
            shutil.copy(os.path.join(ROOT, f), tmp)
        if rel == "DELETE":
            os.remove(os.path.join(tmp, old))
        else:
            path = os.path.join(tmp, rel)
            text = open(path, encoding="utf-8").read()
            if old not in text:
                return None, "mutation target not found"
            open(path, "w", encoding="utf-8").write(text.replace(old, new, 1))
        env = dict(os.environ, GDEMU_TMP=os.path.join(tmp, ".t"))
        cmd = ["smoke", "--seeded", "--actions", "60", "--seed", "3"] if smoke else ["test"]
        r = subprocess.run([sys.executable, "-m", "tools.gdemu"] + cmd, cwd=tmp, capture_output=True, text=True, env=env)
        text = r.stdout + r.stderr
        if smoke:
            first = [ln for ln in text.splitlines() if ln.startswith("unique errors")]
            return r.returncode != 0, (first[-1] if first else text[-200:])
        summary = [ln for ln in text.splitlines() if ln.startswith("passed:")]
        return r.returncode != 0, (summary[-1] if summary else text[-200:])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    if not os.path.isfile(os.path.join(ROOT, "project.godot")):
        print("run this from the folder that contains project.godot")
        return 2
    survivors = []
    smoke = "--smoke" in sys.argv
    for name, rel, old, new in (SMOKE_MUTATIONS if smoke else MUTATIONS):
        killed, info = run_one(name, rel, old, new, smoke)
        if killed is None:
            print("%-34s %s" % (name, info))
            survivors.append(name + " (target missing)")
            continue
        print("%-34s %s   %s" % (name, "KILLED  " if killed else "SURVIVED", info))
        if not killed:
            survivors.append(name)
    print("survivors:", survivors or "none")
    return 1 if survivors else 0


if __name__ == "__main__":
    sys.exit(main())
