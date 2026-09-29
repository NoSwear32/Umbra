# gdemu - run the game's GDScript logic without the Godot engine

`gdemu` transpiles the project's GDScript to Python and runs it under CPython on a small emulated runtime
(GDScript number semantics, `Array`/`Dictionary`/`Packed*Array`, vectors, signals, JSON, files, a few autoload
singletons). It exists because the game was written in an environment where the Godot executable could not
be run: it lets the **engine-independent logic and the test suites be executed anyway**.

```bash
cd game
pip install gdtoolkit           # parser used by the transpiler (Pillow / fonttools optional, see below)
python3 -m tools.gdemu test     # all suites in tests/ (same list as tests/run_tests.gd)
python3 -m tools.gdemu test physics input     # only some suites
python3 -m tools.gdemu check    # transpile every script under src/ and list what it cannot resolve
python3 -m tools.gdemu first-launch [skip]   # the very first launch as a new player plays it (selector, menu, tutorial)
python3 -m tools.gdemu navigation           # what Back does in every context (menus, pause, settings over a paused run, results, replay)
python3 -m tools.gdemu lifecycle            # one run from the first jump to the results, records, replay file, rename, watch, restart and quit
python3 -m tools.gdemu smoke --seeded --actions 600 --seed 7    # boot the whole app on engine stubs and press buttons
python3 -m tools.gdemu smoke --lines --detail game_scene.gd     # ... with line coverage (slow), missed lines of one file
python3 -m tools.gdemu.mutation_check    # inject faults into copies of the project; the suites must notice each
python3 -m tools.gdemu.mutation_check --smoke | --lifecycle   # the same for faults only the monkey run / the scripted run flow can see
python3 -m tools.gdemu dump res://src/core/player_controller.gd    # show the generated Python
GDEMU_DUMP=/tmp/gen python3 -m tools.gdemu test   # keep the generated Python of every script
```

## What it proves - and what it does not

| It executes for real | It does **not** cover |
| --- | --- |
| The deterministic simulation (`src/core`) tick by tick, compared with the golden vectors of the independent Python reference (`tools/reference`) | The Godot engine itself: rendering, scene tree, `Control` layout, input events, audio, sensors, import pipeline, export |
| Input controllers, leaderboards, statistics, replay encoding, save system, settings, character packs, safe-area maths | Engine behaviour of anything in `src/ui`, `src/view` and the engine-heavy autoloads (audio, sensors, UI manager, debug) — `test` skips them, `smoke` runs them on stubs |
| The autoload flows: end of run -> records -> statistics -> unlocks -> replay files -> recovery (`tests/test_flow.gd`) | Real device behaviour: touch latency, tilt sensor noise, performance, Android lifecycle |
| Under `smoke`: the UI screens, views, overlays and engine-heavy autoloads run their own code (on stubs) | What they look like, feel like, or how the real engine reacts to what they do |
| Project configuration (`project.godot`, `export_presets.cfg`) and the shipped assets' basic properties (PNG size, WAV loop chunk, font coverage) | GDScript type-checker diagnostics (use `tools/gdcheck.py` / the engine for that) |

The emulator is my own re-implementation of GDScript semantics; a green run is evidence about the game's logic
and about the tests, **not** a substitute for running `tools/run_tests.sh` with the real engine.
Known deliberate differences: `await` completes immediately, `call_deferred` calls are queued and run by the
harness, vectors use doubles instead of 32-bit floats, dictionaries do not distinguish `1` from `1.0` as keys,
value types (`Vector2`, `Color`) are mutable Python objects.

## Smoke / monkey run (`smoke`)

`smoke` boots **every** autoload from its real script and adds the Main scene, but the engine underneath is a set
of permissive stubs (`engine.py`): nodes keep children, parents, properties and lifecycle order (`_ready`,
`_process`, `_input`, `_draw`), signals can be connected and emitted, tweens complete on the next frame, and
everything else the engine would compute (layout, fonts, audio, themes) is an opaque value that survives
arithmetic. A few engine rules that commonly bite dynamic UI code *are* enforced: touching a freed node fails,
signals skip freed receivers, `add_child()` on a parent that is busy setting up its children fails, and
`get_tree()` / `get_viewport()` are unavailable outside the tree. On top of that a seeded random "monkey" plays the app:

* presses visible buttons (preferring ones not yet pressed), moves sliders, flips toggles, drives custom controls
  through `gui_input`, submits text, sets the clipboard to valid / invalid replays and character packs;
* plays with touch (hold, release, several fingers, drags, cancels) and with tilt (`Input.get_gravity`), pauses,
  presses Back / Escape / F3, backgrounds and resumes the app (`Events` and engine notifications), resizes the window
  and safe area, flips settings, teleports through every theme with the debug tools, watches saved replays;
* `--seeded` first fills the profile (records, replays, unlocks, a custom character) through the real end-of-run
  pipeline, so lists and statistics render real data.

