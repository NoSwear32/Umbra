class_name GameTuning
extends Resource
## Central, designer-editable tuning for the whole game.
##
## Open `res://resources/game_tuning.tres` in the Godot inspector to edit any value
## without touching code. The .tres file only stores overrides: everything not
## listed there falls back to the defaults declared below (single source of truth).
##
## Units: pixels (logical game units), seconds, altitude grows UPWARDS.
## The properties in SIM_KEYS drive the deterministic simulation and are stored
## (snapshot) inside every replay. Everything else is presentation / input tuning.

# ---------------------------------------------------------------------------
# WORLD
# ---------------------------------------------------------------------------
@export_group("World")
## Width of the playable tower. Identical on every device / aspect ratio.
@export var tower_width: float = 640.0
## Logical height of the view (the game uses "keep height" scaling, so every device
## sees the same amount of tower). Also used for camera follow and generation.
@export var view_height: float = 720.0

# ---------------------------------------------------------------------------
# PLAYER
# ---------------------------------------------------------------------------
@export_group("Player body")
@export var player_half_width: float = 20.0
@export var player_height: float = 62.0
## Half width of the "feet" used for platform contact (narrower = more forgiving edges).
@export var foot_half_width: float = 14.0

@export_group("Player horizontal movement")
## Maximum horizontal speed reachable by running (px/s).
@export var max_speed: float = 720.0
## Acceleration on the ground from standstill (px/s^2).
@export var accel_ground: float = 1650.0
## Fraction of the acceleration left when running at max_speed (smooth approach to top speed).
@export_range(0.05, 1.0, 0.01) var accel_at_max_ratio: float = 0.30
## Deceleration when the player pushes the OPPOSITE way on the ground (direction changes take time).
@export var brake_decel: float = 3000.0
## Deceleration on the ground when no direction is held.
@export var ground_friction: float = 1800.0
## Horizontal acceleration in the air (weaker than on the ground).
@export var air_accel: float = 900.0
## Deceleration in the air when pushing against the current direction.
@export var air_brake: float = 1500.0
## Air drag when nothing is held (tiny so momentum is preserved during jumps).
@export var air_friction: float = 40.0

@export_group("Player vertical movement")
@export var gravity: float = 2500.0
@export var max_fall_speed: float = 1900.0
## Jump velocity when standing still (px/s). Apex height = v^2 / (2 * gravity).
@export var base_jump_velocity: float = 870.0
## Jump velocity multiplier at zero horizontal speed.
@export var jump_min_multiplier: float = 1.0
## Jump velocity multiplier at maximum horizontal speed.
@export var jump_max_multiplier: float = 2.2
## Shape of the speed -> jump curve. 0 = linear, 1 = quadratic (needs more speed for big jumps).
@export_range(0.0, 1.0, 0.01) var jump_curve_bias: float = 0.5

@export_group("Wall rebound")
## Fraction of horizontal speed kept after hitting a side wall (1.0 = perfect bounce).
@export_range(0.0, 1.2, 0.01) var wall_rebound_multiplier: float = 0.92
## Extra upward velocity added when rebounding in the air, as a fraction of the impact speed.
@export_range(0.0, 0.5, 0.005) var wall_rebound_vertical_influence: float = 0.06
## Impacts slower than this simply stop the player instead of bouncing (avoids jitter).
@export var wall_rebound_min_speed: float = 60.0

@export_group("Input forgiveness")
## Grace period to still jump after walking off a ledge (seconds).
@export var coyote_time: float = 0.06
## A jump requested this long before landing is executed on landing (seconds).
@export var jump_buffer_time: float = 0.09

