class_name TiltMeter
extends Control
## Horizontal bar that shows the live tilt (calibration screen): dead zone in the middle,
## marker for the current input, plus the angle in degrees.

## Current input, -1 (full left) .. +1 (full right).
var value: float = 0.0
## Current angle relative to neutral, in degrees (display only).
var degrees: float = 0.0
## Dead zone as a fraction of half the bar (0..1).
var dead_fraction: float = 0.1
var sensor_ok: bool = true


func _init() -> void:
	custom_minimum_size = Vector2(640, 96)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(p_value: float, p_degrees: float, p_dead_fraction: float, p_sensor_ok: bool) -> void:
	value = clampf(p_value, -1.0, 1.0)
	degrees = p_degrees
	dead_fraction = clampf(p_dead_fraction, 0.0, 1.0)
	sensor_ok = p_sensor_ok
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var bar: Rect2 = Rect2(0.0, h * 0.30, w, h * 0.34)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.set_corner_radius_all(int(bar.size.y * 0.5))
	draw_style_box(track, bar)
	# dead zone
	var dz: float = w * 0.5 * dead_fraction
	var dead: StyleBoxFlat = StyleBoxFlat.new()
	dead.bg_color = Color(1, 1, 1, 0.14)
	dead.set_corner_radius_all(6)
	draw_style_box(dead, Rect2(w * 0.5 - dz, bar.position.y, dz * 2.0, bar.size.y))
	# centre tick
	draw_line(Vector2(w * 0.5, bar.position.y - 8.0), Vector2(w * 0.5, bar.end.y + 8.0), Color(1, 1, 1, 0.5), 3.0)
	# filled part
	var x: float = w * 0.5 + value * w * 0.5
	var fill: Color = UIKit.C_CYAN if sensor_ok else UIKit.C_DIM
	var fill_rect: Rect2 = Rect2(minf(x, w * 0.5), bar.position.y + 4.0, absf(x - w * 0.5), bar.size.y - 8.0)
	draw_rect(fill_rect, Color(fill, 0.55))
	# marker
	draw_circle(Vector2(x, bar.position.y + bar.size.y * 0.5), bar.size.y * 0.9, UIKit.C_ACCENT)
	draw_circle(Vector2(x, bar.position.y + bar.size.y * 0.5), bar.size.y * 0.55, Color.WHITE)
	var font: Font = ThemeDB.fallback_font
	var txt: String = "%+.1f deg" % degrees if sensor_ok else "no sensor"
	draw_string(font, Vector2(0.0, h - 4.0), "LEFT", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, UIKit.C_DIM)
	draw_string(font, Vector2(0.0, h - 4.0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 22, UIKit.C_TEXT)
	draw_string(font, Vector2(0.0, h - 4.0), "RIGHT", HORIZONTAL_ALIGNMENT_RIGHT, w, 22, UIKit.C_DIM)
