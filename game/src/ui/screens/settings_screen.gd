extends UIScreen
## Settings: CONTROLS, AUDIO, VIDEO, GAMEPLAY, DATA. Every change is applied and saved at once.
## Destructive actions always ask for confirmation.

const TAB_NAMES: Array = ["CONTROLS", "AUDIO", "VIDEO", "GAMEPLAY", "DATA"]
const FPS_VALUES: Array = [0, 30, 60, 90, 120]
const TILT_PRESETS: Array = ["low", "medium", "high", "custom"]

var _tab_buttons: Array = []
var _pages: Array = []
var _control_seg: Dictionary
var _tilt_seg: Dictionary
var _tilt_custom_row: Control
var _sensor_label: Label
var _replay_label: Label
var _name_button: Button
var _tuning: GameTuning
var _current_tab: int = 0
var _touch_widgets: Dictionary = {}


func build() -> void:
	_tuning = TuningStore.get_tuning()
	content.add_child(UIKit.header("SETTINGS", _on_back))
	var body: HBoxContainer = UIKit.hbox(22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	var tabs: VBoxContainer = UIKit.vbox(10)
	tabs.custom_minimum_size = Vector2(240, 0)
	body.add_child(tabs)
	for i in range(TAB_NAMES.size()):
		var b: Button = Button.new()
		b.text = String(TAB_NAMES[i])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 72)
		b.pressed.connect(_on_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)

	var panel: PanelContainer = UIKit.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var stack: VBoxContainer = UIKit.vbox(0)
	panel.add_child(stack)
	var builders: Array = [_page_controls(), _page_audio(), _page_video(), _page_gameplay(), _page_data()]
	for page in builders:
		var sc: ScrollContainer = UIKit.scroll(page)
		sc.visible = false
		stack.add_child(sc)
		_pages.append(sc)
	_show_tab(0)


func refresh() -> void:
	_sync_widgets()
	_show_tab(_current_tab)


func _on_back() -> void:
	UIManager.pop()


func _on_tab(index: int) -> void:
	AudioManager.play_click()
	_show_tab(index)


func _show_tab(index: int) -> void:
	_current_tab = index
	for i in range(_pages.size()):
		(_pages[i] as Control).visible = (i == index)
		var b: Button = _tab_buttons[i]
		b.set_pressed_no_signal(i == index)
		b.theme_type_variation = "SegmentOn" if i == index else "SegmentOff"


