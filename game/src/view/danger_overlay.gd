class_name DangerOverlay
extends Control
## Red glow at the bottom of the screen that grows as the player gets close to the kill line,
## plus a short full-screen flash used for the "tower surge" warning.

var danger: float = 0.0
var flash: float = 0.0
var flash_color: Color = Color(1.0, 0.35, 0.2, 1.0)

var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_danger(value: float) -> void:
	var v: float = clampf(value, 0.0, 1.0)
	if absf(v - danger) > 0.004:
		danger = v
		queue_redraw()


func trigger_flash(color: Color) -> void:
	flash = 1.0
	flash_color = color
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	var changed: bool = false
	if flash > 0.0:
		flash = maxf(flash - delta * 2.2, 0.0)
		changed = true
	if danger > 0.01:
		changed = true
	if changed:
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if danger > 0.01:
		var pulse: float = 0.75 + 0.25 * sin(_time * 9.0)
		var a: float = danger * 0.55 * pulse
		var band: float = 170.0 + 120.0 * danger
		draw_polygon(
			PackedVector2Array([Vector2(0, h - band), Vector2(w, h - band), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(1.0, 0.1, 0.1, 0.0), Color(1.0, 0.1, 0.1, 0.0), Color(1.0, 0.1, 0.1, a), Color(1.0, 0.1, 0.1, a)]))
	if flash > 0.01:
		var edge: float = 120.0
		var c0: Color = Color(flash_color, 0.0)
		var c1: Color = Color(flash_color, 0.45 * flash)
		# left / right / top / bottom edge glows
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(edge, 0), Vector2(edge, h), Vector2(0, h)]), PackedColorArray([c1, c0, c0, c1]))
		draw_polygon(PackedVector2Array([Vector2(w - edge, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - edge, h)]), PackedColorArray([c0, c1, c1, c0]))
