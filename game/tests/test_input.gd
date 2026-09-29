extends RefCounted
## Input: touch zones (hold to move, release to jump - test K), tilt mapping / filtering /
## calibration, and the complete input -> simulation chain.

const LEFT_POINT: Vector2 = Vector2(120.0, 600.0)
const RIGHT_POINT: Vector2 = Vector2(1160.0, 600.0)
const DT_SENSOR: float = 0.02


class JumpCounter:
	extends RefCounted
	var count: int = 0

	func on_jump() -> void:
		count += 1


class SimWatcher:
	extends RefCounted
	var jumps: int = 0

	func on_jumped(_velocity: float, _ratio: float) -> void:
		jumps += 1


## The real InputManager script, detached from the scene tree, with the control mode fixed by
## the test (so no user setting is read or written).
class ModeInput:
	extends "res://src/autoload/input_manager.gd"
	var tilt_mode: bool = true

	func is_tilt_mode() -> bool:
		return tilt_mode


func run(t: TestContext) -> void:
	_touch_basics(t)
	_touch_taps(t)
	_touch_multi(t)
	_touch_slide(t)
	_touch_cancel(t)
	_touch_geometry(t)
	_tilt_angle(t)
	_tilt_mapping(t)
	_tilt_filter(t)
	_tilt_calibration(t)
	_tilt_safety(t)
	_input_manager(t)
	_chain(t)


func _touch() -> TouchInputController:
	var c: TouchInputController = TouchInputController.new()
	c.set_zones(Rect2(20.0, 500.0, 200.0, 200.0), Rect2(1060.0, 500.0, 200.0, 200.0))
	c.min_hold = 0.05
	c.slop = 40.0
	return c


# ---------------------------------------------------------------------------
# Touch controls
# ---------------------------------------------------------------------------
func _touch_basics(t: TestContext) -> void:
	t.suite("touch: hold to move, release to jump (test K)")
	var c: TouchInputController = _touch()
	var jumps: JumpCounter = JumpCounter.new()
	c.jump_requested.connect(jumps.on_jump)
	t.eq(c.axis, 0.0, "idle: no movement")
	t.eq(c.active_zone, TouchInputController.Zone.NONE, "idle: no active button")
	c.touch_down(0, LEFT_POINT, 0.0)
	t.eq(c.axis, -1.0, "holding LEFT accelerates left")
	t.eq(c.active_zone, TouchInputController.Zone.LEFT, "the left button is active")
	t.check(c.is_zone_held(TouchInputController.Zone.LEFT), "the left zone reports a finger")
	t.check(not c.is_zone_held(TouchInputController.Zone.RIGHT), "the right zone does not")
	t.eq(jumps.count, 0, "pressing never jumps")
	c.touch_move(0, LEFT_POINT + Vector2(6.0, -4.0), 0.1)
	t.eq(jumps.count, 0, "small finger movement inside the button does nothing")
	t.eq(c.axis, -1.0, "and the finger still steers")
	c.touch_up(0, 0.4)
	t.eq(jumps.count, 1, "K: releasing after a hold requests exactly one jump")
	t.eq(c.axis, 0.0, "the character stops accelerating")
	t.eq(c.active_zone, TouchInputController.Zone.NONE, "no button is active")
	t.eq(c.touch_count(), 0, "no touches are tracked")
	c.touch_down(1, RIGHT_POINT, 1.0)
	t.eq(c.axis, 1.0, "holding RIGHT accelerates right")
	t.eq(c.active_zone, TouchInputController.Zone.RIGHT, "the right button is active")
	c.touch_up(1, 1.3)
	t.eq(jumps.count, 2, "releasing RIGHT jumps too")
	c.touch_up(1, 1.4)
	t.eq(jumps.count, 2, "a repeated release event is ignored")

	var rapid: TouchInputController = _touch()
	var rapid_jumps: JumpCounter = JumpCounter.new()
	rapid.jump_requested.connect(rapid_jumps.on_jump)
	for i in range(20):
		var base: float = float(i) * 0.5
		rapid.touch_down(0, RIGHT_POINT, base)
		rapid.touch_up(0, base + 0.25)
	t.eq(rapid_jumps.count, 20, "twenty hold/release cycles give exactly twenty jump requests")