# ---------------------------------------------------------------------------
# CONTROLS
# ---------------------------------------------------------------------------
func _page_controls() -> VBoxContainer:
	var page: VBoxContainer = UIKit.vbox(18)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var mode_card: Dictionary = UIKit.section_card("Control scheme")
	page.add_child(mode_card["card"])
	var mode_body: VBoxContainer = mode_card["body"]
	_control_seg = UIKit.segmented(["TOUCH BUTTONS", "TILT + TAP"], 0, _on_control_mode, 260.0)
	mode_body.add_child(_control_seg["row"])

	var touch_card: Dictionary = UIKit.section_card("Touch buttons (release to jump)")
	page.add_child(touch_card["card"])
	var tb: VBoxContainer = touch_card["body"]
	_touch_widgets["opacity"] = UIKit.slider_row("Button opacity", 0.15, 1.0, 0.05, SettingsManager.get_float("touch_opacity"), _set_float.bind("touch_opacity"), _fmt_percent)
	tb.add_child(_touch_widgets["opacity"]["row"])
	_touch_widgets["scale"] = UIKit.slider_row("Button size", 0.6, 1.6, 0.05, SettingsManager.get_float("touch_scale"), _set_float.bind("touch_scale"), _fmt_percent)
	tb.add_child(_touch_widgets["scale"]["row"])
	_touch_widgets["offset_x"] = UIKit.slider_row("Horizontal position", -200.0, 200.0, 5.0, SettingsManager.get_float("touch_offset_x"), _set_float.bind("touch_offset_x"), _fmt_offset)
	tb.add_child(_touch_widgets["offset_x"]["row"])
	_touch_widgets["offset_y"] = UIKit.slider_row("Vertical position", -120.0, 200.0, 5.0, SettingsManager.get_float("touch_offset_y"), _set_float.bind("touch_offset_y"), _fmt_offset)
	tb.add_child(_touch_widgets["offset_y"]["row"])
	_touch_widgets["hold"] = UIKit.slider_row("Release-to-jump threshold", 0.0, 300.0, 10.0, float(SettingsManager.get_int("touch_min_hold_ms")), _set_hold, _fmt_ms)
	tb.add_child(_touch_widgets["hold"]["row"])
	_touch_widgets["swap"] = UIKit.toggle_row("Swap LEFT / RIGHT buttons", SettingsManager.get_bool("touch_swap"), _set_bool.bind("touch_swap"))
	tb.add_child(_touch_widgets["swap"]["row"])
	_touch_widgets["haptics"] = UIKit.toggle_row("Haptic feedback", SettingsManager.get_bool("haptics"), _set_bool.bind("haptics"))
	tb.add_child(_touch_widgets["haptics"]["row"])
	tb.add_child(UIKit.wrap_label("A release only counts as a jump if the button was held at least this long. It filters accidental taps.", UIKit.FS_SMALL, UIKit.C_DIM))

	var tilt_card: Dictionary = UIKit.section_card("Tilt + tap")
	page.add_child(tilt_card["card"])
	var lb: VBoxContainer = tilt_card["body"]
	lb.add_child(UIKit.label("Tilt sensitivity", UIKit.FS_BODY, UIKit.C_TEXT))
	_tilt_seg = UIKit.segmented(["LOW", "MEDIUM", "HIGH", "CUSTOM"], 1, _on_tilt_preset, 150.0)
	lb.add_child(_tilt_seg["row"])
	_touch_widgets["tilt_custom"] = UIKit.slider_row("Custom sensitivity", _tuning.tilt_full_deg_min, _tuning.tilt_full_deg_max, 1.0, SettingsManager.get_float("tilt_custom_deg"), _set_tilt_custom, _fmt_degrees_full)
	_tilt_custom_row = _touch_widgets["tilt_custom"]["row"]
	lb.add_child(_tilt_custom_row)
	_touch_widgets["dead"] = UIKit.slider_row("Dead zone", 0.0, 10.0, 0.5, SettingsManager.get_float("tilt_dead_zone"), _set_float.bind("tilt_dead_zone"), _fmt_degrees)
	lb.add_child(_touch_widgets["dead"]["row"])
	_touch_widgets["invert"] = UIKit.toggle_row("Invert tilt", SettingsManager.get_bool("tilt_invert"), _set_bool.bind("tilt_invert"))
	lb.add_child(_touch_widgets["invert"]["row"])
	var cal_row: HBoxContainer = UIKit.hbox(16)
	cal_row.add_child(UIKit.button("CALIBRATE", _on_calibrate, "primary", Vector2(300, 68)))
	_sensor_label = UIKit.label("", UIKit.FS_SMALL, UIKit.C_DIM)
	_sensor_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cal_row.add_child(_sensor_label)
	lb.add_child(cal_row)
	return page


func _on_control_mode(index: int) -> void:
	SettingsManager.set_value("control_mode", "tilt" if index == 1 else "touch")
	SettingsManager.set_value("control_chosen", true)
	if index == 1 and not SettingsManager.get_bool("tilt_calibrated"):
		UIManager.toast("Tilt selected - please calibrate.")


func _on_tilt_preset(index: int) -> void:
	SettingsManager.set_value("tilt_preset", TILT_PRESETS[index])
	_tilt_custom_row.visible = (index == 3)


func _on_calibrate() -> void:
	UIManager.push_screen("calibrate")


func _set_float(value: float, key: String) -> void:
	SettingsManager.set_value(key, value)


func _set_bool(value: bool, key: String) -> void:
	SettingsManager.set_value(key, value)


