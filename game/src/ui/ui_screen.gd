class_name UIScreen
extends Control
## Base class of every full-screen menu.
##
## Subclasses override build() to fill `content` (a vertical box that already respects the
## device safe area), refresh() to update dynamic data, and on_back() to intercept the
## Android back button. Screens are cached by UIManager and re-used.

var params: Dictionary = {}
var screen_id: String = ""
## Safe-area aware margin container that holds `content`.
var safe: MarginContainer
var content: VBoxContainer


func _ready() -> void:
	theme = UIKit.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe = MarginContainer.new()
	add_child(safe)
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content = UIKit.vbox(14)
	safe.add_child(content)
	_apply_safe_area()
	Events.layout_changed.connect(_apply_safe_area)
	build()


func _apply_safe_area() -> void:
	if safe != null and is_inside_tree():
		SafeArea.apply_to(safe, get_viewport())


## Create the widgets. Called once, after the screen entered the tree.
func build() -> void:
	pass


## Called every time the screen is shown.
func on_enter(p: Dictionary) -> void:
	params = p
	refresh()


func on_exit() -> void:
	pass


## Update data-driven widgets (called by on_enter).
func refresh() -> void:
	pass


## Return true if the back request was handled by the screen itself.
func on_back() -> bool:
	return false


## Convenience: go back one screen.
func go_back() -> void:
	UIManager.pop()