func _touch_taps(t: TestContext) -> void:
	t.suite("touch: accidental taps and the minimum hold")
	var c: TouchInputController = _touch()
	var jumps: JumpCounter = JumpCounter.new()
	c.jump_requested.connect(jumps.on_jump)
	c.touch_down(0, LEFT_POINT, 10.0)
	c.touch_up(0, 10.02)
	t.eq(jumps.count, 0, "a 20 ms tap is below the 50 ms threshold: no jump")
	t.eq(c.axis, 0.0, "and leaves no movement behind")
	c.min_hold = 0.25
	c.touch_down(0, LEFT_POINT, 8.0)
	c.touch_up(0, 8.24)
	t.eq(jumps.count, 0, "just below a raised threshold: no jump")
	c.touch_down(0, LEFT_POINT, 9.0)
	c.touch_up(0, 9.25)
	t.eq(jumps.count, 1, "exactly at the threshold: jump (the threshold is inclusive)")
	c.min_hold = 0.0
	c.touch_down(0, LEFT_POINT, 12.0)
	c.touch_up(0, 12.0)
	t.eq(jumps.count, 2, "a threshold of zero turns every release into a jump")


func _touch_multi(t: TestContext) -> void:
	t.suite("touch: several fingers")
	var c: TouchInputController = _touch()
	var jumps: JumpCounter = JumpCounter.new()
	c.jump_requested.connect(jumps.on_jump)
	c.touch_down(0, LEFT_POINT, 0.0)
	c.touch_down(1, RIGHT_POINT, 0.1)
	t.eq(c.axis, 1.0, "with both buttons down the LAST pressed one steers")
	t.eq(c.touch_count(), 2, "both fingers are tracked")
	c.touch_up(1, 0.5)
	t.eq(jumps.count, 1, "releasing the active button jumps")
	t.eq(c.axis, -1.0, "and hands the direction back to the finger that is still down")
	t.eq(c.active_zone, TouchInputController.Zone.LEFT, "the left button becomes active again")
	c.touch_up(0, 0.7)
	t.eq(c.axis, 0.0, "lifting the last finger stops the movement")

	# releasing the button that is NOT steering never jumps
	var d: TouchInputController = _touch()
	var d_jumps: JumpCounter = JumpCounter.new()
	d.jump_requested.connect(d_jumps.on_jump)
	d.touch_down(0, LEFT_POINT, 0.0)
	d.touch_down(1, RIGHT_POINT, 0.1)
	d.touch_up(0, 0.3)
	t.eq(d_jumps.count, 0, "releasing the inactive button does not jump")
	t.eq(d.axis, 1.0, "and does not disturb the steering")
	d.touch_up(1, 0.5)
	t.eq(d_jumps.count, 1, "the active finger's release jumps")

	# two fingers on the same button
	var e: TouchInputController = _touch()
	var e_jumps: JumpCounter = JumpCounter.new()
	e.jump_requested.connect(e_jumps.on_jump)
	e.touch_down(0, LEFT_POINT, 0.0)
	e.touch_down(1, LEFT_POINT + Vector2(12.0, 8.0), 0.05)
	t.eq(e.axis, -1.0, "two fingers on one button still steer that way")
	e.touch_up(0, 0.4)
	t.eq(e_jumps.count, 0, "lifting the older finger does not jump")
	t.eq(e.axis, -1.0, "the newer finger keeps steering")
	e.touch_up(1, 0.5)
	t.eq(e_jumps.count, 1, "lifting the newest finger jumps")

	# junk input
	var f: TouchInputController = _touch()
	f.touch_down(3, Vector2(640.0, 100.0), 0.0)
	t.eq(f.touch_count(), 0, "a touch outside both buttons is ignored")
	t.eq(f.axis, 0.0, "and does not steer")
	f.touch_down(0, LEFT_POINT, 1.0)
	f.touch_down(0, RIGHT_POINT, 1.1)
	t.eq(f.touch_count(), 1, "a duplicate press event for the same finger is ignored")
	t.eq(f.axis, -1.0, "the original press keeps steering")
	f.touch_up(77, 2.0)
	t.eq(f.touch_count(), 1, "releasing an unknown finger does nothing")