After every action the monkey also checks invariants (leaderboards sorted, at most 20 entries and integer values;
every setting has its declared type and stays inside its range; the selected character is unlocked; no negative
statistics; no duplicate replay ids; input axes within [-1, 1] and zero while gameplay input is off; finite player
state), and **every finished live run is re-simulated from the replay the recorder wrote and must reproduce the
live result exactly** (score, floor, combos, jumps, rebounds, duration) — that ties `GameScene`'s fixed-step loop,
`InputManager` sampling and `ReplayRecorder` to `ReplayPlayer`. A run submitted twice is a violation too. A fixed
warm-up (one played and quit run, a replay watched and left with Back, hostile settings values) runs first when
`--seeded` is given.

`first-launch` is the scripted version of the most important path: a fresh profile, logo splash, control selector,
main menu, PLAY, the interactive tutorial played with real touches (or skipped), then a real run that is paused and
resumed. It checks the expected screens and states at every step. (It found that the tutorial's "you're ready"
panel and the results panel could be on screen at the same time while the practice tower kept rising; the practice
run now stands still behind the panel.)

`navigation` scripts the Android Back button through every context — main menu (asks before leaving), each sub
screen, nested screens, a live run (pause / resume), Settings and calibration opened from the pause menu, the results,
a watched replay. It found that Back inside Settings-from-the-pause-menu resumed the run *behind* the settings
screen (the game was asked before the open screen), that Back did nothing on root screens opened from the game, and
that Back did nothing on the results shown after a replay; all three are fixed in `UIManager.back()` /
`GameScene.handle_back()`. The monkey also checks overlay invariants after every action (results / pause menu /
replay controls / tutorial panel never on screen together, gameplay input off behind them, no menu screen open over a
running unpaused game).

`lifecycle` plays one complete run through the real screens and autoloads: the run ends, the results panel, record banner,
leaderboard entry and replay file appear, the rename prompt works, the replay can be watched (at 4x, to its end, again, and left
with EXIT back to the results), PLAY AGAIN starts a fresh tower, RESTART asks only when the run is worth keeping, and QUIT TO MENU
from a live run saves it and shows the toast.

Every Python-level exception is collected with a GDScript file/line trace. It is a *smoke test*: it finds the
project's own runtime errors (missing keys, null dereferences, bad arguments, broken state transitions) but
cannot tell whether something looks right, and because the stubs accept anything it can not find engine API
misuse (that is what `tools/gdcheck.py` and the real engine are for). Its first run found a genuine defect:
leaving a replay nulled the replay player while the scene kept updating in REPLAY mode for the length of the
fade-out (fixed in `GameScene._on_replay_exit`).

## How much can the suites be trusted? (mutation check)

Injecting single faults into copies of the GDScript and re-running everything is how the harness itself was checked.
`python3 -m tools.gdemu.mutation_check` applies 28 deliberate defects — an off-by-one combo timeout, a weaker wall
rebound, an RNG shift constant, an exclusive touch threshold, an ignored tilt dead zone, a missing landing
tolerance, unchecked replay version and PNG signature, leaderboards that never trim, statistics that count practice
runs, a wrong scroll start floor, combo exponent, theme length and safe-area scale, a lifted landscape lock, an added
network permission, a deleted texture / music loop / font, an off-by-one unlock threshold, a missing flush after a
run, replays that are never pruned or stay linked after deletion, an autosave that is not consumed, unlimited player
names — and every one of them is detected by at least one test.

`--smoke` runs four further faults in code only the smoke run executes (the live loop forgetting to record the
axis, a run that can be finished twice, unclamped settings, an unsorted leaderboard); the monkey's invariants
catch all four.

`--lifecycle` runs eight faults in the player-facing run flow that only the scripted `lifecycle` check walks
through (RESTART that never asks, quitting a run without saving it, every new run on the same tower, a replay
watched from the results that leaves for the menu, WATCH AGAIN forgetting where it came from, a rename prompt that
ignores the typed name, the pause button or gameplay input left on under the results); all eight are detected, each
with a readable "FAIL ..." line.

## Layout

| File | Role |
| --- | --- |
| `transpile.py` | gdtoolkit parse tree -> Python source (classes, members, statics, enums, signals, lambdas, `await`, `match`) |
| `runtime.py` | GDScript/engine semantics and types used by the generated code |
| `media.py` | `Image`, `Texture2D`, `Font`, `AudioStreamWAV` backed by the real files (needs Pillow / fontTools, optional) |
| `engine.py` | permissive stand-ins for engine nodes, resources and singletons (used by `smoke`) |
| `smoke.py` | the monkey, profile seeding and line coverage |
| `mutation_check.py` | fault injection to measure how sensitive the suites are |
| `gd_utils.py` | names of GDScript utility functions (from the 4.3 API dump) |
| `loader.py` | project registry, lazy global names, autoload boot order, traceback mapping back to `.gd` lines |
| `__main__.py` | command line (`test`, `check`, `dump`) |
