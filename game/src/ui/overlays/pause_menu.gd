class_name PauseMenu
extends Control
## Pause overlay: Resume, Restart, Settings, Quit to menu. While it is open the simulation is
## frozen, no gameplay input is accepted and the sensor is off (handled by GameScene).

signal resume_pressed
signal restart_pressed
signal settings_pressed
signal quit_pressed

var _summary: Label


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	theme = UIKit.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = UIKit.panel()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var body: VBoxContainer = UIKit.vbox(14)
	panel.add_child(body)
	body.add_child(UIKit.label("PAUSED", UIKit.FS_H1 + 8, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_summary = UIKit.label("", UIKit.FS_BODY, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_summary)
	body.add_child(UIKit.spacer(4))
	body.add_child(UIKit.button("RESUME", _on_resume, "primary", Vector2(0, 84)))
	body.add_child(UIKit.button("RESTART", _on_restart, "secondary", Vector2(0, 72)))
	body.add_child(UIKit.button("SETTINGS", _on_settings, "secondary", Vector2(0, 72)))
	body.add_child(UIKit.button("QUIT TO MENU", _on_quit, "danger", Vector2(0, 72)))


func open(score: int, floor_reached: int, seconds: float) -> void:
	_summary.text = "Score %s   -   Floor %d   -   %s" % [Fmt.number(score), floor_reached, Fmt.duration(seconds)]
	visible = true


func close() -> void:
	visible = false


func _on_resume() -> void:
	resume_pressed.emit()


func _on_restart() -> void:
	restart_pressed.emit()


func _on_settings() -> void:
	settings_pressed.emit()


func _on_quit() -> void:
	quit_pressed.emit()