# ---------------------------------------------------------------------------
# PLATFORMS
# ---------------------------------------------------------------------------
@export_group("Platforms")
## Average vertical distance between floors at the start / at full difficulty.
@export var platform_spacing_start: float = 104.0
@export var platform_spacing_end: float = 124.0
@export var platform_spacing_jitter: float = 6.0
@export var platform_spacing_min: float = 84.0
## Spacing is always limited to (base jump apex - clearance) so a standing jump can always reach the next floor.
@export var platform_clearance: float = 14.0
## Platform width range (min, max) at floor 0 and at full difficulty.
@export var platform_width_start_min: float = 300.0
@export var platform_width_start_max: float = 420.0
@export var platform_width_end_min: float = 96.0
@export var platform_width_end_max: float = 190.0
## Number of floors over which difficulty ramps from 0 to 1.
@export var difficulty_ramp_floors: int = 700
## Fraction of the *provably jumpable* horizontal gap the generator may use (start / full difficulty).
@export_range(0.05, 3.0, 0.01) var reach_factor_start: float = 0.32
@export_range(0.05, 3.0, 0.01) var reach_factor_end: float = 0.85
## Every N-th floor is a wide landmark platform (0 disables).
@export var landmark_interval: int = 10
@export var landmark_min_width: float = 400.0
@export_range(0.0, 1.0, 0.01) var pattern_stairs_chance: float = 0.28
@export_range(0.0, 1.0, 0.01) var pattern_zigzag_chance: float = 0.24
@export var pattern_min_run: int = 3
@export var pattern_max_run: int = 6
## How far above the camera top platforms are generated (px).
@export var generate_ahead: float = 900.0

# ---------------------------------------------------------------------------
# SCROLLING
# ---------------------------------------------------------------------------
@export_group("Scrolling")
## The tower starts scrolling when this floor is first reached.
@export var scroll_start_floor: int = 5
## Scroll speed of stage 0 and the asymptotic maximum (px/s).
@export var scroll_speed_start: float = 36.0
@export var scroll_speed_max: float = 480.0
## Seconds between speed increases.
@export var scroll_stage_seconds: float = 30.0
## Stage at which the speed is half way between start and max: v = start + (max-start) * s / (s + halfpoint).
@export var scroll_stage_halfpoint: float = 14.0
## Seconds over which the scroll speed eases in when scrolling starts.
@export var scroll_ramp_seconds: float = 2.0
## Seconds over which the speed changes smoothly when a new stage begins.
@export var scroll_stage_blend_seconds: float = 1.5
## The camera follows the player upwards when the head passes this fraction of the view height.
@export_range(0.3, 0.9, 0.01) var camera_follow_line: float = 0.60
## How quickly the camera catches up when the player is above the follow line (fraction per tick).
## 1.0 = hard clamp, smaller = softer. The kill line always matches the visible screen bottom.
@export_range(0.05, 1.0, 0.01) var camera_follow_gain: float = 0.30
## Altitude of the bottom of the view at the start of a run (negative shows some ground).
@export var camera_start_bottom: float = -64.0
## Extra pixels below the screen before the run ends.
@export var death_margin: float = 0.0

# ---------------------------------------------------------------------------
# COMBO + SCORE
# ---------------------------------------------------------------------------
@export_group("Combo")
## A landing that advanced at least this many floors is a combo jump.
@export var combo_min_floors: int = 2
## Seconds allowed between combo landings.
@export var combo_timeout: float = 3.0
@export var combo_min_jumps_for_bonus: int = 2
@export var combo_min_total_floors_for_bonus: int = 4
## Bonus = floors ^ exponent * multiplier (integer maths).
@export_range(1, 3, 1) var combo_bonus_exponent: int = 2
@export var combo_bonus_multiplier: int = 1
## If true, only landings on floors above the highest reached count for combos.
@export var combo_only_new_floors: bool = false

@export_group("Score")
@export var points_per_floor: int = 10

@export_group("Combo praise (presentation)")
## Minimum combo floors for each praise message (ascending) and the message shown.
@export var praise_min_floors: PackedInt32Array = PackedInt32Array([4, 8, 14, 22, 32, 45, 65, 90, 130, 200])
@export var praise_texts: PackedStringArray = PackedStringArray([
	"NICE HOP!", "SPRINGY!", "SKY HIGH!", "GUST FORCE!", "SPIRE RUSH!",
	"STORMBREAKER!", "COMET LEAP!", "ASTRAL CLIMB!", "UNSTOPPABLE!", "LEGEND OF THE SPIRE!"])

