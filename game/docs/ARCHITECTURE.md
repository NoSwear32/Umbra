# Architecture

Spire Sprint is split into a **deterministic simulation** that knows nothing about the engine's scene tree, and a
**presentation layer** that reads the simulation and never changes it.

```
 input devices ──► InputManager ──(axis, jump)──┐
   touch / tilt / keys      ▲                    ▼
                  Touch/TiltInputController   RunManager.tick()  ◄── fixed 120 Hz, in GameScene._process
                            │                    │
                            │                    ├─ PlayerController   movement, jumps, walls, one-way landing
                            │                    ├─ PlatformGenerator  seeded endless tower
                            │                    ├─ ScrollDifficultyManager   surge + camera bottom
                            │                    ├─ ComboManager / ScoreManager
                            │                    └─ signals: jumped, landed, wall_rebounded, new_floor_reached,
                            ▼                       combo_*, speed_stage_changed, run_ended ...
                    ReplayRecorder ◄─ same (axis, jump) every tick
                                                     │
                                                     ▼
       GameScene ─► PlayerView / TowerView / BackdropView / FxLayer / HUD / CameraController / AudioManager
```

## Layers

| Layer | Directory | May use | Rules |
| --- | --- | --- | --- |
| Simulation | `src/core` | `SimConst`, `SimRng`, `GameTuning` | No nodes, no autoloads, no engine randomness/time. Only `+ − * /` and `sqrt` on floats. |
| Data | `src/data` | core | Tuning resource, leaderboard providers, statistics rules, character definitions and pack validation. Plain classes, unit-testable without a scene. |
| Input logic | `src/input` | — | Pure state machines fed with synthetic events (touch zones, tilt filter). |
| Services | `src/autoload` | everything below | Autoloaded singletons; they talk to each other through direct calls for commands and through `Events` (signal bus) for notifications. |
| View | `src/view`, `src/ui` | services, core (read-only) | Nodes, drawing, tweens, particles. Built in code, so there are no scene files to merge. |

## The fixed-timestep loop

`GameScene._process(delta)` accumulates real time (clamped to `MAX_FRAME_TIME`) and runs `RunManager.tick()`
zero or more times at exactly `1 / SimConst.TICK_RATE` (120 Hz), with a cap of `MAX_STEPS_PER_FRAME` so a long stall
never causes a spiral of death. The remainder of the accumulator becomes the interpolation factor
`alpha`, and every view interpolates between the previous and the current simulated state. Consequences:

* 60, 90, 120 or 144 Hz screens all run *exactly* the same physics; higher refresh rates just look smoother.
* The physics never depends on frame time; slow devices lose smoothness, not correctness.
* Input is sampled once per tick (`InputManager.sample_axis()` / `consume_jump()`); touches are processed in
  `_input()` with no per-frame polling latency.
* Pausing simply stops accumulating; nothing runs on a timer that needs to be paused separately (combo and
  scroll timers count *ticks*).

Coordinates: the simulation uses **altitude** (y grows upwards, feet position) and `x` in `0 … tower_width`.
Views convert to screen space (`y_screen = −altitude`) in `CameraController.apply_to`.

## Determinism contract

1. `SimRng` (xorshift128, 32-bit) is the only random source inside `src/core`.
2. The order of random draws in `PlatformGenerator` is part of the replay format — never reorder them.
3. All timers are integers counting ticks (`GameTuning.coyote_ticks()` etc. use `int(x · 120 + 0.5)`).
4. Input reaches the simulation as *(axis quantised to −127…127, jump flag)* per tick — exactly what replays store.
5. Any change to the arithmetic in `src/core` requires bumping `SimConst.SIM_VERSION`.

`tools/reference/sim_ref.py` re-implements the same simulation in Python; `tools/reference/gen_golden.py` writes
`tests/golden/*.json` (RNG streams, tower layouts, physics scenarios, bot runs, combo sequences) and the GDScript
tests replay those inputs and compare state tick by tick. Python and GDScript agree because both use IEEE-754
doubles and the same operation order.

## Modules

| Module | Responsibility |
| --- | --- |
| `GameManager` | App state machine (menu / playing / paused / game over), run lifecycle, results → records/statistics/replays. |
| `RunManager` | One run: owns player, tower, scroll, combo and score; `tick(axis, jump)`; emits gameplay signals; builds the result dictionary. |
| `PlayerController` | Kinematic movement: progressive acceleration, friction, air control, speed-dependent jump, wall rebounds, swept one-way landing, coyote/buffer. |
| `PlatformGenerator` | Deterministic tower: floor spacing, widths, patterns (stairs, zig-zag), landmarks, reachability guarantee. |
| `ScrollDifficultyManager` | Surge start at floor 5, stage every ~30 s, camera-bottom (kill line) and smooth follow. |
| `ComboManager`, `ScoreManager` | Combo chain rules and integer-safe score. |
| `ReplayRecorder` / `ReplayPlayer` / `ReplayData` | Record inputs by tick, re-simulate for playback, versioned validated file format. |
| `InputManager` | One place turning devices into `(axis, jump)`; block rectangles keep taps on the Pause button from jumping. |
| `TouchInputController` | Two zones, hold to run, release to jump, min-hold filter, multi-touch. |
| `TiltInputController` + `SensorManager` | Gravity vector → angle → calibration → smoothing → dead zone → curve; settle/spike protection; sensor only polled while playing. |
| `CameraController` | Screen shake and smoothing for the *view* (never the simulation). |
| `ThemeManager` | 11 environments, colour blending between themes, background texture preloading. |
| `CharacterManager` | Roster, unlock rules, custom packs (`CharacterPack` validation). |
| `AudioManager` | Bus setup, pooled SFX players, crossfaded looping music, volume/mute, lifecycle pause. |
| `SaveManager` | Versioned JSON profile, atomic writes, backup, migration (see below). |
| `SettingsManager`, `StatisticsManager`, `LeaderboardManager` | Typed settings with ranges; lifetime statistics; local leaderboards behind a provider interface. |
| `UIManager` | Screen stack, transitions, dialogs, toasts, Android back handling. |
| `AndroidLifecycleManager` | Focus/pause/resume/back/close → game events; forces landscape and keeps the screen on. |
| `DebugManager` | Developer panel (debug builds only, see below). |