func _touch_slide(t: TestContext) -> void:
	t.suite("touch: fingers sliding around")
	var c: TouchInputController = _touch()
	var jumps: JumpCounter = JumpCounter.new()
	c.jump_requested.connect(jumps.on_jump)
	c.touch_down(0, LEFT_POINT, 0.0)
	c.touch_move(0, Vector2(250.0, 600.0), 0.2)
	t.eq(c.axis, -1.0, "a finger 30 px outside the button (inside the slop) still steers")
	t.eq(jumps.count, 0, "without jumping")
	c.touch_move(0, Vector2(300.0, 600.0), 0.4)
	t.eq(jumps.count, 1, "sliding well outside the button counts as a release")
	t.eq(c.axis, 0.0, "and stops the movement")
	t.eq(c.touch_count(), 0, "the finger is no longer tracked")

	# sliding from one button onto the other: release + fresh press
	c.touch_down(1, LEFT_POINT, 1.0)
	c.touch_move(1, Vector2(1100.0, 600.0), 1.5)
	t.eq(jumps.count, 2, "sliding off LEFT releases it (jump)")
	t.eq(c.axis, 1.0, "and the finger now steers RIGHT")
	t.eq(c.active_zone, TouchInputController.Zone.RIGHT, "the right button is active")
	c.cancel_all()

	# a short brush across the button is not a jump
	c.touch_down(2, LEFT_POINT, 5.0)
	c.touch_move(2, Vector2(600.0, 100.0), 5.01)
	t.eq(jumps.count, 2, "a 10 ms touch that slides away does not jump")
	t.eq(c.axis, 0.0, "and leaves no movement")


func _touch_cancel(t: TestContext) -> void:
	t.suite("touch: cancelled touches, pause and disabling")
	var c: TouchInputController = _touch()
	var jumps: JumpCounter = JumpCounter.new()
	c.jump_requested.connect(jumps.on_jump)
	c.touch_down(0, LEFT_POINT, 0.0)
	c.touch_cancel(0)
	t.eq(jumps.count, 0, "a cancelled touch never jumps")
	t.eq(c.axis, 0.0, "and stops the movement")
	c.touch_down(0, LEFT_POINT, 1.0)
	c.touch_down(1, RIGHT_POINT, 1.1)
	c.cancel_all()
	t.eq(c.axis, 0.0, "pausing (cancel_all) stops the movement")
	t.eq(jumps.count, 0, "and never causes a jump")
	c.touch_up(0, 2.0)
	c.touch_up(1, 2.0)
	t.eq(jumps.count, 0, "late release events after a pause do not jump")

	c.touch_down(0, LEFT_POINT, 3.0)
	c.set_enabled(false)
	t.eq(c.axis, 0.0, "disabling the controller stops the movement")
	t.eq(c.touch_count(), 0, "and forgets every finger")
	c.touch_down(0, LEFT_POINT, 3.1)
	t.eq(c.axis, 0.0, "touches are ignored while disabled")
	c.touch_up(0, 3.6)
	t.eq(jumps.count, 0, "no jump while disabled")
	c.set_enabled(true)
	c.touch_down(0, LEFT_POINT, 4.0)
	c.touch_up(0, 4.3)
	t.eq(jumps.count, 1, "the controller works again once re-enabled")


func _touch_geometry(t: TestContext) -> void:
	t.suite("touch: button hit areas")
	var c: TouchInputController = _touch()
	t.eq(c.zone_at(LEFT_POINT), TouchInputController.Zone.LEFT, "the left button")
	t.eq(c.zone_at(RIGHT_POINT), TouchInputController.Zone.RIGHT, "the right button")
	t.eq(c.zone_at(Vector2(640.0, 360.0)), TouchInputController.Zone.NONE, "the middle of the screen is not a button")
	t.eq(c.zone_at(Vector2(10.0, 600.0)), TouchInputController.Zone.NONE, "just outside the left button")
	t.eq(c.zone_at(Vector2(10.0, 600.0), 15.0), TouchInputController.Zone.LEFT, "an inflated hit area reaches it")
	c.set_zones(Rect2(1060.0, 500.0, 200.0, 200.0), Rect2(20.0, 500.0, 200.0, 200.0))
	t.eq(c.zone_at(LEFT_POINT), TouchInputController.Zone.RIGHT, "swapped buttons: the left rectangle now steers right")
	c.touch_down(0, LEFT_POINT, 0.0)
	t.eq(c.axis, 1.0, "and holding it moves right")


