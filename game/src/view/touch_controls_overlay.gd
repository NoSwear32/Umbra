class_name TouchControlsOverlay
extends Control
## Draws the two large LEFT / RIGHT touch buttons in the lower corners (touch mode) or a slim
## tilt indicator (tilt mode), and publishes the hit rectangles to the input layer.
##
## Size, opacity, position and left/right swap come from the settings. Buttons brighten while
## they are held. Hit zones are larger than the drawn buttons (a generous margin) so quick
## presses at high speed never miss.

const BASE_SIZE: float = 190.0
const HIT_GROW: float = 48.0

var _left_btn: Rect2 = Rect2()
var _right_btn: Rect2 = Rect2()
var _bright_left: float = 0.0
var _bright_right: float = 0.0
var _tilt_mode: bool = false
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style.set_corner_radius_all(30)
	_style.set_border_width_all(4)
	_style.anti_aliasing = true
	Events.layout_changed.connect(relayout)
	Events.settings_changed.connect(_on_settings_changed)
	relayout.call_deferred()


func _on_settings_changed(_key: String) -> void:
	relayout()


## Recomputes the button rectangles from the settings and the safe area.
func relayout() -> void:
	if not is_inside_tree():
		return
	_tilt_mode = SettingsManager.is_tilt_mode()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ins: Vector4 = SafeArea.get_insets(get_viewport())
	var s: float = BASE_SIZE * SettingsManager.get_float("touch_scale")
	var inward: float = SettingsManager.get_float("touch_offset_x")
	var up: float = SettingsManager.get_float("touch_offset_y")
	var y: float = vp.y - ins.w - s - up
	var pos_a: Rect2 = Rect2(ins.x + inward, y, s, s)
	var pos_b: Rect2 = Rect2(vp.x - ins.z - s - inward, y, s, s)
	if SettingsManager.get_bool("touch_swap"):
		_left_btn = pos_b
		_right_btn = pos_a
	else:
		_left_btn = pos_a
		_right_btn = pos_b
	var full: Rect2 = Rect2(Vector2.ZERO, vp)
	var zone_l: Rect2 = _left_btn.grow(HIT_GROW).intersection(full)
	var zone_r: Rect2 = _right_btn.grow(HIT_GROW).intersection(full)
	InputManager.touch.set_zones(zone_l, zone_r)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _tilt_mode:
		queue_redraw()
		return
	var held_l: bool = InputManager.touch.is_zone_held(TouchInputController.Zone.LEFT)
	var held_r: bool = InputManager.touch.is_zone_held(TouchInputController.Zone.RIGHT)
	var new_l: float = move_toward(_bright_left, 1.0 if held_l else 0.0, delta * (14.0 if held_l else 6.0))
	var new_r: float = move_toward(_bright_right, 1.0 if held_r else 0.0, delta * (14.0 if held_r else 6.0))
	if new_l != _bright_left or new_r != _bright_right:
		_bright_left = new_l
		_bright_right = new_r
		queue_redraw()


func _draw() -> void:
	var alpha: float = SettingsManager.get_float("touch_opacity")
	if _tilt_mode:
		_draw_tilt(alpha)
		return
	_draw_pad(_left_btn, _bright_left, alpha, true)
	_draw_pad(_right_btn, _bright_right, alpha, false)


func _draw_pad(r: Rect2, bright: float, alpha: float, is_left: bool) -> void:
	# brighter while held (controls "light up" so the player sees the input registered)
	var fill_a: float = clampf(alpha * 0.20 + bright * 0.36, 0.0, 0.9)
	var border_a: float = clampf(alpha * 0.55 + bright * 0.40, 0.0, 1.0)
	_style.bg_color = Color(1, 1, 1, fill_a)
	_style.border_color = Color(1, 1, 1, border_a)
	draw_style_box(_style, r)
	var c: Vector2 = r.get_center()
	var k: float = r.size.x * 0.20
	var dirn: float = -1.0 if is_left else 1.0
	var glyph: Color = Color(1, 1, 1, clampf(alpha * 0.85 + bright * 0.4, 0.0, 1.0))
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(dirn * k * 1.05, 0.0),
		c + Vector2(-dirn * k * 0.75, -k * 1.05),
		c + Vector2(-dirn * k * 0.75, k * 1.05)]), glyph)
	var font: Font = ThemeDB.fallback_font
	var txt: String = "LEFT" if is_left else "RIGHT"
	draw_string(font, Vector2(r.position.x, r.end.y - r.size.y * 0.11), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.x * 0.115), Color(1, 1, 1, glyph.a * 0.8))


func _draw_tilt(alpha: float) -> void:
	# slim indicator at the bottom centre: shows the tilt input so players learn the range
	var vp: Vector2 = size
	var ins: Vector4 = SafeArea.get_insets(get_viewport())
	var w: float = 320.0
	var bar: Rect2 = Rect2((vp.x - w) * 0.5, vp.y - ins.w - 24.0, w, 12.0)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.10 * alpha + 0.05)
	sb.set_corner_radius_all(6)
	draw_style_box(sb, bar)
	var axis: float = SensorManager.tilt.axis
	var x: float = bar.get_center().x + axis * w * 0.5
	draw_circle(Vector2(bar.get_center().x, bar.get_center().y), 2.5, Color(1, 1, 1, 0.5))
	draw_circle(Vector2(x, bar.get_center().y), 9.0, Color(1, 1, 1, 0.55 + 0.35 * absf(axis)))