# ---------------------------------------------------------------------------
# CONTROLS
# ---------------------------------------------------------------------------
@export_group("Touch controls")
## A release counts as a jump only if the direction was held at least this long (seconds).
@export var touch_release_min_hold: float = 0.05
## Maximum value the user can select for the threshold in Settings (seconds).
@export var touch_release_min_hold_max: float = 0.30

@export_group("Tilt controls")
## Tilt dead zone in degrees (sensor jitter around neutral is ignored).
@export var tilt_dead_zone_deg: float = 2.0
## Degrees of tilt (beyond the dead zone) that produce full input, per sensitivity preset.
@export var tilt_full_deg_low: float = 26.0
@export var tilt_full_deg_medium: float = 18.0
@export var tilt_full_deg_high: float = 12.0
## Range of the custom sensitivity slider (degrees for full input).
@export var tilt_full_deg_min: float = 6.0
@export var tilt_full_deg_max: float = 40.0
## Low-pass filter time constant for the sensor (seconds). Smaller = snappier.
@export var tilt_smoothing_time: float = 0.05
## Response curve: 0 = linear, 1 = quadratic (finer control near the centre).
@export_range(0.0, 1.0, 0.01) var tilt_response_curve: float = 0.30
## Samples changing faster than this (deg/s) after a resume are treated as spikes and ignored.
@export var tilt_spike_deg_per_sec: float = 2500.0
## Number of sensor samples to discard after enabling the sensor (avoids resume spikes).
@export var tilt_settle_samples: int = 6

@export_group("Feel / presentation")
## Time constant of the visual camera smoothing (does not influence the simulation).
@export var camera_smooth_time: float = 0.09
## 0 disables screen shake completely.
@export_range(0.0, 2.0, 0.05) var screen_shake_scale: float = 1.0
## Speed ratio above which speed lines / trails appear.
@export_range(0.0, 1.0, 0.01) var speed_effect_ratio: float = 0.55


## Properties that are part of the deterministic simulation (stored in replays).
const SIM_KEYS: Array = [
	"tower_width", "view_height",
	"player_half_width", "player_height", "foot_half_width",
	"max_speed", "accel_ground", "accel_at_max_ratio", "brake_decel", "ground_friction",
	"air_accel", "air_brake", "air_friction",
	"gravity", "max_fall_speed", "base_jump_velocity",
	"jump_min_multiplier", "jump_max_multiplier", "jump_curve_bias",
	"wall_rebound_multiplier", "wall_rebound_vertical_influence", "wall_rebound_min_speed",
	"coyote_time", "jump_buffer_time",
	"platform_spacing_start", "platform_spacing_end", "platform_spacing_jitter",
	"platform_spacing_min", "platform_clearance",
	"platform_width_start_min", "platform_width_start_max",
	"platform_width_end_min", "platform_width_end_max",
	"difficulty_ramp_floors", "reach_factor_start", "reach_factor_end",
	"landmark_interval", "landmark_min_width",
	"pattern_stairs_chance", "pattern_zigzag_chance", "pattern_min_run", "pattern_max_run",
	"generate_ahead",
	"scroll_start_floor", "scroll_speed_start", "scroll_speed_max", "scroll_stage_seconds",
	"scroll_stage_halfpoint", "scroll_ramp_seconds", "scroll_stage_blend_seconds",
	"camera_follow_line", "camera_follow_gain", "camera_start_bottom", "death_margin",
	"combo_min_floors", "combo_timeout", "combo_min_jumps_for_bonus",
	"combo_min_total_floors_for_bonus", "combo_bonus_exponent", "combo_bonus_multiplier",
	"combo_only_new_floors",
	"points_per_floor",
]