func _set_hold(value: float) -> void:
	SettingsManager.set_value("touch_min_hold_ms", int(value))


func _set_tilt_custom(value: float) -> void:
	SettingsManager.set_value("tilt_custom_deg", value)


static func _fmt_percent(v: float) -> String:
	return "%d%%" % int(v * 100.0 + 0.5)


static func _fmt_offset(v: float) -> String:
	return "%+d" % int(v)


static func _fmt_ms(v: float) -> String:
	return "%d ms" % int(v)


static func _fmt_degrees(v: float) -> String:
	return "%.1f deg" % v


static func _fmt_degrees_full(v: float) -> String:
	return "%d deg" % int(v)


# ---------------------------------------------------------------------------
# AUDIO
# ---------------------------------------------------------------------------
func _page_audio() -> VBoxContainer:
	var page: VBoxContainer = UIKit.vbox(18)
	var card: Dictionary = UIKit.section_card("Volume")
	page.add_child(card["card"])
	var b: VBoxContainer = card["body"]
	_touch_widgets["vol_master"] = UIKit.slider_row("Master volume", 0.0, 1.0, 0.05, SettingsManager.get_float("vol_master"), _set_float.bind("vol_master"), _fmt_percent)
	b.add_child(_touch_widgets["vol_master"]["row"])
	_touch_widgets["vol_music"] = UIKit.slider_row("Music volume", 0.0, 1.0, 0.05, SettingsManager.get_float("vol_music"), _set_float.bind("vol_music"), _fmt_percent)
	b.add_child(_touch_widgets["vol_music"]["row"])
	_touch_widgets["vol_sfx"] = UIKit.slider_row("Sound effects volume", 0.0, 1.0, 0.05, SettingsManager.get_float("vol_sfx"), _set_float.bind("vol_sfx"), _fmt_percent)
	b.add_child(_touch_widgets["vol_sfx"]["row"])
	_touch_widgets["mute"] = UIKit.toggle_row("Mute everything", SettingsManager.get_bool("mute"), _set_bool.bind("mute"))
	b.add_child(_touch_widgets["mute"]["row"])
	_touch_widgets["haptics2"] = UIKit.toggle_row("Haptic feedback", SettingsManager.get_bool("haptics"), _set_bool.bind("haptics"))
	b.add_child(_touch_widgets["haptics2"]["row"])
	return page


# ---------------------------------------------------------------------------
# VIDEO
# ---------------------------------------------------------------------------
func _page_video() -> VBoxContainer:
	var page: VBoxContainer = UIKit.vbox(18)
	var card: Dictionary = UIKit.section_card("Performance and effects")
	page.add_child(card["card"])
	var b: VBoxContainer = card["body"]
	b.add_child(UIKit.label("Frame rate limit", UIKit.FS_BODY, UIKit.C_TEXT))
	_touch_widgets["fps"] = UIKit.segmented(["AUTO", "30", "60", "90", "120"], 0, _on_fps, 130.0)
	b.add_child(_touch_widgets["fps"]["row"])
	b.add_child(UIKit.wrap_label("AUTO follows the display refresh rate. Gameplay speed never depends on it: the simulation always runs at a fixed rate.", UIKit.FS_SMALL, UIKit.C_DIM))
	b.add_child(UIKit.spacer(6))
	b.add_child(UIKit.label("Particles", UIKit.FS_BODY, UIKit.C_TEXT))
	_touch_widgets["particles"] = UIKit.segmented(["LOW", "MEDIUM", "HIGH"], 2, _on_particles, 170.0)
	b.add_child(_touch_widgets["particles"]["row"])
	_touch_widgets["shake"] = UIKit.toggle_row("Screen shake", SettingsManager.get_bool("screen_shake"), _set_bool.bind("screen_shake"))
	b.add_child(_touch_widgets["shake"]["row"])
	_touch_widgets["reduced"] = UIKit.toggle_row("Reduced effects mode", SettingsManager.get_bool("reduced_effects"), _set_bool.bind("reduced_effects"))
	b.add_child(_touch_widgets["reduced"]["row"])
	b.add_child(UIKit.wrap_label("Reduced effects turns off screen shake, speed lines, trails and most particles for maximum clarity.", UIKit.FS_SMALL, UIKit.C_DIM))
	_touch_widgets["show_fps"] = UIKit.toggle_row("Show FPS counter", SettingsManager.get_bool("show_fps"), _set_bool.bind("show_fps"))
	b.add_child(_touch_widgets["show_fps"]["row"])
	return page


