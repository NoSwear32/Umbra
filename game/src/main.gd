extends Node
## Entry point (res://scenes/main.tscn). Creates the game scene, shows the logo splash on the
## very first launch, then the control selector, then the main menu.
##
## Everything else (autoloads, screens, gameplay) is created by the systems themselves.

var game: GameScene
var _splash_layer: CanvasLayer


func _ready() -> void:
	game = GameScene.new()
	add_child(game)
	_start_flow.call_deferred()


func _start_flow() -> void:
	if GameManager.is_first_launch():
		await _show_splash()
		UIManager.show_screen("control_select", {"next": "main_menu"})
	else:
		UIManager.show_screen("main_menu")


## Logo splash (first launch only): fades in, holds for a moment, fades out.
func _show_splash() -> void:
	_splash_layer = CanvasLayer.new()
	_splash_layer.layer = 90
	add_child(_splash_layer)
	var bg: ColorRect = ColorRect.new()
	bg.color = UIKit.C_BG
	_splash_layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box: VBoxContainer = VBoxContainer.new()
	box.theme = UIKit.get_theme()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_splash_layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var logo: TextureRect = UIKit.logo_rect(600.0)
	if logo != null:
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(logo)
	else:
		var t1: Label = UIKit.label("SPIRE", 132, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
		t1.add_theme_constant_override("outline_size", 14)
		box.add_child(t1)
		var t2: Label = UIKit.label("SPRINT", 132, UIKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		t2.add_theme_constant_override("outline_size", 14)
		box.add_child(t2)
	box.add_child(UIKit.label("An endless climb", UIKit.FS_H2, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	box.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.45)
	tw.tween_interval(1.0)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	await tw.finished
	_splash_layer.queue_free()
	_splash_layer = null
