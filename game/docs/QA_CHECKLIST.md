# QA checklist

Two parts: what the **automated tests** cover (headless, `tools/run_tests.sh`) and what has to be checked
**by hand on a device**. The automated part could not be executed where the project was written (no engine
available), so run it first — every unchecked box below is work still to be confirmed.

## 1. Required test cases A–O

| # | Case | Automated | On device |
| --- | --- | --- | --- |
| **A** | Standing jump | `test_physics.gd` — apex ≈ 1.5 floors | ☐ standing jump feels like a small hop |
| **B** | Moderate speed → noticeably higher | `test_physics.gd` — apex ≥ 1.5× the standing jump, ≥ 2 floors | ☐ |
| **C** | Max speed → large multi-floor jump | `test_physics.gd` — ≥ 5 floors, bounded by the curve | ☐ ~7 floors at full speed |
| **D** | Wall at high speed rebounds, momentum kept | `test_physics.gd` — reversed velocity, ≥ 90 % kept | ☐ bounce feels lively, not sticky |
| **E** | One-way platforms: rise through, land on top | `test_physics.gd` + swept-landing (tunnelling) tests at extreme fall speeds | ☐ |
| **F** | Chained 2+ floor jumps start a combo | `test_combo_score.gd` (+ golden sequences) | ☐ combo panel appears, bar shrinks |
| **G** | One-floor jump ends the combo (pays floors²) | `test_combo_score.gd` | ☐ |
| **H** | Waiting longer than the timeout ends it | `test_combo_score.gd` (tick-exact) | ☐ |
| **I** | Falling to a lower floor ends it | `test_combo_score.gd` | ☐ |
| **J** | Falling below the screen ends the run exactly once | `test_physics.gd`, `test_run.gd` | ☐ one game-over, one record entry |
| **K** | Touch: hold + release = exactly one jump | `test_input.gd` (controller, InputManager wiring, input→sim chain) | ☐ |
| **L** | Tilt right → smooth response | `test_input.gd` (filter, dead zone, curve, calibration) | ☐ tilt both landscape orientations |
| **M** | Tilt mode: tap play area = exactly one jump | `test_input.gd` (InputManager) | ☐ |
| **N** | Tilt mode: tapping Pause never jumps | `test_input.gd` (block rectangles) | ☐ |
| **O** | Backgrounding and resuming: no movement, no sensor spike | `test_input.gd` (settle samples, spike rejection, sensor loss, `cancel_all`) | ☐ press Home during play, return, wait, resume |

## 2. Automated suites

| Suite | Covers |
| --- | --- |
| `test_rng.gd` | xorshift stream vs Python golden values, ranges, seeding |
| `test_tower.gd` | determinism per seed, reachability guarantees, spacing/width limits, patterns, landmarks |
| `test_physics.gd` | golden scenarios (tick-exact vs Python), jump table, wall, one-way platforms, coyote/buffer, single death |
| `test_combo_score.gd` | combo rules, integer-safe bonus, score, floor numbering |
| `test_run.gd` | scroll start at floor 5, staged speed-ups (~30 s), camera follow, frame-rate independence |
| `test_replay.gd` | event encoding, exact playback through JSON, tuning snapshots, corruption/version checks |
| `test_save.gd` | atomic writes, crash recovery, backup, migration, forward compatibility |
| `test_records.gd` | leaderboards (ranking, ties, trimming, record flags, damaged data, provider interface), statistics |
| `test_input.gd` | touch zones and multi-touch, tilt mapping/filter/calibration/safety, InputManager taps, input→sim |
| `test_config.gd` | landscape/scaling/sensor settings, tuning classification and snapshots, safe-area maths, themes, export presets, assets |
| `test_characters.gd` | sheet layout contract, animation fallbacks, custom-pack validation and safety |

Expected result: `ALL TESTS PASSED` and exit code 0. The script also fails the run if the engine printed
`SCRIPT ERROR` (GDScript continues after a runtime error, so a green summary alone is not enough).

## 3. Manual checklist (Android device)

### Display and system
- [ ] Only landscape is possible; rotating the device 180° switches between the two landscape orientations without restarting.
- [ ] Immersive fullscreen: no status bar or navigation bar while playing; swiping from the edge shows them briefly.
- [ ] Camera cut-out / punch-hole / rounded corners never cover the HUD, the pause button or menu text (test a notched phone in both landscape directions).
- [ ] 16:9, 18:9, 20:9 and 21:9 devices see the same amount of tower height; the tower is 640 units wide on all of them.
- [ ] 60 / 90 / 120 Hz: motion is smooth, the physics feels identical; *Settings ▸ Video ▸ FPS limit* works.
- [ ] Split-screen / resizing is not offered (the activity is landscape-only) and nothing breaks on a tablet.

