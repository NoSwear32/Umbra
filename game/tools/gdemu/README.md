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
python3 -m tools.gdemu smoke --seeded --actions 600 --seed 7    # boot the whole app on engine stubs and press buttons
python3 -m tools.gdemu smoke --lines --detail game_scene.gd     # ... with line coverage (slow), missed lines of one file
python3 -m tools.gdemu.mutation_check    # inject faults into copies of the project; the suites must notice each
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
arithmetic. On top of that a seeded random "monkey" plays the app:

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
