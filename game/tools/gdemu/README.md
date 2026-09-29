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
python3 -m tools.gdemu dump res://src/core/player_controller.gd    # show the generated Python
GDEMU_DUMP=/tmp/gen python3 -m tools.gdemu test   # keep the generated Python of every script
```

## What it proves - and what it does not

| It executes for real | It does **not** cover |
| --- | --- |
| The deterministic simulation (`src/core`) tick by tick, compared with the golden vectors of the independent Python reference (`tools/reference`) | The Godot engine itself: rendering, scene tree, `Control` layout, input events, audio, sensors, import pipeline, export |
| Input controllers, leaderboards, statistics, replay encoding, save system, settings, character packs, safe-area maths | Anything in `src/ui`, `src/view` (they need `Node`/`Control`/`CanvasItem`) and the engine-heavy autoloads (audio, sensors, UI manager, debug) |
| The autoload flows: end of run -> records -> statistics -> unlocks -> replay files -> recovery (`tests/test_flow.gd`) | Real device behaviour: touch latency, tilt sensor noise, performance, Android lifecycle |
| Project configuration (`project.godot`, `export_presets.cfg`) and the shipped assets' basic properties (PNG size, WAV loop chunk, font coverage) | GDScript type-checker diagnostics (use `tools/gdcheck.py` / the engine for that) |

The emulator is my own re-implementation of GDScript semantics; a green run is evidence about the game's logic
and about the tests, **not** a substitute for running `tools/run_tests.sh` with the real engine.
Known deliberate differences: `await` completes immediately, `call_deferred` calls are queued and run by the
harness, vectors use doubles instead of 32-bit floats, dictionaries do not distinguish `1` from `1.0` as keys,
value types (`Vector2`, `Color`) are mutable Python objects.

## How much can the suites be trusted? (mutation check)

Injecting single faults into copies of the GDScript and re-running everything is how the harness was checked:
28 deliberate defects (off-by-one combo timeout, wrong rebound multiplier, RNG shift constant, inclusive/exclusive
touch threshold, dead zone, missing landing tolerance, leaderboard trimming, replay version check, PNG signature,
scroll start floor, combo exponent, theme length, safe-area scale, orientation lock, network permission, unlock threshold, missing flush, no pruning, stale replay links, kept autosave, missing
art/audio/font ...) were all detected by at least one test. See `tools/gdemu/mutation_check.py`.

## Layout

| File | Role |
| --- | --- |
| `transpile.py` | gdtoolkit parse tree -> Python source (classes, members, statics, enums, signals, lambdas, `await`, `match`) |
| `runtime.py` | GDScript/engine semantics and types used by the generated code |
| `media.py` | `Image`, `Texture2D`, `Font`, `AudioStreamWAV` backed by the real files (needs Pillow / fontTools, optional) |
| `loader.py` | project registry, lazy global names, autoload boot order, traceback mapping back to `.gd` lines |
| `__main__.py` | command line (`test`, `check`, `dump`) |
