class_name GameOverPanel
extends Control
## Game-over screen: FINAL SCORE (counts up), HIGHEST FLOOR, BEST COMBO, RUN TIME, record
## badges (NEW HIGH SCORE / NEW FLOOR RECORD / NEW COMBO RECORD) and the four actions
## PLAY AGAIN, WATCH REPLAY, SAVE / RENAME REPLAY, MAIN MENU.

signal play_again_pressed
signal watch_replay_pressed
signal save_replay_pressed
signal main_menu_pressed

var _title: Label
var _score_label: Label
var _floor_label: Label
var _combo_label: Label
var _time_label: Label
var _badges: VBoxContainer
var _unlock_label: Label
var _watch_button: Button
var _save_button: Button
var _tween: Tween = null


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	theme = UIKit.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.68)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var safe: MarginContainer = MarginContainer.new()
	add_child(safe)
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.apply_to(safe, get_viewport())
	Events.layout_changed.connect(_relayout.bind(safe))

	var row: HBoxContainer = UIKit.hbox(34)
	safe.add_child(row)

	# ---- results
	var card: PanelContainer = UIKit.panel()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)
	var rv: VBoxContainer = UIKit.vbox(6)
	card.add_child(rv)
	_title = UIKit.label("GAME OVER", UIKit.FS_H1 + 10, UIKit.C_BAD, HORIZONTAL_ALIGNMENT_CENTER)
	rv.add_child(_title)
	rv.add_child(UIKit.label("FINAL SCORE", UIKit.FS_SMALL, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_score_label = UIKit.label("0", 84, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_score_label.add_theme_constant_override("outline_size", 10)
	rv.add_child(_score_label)
	var stats: HBoxContainer = UIKit.hbox(12)
	rv.add_child(stats)
	_floor_label = _stat_block(stats, "HIGHEST FLOOR")
	_combo_label = _stat_block(stats, "BEST COMBO")
	_time_label = _stat_block(stats, "RUN TIME")
	_badges = UIKit.vbox(4)
	rv.add_child(_badges)
	_unlock_label = UIKit.label("", UIKit.FS_BODY, UIKit.C_GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	rv.add_child(_unlock_label)

	# ---- actions
	var actions: VBoxContainer = UIKit.vbox(14)
	actions.custom_minimum_size = Vector2(460, 0)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	actions.add_child(UIKit.button("PLAY AGAIN", _on_play_again, "primary", Vector2(0, 110)))
	_watch_button = UIKit.button("WATCH REPLAY", _on_watch, "secondary", Vector2(0, 72))
	actions.add_child(_watch_button)
	_save_button = UIKit.button("SAVE / RENAME REPLAY", _on_save, "secondary", Vector2(0, 72))
	actions.add_child(_save_button)
	actions.add_child(UIKit.button("MAIN MENU", _on_menu, "ghost", Vector2(0, 72)))


func _relayout(safe: MarginContainer) -> void:
	SafeArea.apply_to(safe, get_viewport())


func _stat_block(parent: HBoxContainer, title: String) -> Label:
	var v: VBoxContainer = UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(title, UIKit.FS_SMALL - 2, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var l: Label = UIKit.label("-", UIKit.FS_H2, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(l)
	parent.add_child(v)
	return l


## summary: GameManager.finish_run() result. replay_available: false for practice/debug runs.
func show_summary(summary: Dictionary, replay_available: bool, title: String = "GAME OVER") -> void:
	var r: Dictionary = summary["result"]
	var records: Dictionary = summary.get("records", {})
	_title.text = title
	_floor_label.text = str(int(r.get("highest_floor", 0)))
	var cf: int = int(r.get("best_combo_floors", 0))
	_combo_label.text = "%d floors" % cf if cf > 0 else "-"
	_time_label.text = Fmt.duration(float(r.get("duration", 0.0)))
	_watch_button.visible = replay_available
	_save_button.visible = replay_available and not String(summary.get("replay_id", "")).is_empty()

	for c in _badges.get_children():
		c.queue_free()
	var badge_defs: Array = [["score", "NEW HIGH SCORE!"], ["floor", "NEW FLOOR RECORD!"], ["combo", "NEW COMBO RECORD!"]]
	for b in badge_defs:
		if bool(records.get(String(b[0]), false)):
			var l: Label = UIKit.label(String(b[1]), UIKit.FS_H2, UIKit.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
			l.add_theme_constant_override("outline_size", 8)
			_badges.add_child(l)
			_pulse(l)
	var new_chars: Array = summary.get("new_characters", [])
	if new_chars.is_empty():
		_unlock_label.text = ""
	else:
		var names: PackedStringArray = PackedStringArray()
		for id in new_chars:
			names.append(CharacterManager.get_def(String(id)).display_name)
		_unlock_label.text = "CHARACTER UNLOCKED: %s" % ", ".join(names)

	visible = true
	modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	_tween.tween_method(_set_score, 0, int(r.get("score", 0)), 0.9).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _set_score(value: Variant) -> void:
	_score_label.text = Fmt.number(int(value))


func _pulse(l: Label) -> void:
	l.pivot_offset = l.size * 0.5
	var tw: Tween = create_tween()
	tw.set_loops(0)
	tw.tween_property(l, "scale", Vector2(1.08, 1.08), 0.45)
	tw.tween_property(l, "scale", Vector2.ONE, 0.45)


func close() -> void:
	visible = false
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _on_play_again() -> void:
	play_again_pressed.emit()


func _on_watch() -> void:
	watch_replay_pressed.emit()


func _on_save() -> void:
	save_replay_pressed.emit()


func _on_menu() -> void:
	main_menu_pressed.emit()