# ---------------------------------------------------------------------------
# Tilt controls
# ---------------------------------------------------------------------------
## Gravity as the sensor reports it: +x points to the side of the screen that is tilted down.
func _grav(deg: float, pitch_deg: float = 0.0) -> Vector3:
	var a: float = deg_to_rad(deg)
	var p: float = deg_to_rad(pitch_deg)
	return Vector3(sin(a), cos(a) * sin(p), cos(a) * cos(p)) * 9.81


## A controller with no filtering so single samples can be checked exactly.
func _tilt() -> TiltInputController:
	var c: TiltInputController = TiltInputController.new()
	c.smoothing_time = 0.0
	c.settle_samples = 0
	c.response_curve = 0.0
	c.dead_zone_deg = 2.0
	c.full_deg = 18.0
	return c


func _tilt_angle(t: TestContext) -> void:
	t.suite("tilt: angle from the gravity vector")
	t.near(TiltInputController.tilt_degrees(Vector3(0.0, 0.0, 9.81)), 0.0, 1e-6, "lying flat is 0 degrees")
	t.near(TiltInputController.tilt_degrees(_grav(30.0)), 30.0, 1e-4, "30 degrees to the right")
	t.near(TiltInputController.tilt_degrees(_grav(-30.0)), -30.0, 1e-4, "left is negative")
	t.near(TiltInputController.tilt_degrees(Vector3(9.81, 0.0, 0.0)), 90.0, 1e-6, "on its side is 90 degrees")
	for pitch in [0.0, 20.0, 45.0, 70.0]:
		t.near(TiltInputController.tilt_degrees(_grav(15.0, float(pitch))), 15.0, 1e-3, "the angle does not depend on how the device is pitched (%d deg)" % int(pitch))
	t.near(TiltInputController.tilt_degrees(_grav(12.0) * 0.4), 12.0, 1e-3, "nor on the magnitude of the vector")
	t.eq(TiltInputController.tilt_degrees(Vector3.ZERO), 0.0, "no data reads as 0 degrees")


