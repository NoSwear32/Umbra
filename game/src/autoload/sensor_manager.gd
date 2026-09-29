extends Node
## Autoload "SensorManager": reads the gravity/accelerometer sensor and turns it into the
## tilt axis (see TiltInputController for the maths).
##
## The sensor is only polled while `active` is true (a tilt-mode run that is not paused).
## Every activation resets the filter and discards the first samples, so resuming after a
## pause, a notification or an app switch can never produce a sudden movement spike.

signal calibration_done(neutral_deg: float)

var tilt: TiltInputController = TiltInputController.new()
## True while the sensor is being polled.
var active: bool = false
## Latest raw sample (gravity, or accelerometer as a fallback) - shown by the debug overlay.
var raw_sample: Vector3 = Vector3.ZERO
## True when the device delivered a usable sample recently.
var sensor_available: bool = false

## Desktop testing: with no sensor, LEFT/RIGHT keys simulate a tilt of this many degrees.
var simulated_tilt_deg: float = 12.0

var _keys_axis: float = 0.0
var _last_sample_time: float = -100.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	Events.settings_changed.connect(_on_settings_changed)
	apply_settings()


func _on_settings_changed(_key: String) -> void:
	apply_settings()


## Copies the user's tilt settings and the tuning constants into the controller.
func apply_settings() -> void:
	var t: GameTuning = TuningStore.get_tuning()
	tilt.dead_zone_deg = SettingsManager.get_float("tilt_dead_zone")
	tilt.full_deg = SettingsManager.tilt_full_degrees(t)
	tilt.smoothing_time = t.tilt_smoothing_time
	tilt.response_curve = t.tilt_response_curve
	tilt.spike_deg_per_sec = t.tilt_spike_deg_per_sec
	tilt.settle_samples = t.tilt_settle_samples
	tilt.invert = SettingsManager.get_bool("tilt_invert")
	tilt.neutral_deg = SettingsManager.get_float("tilt_neutral_deg")
	tilt.calibrated = SettingsManager.get_bool("tilt_calibrated")


## Starts / stops polling. Starting always resets the filter (settle period).
func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	set_process(value)
	if value:
		tilt.reset()
	else:
		tilt.axis = 0.0


## Desktop keyboard hook: InputManager forwards the arrow keys here.
func set_keys_axis(value: float) -> void:
	_keys_axis = value


## Current sensor vector (gravity preferred, accelerometer as fallback).
func read_sensor() -> Vector3:
	var g: Vector3 = Input.get_gravity()
	if g.length() < 0.5:
		var a: Vector3 = Input.get_accelerometer()
		if a.length() >= 0.5:
			g = a
	return g


func _process(delta: float) -> void:
	if not active:
		return
	var g: Vector3 = read_sensor()
	if g.length() >= 0.5:
		sensor_available = true
		_last_sample_time = Time.get_ticks_msec() / 1000.0
	elif not OS.has_feature("mobile") and absf(_keys_axis) > 0.01:
		# desktop without a sensor: synthesise a gravity vector from the arrow keys
		var rad: float = deg_to_rad(simulated_tilt_deg * _keys_axis + tilt.neutral_deg)
		g = Vector3(sin(rad), -cos(rad), 0.0) * 9.81
	elif not OS.has_feature("mobile"):
		var rad0: float = deg_to_rad(tilt.neutral_deg)
		g = Vector3(sin(rad0), -cos(rad0), 0.0) * 9.81
	else:
		sensor_available = false
	raw_sample = g
	tilt.feed(g, delta)


## Stores the current device orientation as the neutral position.
## Returns false if no sensor data is available.
func calibrate_now() -> bool:
	var g: Vector3 = read_sensor()
	if g.length() < 0.5:
		if OS.has_feature("mobile"):
			return false
		g = Vector3(0.0, -9.81, 0.0)
	tilt.calibrate(g)
	SettingsManager.set_value("tilt_neutral_deg", tilt.neutral_deg)
	SettingsManager.set_value("tilt_calibrated", true)
	calibration_done.emit(tilt.neutral_deg)
	return true


func clear_calibration() -> void:
	tilt.clear_calibration()
	SettingsManager.reset_calibration()


## Live tilt angle (degrees, relative to neutral) for the calibration preview.
## Works without activating the gameplay filter.
func preview_degrees() -> float:
	var g: Vector3 = read_sensor()
	if g.length() < 0.5:
		return 0.0
	return TiltInputController.tilt_degrees(g) - tilt.neutral_deg
