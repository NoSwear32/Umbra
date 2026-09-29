class_name ControlDiagram
extends Control
## Small illustration of a control scheme: a landscape phone with either two touch pads
## (release to jump) or tilt arrows (tap to jump).

var mode: String = "touch"
var highlighted: bool = false


func _init(p_mode: String = "touch") -> void:
	mode = p_mode
	custom_minimum_size = Vector2(300, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var phone: Rect2 = Rect2(size.x * 0.12, size.y * 0.06, size.x * 0.76, size.y * 0.88)
	var body: StyleBoxFlat = StyleBoxFlat.new()
	body.bg_color = Color("0f1330")
	body.border_color = UIKit.C_ACCENT if highlighted else UIKit.C_DIM
	body.set_border_width_all(4)
	body.set_corner_radius_all(22)
	draw_style_box(body, phone)
	var accent: Color = UIKit.C_CYAN
	if mode == "touch":
		var pad_w: float = phone.size.x * 0.24
		var pad_h: float = phone.size.y * 0.34
		var pad: StyleBoxFlat = StyleBoxFlat.new()
		pad.bg_color = Color(accent, 0.55)
		pad.border_color = accent
		pad.set_border_width_all(3)
		pad.set_corner_radius_all(14)
		var left_pad: Rect2 = Rect2(phone.position.x + 14.0, phone.end.y - pad_h - 14.0, pad_w, pad_h)
		var right_pad: Rect2 = Rect2(phone.end.x - pad_w - 14.0, phone.end.y - pad_h - 14.0, pad_w, pad_h)
		draw_style_box(pad, left_pad)
		draw_style_box(pad, right_pad)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, left_pad.position + Vector2(0.0, pad_h * 0.62), "<", HORIZONTAL_ALIGNMENT_CENTER, pad_w, 34, Color.WHITE)
		draw_string(font, right_pad.position + Vector2(0.0, pad_h * 0.62), ">", HORIZONTAL_ALIGNMENT_CENTER, pad_w, 34, Color.WHITE)
		# a tiny tower in the middle
		var mid_x: float = phone.get_center().x
		for i in range(3):
			draw_rect(Rect2(mid_x - 34.0 + float(i) * 14.0, phone.position.y + 22.0 + float(i) * 26.0, 68.0, 8.0), UIKit.C_ACCENT)
	else:
		var c: Vector2 = phone.get_center()
		# tilt arrows around the phone
		draw_arc(c, phone.size.y * 0.62, deg_to_rad(200.0), deg_to_rad(250.0), 16, accent, 5.0, true)
		draw_arc(c, phone.size.y * 0.62, deg_to_rad(290.0), deg_to_rad(340.0), 16, accent, 5.0, true)
		var font2: Font = ThemeDB.fallback_font
		draw_string(font2, Vector2(phone.position.x, c.y + 10.0), "TILT", HORIZONTAL_ALIGNMENT_CENTER, phone.size.x, 34, Color.WHITE)
		draw_string(font2, Vector2(phone.position.x, c.y + 46.0), "+ TAP", HORIZONTAL_ALIGNMENT_CENTER, phone.size.x, 26, UIKit.C_ACCENT)