func _tilt_mapping(t: TestContext) -> void:
	t.suite("tilt: response curve and sensitivity")
	for rel in [0.0, 1.0, -1.0, 1.99, -1.99, 2.0]:
		t.eq(TiltInputController.map_angle(float(rel), 2.0, 18.0, 0.0, false, 1.0), 0.0, "inside the dead zone (%.2f deg) there is no input" % float(rel))
	t.near(TiltInputController.map_angle(11.0, 2.0, 18.0, 0.0, false, 1.0), 0.5, 1e-9, "linear: half of the range gives half input")
	t.near(TiltInputController.map_angle(-11.0, 2.0, 18.0, 0.0, false, 1.0), -0.5, 1e-9, "left mirrors right")
	t.near(TiltInputController.map_angle(20.0, 2.0, 18.0, 0.0, false, 1.0), 1.0, 1e-9, "full deflection")
	t.near(TiltInputController.map_angle(90.0, 2.0, 18.0, 0.0, false, 1.0), 1.0, 1e-9, "more tilt is clamped to full")
	t.near(TiltInputController.map_angle(-90.0, 2.0, 18.0, 0.0, false, 1.0), -1.0, 1e-9, "also on the left")
	t.near(TiltInputController.map_angle(11.0, 2.0, 18.0, 1.0, false, 1.0), 0.25, 1e-9, "a fully quadratic curve gives a quarter at half range")
	t.near(TiltInputController.map_angle(11.0, 2.0, 18.0, 0.3, false, 1.0), 0.425, 1e-9, "the default curve is slightly gentle near the middle")
	t.eq(TiltInputController.map_angle(2.5, 2.0, 18.0, 0.0, false, 1.0), 0.0, "residuals below 4 percent snap to zero")
	t.check(TiltInputController.map_angle(3.0, 2.0, 18.0, 0.0, false, 1.0) > 0.05, "a clear tilt just outside the dead zone does move the character")
	t.near(TiltInputController.map_angle(11.0, 2.0, 18.0, 0.0, true, 1.0), -0.5, 1e-9, "invert flips the direction")
	t.near(TiltInputController.map_angle(-11.0, 2.0, 18.0, 0.0, true, 1.0), 0.5, 1e-9, "on both sides")
	t.near(TiltInputController.map_angle(40.0, 2.0, 18.0, 0.0, false, 0.6), 0.6, 1e-9, "the clamp limits the maximum input")
	t.near(TiltInputController.map_angle(-40.0, 2.0, 18.0, 0.0, false, 0.6), -0.6, 1e-9, "on the left too")
	var previous: float = -1.0
	var monotonic: bool = true
	for i in range(0, 300):
		var v: float = TiltInputController.map_angle(float(i) * 0.1, 2.0, 18.0, 0.3, false, 1.0)
		if v < previous:
			monotonic = false
		previous = v
	t.check(monotonic, "more tilt never gives less input")

	var tuning: GameTuning = GameTuning.new()
	t.check(tuning.tilt_full_deg_low > tuning.tilt_full_deg_medium and tuning.tilt_full_deg_medium > tuning.tilt_full_deg_high, "sensitivity presets are ordered Low > Medium > High (degrees to full input)")
	var curve: float = tuning.tilt_response_curve
	var low: float = TiltInputController.map_angle(10.0, 2.0, tuning.tilt_full_deg_low, curve, false, 1.0)
	var medium: float = TiltInputController.map_angle(10.0, 2.0, tuning.tilt_full_deg_medium, curve, false, 1.0)
	var high: float = TiltInputController.map_angle(10.0, 2.0, tuning.tilt_full_deg_high, curve, false, 1.0)
	t.check(low < medium and medium < high, "the same tilt gives more input at a higher sensitivity")
	for preset_full in [tuning.tilt_full_deg_low, tuning.tilt_full_deg_medium, tuning.tilt_full_deg_high]:
		t.near(TiltInputController.map_angle(2.0 + float(preset_full), 2.0, float(preset_full), curve, false, 1.0), 1.0, 1e-9, "every preset reaches full input at its own angle (%.0f deg)" % float(preset_full))
	t.check(tuning.tilt_full_deg_min < tuning.tilt_full_deg_high and tuning.tilt_full_deg_max > tuning.tilt_full_deg_low, "the custom range covers every preset")

	var defaults: TiltInputController = TiltInputController.new()
	t.near(defaults.dead_zone_deg, tuning.tilt_dead_zone_deg, 1e-9, "controller defaults match the tuning (dead zone)")
	t.near(defaults.smoothing_time, tuning.tilt_smoothing_time, 1e-9, "controller defaults match the tuning (smoothing)")
	t.near(defaults.response_curve, tuning.tilt_response_curve, 1e-9, "controller defaults match the tuning (curve)")
	t.near(defaults.spike_deg_per_sec, tuning.tilt_spike_deg_per_sec, 1e-9, "controller defaults match the tuning (spike limit)")
	t.eq(defaults.settle_samples, tuning.tilt_settle_samples, "controller defaults match the tuning (settle samples)")


