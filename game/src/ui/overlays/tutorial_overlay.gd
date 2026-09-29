class_name TutorialOverlay
extends Control
## Short interactive tutorial that runs inside a practice run (no scores, no records).
##
## Each step waits for the player to actually do the thing ("hold to run", "release to jump",
## "bounce off a wall", "start a combo") and advances automatically. A NEXT button appears when
## a step takes long, and SKIP TUTORIAL is always available, so experienced players are never
## held up. The rising tower is switched on only for the last step.

signal skipped
signal completed
signal play_pressed
signal menu_pressed
signal enable_scroll

const TOUCH_STEPS: Array = [
	{"id": "move", "text": "Hold LEFT or RIGHT to run", "hint": "Keep holding to speed up."},
	{"id": "speed", "text": "Build speed", "hint": "Hold the direction until you are running fast."},
	{"id": "jump", "text": "RELEASE the button to jump", "hint": "Let go of the direction you are holding - that is the jump."},
	{"id": "high_jump", "text": "More speed = higher jump", "hint": "Run fast first, then release. Jump over several floors!"},
	{"id": "wall", "text": "Bounce off the walls", "hint": "Run into a wall at speed. You keep almost all of it."},
	{"id": "combo", "text": "Skip floors to start a combo", "hint": "Land 2+ floors higher, then do it again within 3 seconds."},
	{"id": "danger", "text": "Don't fall below the screen!", "hint": "The tower rises faster and faster. Keep climbing."},
]
const TILT_STEPS: Array = [
	{"id": "move", "text": "Tilt left / right to run", "hint": "Keep tilting to speed up."},
	{"id": "jump", "text": "TAP the screen to jump", "hint": "Tap anywhere (except the pause button)."},
	{"id": "high_jump", "text": "More speed = higher jump", "hint": "Tilt to build speed, then tap. Jump over several floors!"},
	{"id": "wall", "text": "Bounce off the walls", "hint": "Run into a wall at speed. You keep almost all of it."},
	{"id": "combo", "text": "Skip floors for combos", "hint": "Land 2+ floors higher, then do it again within 3 seconds."},
	{"id": "danger", "text": "Stay ahead of the rising tower!", "hint": "It rises faster and faster. Keep climbing."},
]
const NEXT_AFTER_SECONDS: float = 12.0
const DANGER_STEP_SECONDS: float = 8.0

var active: bool = false

var _steps: Array = []
var _index: int = 0
var _step_time: float = 0.0
var _move_time: float = 0.0
var _card: PanelContainer
var _counter: Label
var _title: Label
var _hint: Label
var _next_button: Button
var _skip_button: Button
var _done_panel: PanelContainer


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	theme = UIKit.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card = UIKit.panel("BannerPanel")
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var v: VBoxContainer = UIKit.vbox(4)
	_card.add_child(v)
	_counter = UIKit.label("", UIKit.FS_SMALL, UIKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_counter)
	_title = UIKit.label("", 40, UIKit.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_title)
	_hint = UIKit.wrap_label("", UIKit.FS_BODY - 2, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.custom_minimum_size = Vector2(560, 0)
	v.add_child(_hint)
	_next_button = UIKit.button("NEXT", _advance, "secondary", Vector2(160, 56))
	_next_button.visible = false
	_next_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_next_button)

	_skip_button = UIKit.button("SKIP TUTORIAL", _on_skip, "ghost", Vector2(260, 56))
	_skip_button.add_theme_font_size_override("font_size", 22)
	add_child(_skip_button)

	_done_panel = UIKit.panel()
	_done_panel.visible = false
	add_child(_done_panel)
	var dv: VBoxContainer = UIKit.vbox(14)
	_done_panel.add_child(dv)
	dv.add_child(UIKit.label("YOU'RE READY!", UIKit.FS_H1 + 6, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	dv.add_child(UIKit.wrap_label("Speed, walls, big jumps and combos - that's everything. Now climb as high as you can.", UIKit.FS_BODY, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var row: HBoxContainer = UIKit.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button("PLAY", _on_play, "primary", Vector2(260, 78)))
	row.add_child(UIKit.button("MENU", _on_menu, "secondary", Vector2(220, 78)))
	dv.add_child(row)
	Events.layout_changed.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	if _card == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ins: Vector4 = SafeArea.get_insets(get_viewport())
	_card.reset_size()
	_card.position = Vector2((vp.x - _card.size.x) * 0.5, ins.y + 6.0)
	_skip_button.reset_size()
	_skip_button.position = Vector2((vp.x - _skip_button.size.x) * 0.5, vp.y - ins.w - _skip_button.size.y - 4.0)
	_done_panel.reset_size()
	_done_panel.position = (vp - _done_panel.size) * 0.5


func start(touch_mode: bool) -> void:
	_steps = TOUCH_STEPS if touch_mode else TILT_STEPS
	_index = 0
	_step_time = 0.0
	_move_time = 0.0
	active = true
	visible = true
	_done_panel.visible = false
	_card.visible = true
	_skip_button.visible = true
	_show_step()


func stop() -> void:
	active = false
	visible = false


## True while the "you're ready" panel (after the last step) is on screen.
func is_finished_panel_visible() -> bool:
	return _done_panel != null and _done_panel.visible


func _show_step() -> void:
	var s: Dictionary = _steps[_index]
	_counter.text = "STEP %d / %d" % [_index + 1, _steps.size()]
	_title.text = String(s["text"])
	_hint.text = String(s["hint"])
	_step_time = 0.0
	_move_time = 0.0
	_next_button.visible = false
	if String(s["id"]) == "danger":
		enable_scroll.emit()
	_layout.call_deferred()
	AudioManager.play_sfx("ui_click", 1.3, -6.0)


func _current_id() -> String:
	return String(_steps[_index]["id"])


func _advance() -> void:
	if not active:
		return
	_index += 1
	if _index >= _steps.size():
		_finish()
	else:
		_show_step()


func _finish() -> void:
	active = false
	_card.visible = false
	_skip_button.visible = false
	_done_panel.visible = true
	AudioManager.play_sfx("record", 1.0, -3.0)
	completed.emit()
	_layout.call_deferred()


# ---------------------------------------------------------------------------
# Events from the game
# ---------------------------------------------------------------------------
func notify_jump(speed_ratio: float) -> void:
	if not active:
		return
	var id: String = _current_id()
	if id == "jump" or (id == "high_jump" and speed_ratio >= 0.55):
		_advance()


func notify_wall(speed: float) -> void:
	if active and _current_id() == "wall" and speed >= 260.0:
		_advance()


func notify_combo_started() -> void:
	if active and _current_id() == "combo":
		_advance()


## Called every frame with the current run.
func update_view(delta: float, run: RunManager) -> void:
	if not active:
		return
	_step_time += delta
	if _step_time > NEXT_AFTER_SECONDS and not _next_button.visible and _current_id() != "danger":
		_next_button.visible = true
		_layout.call_deferred()
	var id: String = _current_id()
	var ratio: float = run.player.speed_ratio()
	if id == "move":
		if absf(run.player.vx) > 140.0:
			_move_time += delta
		if _move_time > 0.35:
			_advance()
	elif id == "speed":
		if ratio >= 0.6:
			_advance()
	elif id == "danger":
		if _step_time >= DANGER_STEP_SECONDS:
			_advance()


func _on_skip() -> void:
	active = false
	skipped.emit()


func _on_play() -> void:
	play_pressed.emit()


func _on_menu() -> void:
	menu_pressed.emit()
