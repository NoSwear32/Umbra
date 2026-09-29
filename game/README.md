# Spire Sprint

An endless, momentum-driven tower climber for Android (landscape), made with **Godot 4.3+ and GDScript**.

Run, build speed, and leap up a procedurally generated tower that never ends and never repeats. Bigger run-ups
mean bigger jumps — skip several floors at once, chain those leaps into combos, and stay ahead of the
tower's rising *surge* line. Everything you see and hear — art, characters, sound, music, logotype, UI — was
made for this project from scratch (see [docs/ORIGINALITY.md](docs/ORIGINALITY.md)).

> **Verification status — please read.** The Godot engine itself could **not** be run where this was authored,
> so nothing here has been built, imported, exported or played by the engine. What was done instead:
>
> * static checks — syntax, names, signatures and argument counts against the Godot 4.3–4.7 API dumps
>   (`tools/check_static.sh`), a Python reference implementation of the simulation with golden test vectors,
>   numeric/visual checks of the generated art, audio and font;
> * **execution on an emulator of the GDScript logic** (`python3 -m tools.gdemu test`): every test suite
>   (3.3k checks, including tick-exact comparison of the simulation with the reference) passes; 40 injected
>   defects (28 in the logic, 12 in the game loop and the run flow) are all detected; scripted "human path"
>   checks (the very first launch, the Back button in every context, one run from the first jump to results,
>   records, replay and quit) pass; and a "monkey" run that boots all autoloads and the main scene on engine
>   *stubs* visits every screen without a runtime error or a broken state invariant. Those checks found and fixed
>   four real bugs in the game code (leaving a replay, the tutorial panel and the results on screen together,
>   Back resuming a run behind an open settings screen, a stale toggle). See
>   [tools/gdemu/README.md](tools/gdemu/README.md) for exactly what that does and does not prove.
>
> The automated tests, the Android export and on-device behaviour (layout, rendering, sound, touch and tilt
> feel, lifecycle, performance) have therefore **not** been executed by the engine yet. The first things to do on
> a machine with Godot are `tools/run_tests.sh` and the checklist in [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md).
>
> A GitHub Actions job that runs the suites in the official Godot build ran automatically on the first pushes and
> **failed in its import/test step**. Its log was not analysed while this was authored, so that log is the first
> thing to look at (the job is opt-in now, see *Continuous integration* below).
>
> Expect to fix a few small engine-specific issues on first contact; the architecture and test coverage are there
> to make that quick.

## Quick start

1. Install **Godot 4.3 or newer** (the standard build, not .NET) and the matching **export templates**.
2. Open `game/project.godot` in the editor, let it import the assets once, press **F5**.
3. On a desktop: `←` `→` / `A` `D` move, `Space` jumps, mouse clicks emulate touches, `Esc` / `P` pause,
   `F3` opens the developer panel (debug builds only).
4. Run the automated tests headless:

   ```bash
   tools/run_tests.sh /path/to/godot        # imports the project, then runs every suite
   ```

5. Build for Android: see [docs/EXPORT_ANDROID.md](docs/EXPORT_ANDROID.md).

## How it plays

* **Two control modes** (chosen on first launch, changeable any time in *Settings ▸ Controls*):
  * **Touch** — hold the big **LEFT** or **RIGHT** button in the lower corners to run in that direction; **release to jump**.
    The longer you ran, the harder the jump. Multi-touch aware, adjustable button size, opacity, position,
    left/right swap and a minimum-hold filter so accidental taps do not jump.
  * **Tilt** — tilt the device to run, **tap anywhere** to jump. Smoothing, dead zone, three sensitivity presets
    plus a custom slider, a *Calibrate* step (“Hold your device in a comfortable playing position.”), invert,
    and the sensor is switched off whenever the game is paused or loses focus.
* **Momentum** — acceleration builds progressively, direction changes take time, air control is weaker than
  ground control, walls bounce you back without stealing your speed.
* **Floors & combos** — every platform is a numbered floor. Jumps that gain 2+ floors chain into a combo
  (about 3 s between landings); a finished chain pays `floors²` bonus points on top of 10 points per new floor.
* **The surge** — from floor 5 the whole tower starts to rise, faster every ~30 s. Fall below the bottom of the
  screen and the run is over.
* **11 tower themes** (every 100 floors; floor 1000+ is the endless finale), 7 unlockable characters plus
  custom character packs, local leaderboards (score / floor / combo), lifetime statistics, and replays you can
  watch, rename, share and delete.

## Project layout