func _tilt_filter(t: TestContext) -> void:
	t.suite("tilt: filtering and dead zone")
	var c: TiltInputController = _tilt()
	var a: float = c.feed(_grav(10.0), DT_SENSOR)
	t.near(a, 8.0 / 18.0, 1e-3, "10 degrees with a 2 degree dead zone gives 8/18 of full input")
	t.check(c.sensor_present, "a valid sample marks the sensor as present")
	t.check(c.feed(_grav(-10.0), DT_SENSOR) < 0.0, "tilting left gives negative input")

	# sensor noise around the neutral pose never moves the character
	var jitter: TiltInputController = _tilt()
	jitter.smoothing_time = 0.05
	var rng: SimRng = SimRng.new(99)
	var worst: float = 0.0
	for i in range(400):
		var noise: float = float(rng.range_i(-1000, 1000)) / 1000.0 * 1.5
		jitter.feed(_grav(noise), 1.0 / 60.0)
		worst = maxf(worst, absf(jitter.axis))
	t.eq(worst, 0.0, "noise of +-1.5 degrees inside the dead zone gives exactly zero input")

	# a step input is smoothed (no sudden jump), then converges
	var smooth: TiltInputController = _tilt()
	smooth.smoothing_time = 0.05
	smooth.feed(_grav(0.0), 1.0 / 60.0)
	var previous: float = 0.0
	var largest_step: float = 0.0
	var first: float = 0.0
	var last: float = 0.0
	for i in range(60):
		last = smooth.feed(_grav(20.0), 1.0 / 60.0)
		if i == 0:
			first = last
		largest_step = maxf(largest_step, absf(last - previous))
		previous = last
	t.check(first > 0.0 and first < 0.5, "the response ramps up instead of jumping (first sample %.2f)" % first)
	t.check(largest_step < 0.35, "no sample-to-sample jump larger than 0.35 (%.2f)" % largest_step)
	t.near(last, 1.0, 0.02, "and converges to the target")

	# zero or missing time deltas are handled
	var odd: TiltInputController = _tilt()
	odd.smoothing_time = 0.05
	var v0: float = odd.feed(_grav(10.0), 0.0)
	t.check(is_finite(v0) and v0 > 0.0, "a zero time step gives a finite answer")
	var v1: float = odd.feed(_grav(10.0), 1.0)
	t.check(is_finite(v1), "a huge time step is fine too")


func _tilt_calibration(t: TestContext) -> void:
	t.suite("tilt: calibration")
	var c: TiltInputController = _tilt()
	t.check(not c.calibrated, "not calibrated at the start")
	c.calibrate(_grav(25.0))
	t.check(c.calibrated, "calibration is recorded")
	t.near(c.neutral_deg, 25.0, 1e-3, "the neutral angle is the current pose")
	t.eq(c.feed(_grav(25.0), DT_SENSOR), 0.0, "the calibrated pose gives no input")
	t.near(c.feed(_grav(45.0), DT_SENSOR), 1.0, 1e-3, "20 degrees to the right of it is full right")
	t.near(c.feed(_grav(5.0), DT_SENSOR), -1.0, 1e-3, "20 degrees to the left is full left")
	t.near(c.feed(_grav(25.0 + 7.0), DT_SENSOR), 5.0 / 18.0, 1e-3, "and partial tilt is relative to the calibrated pose")
	c.clear_calibration()
	t.check(not c.calibrated, "calibration can be cleared")
	t.eq(c.neutral_deg, 0.0, "back to the default neutral pose")
	# a device held at an extreme pose is still usable after calibrating there
	var lap: TiltInputController = _tilt()
	lap.calibrate(_grav(-35.0))
	t.eq(lap.feed(_grav(-35.0), DT_SENSOR), 0.0, "an unusual neutral pose is respected")
	t.check(lap.feed(_grav(-20.0), DT_SENSOR) > 0.5, "tilting back towards level moves right")


func _tilt_safety(t: TestContext) -> void:
	t.suite("tilt: settling, glitches and sensor loss")
	# after (re)starting the sensor the first samples are discarded - no spike after a pause
	var c: TiltInputController = _tilt()
	c.settle_samples = 6
	c.reset()
	var quiet: bool = true
	for i in range(6):
		if c.feed(_grav(30.0), DT_SENSOR) != 0.0:
			quiet = false
	t.check(quiet, "the first six samples after a restart are ignored, whatever the pose")
	t.near(c.feed(_grav(30.0), DT_SENSOR), 1.0, 1e-3, "then the tilt is honoured")
	c.reset()
	t.eq(c.axis, 0.0, "reset clears the output")
	t.eq(c.feed(_grav(-40.0), DT_SENSOR), 0.0, "and settles again")

	# a one-sample glitch is ignored, a lasting change is accepted
	var g: TiltInputController = _tilt()
	g.feed(_grav(0.0), 1.0 / 60.0)
	t.eq(g.feed(_grav(80.0), 1.0 / 60.0), 0.0, "an 80 degree jump in one frame is rejected as a glitch")
	t.eq(g.feed(_grav(0.0), 1.0 / 60.0), 0.0, "and forgotten afterwards")
	var seq: PackedFloat32Array = PackedFloat32Array()
	for i in range(6):
		seq.append(g.feed(_grav(80.0), 1.0 / 60.0))
	t.check(seq[0] == 0.0 and seq[1] == 0.0 and seq[2] == 0.0, "a persisting jump is rejected for three samples")
	t.check(seq[3] > 0.99 and seq[5] > 0.99, "then accepted as a real movement")

	# missing sensor
	var m: TiltInputController = _tilt()
	m.feed(_grav(20.0), DT_SENSOR)
	t.check(m.axis > 0.5, "tilted right")
	t.eq(m.feed(Vector3.ZERO, DT_SENSOR), 0.0, "sensor loss stops the movement")
	t.check(not m.sensor_present, "and is reported")
	t.eq(m.feed(Vector3(0.1, 0.1, 0.1), DT_SENSOR), 0.0, "an implausibly weak vector counts as no sensor")
	t.check(m.feed(_grav(20.0), DT_SENSOR) > 0.5, "the sensor recovers when data returns")
	t.check(m.sensor_present, "and is reported present again")

	# clamp
	var k: TiltInputController = _tilt()
	k.max_input = 0.6
	t.near(k.feed(_grav(60.0), DT_SENSOR), 0.6, 1e-9, "the clamp limits the right side")
	t.near(k.feed(_grav(-60.0), 0.5), -0.6, 1e-9, "and the left side")


