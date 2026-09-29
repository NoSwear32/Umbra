extends UIScreen
## Tilt calibration: "Hold your device in a comfortable playing position", tap CALIBRATE,
## the current angle becomes the neutral position. A live meter shows the resulting input.

var _meter: TiltMeter
var _status: Label
var _sensor_note: Label
var _invert: Dictionary
var _shown_deg: float = 0.0
var _tuning: GameTuning


func build() -> void:
	_tuning = TuningStore.get_tuning()
	content.add_child(UIKit.header("CALIBRATE TILT", _on_back))
	var card: PanelContainer = UIKit.panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(card)
	var body: VBoxContainer = UIKit.vbox(16)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(body)
	body.add_child(UIKit.label("Hold your device in a comfortable playing position.", UIKit.FS_H2, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.wrap_label("Then tap CALIBRATE. Tilting left or right from this position moves the character. If the bar below moves the wrong way, switch INVERT on.", UIKit.FS_BODY, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_meter = TiltMeter.new()
	_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_meter)
	_status = UIKit.label("", UIKit.FS_BODY, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_status)
	_sensor_note = UIKit.label("", UIKit.FS_SMALL, UIKit.C_BAD, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_sensor_note)
	_invert = UIKit.toggle_row("Invert tilt direction", SettingsManager.get_bool("tilt_invert"), _on_invert)
	(_invert["row"] as Control).custom_minimum_size = Vector2(560, 64)
	(_invert["row"] as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_invert["row"])
	var row: HBoxContainer = UIKit.hbox(20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button("CALIBRATE", _on_calibrate, "primary", Vector2(360, 84)))
	row.add_child(UIKit.button("DONE", _on_done, "secondary", Vector2(260, 84)))
	body.add_child(row)


func refresh() -> void:
	_shown_deg = 0.0
	(_invert["button"] as Button).set_pressed_no_signal(SettingsManager.get_bool("tilt_invert"))
	UIKit.style_toggle(_invert["button"] as Button)
	_update_status()


func _update_status() -> void:
	if SettingsManager.get_bool("tilt_calibrated"):
		_status.text = "Neutral angle saved: %+.1f deg" % SettingsManager.get_float("tilt_neutral_deg")
	else:
		_status.text = "Not calibrated yet."


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var g: Vector3 = SensorManager.read_sensor()
	var ok: bool = g.length() >= 0.5
	var deg: float = 0.0
	if ok:
		deg = TiltInputController.tilt_degrees(g) - SettingsManager.get_float("tilt_neutral_deg")
	_shown_deg += (deg - _shown_deg) * minf(1.0, delta * 14.0)
	var dead: float = SettingsManager.get_float("tilt_dead_zone")
	var full: float = SettingsManager.tilt_full_degrees(_tuning)
	var axis: float = TiltInputController.map_angle(_shown_deg, dead, full, _tuning.tilt_response_curve, SettingsManager.get_bool("tilt_invert"), 1.0)
	_meter.set_values(axis, _shown_deg, dead / (dead + full), ok)
	if ok:
		_sensor_note.text = ""
	elif OS.has_feature("mobile"):
		_sensor_note.text = "No tilt sensor data. Try Touch controls instead."
	else:
		_sensor_note.text = "No tilt sensor on this device (desktop). Touch controls are recommended."


func _on_invert(value: bool) -> void:
	SettingsManager.set_value("tilt_invert", value)


func _on_calibrate() -> void:
	if SensorManager.calibrate_now():
		AudioManager.play_sfx("unlock", 1.2, -4.0)
		UIManager.toast("Calibrated!")
		_update_status()
	else:
		UIManager.toast("No tilt sensor detected.")


func _on_done() -> void:
	var next: String = String(params.get("next", ""))
	if next.is_empty():
		UIManager.pop()
	else:
		UIManager.show_screen(next)


func _on_back() -> void:
	UIManager.pop()
