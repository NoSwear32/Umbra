class_name TiltInputController
extends RefCounted
## Control mode B: tilt the device to move (tap anywhere to jump - see InputManager).
##
## Pure logic: feed it gravity-sensor vectors, read `axis` (-1 .. +1).
##
##   gravity sample -> tilt angle (deg) -> minus calibrated neutral -> low-pass filter
##   -> dead zone -> sensitivity scaling -> response curve -> clamp -> axis
##
## The tilt angle is asin(g.x / |g|): the component of gravity along the screen's
## horizontal axis (Godot reports it with +x = right side of the screen down, for
## every landscape rotation on Android). That is independent of how the device is
## pitched, so it works held upright or lying in the lap.
##
## Safety features
##  * settle: the first N samples after enabling/resuming are discarded (no spikes),
##  * spike rejection: an absurd one-sample jump is ignored,
##  * dead zone: sensor noise around the neutral position never moves the character,
##  * tiny residual values (|axis| < 0.04) snap to exactly 0.

## Degrees around neutral that are ignored.
var dead_zone_deg: float = 2.0
## Degrees BEYOND the dead zone that give full input.
var full_deg: float = 18.0
## Low-pass time constant in seconds (0 = no smoothing).
var smoothing_time: float = 0.05
## 0 = linear response, 1 = quadratic.
var response_curve: float = 0.30
var invert: bool = false
var max_input: float = 1.0
## Tilt angle (degrees) that counts as "not tilted" - stored by calibration.
var neutral_deg: float = 0.0
var calibrated: bool = false
var spike_deg_per_sec: float = 2500.0
var settle_samples: int = 6

## Output.
var axis: float = 0.0
## Debug values.
var raw_deg: float = 0.0
var filtered_deg: float = 0.0
var sensor_present: bool = false

var _settle_left: int = 0
var _has_sample: bool = false
var _spike_count: int = 0


## Signed tilt angle in degrees derived from a gravity vector (0 when no data).
static func tilt_degrees(gravity: Vector3) -> float:
	var mag: float = gravity.length()
	if mag < 0.0001:
		return 0.0
	var s: float = clampf(gravity.x / mag, -1.0, 1.0)
	return rad_to_deg(asin(s))


## Pure mapping from a (filtered) angle relative to neutral to an axis value.
static func map_angle(rel_deg: float, dead_zone: float, full: float, curve: float, p_invert: bool, p_max: float) -> float:
	var m: float = absf(rel_deg) - dead_zone
	var t: float = 0.0
	if m > 0.0:
		t = clampf(m / maxf(full, 0.1), 0.0, 1.0)
		t = t + (t * t - t) * curve
	var dir_sign: float = 1.0
	if rel_deg < 0.0:
		dir_sign = -1.0
	if p_invert:
		dir_sign = -dir_sign
	var a: float = dir_sign * t * p_max
	if absf(a) < 0.04:
		a = 0.0
	return a


## Forgets all filter state; the next `settle_samples` samples are discarded.
## Call whenever the sensor is (re)enabled: game start, resume after pause, app focus.
func reset() -> void:
	_settle_left = settle_samples
	_has_sample = false
	_spike_count = 0
	axis = 0.0
	filtered_deg = 0.0
	raw_deg = 0.0


## Stores the current device orientation as the neutral position.
func calibrate(gravity: Vector3) -> void:
	neutral_deg = tilt_degrees(gravity)
	calibrated = true
	reset()


func clear_calibration() -> void:
	neutral_deg = 0.0
	calibrated = false
	reset()


## Processes one sensor sample. `dt` is the time since the previous sample.
func feed(gravity: Vector3, dt: float) -> float:
	if gravity.length() < 0.5:
		sensor_present = false
		axis = 0.0
		return 0.0
	sensor_present = true
	var rel: float = tilt_degrees(gravity) - neutral_deg
	raw_deg = rel

	if _settle_left > 0:
		_settle_left -= 1
		filtered_deg = rel
		_has_sample = true
		axis = 0.0
		return 0.0

	if not _has_sample:
		filtered_deg = rel
		_has_sample = true
	else:
		var delta: float = rel - filtered_deg
		if dt > 0.0 and absf(delta) / dt > spike_deg_per_sec and _spike_count < 3:
			# implausible jump: ignore this sample (but resync if it persists)
			_spike_count += 1
			return axis
		_spike_count = 0
		var alpha: float = 1.0
		if smoothing_time > 0.0 and dt > 0.0:
			alpha = 1.0 - exp(-dt / smoothing_time)
		filtered_deg = filtered_deg + delta * alpha

	axis = map_angle(filtered_deg, dead_zone_deg, full_deg, response_curve, invert, max_input)
	return axis