# ---------------------------------------------------------------------------
# InputManager: tilt-mode taps (tests M and N) and the touch-mode wiring
# ---------------------------------------------------------------------------
func _screen_touch(index: int, pos: Vector2, pressed: bool, canceled: bool = false) -> InputEventScreenTouch:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	e.canceled = canceled
	return e


func _input_manager(t: TestContext) -> void:
	t.suite("input manager: tilt-mode taps (tests M and N)")
	var im: ModeInput = ModeInput.new()
	im.tilt_mode = true
	im.gameplay_enabled = true
	var signals: JumpCounter = JumpCounter.new()
	im.jump_input.connect(signals.on_jump)
	var middle: Vector2 = Vector2(640.0, 360.0)
	t.check(not im.consume_jump(), "no jump without a tap")
	im._input(_screen_touch(0, middle, true))
	t.check(im.consume_jump(), "M: a tap anywhere on the play area requests a jump")
	t.check(not im.consume_jump(), "M: and exactly one (the request is consumed)")
	t.eq(signals.count, 1, "M: one feedback signal")
	im._input(_screen_touch(0, middle, false))
	t.check(not im.consume_jump(), "M: lifting the finger does not jump again")
	im._input(_screen_touch(0, Vector2(120.0, 600.0), true))
	t.check(im.consume_jump(), "M: taps over the (hidden) touch buttons area also jump in tilt mode")
	im._input(_screen_touch(0, middle, true, true))
	t.check(not im.consume_jump(), "a cancelled touch never jumps")
	# two quick taps are two separate jump requests
	im._input(_screen_touch(1, middle, true))
	im._input(_screen_touch(2, middle + Vector2(30.0, 0.0), true))
	t.check(im.consume_jump(), "two taps in one frame ask for a jump")
	t.check(not im.consume_jump(), "but the request is a flag, not a counter: the simulation sees one")

	# N: the pause button (and any registered UI rectangle) never jumps
	var pause_rect: Rect2 = Rect2(1180.0, 24.0, 74.0, 74.0)
	im.register_block_rect("hud_pause", pause_rect)
	im._input(_screen_touch(0, pause_rect.get_center(), true))
	t.check(not im.consume_jump(), "N: tapping Pause does not jump")
	im._input(_screen_touch(0, Vector2(1174.0, 60.0), true))
	t.check(not im.consume_jump(), "N: the blocked area is a little larger than the button")
	im._input(_screen_touch(0, Vector2(1090.0, 60.0), true))
	t.check(im.consume_jump(), "N: a tap well away from the button jumps")
	im.unregister_block_rect("hud_pause")
	im._input(_screen_touch(0, pause_rect.get_center(), true))
	t.check(im.consume_jump(), "N: with the button gone (menus) the area is normal again")

	# while gameplay is disabled (pause menu, game over) nothing jumps and nothing is left latched
	im.gameplay_enabled = false
	im._input(_screen_touch(0, middle, true))
	t.check(not im.consume_jump(), "taps do nothing while gameplay input is off")
	im.gameplay_enabled = true
	t.check(not im.consume_jump(), "and nothing is remembered for later")
	im.free()

	t.suite("input manager: touch mode wiring")
	var tm: ModeInput = ModeInput.new()
	tm.tilt_mode = false
	tm.gameplay_enabled = true
	# InputManager._ready() connects this in the game; the detached test instance does it by hand
	tm.touch.jump_requested.connect(tm._on_touch_jump)
	tm.touch.set_zones(Rect2(20.0, 500.0, 200.0, 200.0), Rect2(1060.0, 500.0, 200.0, 200.0))
	tm.touch.min_hold = 0.0
	t.eq(tm.sample_axis(), 0.0, "idle: no movement")
	tm._input(_screen_touch(0, LEFT_POINT, true))
	t.eq(tm.sample_axis(), -1.0, "holding the left button moves left")
	t.check(not tm.consume_jump(), "pressing a button does not jump")
	tm._input(_screen_touch(0, LEFT_POINT, false))
	t.check(tm.consume_jump(), "K: releasing it requests one jump")
	t.check(not tm.consume_jump(), "K: exactly one")
	t.eq(tm.sample_axis(), 0.0, "and stops the movement")
	tm._input(_screen_touch(0, middle, true))
	t.check(not tm.consume_jump(), "a tap outside the buttons does nothing in touch mode")
	tm.touch.min_hold = 60.0
	tm._input(_screen_touch(1, RIGHT_POINT, true))
	tm._input(_screen_touch(1, RIGHT_POINT, false))
	t.check(not tm.consume_jump(), "a release before the minimum hold time does not jump")
	tm.touch.min_hold = 0.0
	tm._input(_screen_touch(1, RIGHT_POINT, true))
	tm._input(_screen_touch(1, RIGHT_POINT, false))
	t.check(tm._jump_latched, "a jump request waits for the next simulation tick")
	tm.clear_state()
	t.check(not tm.consume_jump(), "clearing the input state (resume after pause) drops a pending jump")
	tm._input(_screen_touch(1, RIGHT_POINT, true))
	tm.gameplay_enabled = false
	tm.touch.set_enabled(false)
	tm._input(_screen_touch(1, RIGHT_POINT, false))
	t.check(not tm.consume_jump(), "disabling gameplay input (pause) never turns a held finger into a jump")
	tm.free()


