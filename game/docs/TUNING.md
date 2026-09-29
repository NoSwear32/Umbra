# Tuning guide

Every gameplay number lives in **one resource**: `resources/game_tuning.tres` (class `GameTuning`,
`src/data/game_tuning.gd`). Open it in the Godot inspector and change values — no code needed. The `.tres`
file only stores *overrides*; anything not listed there uses the default declared in `game_tuning.gd`
(single source of truth), and `sanitize()` clamps values to ranges the simulation can survive.

Units: **pixels** in logical game space (the view is always 720 px tall), **seconds**, altitude grows **upwards**.
One floor ≈ 104–124 px.

## Two kinds of values

| Kind | Where | Stored in replays? |
| --- | --- | --- |
| **Simulation** values (`GameTuning.SIM_KEYS`, 62 of them): physics, platforms, scrolling, combo, score | everything in the *World … Score* groups | **Yes** — every replay carries a snapshot, so old replays keep playing exactly as recorded after you retune |
| **Presentation / input** values: touch and tilt tuning, praise messages, camera smoothing, shake, speed effects | *Touch controls … Feel* groups | No |

`tests/test_config.gd` fails if a new exported value is added without classifying it, so a physics tunable can never
be forgotten in the replay snapshot. **Changing simulation *code*** in `src/core/` (not just a number) changes how old
replays would play: bump `SimConst.SIM_VERSION` so they are flagged as incompatible instead of silently drifting.

## The feel in numbers (defaults)

| | |
| --- | --- |
| Time to reach 90 % of top speed from standstill | ≈ 0.7 s |
| Standing jump | 151 px ≈ 1.5 floors |
| Jump at 25 / 50 / 75 / 100 % of top speed | 213 / 318 / 484 / 733 px ≈ 2.0 / 3.1 / 4.7 / 7.0 floors |
| Scroll speed by stage (every 30 s) | 36 → 66 → 92 px/s …; ≈ 260 px/s after 7 min, ≈ 330 after 14 min, → 480 asymptote |
| Combo | 2+ floors per jump, ≈ 3 s between landings, bonus = floors² |
| Score | 10 points per *new* floor + combo bonuses |

## World