```
game/
├─ project.godot            landscape, keep-height scaling, autoloads, sensors
├─ export_presets.cfg       Android APK (sideload) + AAB (Google Play) presets
├─ resources/game_tuning.tres   every gameplay number in one editable resource
├─ scenes/main.tscn         one scene: src/main.gd builds everything else in code
├─ src/
│  ├─ core/       deterministic simulation (no nodes!): PlayerController, PlatformGenerator, RunManager,
│  │              ScrollDifficultyManager, ComboManager, ScoreManager, ReplayRecorder/Player/Data, SimRng
│  ├─ data/       GameTuning, leaderboard providers, statistics, character definitions/packs
│  ├─ input/      TouchInputController, TiltInputController (pure logic, unit tested)
│  ├─ autoload/   GameManager, SaveManager, SettingsManager, InputManager, SensorManager, AudioManager,
│  │              ThemeManager, CharacterManager, LeaderboardManager, StatisticsManager, ReplayManager,
│  │              UIManager, AndroidLifecycleManager, DebugManager, Events
│  ├─ view/       GameScene (orchestrator), TowerView, PlayerView, BackdropView, FxLayer, HUD, camera
│  ├─ ui/         UIKit (theme), screens (menu, settings, scores...), overlays (pause, game over, tutorial)
│  └─ util/       SafeArea, Haptics, ShareUtil, Fmt
├─ assets/        art (themes, characters, logo), display font, audio (SFX + music), launcher icons — all generated
├─ tests/         headless test suites + golden vectors from the Python reference simulation
├─ tools/         generators (audio, art), reference simulation, static checker, scripts
└─ docs/          architecture, tuning guide, QA checklist, export guide, formats
```

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | modules, the fixed-timestep loop, determinism rules, save system, UI structure |
| [docs/TUNING.md](docs/TUNING.md) | every tunable value: meaning, unit, default, what changing it does |
| [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md) | test cases A–O, controls, lifecycle, devices, performance |
| [docs/EXPORT_ANDROID.md](docs/EXPORT_ANDROID.md) | toolchain, signing, command-line and editor export, troubleshooting |
| [docs/REPLAY_FORMAT.md](docs/REPLAY_FORMAT.md) | replay file format and the determinism contract |
| [docs/ORIGINALITY.md](docs/ORIGINALITY.md) | what is original, what is third-party (the engine), how assets are made |

## Tooling

| Command | Purpose |
| --- | --- |
| `tools/run_tests.sh [godot]` | import + run all headless test suites (needs Godot) |
| `tools/check_static.sh [api.json]` | gdparse, gdlint, gdcheck (names/signatures vs engine API) and golden-vector check (no engine needed at run time) |
| `python3 -m tools.gdemu test` / `smoke` | run the tests / a whole-app monkey run on the GDScript emulator (no engine; see `tools/gdemu/README.md`) |
| `python3 tools/reference/gen_golden.py` | regenerate `tests/golden/*.json` from the Python reference simulation |
| `python3 tools/generate_audio.py` | regenerate all sound effects and music (`assets/audio`) |
| `python3 tools/gen_art.py [themes\|characters\|ui]` | regenerate themes, character sheets, logo and icons |
| `python3 tools/gen_font.py` | regenerate the game's own display typeface (`assets/fonts/spire_display.ttf`) |

**Continuous integration.** `.github/workflows/spire-sprint.yml` (repository root; runs only for changes under
`game/`) has two jobs. The *emulated* job — static checks, all test suites, the scripted first-launch / Back-button /
run-lifecycle checks and a short monkey run on the GDScript emulator — is pure Python and runs on every push and pull
request. The *godot* job runs the same suites inside the official Godot 4.3 headless build (plus the API-based static
checker against that engine's own `extension_api.json`); because it downloads and executes the engine binary it is
**opt-in** — start it from *Actions ▸ Spire Sprint (Godot game) ▸ Run workflow*. On the first pushes it ran
automatically and **failed in its "import the project and run every test suite" step**; the cause has not been
investigated, so that log is the first thing to read. Delete the workflow if you do not want it.

The art and audio generators need Python 3 with `numpy` and `Pillow`, the font generator additionally `fonttools` and
`shapely`; `gdcheck.py` and the linters need `gdtoolkit`.

## Determinism in one paragraph

The simulation (`src/core`) is a plain-data model stepped at a fixed 120 Hz using only `+ - * /` and `sqrt`,
seeded by a custom xorshift generator. The renderer interpolates between ticks, so 60/90/120/144 Hz displays run
*identical* physics. A run is fully described by its seed, its tuning snapshot and the list of input changes with
their tick numbers — which is exactly what a replay stores. A pure-Python twin of the simulation
(`tools/reference/sim_ref.py`) produces golden vectors that the GDScript tests compare against tick by tick.

## Custom characters

The **Character** screen has *IMPORT FILE* (Android's file picker) and *PASTE PACK* (from the clipboard). A
`.spirechar` file is one JSON document with an embedded PNG sprite sheet (frames of 16–256 px, one row per
animation, 1536 px maximum sheet size). Packs can never run code; every field is validated against hard limits
(see `src/data/character_pack.gd`). `python3 tools/make_character_pack.py --help` builds a pack from a PNG sheet,
for example `python3 tools/make_character_pack.py assets/art/characters/pip.png --id my_fox --name "My Fox"`.