# ---------------------------------------------------------------------------
# Input -> simulation
# ---------------------------------------------------------------------------
func _chain(t: TestContext) -> void:
	t.suite("input to simulation: one release, one jump")
	var tuning: GameTuning = GameTuning.new()
	var sim: RunManager = RunManager.new(tuning, 5)
	var c: TouchInputController = _touch()
	var requests: JumpCounter = JumpCounter.new()
	c.jump_requested.connect(requests.on_jump)
	var watcher: SimWatcher = SimWatcher.new()
	sim.jumped.connect(watcher.on_jumped)
	var handled: int = 0
	var airborne_ticks: int = 0
	var air_press: int = -1
	var released_in_air: bool = false
	var grounded_before_second: bool = false
	for i in range(320):
		var now: float = float(i) * SimConst.DT
		if i == 12:
			c.touch_down(0, RIGHT_POINT, now)
		if i == 72:
			c.touch_up(0, now)
		if sim.player.grounded:
			airborne_ticks = 0
		else:
			airborne_ticks += 1
		if airborne_ticks == 12 and air_press < 0:
			air_press = i
			c.touch_down(1, LEFT_POINT, now)
		if air_press >= 0 and i == air_press + 12:
			released_in_air = not sim.player.grounded
			c.touch_up(1, now)
		if i == 200:
			grounded_before_second = sim.player.grounded
			c.touch_down(2, LEFT_POINT, now)
		if i == 224:
			c.touch_up(2, now)
		var jump: bool = requests.count > handled
		handled = requests.count
		sim.tick(c.axis, jump)
	t.eq(requests.count, 3, "three releases produced three jump requests")
	t.check(released_in_air, "the second release happened in mid-air")
	t.check(grounded_before_second, "the character had landed before the third release")
	t.eq(watcher.jumps, 2, "the release in mid-air did not create a double jump; the grounded ones jumped")
