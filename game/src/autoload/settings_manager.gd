extends Node
## Autoload "SettingsManager": typed access to every user setting.
##
## Values live in SaveManager.section("settings") (so they are saved with the profile);
## this class adds defaults, type coercion, range clamping, change signals and applies
## the settings that affect the engine (frame cap, ...).

const CONTROL_TOUCH: String = "touch"
const CONTROL_TILT: String = "tilt"

const TILT_LOW: String = "low"
const TILT_MEDIUM: String = "medium"
const TILT_HIGH: String = "high"
const TILT_CUSTOM: String = "custom"

## Every known setting with its default. The default's type defines the setting's type.
const DEFAULTS: Dictionary = {
	# profile / flow
	"player_name": "Climber",
	"control_mode": "touch",
	"control_chosen": false,
	"tutorial_done": false,
	# touch controls
	"touch_opacity": 0.55,
	"touch_scale": 1.0,
	"touch_offset_x": 0.0,
	"touch_offset_y": 0.0,
	"touch_swap": false,
	"touch_min_hold_ms": 50,
	# shared
	"haptics": true,
	# tilt controls
	"tilt_preset": "medium",
	"tilt_custom_deg": 18.0,
	"tilt_dead_zone": 2.0,
	"tilt_invert": false,
	"tilt_neutral_deg": 0.0,
	"tilt_calibrated": false,
	# audio
	"vol_master": 1.0,
	"vol_music": 0.7,
	"vol_sfx": 1.0,
	"mute": false,
	# video
	"fps_limit": 0,
	"screen_shake": true,
	"particles": 2,
	"reduced_effects": false,
	"show_fps": false,
}

## [min, max] for numeric settings.
const RANGES: Dictionary = {
	"touch_opacity": [0.15, 1.0],
	"touch_scale": [0.6, 1.6],
	"touch_offset_x": [-200.0, 200.0],
	"touch_offset_y": [-120.0, 200.0],
	"touch_min_hold_ms": [0, 300],
	"tilt_custom_deg": [6.0, 40.0],
	"tilt_dead_zone": [0.0, 10.0],
	"tilt_neutral_deg": [-90.0, 90.0],
	"vol_master": [0.0, 1.0],
	"vol_music": [0.0, 1.0],
	"vol_sfx": [0.0, 1.0],
	"fps_limit": [0, 240],
	"particles": [0, 2],
}

const PLAYER_NAME_MAX: int = 14

var _values: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.loaded.connect(_on_save_loaded)
	_on_save_loaded()


func _on_save_loaded() -> void:
	_values = SaveManager.section("settings")
	for key in DEFAULTS:
		if not _values.has(key):
			_values[key] = DEFAULTS[key]
	# sanitise anything that came from disk
	for key in DEFAULTS:
		_values[key] = _coerce(key, _values[key])
	apply_engine_settings()
	Events.settings_changed.emit("*")


func get_value(key: String) -> Variant:
	if _values.has(key):
		return _values[key]
	return DEFAULTS.get(key)


func get_float(key: String) -> float:
	return float(get_value(key))


func get_int(key: String) -> int:
	return int(get_value(key))


func get_bool(key: String) -> bool:
	return bool(get_value(key))


func get_string(key: String) -> String:
	return String(get_value(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("SettingsManager: unknown setting '%s'" % key)
		return
	var v: Variant = _coerce(key, value)
	if _values.has(key) and _values[key] == v:
		return
	_values[key] = v
	SaveManager.mark_dirty()
	if key == "fps_limit":
		apply_engine_settings()
	if key == "control_mode":
		Events.control_mode_changed.emit(String(v))
	Events.settings_changed.emit(key)


func reset_to_defaults(keys: Array = []) -> void:
	var list: Array = keys if not keys.is_empty() else DEFAULTS.keys()
	for k in list:
		_values[k] = DEFAULTS[k]
	SaveManager.mark_dirty()
	apply_engine_settings()
	Events.settings_changed.emit("*")


## Clears the tilt calibration (Settings > Gameplay > Reset control calibration).
func reset_calibration() -> void:
	_values["tilt_neutral_deg"] = 0.0
	_values["tilt_calibrated"] = false
	SaveManager.mark_dirty()
	Events.settings_changed.emit("tilt_neutral_deg")


func is_tilt_mode() -> bool:
	return get_string("control_mode") == CONTROL_TILT


## Degrees of tilt (beyond the dead zone) that give full input for the chosen sensitivity.
func tilt_full_degrees(tuning: GameTuning) -> float:
	match get_string("tilt_preset"):
		TILT_LOW:
			return tuning.tilt_full_deg_low
		TILT_HIGH:
			return tuning.tilt_full_deg_high
		TILT_CUSTOM:
			return clampf(get_float("tilt_custom_deg"), tuning.tilt_full_deg_min, tuning.tilt_full_deg_max)
	return tuning.tilt_full_deg_medium


func apply_engine_settings() -> void:
	var cap: int = get_int("fps_limit")
	Engine.max_fps = cap


func _coerce(key: String, value: Variant) -> Variant:
	var def: Variant = DEFAULTS[key]
	var out: Variant = def
	match typeof(def):
		TYPE_BOOL:
			out = bool(value) if (value is bool or value is int or value is float) else def
		TYPE_INT:
			out = int(value) if (value is int or value is float) else def
		TYPE_FLOAT:
			out = float(value) if (value is int or value is float) else def
		TYPE_STRING:
			out = String(value) if value is String else def
	if RANGES.has(key) and (out is int or out is float):
		var r: Array = RANGES[key]
		if out is int:
			out = clampi(int(out), int(r[0]), int(r[1]))
		else:
			out = clampf(float(out), float(r[0]), float(r[1]))
	if key == "control_mode" and out != CONTROL_TOUCH and out != CONTROL_TILT:
		out = CONTROL_TOUCH
	if key == "tilt_preset" and not [TILT_LOW, TILT_MEDIUM, TILT_HIGH, TILT_CUSTOM].has(out):
		out = TILT_MEDIUM
	if key == "player_name":
		out = String(out).strip_edges().substr(0, PLAYER_NAME_MAX)
		if String(out).is_empty():
			out = DEFAULTS["player_name"]
	return out