### Controls
- [ ] First launch: the control selector appears, the choice is saved and can be changed in *Settings ▸ Controls*.
- [ ] Touch: hold LEFT accelerates smoothly, hold RIGHT likewise; release jumps once; a tiny tap below the minimum hold does not jump; both thumbs (multi-touch) behave as documented; size/opacity/offset/swap/haptics settings apply live and persist.
- [ ] Tilt: neutral pose calibrates via *Calibrate* (text: “Hold your device in a comfortable playing position.”); tilt right/left moves accordingly in **both** landscape orientations; dead zone ignores hand tremor; Low/Medium/High/Custom sensitivity; invert; tap anywhere jumps; tapping Pause does not.
- [ ] Sensors stop when paused/backgrounded (check battery/“sensor in use” indicators) and restart without a jump in movement.

### Gameplay
- [ ] The first floors are wide and easy; the tower starts rising at floor 5 with an on-screen surge notification; it speeds up about every 30 s.
- [ ] Combos: panel, timer bar, praise messages, fanfare tiers, bonus added exactly once; score = 10 × new floors + bonuses.
- [ ] Themes change every 100 floors with smooth colour blending (use the debug panel: floors 100, 500, 1000).
- [ ] Danger glow and beeps near the bottom edge; near-fall pose; game over is immediate and happens once.
- [ ] Wall rebounds keep momentum; landing never removes speed.
- [ ] Tutorial (first launch, skippable, replayable from *Help* and *Settings ▸ Gameplay*) teaches run → jump → higher jumps with speed → walls → combos → the rising tower.
- [ ] *About ▸ Licences* shows the Godot licence text and the component list (scrolls with a finger drag).

### Lifecycle and data
- [ ] Home button, recents, incoming call, notification shade, screen lock, back gesture: the run pauses, audio stops, the sensor stops, resuming shows the pause menu.
- [ ] Force-stop during a run: on next launch the interrupted run appears in *Replays* (marked incomplete) and records/statistics are consistent.
- [ ] Records: new-record banners for score, floor and combo; top-N lists sorted; ties keep the older entry first.
- [ ] Statistics screen matches what was played; practice/debug runs are excluded.
- [ ] Replays: save, rename, watch (speeds), delete, share (Android share sheet), import (clipboard). Playback is identical to the live run.
- [ ] Corrupt the profile (adb: overwrite `profile.json` with garbage): the game starts, recovers from the backup or a clean profile.
- [ ] *Settings ▸ Data*: every destructive action asks for confirmation; reset-all asks twice.
- [ ] Custom character import (file and clipboard): valid pack appears, invalid packs are rejected with a readable reason.

### Audio and haptics
- [ ] Master/music/effects volumes and mute; music loops seamlessly; sounds are pooled (no dropouts during heavy combos).
- [ ] Haptics on/off; interrupted audio (phone call) recovers.

### Performance (mid-range device)
- [ ] Sustained frame rate at the display's refresh rate (or the chosen cap); no periodic hitches (GC, theme change, particle bursts).
- [ ] Memory stays flat over a long run (tower platforms are pooled; ~100 bytes per generated floor).
- [ ] No noticeable heating over 10 minutes; *Settings ▸ Video* “reduced effects” lowers the load.
- [ ] Cold start to menu in a few seconds; APK/AAB size is reasonable (art and audio are about 6 MB before compression).

### Accessibility and polish
- [ ] Touch targets ≥ 48 dp; text contrast is readable on all themes; screen shake and particles can be reduced or turned off.
- [ ] No text is clipped at any supported aspect ratio; long player names are limited.

## 4. Regression tips

* After any change in `src/core`: run the tests, and if the arithmetic changed, bump `SimConst.SIM_VERSION` and
  regenerate the golden vectors (`python3 tools/reference/gen_golden.py`) from an updated `sim_ref.py`.
* After changing assets: `python3 tools/generate_audio.py` / `python3 tools/gen_art.py`, then reopen the project once so
  Godot re-imports them.
* `tools/check_static.sh` catches typos, wrong signatures and style problems without starting the engine.