func _on_fps(index: int) -> void:
	SettingsManager.set_value("fps_limit", int(FPS_VALUES[index]))


func _on_particles(index: int) -> void:
	SettingsManager.set_value("particles", index)


# ---------------------------------------------------------------------------
# GAMEPLAY
# ---------------------------------------------------------------------------
func _page_gameplay() -> VBoxContainer:
	var page: VBoxContainer = UIKit.vbox(18)
	var card: Dictionary = UIKit.section_card("Help and profile")
	page.add_child(card["card"])
	var b: VBoxContainer = card["body"]
	b.add_child(UIKit.button("HOW TO PLAY", _on_help, "secondary", Vector2(0, 72)))
	b.add_child(UIKit.button("PRACTICE RUN (INTERACTIVE TUTORIAL)", _on_tutorial, "primary", Vector2(0, 72)))
	_name_button = UIKit.button("", _on_change_name, "secondary", Vector2(0, 72))
	b.add_child(_name_button)
	b.add_child(UIKit.button("RESET CONTROL CALIBRATION", _on_reset_calibration, "ghost", Vector2(0, 72)))
	return page


func _on_help() -> void:
	UIManager.push_screen("help")


func _on_tutorial() -> void:
	UIManager.game.begin_tutorial()


func _on_change_name() -> void:
	UIManager.prompt_text("Player name", SettingsManager.get_string("player_name"), SettingsManager.PLAYER_NAME_MAX, _apply_name)


func _apply_name(text: String) -> void:
	SettingsManager.set_value("player_name", text)
	_sync_widgets()


func _on_reset_calibration() -> void:
	SensorManager.clear_calibration()
	UIManager.toast("Calibration cleared. Calibrate again before playing with tilt.")
	_sync_widgets()


# ---------------------------------------------------------------------------
# DATA
# ---------------------------------------------------------------------------
func _page_data() -> VBoxContainer:
	var page: VBoxContainer = UIKit.vbox(18)
	var card: Dictionary = UIKit.section_card("Replays")
	page.add_child(card["card"])
	var rb: VBoxContainer = card["body"]
	_replay_label = UIKit.label("", UIKit.FS_BODY, UIKit.C_DIM)
	rb.add_child(_replay_label)
	rb.add_child(UIKit.button("OPEN REPLAYS", _on_open_replays, "secondary", Vector2(0, 72)))
	rb.add_child(UIKit.button("DELETE ALL REPLAYS", _on_delete_replays, "danger", Vector2(0, 72)))

	var card2: Dictionary = UIKit.section_card("Records and progress")
	page.add_child(card2["card"])
	var b: VBoxContainer = card2["body"]
	b.add_child(UIKit.button("RESET STATISTICS", _on_reset_stats, "danger", Vector2(0, 72)))
	b.add_child(UIKit.button("RESET HIGH SCORES", _on_reset_scores, "danger", Vector2(0, 72)))
	b.add_child(UIKit.button("RESET ALL SAVED DATA", _on_reset_all, "danger", Vector2(0, 72)))
	b.add_child(UIKit.wrap_label("Resetting cannot be undone. Your progress is stored only on this device.", UIKit.FS_SMALL, UIKit.C_DIM))
	return page


func _on_open_replays() -> void:
	UIManager.push_screen("replays")


func _on_delete_replays() -> void:
	UIManager.confirm("Delete all replays?", "Every saved replay will be removed. High scores stay.", "DELETE ALL", _do_delete_replays, true)


