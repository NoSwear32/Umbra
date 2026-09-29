class_name BackdropView
extends Control
## Everything behind the platforms, in screen space: vertical colour gradient, two parallax
## texture layers, the darker tower interior and the two side walls. Two "slots" hold the
## current and the next theme so themes cross-fade smoothly instead of popping.
##
## Layers are TextureRects in tile mode that are simply moved (no per-frame drawing work),
## which is very cheap on mobile GPUs.

const WALL_W: float = 64.0
const FAR_FACTOR: float = 0.22
const NEAR_FACTOR: float = 0.50

var tower_width: float = 640.0

var _top: Color = Color("1b2433")
var _bottom: Color = Color("2d3b3a")
var _slots: Array = []
var _slot_theme: Array = [-1, -1]
var _panel: ColorRect
var _edge_l: ColorRect
var _edge_r: ColorRect
var _fallback_l: ColorRect
var _fallback_r: ColorRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	# draw order: parallax far -> near -> tower interior -> walls
	var far_rects: Array = [_make_tex_rect(false), _make_tex_rect(false)]
	var near_rects: Array = [_make_tex_rect(false), _make_tex_rect(false)]
	_panel = ColorRect.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.color = Color(0, 0, 0, 0.3)
	add_child(_panel)
	_fallback_l = _make_fallback()
	_fallback_r = _make_fallback()
	var wall_l: Array = [_make_tex_rect(false), _make_tex_rect(false)]
	var wall_r: Array = [_make_tex_rect(true), _make_tex_rect(true)]
	_edge_l = _make_fallback()
	_edge_r = _make_fallback()
	for i in range(2):
		_slots.append({"far": far_rects[i], "near": near_rects[i], "wl": wall_l[i], "wr": wall_r[i]})


func _make_tex_rect(flip: bool) -> TextureRect:
	var t: TextureRect = TextureRect.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.flip_h = flip
	add_child(t)
	return t


func _make_fallback() -> ColorRect:
	var c: ColorRect = ColorRect.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _draw() -> void:
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([_top, _top, _bottom, _bottom]))


func _assign_slot(i: int, theme_index: int) -> void:
	if _slot_theme[i] == theme_index:
		return
	_slot_theme[i] = theme_index
	var slot: Dictionary = _slots[i]
	(slot["far"] as TextureRect).texture = ThemeManager.get_texture("bg_far", theme_index)
	(slot["near"] as TextureRect).texture = ThemeManager.get_texture("bg_near", theme_index)
	var wall: Texture2D = ThemeManager.get_texture("wall", theme_index)
	(slot["wl"] as TextureRect).texture = wall
	(slot["wr"] as TextureRect).texture = wall


func _place_tiled(rect: TextureRect, factor: float, cam_bottom: float, x: float, w: float, alpha: float) -> void:
	var tex: Texture2D = rect.texture
	if tex == null or alpha <= 0.003:
		rect.visible = false
		return
	rect.visible = true
	rect.modulate.a = alpha
	var th: float = float(tex.get_height())
	rect.size = Vector2(w, size.y + th)
	rect.position = Vector2(x, fposmod(size.y + cam_bottom * factor, th) - th)


## Called every frame. cam_bottom: altitude of the bottom of the view (interpolated).
## blend: ThemeManager.blended_at() result.
func update_view(cam_bottom: float, blend: Dictionary) -> void:
	if size.x <= 0.0 or _slots.is_empty():
		return
	var left: float = (size.x - tower_width) * 0.5
	var from_idx: int = int(blend["from"])
	var to_idx: int = int(blend["to"])
	var t: float = float(blend["t"])
	_assign_slot(0, from_idx)
	_assign_slot(1, to_idx)
	var a0: float = 1.0
	var a1: float = t
	for i in range(2):
		var a: float = a0 if i == 0 else a1
		var slot: Dictionary = _slots[i]
		_place_tiled(slot["far"], FAR_FACTOR, cam_bottom, 0.0, size.x, a * 0.9)
		_place_tiled(slot["near"], NEAR_FACTOR, cam_bottom, 0.0, size.x, a)
		_place_tiled(slot["wl"], 1.0, cam_bottom, left - WALL_W, WALL_W, a)
		_place_tiled(slot["wr"], 1.0, cam_bottom, left + tower_width, WALL_W, a)

	var accent: Color = blend["accent"]
	_panel.position = Vector2(left, 0.0)
	_panel.size = Vector2(tower_width, size.y)
	_panel.color = Color(0.0, 0.0, 0.0, float(blend["panel_alpha"]))

	var wall_a: Color = (ThemeManager.get_theme(from_idx)["wall_a"] as Color).lerp(ThemeManager.get_theme(to_idx)["wall_a"], t)
	_fallback_l.position = Vector2(left - WALL_W, 0.0)
	_fallback_l.size = Vector2(WALL_W, size.y)
	_fallback_l.color = wall_a
	_fallback_r.position = Vector2(left + tower_width, 0.0)
	_fallback_r.size = Vector2(WALL_W, size.y)
	_fallback_r.color = wall_a
	_edge_l.position = Vector2(left - 3.0, 0.0)
	_edge_l.size = Vector2(3.0, size.y)
	_edge_l.color = Color(accent, 0.55)
	_edge_r.position = Vector2(left + tower_width, 0.0)
	_edge_r.size = Vector2(3.0, size.y)
	_edge_r.color = Color(accent, 0.55)

	var top: Color = blend["bg_top"]
	var bottom: Color = blend["bg_bottom"]
	if not top.is_equal_approx(_top) or not bottom.is_equal_approx(_bottom):
		_top = top
		_bottom = bottom
		queue_redraw()