| Parameter | Default | Effect |
| --- | --- | --- |
| `tower_width` | 640 | Width of the playable tower, identical on every device. Wider aspect ratios only add decoration. |
| `view_height` | 720 | Logical view height (also the project's viewport height; a test checks they match). |

## Player body

| Parameter | Default | Effect |
| --- | --- | --- |
| `player_half_width` | 20 | Half width used for wall contact. |
| `player_height` | 62 | Body height; also where the scarf attaches and the head that must stay on screen. |
| `foot_half_width` | 14 | Half width of the feet for platform contact. Smaller = stricter edges, larger = more forgiving. |

## Horizontal movement

| Parameter | Default | Effect |
| --- | --- | --- |
| `max_speed` | 720 px/s | Top running speed. Also scales the jump bonus. |
| `accel_ground` | 1650 px/s² | Acceleration from standstill. Lower = heavier start, higher = snappier. |
| `accel_at_max_ratio` | 0.30 | Fraction of the acceleration still available at top speed. Lower = a long, smooth approach to top speed. |
| `brake_decel` | 3000 px/s² | Deceleration when pushing the *opposite* way on the ground (direction changes cost time). |
| `ground_friction` | 1800 px/s² | Slow-down on the ground when nothing is held. |
| `air_accel` | 900 px/s² | Air control. 0 would remove all steering in the air. |
| `air_brake` | 1500 px/s² | Braking in the air when pushing against the current direction. |
| `air_friction` | 40 px/s² | Tiny air drag so momentum is preserved across a jump. |

## Vertical movement

| Parameter | Default | Effect |
| --- | --- | --- |
| `gravity` | 2500 px/s² | Higher = snappier, shorter jumps at the same velocity. |
| `max_fall_speed` | 1900 px/s | Terminal velocity. |
| `base_jump_velocity` | 870 px/s | Take-off speed when standing still (apex = v² / 2g ≈ 151 px). |
| `jump_min_multiplier` | 1.0 | Jump velocity factor at zero speed. |
| `jump_max_multiplier` | 2.2 | Factor at top speed (apex grows with its square: ≈ 4.8× the standing jump). |
| `jump_curve_bias` | 0.5 | 0 = linear speed→jump curve, 1 = quadratic (big jumps need real speed). |

## Wall rebound

| Parameter | Default | Effect |
| --- | --- | --- |
| `wall_rebound_multiplier` | 0.92 | Fraction of horizontal speed kept when hitting a side wall. 1.0 = perfect bounce. |
| `wall_rebound_vertical_influence` | 0.06 | Extra upward velocity in the air, as a fraction of the impact speed (rewards skilful bounces). |
| `wall_rebound_min_speed` | 60 px/s | Slower impacts just stop the player (avoids jitter at walls). |

## Input forgiveness

| Parameter | Default | Effect |
| --- | --- | --- |
| `coyote_time` | 0.06 s | Jump still works this long after walking off a ledge. |
| `jump_buffer_time` | 0.09 s | A jump requested this long before landing fires on landing. |

Both are converted to whole simulation ticks (120 Hz) with `int(x * 120 + 0.5)`.

## Platforms

| Parameter | Default | Effect |
| --- | --- | --- |
| `platform_spacing_start` / `_end` | 104 / 124 px | Average floor height at floor 0 / full difficulty. |
| `platform_spacing_jitter` | ±6 px | Random variation per floor. |
| `platform_spacing_min` | 84 px | Lower bound after jitter. |
| `platform_clearance` | 14 px | Spacing is always capped at *standing apex − clearance*, so a standing jump can always reach the next floor. |
| `platform_width_start_min/max` | 300 / 420 px | Width range at floor 0 (easy, wide). |
| `platform_width_end_min/max` | 96 / 190 px | Width range at full difficulty. |
| `difficulty_ramp_floors` | 700 | Floors over which difficulty goes 0 → 1. |
| `reach_factor_start` / `_end` | 0.32 / 0.85 | Fraction of the *provably jumpable* horizontal gap the generator may use. Below 1.0 every gap is guaranteed reachable. |
| `landmark_interval`, `landmark_min_width` | 10, 400 px | Every 10th floor is a wide resting platform (0 disables). |
| `pattern_stairs_chance`, `pattern_zigzag_chance` | 0.28, 0.24 | Chance that a run of floors forms a staircase / zig-zag route (good for multi-floor jumps). |
| `pattern_min_run`, `pattern_max_run` | 3, 6 | Length range of those runs. |
| `generate_ahead` | 900 px | How far above the camera platforms are created. |

The generator is deterministic per seed and *never* produces an unreachable floor: the horizontal gap is capped by
a conservative bound derived from the physics (`PlatformGenerator.max_gap`); `tests/test_tower.gd` verifies it with
bots and thousands of platform pairs.

## Scrolling (the surge)

| Parameter | Default | Effect |
| --- | --- | --- |
| `scroll_start_floor` | 5 | The tower starts rising when this floor is first reached. |
| `scroll_speed_start` / `_max` | 36 / 480 px/s | Speed of stage 0 and the asymptotic maximum. |
| `scroll_stage_seconds` | 30 s | Time between speed-ups. |
| `scroll_stage_halfpoint` | 14 | Stage at which the speed is half way to the maximum: `v = start + (max − start) · s / (s + halfpoint)`. |
| `scroll_ramp_seconds` | 2 s | Ease-in when scrolling starts. |
| `scroll_stage_blend_seconds` | 1.5 s | Smooth transition to the next stage's speed. |
| `camera_follow_line` | 0.60 | The camera follows upwards when the head passes this fraction of the view height. |
| `camera_follow_gain` | 0.30 | How fast the camera catches up per tick (1.0 = hard clamp). |
| `camera_start_bottom` | −64 px | Where the bottom of the view starts (negative shows a little ground). |
| `death_margin` | 0 | Extra pixels below the screen before the run ends. |

## Combo & score

| Parameter | Default | Effect |
| --- | --- | --- |
| `combo_min_floors` | 2 | A landing advancing at least this many floors is a combo jump. |
| `combo_timeout` | 3.0 s | Time allowed between combo landings (measured in ticks, so it pauses with the game). |
| `combo_min_jumps_for_bonus` | 2 | Shortest paying chain (jumps). |
| `combo_min_total_floors_for_bonus` | 4 | Shortest paying chain (floors). |
| `combo_bonus_exponent`, `combo_bonus_multiplier` | 2, 1 | Bonus = floors^exponent × multiplier (integer maths; saturates instead of overflowing). |
| `combo_only_new_floors` | false | If true, only landings above the highest floor reached count for combos. |
| `points_per_floor` | 10 | Points for every *newly reached* floor (re-climbing never pays twice). |

## Combo praise (presentation)

`praise_min_floors` / `praise_texts` are parallel lists: the message with the largest threshold not above the
combo's floor count is shown (NICE HOP! → LEGEND OF THE SPIRE!).

## Touch controls

| Parameter | Default | Effect |
| --- | --- | --- |
| `touch_release_min_hold` | 0.05 s | Default minimum hold for a release to count as a jump (users can change it in Settings). |
| `touch_release_min_hold_max` | 0.30 s | Upper end of that setting. |

The size, opacity, position, swap and haptics of the on-screen buttons are *user* settings
(`SettingsManager.DEFAULTS`), not tuning values.

## Tilt controls

| Parameter | Default | Effect |
| --- | --- | --- |
| `tilt_dead_zone_deg` | 2° | Tilt around the neutral pose that is ignored (sensor jitter never moves the character). |
| `tilt_full_deg_low/medium/high` | 26 / 18 / 12° | Degrees *beyond the dead zone* that give full input, per sensitivity preset. |
| `tilt_full_deg_min/max` | 6 / 40° | Range of the *Custom* slider. |
| `tilt_smoothing_time` | 0.05 s | Low-pass time constant. Smaller = snappier, larger = smoother. |
| `tilt_response_curve` | 0.30 | 0 = linear, 1 = quadratic (finer control near the centre). |
| `tilt_spike_deg_per_sec` | 2500 | A single sample changing faster than this is ignored as a glitch (accepted if it persists). |
| `tilt_settle_samples` | 6 | Samples discarded whenever the sensor is (re)enabled: no spike after pause/resume. |

## Feel / presentation

| Parameter | Default | Effect |
| --- | --- | --- |
| `camera_smooth_time` | 0.09 s | Visual camera smoothing only (never affects the simulation). |
| `screen_shake_scale` | 1.0 | 0 disables shake entirely (the user setting also has an off switch). |
| `speed_effect_ratio` | 0.55 | Speed fraction above which speed lines / trails appear. |

## Recipes

* **Floatier, more forgiving:** `gravity` 2200, `air_accel` 1100, `coyote_time` 0.09.
* **Heavier, more precise:** `accel_ground` 1400, `brake_decel` 3600, `air_accel` 700.
* **Longer easy phase:** raise `scroll_start_floor` to 10 and `difficulty_ramp_floors` to 1000.
* **Harsher surge:** `scroll_stage_seconds` 20, `scroll_speed_max` 620.
* **Bigger combo rewards:** `combo_bonus_exponent` 3 (cubic) or `combo_bonus_multiplier` 2.
* **Stricter edges:** lower `foot_half_width` (e.g. 10).
* **Bigger gaps late in the run:** raise `reach_factor_end`. Up to 1.0 every gap can still be crossed from a
  standing start; above 1.0 the generator may create gaps that *require* momentum.

After changing physics values run `tools/run_tests.sh`: the jump-height tests (A–C), wall test (D), one-way test
(E) and reachability tests will tell you when a change breaks the design targets. The golden vectors in
`tests/golden/` describe the *default* tuning; regenerate them with `tools/reference/gen_golden.py` after editing
the defaults in **both** `game_tuning.gd` and `tools/reference/sim_ref.py`.

## Design targets this tuning aims at

* The first run is understandable within seconds; the first floors are wide, close and easy, and nothing scrolls
  until floor 5.
* After a minute or two the player needs better movement, momentum control and faster decisions: platforms
  narrow, gaps grow towards the reach limit, and the surge accelerates every 30 s.
* Advanced techniques pay off — acceleration timing, direction changes, wall rebounds (speed is kept), controlled
  high-speed landings, multi-floor routes (stairs/zig-zag patterns) and long combo chains (`floors²`).
* The skill ceiling is high: top-speed jumps skip seven floors, the combo bonus grows quadratically, and there is
  no cap on the tower.