func _do_delete_replays() -> void:
	ReplayManager.delete_all()
	_sync_widgets()
	UIManager.toast("Replays deleted")


func _on_reset_stats() -> void:
	UIManager.confirm("Reset statistics?", "All lifetime statistics will be set back to zero.", "RESET", _do_reset_stats, true)


func _do_reset_stats() -> void:
	StatisticsManager.reset()
	UIManager.toast("Statistics reset")


func _on_reset_scores() -> void:
	UIManager.confirm("Reset high scores?", "All local leaderboard entries will be deleted.", "RESET", _do_reset_scores, true)


func _do_reset_scores() -> void:
	LeaderboardManager.clear_all()
	UIManager.toast("High scores reset")


func _on_reset_all() -> void:
	UIManager.confirm("Reset ALL data?", "Settings, records, statistics, unlocked characters and replays will be erased.", "CONTINUE", _second_reset_confirm, true)


func _second_reset_confirm() -> void:
	UIManager.confirm("Are you absolutely sure?", "This wipes everything and restarts the first-time setup.", "ERASE EVERYTHING", _do_reset_all, true)


func _do_reset_all() -> void:
	ReplayManager.delete_all()
	SaveManager.reset_all()
	UIManager.toast("All data erased")
	UIManager.show_screen("control_select", {"next": "main_menu"})


# ---------------------------------------------------------------------------
# Sync widgets with the current settings (called on enter)
# ---------------------------------------------------------------------------
func _sync_widgets() -> void:
	if _control_seg.is_empty():
		return
	UIKit.set_segment(_control_seg["buttons"], 1 if SettingsManager.is_tilt_mode() else 0)
	var preset: int = TILT_PRESETS.find(SettingsManager.get_string("tilt_preset"))
	UIKit.set_segment(_tilt_seg["buttons"], maxi(preset, 0))
	_tilt_custom_row.visible = (preset == 3)
	var fps_idx: int = FPS_VALUES.find(SettingsManager.get_int("fps_limit"))
	UIKit.set_segment(_touch_widgets["fps"]["buttons"], maxi(fps_idx, 0))
	UIKit.set_segment(_touch_widgets["particles"]["buttons"], SettingsManager.get_int("particles"))
	if SensorManager.read_sensor().length() >= 0.5:
		_sensor_label.text = "Tilt sensor detected"
	elif OS.has_feature("mobile"):
		_sensor_label.text = "No tilt sensor found - use touch controls"
	else:
		_sensor_label.text = "Desktop: no tilt sensor (arrow keys simulate tilt)"
	_replay_label.text = "%d replay(s) stored on this device." % ReplayManager.count()
	_name_button.text = "PLAYER NAME:  %s" % SettingsManager.get_string("player_name")
	# sliders and toggles (assigning the same value is harmless: SettingsManager ignores no-ops)
	var slider_keys: Dictionary = {
		"opacity": "touch_opacity", "scale": "touch_scale", "offset_x": "touch_offset_x",
		"offset_y": "touch_offset_y", "tilt_custom": "tilt_custom_deg", "dead": "tilt_dead_zone",
		"vol_master": "vol_master", "vol_music": "vol_music", "vol_sfx": "vol_sfx",
	}
	for wk in slider_keys:
		var s: HSlider = _touch_widgets[wk]["slider"]
		s.value = SettingsManager.get_float(String(slider_keys[wk]))
	(_touch_widgets["hold"]["slider"] as HSlider).value = float(SettingsManager.get_int("touch_min_hold_ms"))
	var toggle_keys: Dictionary = {
		"swap": "touch_swap", "haptics": "haptics", "haptics2": "haptics", "invert": "tilt_invert",
		"mute": "mute", "shake": "screen_shake", "reduced": "reduced_effects", "show_fps": "show_fps",
	}
	for tk in toggle_keys:
		var tb: Button = _touch_widgets[tk]["button"]
		tb.set_pressed_no_signal(SettingsManager.get_bool(String(toggle_keys[tk])))
		UIKit.style_toggle(tb)
