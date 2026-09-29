class_name ReplayOverlay
extends Control
## Controls shown while a replay is being watched: playback speed and EXIT. When the replay
## ends a small panel offers WATCH AGAIN / BACK. Replays never submit scores.

signal exit_pressed
signal speed_changed(factor: float)
signal again_pressed

const SPEEDS: Array = [0.5, 1.0, 2.0, 4.0]

var _bar: PanelContainer
var _seg: Dictionary
var _finished_panel: PanelContainer
var _info: Label


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	theme = UIKit.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar = UIKit.panel("BannerPanel")
	add_child(_bar)
	var h: HBoxContainer = UIKit.hbox(14)
	_bar.add_child(h)
	_info = UIKit.label("REPLAY", UIKit.FS_BODY, UIKit.C_CYAN)
	_info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_info)
	_seg = UIKit.segmented(["0.5x", "1x", "2x", "4x"], 1, _on_speed, 84.0)
	h.add_child(_seg["row"])
	h.add_child(UIKit.button("EXIT", _on_exit, "danger", Vector2(120, 60)))

	_finished_panel = UIKit.panel()
	_finished_panel.visible = false
	add_child(_finished_panel)
	var v: VBoxContainer = UIKit.vbox(14)
	_finished_panel.add_child(v)
	v.add_child(UIKit.label("REPLAY FINISHED", UIKit.FS_H1, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var row: HBoxContainer = UIKit.hbox(16)
	row.add_child(UIKit.button("WATCH AGAIN", _on_again, "primary", Vector2(300, 76)))
	row.add_child(UIKit.button("BACK", _on_exit, "secondary", Vector2(240, 76)))
	v.add_child(row)
	Events.layout_changed.connect(_layout)
	_layout.call_deferred()


func _layout() -> void:
	if _bar == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ins: Vector4 = SafeArea.get_insets(get_viewport())
	_bar.reset_size()
	_bar.position = Vector2((vp.x - _bar.size.x) * 0.5, ins.y)
	_finished_panel.reset_size()
	_finished_panel.position = (vp - _finished_panel.size) * 0.5


func open() -> void:
	visible = true
	_finished_panel.visible = false
	_bar.visible = true
	UIKit.set_segment(_seg["buttons"], 1)
	_layout.call_deferred()


func show_finished() -> void:
	_finished_panel.visible = true
	_bar.visible = false
	_layout.call_deferred()


func set_info(text: String) -> void:
	_info.text = text


func close() -> void:
	visible = false
	_finished_panel.visible = false


func _on_speed(index: int) -> void:
	speed_changed.emit(float(SPEEDS[index]))


func _on_exit() -> void:
	exit_pressed.emit()


func _on_again() -> void:
	again_pressed.emit()