# ---------------------------------------------------------------------------
# Derived values (all integer tick counts use int(x + 0.5) rounding, same as the reference sim)
# ---------------------------------------------------------------------------
func coyote_ticks() -> int:
	return int(coyote_time * float(SimConst.TICK_RATE) + 0.5)


func buffer_ticks() -> int:
	return int(jump_buffer_time * float(SimConst.TICK_RATE) + 0.5)


func combo_ticks() -> int:
	return int(combo_timeout * float(SimConst.TICK_RATE) + 0.5)


func stage_ticks() -> int:
	return maxi(1, int(scroll_stage_seconds * float(SimConst.TICK_RATE) + 0.5))


func blend_ticks() -> int:
	return int(scroll_stage_blend_seconds * float(SimConst.TICK_RATE) + 0.5)


func ramp_ticks() -> int:
	return int(scroll_ramp_seconds * float(SimConst.TICK_RATE) + 0.5)


## Apex height (px) of a standing jump.
func base_apex() -> float:
	return base_jump_velocity * base_jump_velocity / (2.0 * gravity)


## Speed at which a jump reaches `floors` floors of the starting spacing (used by tutorials/debug).
func jump_apex_for_ratio(ratio: float) -> float:
	var r: float = clampf(ratio, 0.0, 1.0)
	var f: float = r + (r * r - r) * jump_curve_bias
	var m: float = jump_min_multiplier + (jump_max_multiplier - jump_min_multiplier) * f
	var v: float = base_jump_velocity * m
	return v * v / (2.0 * gravity)


## Clamp values to ranges the simulation can handle (prevents divide by zero etc.).
func sanitize() -> void:
	tower_width = maxf(tower_width, 320.0)
	view_height = maxf(view_height, 360.0)
	player_half_width = maxf(player_half_width, 4.0)
	player_height = maxf(player_height, 8.0)
	foot_half_width = clampf(foot_half_width, 2.0, player_half_width)
	max_speed = maxf(max_speed, 50.0)
	gravity = maxf(gravity, 100.0)
	max_fall_speed = maxf(max_fall_speed, 200.0)
	base_jump_velocity = maxf(base_jump_velocity, 100.0)
	difficulty_ramp_floors = maxi(difficulty_ramp_floors, 1)
	pattern_min_run = maxi(pattern_min_run, 1)
	pattern_max_run = maxi(pattern_max_run, pattern_min_run)
	scroll_stage_seconds = maxf(scroll_stage_seconds, 1.0)
	scroll_stage_halfpoint = maxf(scroll_stage_halfpoint, 0.01)
	combo_bonus_exponent = clampi(combo_bonus_exponent, 1, 3)
	combo_min_floors = maxi(combo_min_floors, 1)
	platform_width_start_min = minf(platform_width_start_min, platform_width_start_max)
	platform_width_end_min = minf(platform_width_end_min, platform_width_end_max)
	tilt_full_deg_min = maxf(tilt_full_deg_min, 1.0)
	tilt_full_deg_max = maxf(tilt_full_deg_max, tilt_full_deg_min + 1.0)


# ---------------------------------------------------------------------------
# Replay snapshots
# ---------------------------------------------------------------------------
func to_sim_dict() -> Dictionary:
	var d: Dictionary = {}
	for key in SIM_KEYS:
		d[key] = get(key)
	return d


func apply_sim_dict(d: Dictionary) -> void:
	for key in SIM_KEYS:
		if not d.has(key):
			continue
		var cur: Variant = get(key)
		var v: Variant = d[key]
		match typeof(cur):
			TYPE_INT:
				set(key, int(v))
			TYPE_FLOAT:
				set(key, float(v))
			TYPE_BOOL:
				set(key, bool(v))
	sanitize()


## Stable hash of the simulation-relevant values (detects tuning drift between recording and playback).
func sim_hash() -> int:
	return JSON.stringify(to_sim_dict(), "", true, true).hash()


static func from_sim_dict(d: Dictionary) -> GameTuning:
	var t: GameTuning = GameTuning.new()
	t.apply_sim_dict(d)
	return t
