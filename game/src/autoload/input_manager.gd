extends Node
## Autoload "InputManager": one place that turns raw device input into the two numbers the
## simulation needs every tick - a horizontal axis (-1..1) and a jump request.
##
##   Touch mode : TouchInputController (hold LEFT/RIGHT, release to jump)
##   Tilt mode  : SensorManager (tilt to move) + tap anywhere to jump
##   Desktop    : arrow keys / A D + Space, handy for development (never shown to players)
##
## Input is sampled in `_input()` (before the UI sees an event) so latency is minimal. Taps
## that land on registered "block rects" (the pause button...) never cause a jump.

signal jump_input        ## a jump was requested (for feedback only)

## Touch controller (public so the overlay can publish its button rectangles).
var touch: TouchInputController = TouchInputController.new()

## Gameplay input on/off. Off while paused, in menus and on the game-over screen.
var gameplay_enabled: bool = false

var _jump_latched: bool = false
var _key_left: bool = false
var _key_right: bool = false
var _block_rects: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.use_accumulated_input = false
	touch.jump_requested.connect(_on_touch_jump)
	Events.settings_changed.connect(_on_settings_changed)
	Events.control_mode_changed.connect(_on_control_mode_changed)
	apply_settings()


func _on_settings_changed(_key: String) -> void:
	apply_settings()


func _on_control_mode_changed(_mode: String) -> void:
	touch.cancel_all()
	_jump_latched = false
	SensorManager.set_active(gameplay_enabled and is_tilt_mode())


func apply_settings() -> void:
	touch.min_hold = float(SettingsManager.get_int("touch_min_hold_ms")) / 1000.0


func is_tilt_mode() -> bool:
	return SettingsManager.is_tilt_mode()


## Enables or disables gameplay input. Disabling drops all touches (no jump on release),
## clears buffered jumps and stops the tilt sensor.
func set_gameplay_enabled(value: bool) -> void:
	gameplay_enabled = value
	touch.set_enabled(value)
	if not value:
		_jump_latched = false
	SensorManager.set_active(value and is_tilt_mode())


## Forget everything that is currently held or buffered (restart, resume from pause).
func clear_state() -> void:
	touch.cancel_all()
	_jump_latched = false
	if gameplay_enabled and is_tilt_mode():
		SensorManager.set_active(false)
		SensorManager.set_active(true)


# ---------------------------------------------------------------------------
# Per-tick sampling (called by the game loop)
# ---------------------------------------------------------------------------
func sample_axis() -> float:
	if not gameplay_enabled:
		return 0.0
	var key_axis: float = 0.0
	if _key_left:
		key_axis -= 1.0
	if _key_right:
		key_axis += 1.0
	if key_axis != 0.0 and not OS.has_feature("mobile"):
		return key_axis
	if is_tilt_mode():
		return SensorManager.tilt.axis
	return touch.axis


## Returns true once per jump request (edge triggered).
func consume_jump() -> bool:
	if not gameplay_enabled:
		_jump_latched = false
		return false
	var j: bool = _jump_latched
	_jump_latched = false
	return j


# ---------------------------------------------------------------------------
# UI exclusion zones
# ---------------------------------------------------------------------------
## Registers a rectangle (viewport coordinates) where taps must not jump (e.g. Pause button).
func register_block_rect(id: String, rect: Rect2) -> void:
	_block_rects[id] = rect


func unregister_block_rect(id: String) -> void:
	_block_rects.erase(id)


func is_blocked(pos: Vector2) -> bool:
	for id in _block_rects:
		var r: Rect2 = _block_rects[id]
		if r.grow(10.0).has_point(pos):
			return true
	return false


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
func _on_touch_jump() -> void:
	if gameplay_enabled and not is_tilt_mode():
		_jump_latched = true
		jump_input.emit()


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if not gameplay_enabled:
			return
		if is_tilt_mode():
			# tap anywhere (except on UI) = jump, on press for the lowest latency
			if st.pressed and not st.canceled and not is_blocked(st.position):
				_jump_latched = true
				jump_input.emit()
		else:
			if st.canceled:
				touch.touch_cancel(st.index)
			elif st.pressed:
				if not is_blocked(st.position):
					touch.touch_down(st.index, st.position, _now())
			else:
				touch.touch_up(st.index, _now())
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if gameplay_enabled and not is_tilt_mode():
			touch.touch_move(sd.index, sd.position, _now())
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.echo:
			return
		match k.physical_keycode:
			KEY_LEFT, KEY_A:
				_key_left = k.pressed
				_forward_keys()
			KEY_RIGHT, KEY_D:
				_key_right = k.pressed
				_forward_keys()
			KEY_SPACE, KEY_UP, KEY_W:
				if k.pressed and gameplay_enabled:
					_jump_latched = true
					jump_input.emit()
			KEY_ESCAPE, KEY_P:
				if k.pressed and not _text_input_focused():
					Events.back_requested.emit()


func _text_input_focused() -> bool:
	var f: Control = get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _forward_keys() -> void:
	var a: float = 0.0
	if _key_left:
		a -= 1.0
	if _key_right:
		a += 1.0
	SensorManager.set_keys_axis(a)