## Save system

* One JSON profile `user://spire_sprint/profile.json` with `version`, `settings`, `stats`, `leaderboards`,
  `unlocked`, `replays` (metadata only), `custom_characters`, `selected_character`. Replay bodies are separate files
  (`replays/<id>.replay.json`) and custom character packs live in `characters/<id>.spirechar`.
* **Atomic write**: write `profile.tmp.json`, read it back and parse-verify it, move the old file to
  `profile.bak.json`, rename the temp file into place. A crash at any step leaves a loadable file.
* **Load order**: main → temp (newer than backup) → backup → fresh profile. A corrupted main file is kept as
  `profile.corrupt.json` for inspection.
* **Migration**: `SaveManager.migrations[n]` upgrades version *n* to *n + 1*; missing sections are filled with defaults;
  a file from a *newer* game version is never downgraded or wiped (unknown keys survive).
* Saves are debounced (dirty flag + short timer) and flushed on pause, focus loss and exit.
* **Test sandbox**: `SaveManager.enter_sandbox(dir)` redirects the profile, replay and character folders to a scratch
  directory and starts from a fresh profile; `leave_sandbox()` restores the player's own data. `tests/test_flow.gd`
  uses it to exercise the real managers without ever touching a real profile.

## Replays

A replay is `seed + tuning snapshot + input events by tick` (see [REPLAY_FORMAT.md](REPLAY_FORMAT.md)). Live runs
record continuously; an interrupted run is stored as an incomplete snapshot and reconstructed by re-simulation.
Replays are watch-only: they never write statistics, records or leaderboards, and nothing is ever submitted
online.

## Views and UI

* `GameScene` orchestrates: menu backdrop, live run, tutorial, replay, pause, game over. Modes: `MENU`, `LIVE`,
  `TUTORIAL`, `REPLAY`.
* `TowerView` pools `PlatformView` nodes (drawn once, recycled as the camera rises); `BackdropView` moves tiled
  `TextureRect` layers instead of redrawing; `FxLayer` uses pooled particle arrays; nothing allocates per frame in
  the steady state.
* `UIKit` builds the whole UI theme in code (type variations, generated slider grabbers) so screens are ~100 lines
  each. `SafeArea` converts the OS cut-out/gesture insets to logical units and every screen lays out inside them.
* Scaling: `canvas_items` + `keep_height` on a 1280 × 720 base — every device shows the same 720 units of height;
  ultra-wide screens only get more decoration on the sides, never a wider playfield.

## Android specifics

* Landscape (sensor, both directions) is set in the project *and* re-applied at runtime; immersive mode comes from
  the export preset; the screen stays on while the app runs.
* `NOTIFICATION_APPLICATION_PAUSED` / `FOCUS_OUT` → sensor stopped, touches cancelled, audio paused, profile flushed,
  the run pauses itself. Coming back shows the pause menu; the run never resumes on its own.
* Tilt: Godot delivers the gravity vector with +x toward the right edge of the *screen* in both landscape
  orientations, so tilt-right is the sign of `gravity.x`; the angle is `asin(gx / |g|)`, independent of device pitch.
* The back button/gesture maps to `Events.back_requested`: it closes overlays and screens, pauses during play and asks
  for confirmation on the main menu.
* Sharing replays uses Android's `ACTION_SEND` through `JavaClassWrapper`, with a clipboard fallback; imports use the
  system file picker where the engine offers it (Storage Access Framework), so no storage permission is needed.

## Developer tools

Available **only** in debug builds (`OS.is_debug_build()`; the manager is inert in release exports): open with `F3`
or by tapping the version in *About* seven times. Teleport to floor 100/500/1000, next theme, scroll stage ±,
new/same seed, invincibility, force game over, 15 FPS simulation. Any run that used a debug command is flagged
*debug used* and never reaches records, leaderboards or statistics. The FPS counter is a normal user setting.

## Testing

`tests/run_tests.gd` runs the suites in `tests/` inside the engine; see [QA_CHECKLIST.md](QA_CHECKLIST.md) for how
they map to the required test cases A–O and for the manual device checklist.

`tools/gdemu` runs the same suites — and a whole-app monkey run on engine stubs — without the engine, by translating
the GDScript to Python; see its README for what that does and does not prove. `GameManager.replay_save_delay`
(0.45 s in the game, 0 in tests) is the one production knob that exists for testability: it makes the deferred
replay write synchronous.
