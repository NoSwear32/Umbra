class_name PlatformView
extends Node2D
## Draws one platform. The node origin is the top-left corner of the walkable surface; the body
## hangs downwards (screen y grows downwards, altitude grows upwards).
##
## Platforms are drawn ONCE per recycle (the engine caches the draw commands), so the elaborate
## per-theme decoration costs nothing while the tower scrolls. Readability rules: the top
## surface is always the brightest element and has a dark outline against any background.

const THICK: float = 26.0
const LANDMARK_THICK: float = 34.0
const GROUND_THICK: float = 1100.0

const STYLE_STONE: int = 0
const STYLE_GIRDER: int = 1
const STYLE_NEON: int = 2
const STYLE_VINE: int = 3
const STYLE_CRYSTAL: int = 4
const STYLE_BRASS: int = 5
const STYLE_STORM: int = 6
const STYLE_GLASS: int = 7
const STYLE_MARBLE: int = 8
const STYLE_STAR: int = 9
const STYLE_GOLD: int = 10

var data: PlatformData = null
var theme_def: Dictionary = {}

var _w: float = 0.0
var _h: float = THICK


func setup(p: PlatformData, theme: Dictionary) -> void:
	data = p
	theme_def = theme
	_w = p.width
	match p.kind:
		SimConst.KIND_LANDMARK:
			_h = LANDMARK_THICK
		SimConst.KIND_GROUND:
			_h = GROUND_THICK
		_:
			_h = THICK
	position = Vector2(p.left(), -p.y)
	visible = true
	queue_redraw()


func release() -> void:
	data = null
	visible = false


func _draw() -> void:
	if data == null or theme_def.is_empty():
		return
	var w: float = _w
	var h: float = _h
	var body: Color = theme_def["plat_body"]
	var top: Color = theme_def["plat_top"]
	var edge: Color = theme_def["plat_edge"]
	var deco: Color = theme_def["plat_deco"]
	var accent: Color = theme_def["accent"]
	var style: int = int(theme_def["style"])
	var rng: SimRng = SimRng.new(data.variant + data.floor_index * 7919)
	var detail_h: float = minf(h, 64.0)

	# rounded body with outline and soft shadow
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = body
	sb.border_color = edge
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(7)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	draw_style_box(sb, Rect2(0.0, 0.0, w, h))
	# vertical shading (lighter top, darker bottom)
	var shade_h: float = minf(detail_h, h) - 6.0
	draw_polygon(
		PackedVector2Array([Vector2(3, 3), Vector2(w - 3, 3), Vector2(w - 3, 3 + shade_h), Vector2(3, 3 + shade_h)]),
		PackedColorArray([body.lightened(0.22), body.lightened(0.22), body.darkened(0.30), body.darkened(0.30)]))

	match style:
		STYLE_STONE:
			_detail_stone(w, detail_h, rng, edge, deco)
		STYLE_GIRDER:
			_detail_girder(w, detail_h, rng, edge, deco)
		STYLE_NEON:
			_detail_neon(w, detail_h, accent, deco)
		STYLE_VINE:
			_detail_vine(w, detail_h, rng, edge, deco)
		STYLE_CRYSTAL:
			_detail_crystal(w, detail_h, rng, body, deco)
		STYLE_BRASS:
			_detail_brass(w, detail_h, rng, edge, deco)
		STYLE_STORM:
			_detail_storm(w, detail_h, rng, edge, deco)
		STYLE_GLASS:
			_detail_glass(w, detail_h, edge, deco)
		STYLE_MARBLE:
			_detail_marble(w, detail_h, rng, edge, deco)
		STYLE_STAR:
			_detail_star(w, detail_h, rng, accent, deco)
		STYLE_GOLD:
			_detail_gold(w, detail_h, edge, deco)

	# bright walkable surface (always the most readable part)
	draw_rect(Rect2(3.0, 3.0, w - 6.0, 6.0), top)
	draw_rect(Rect2(3.0, 3.0, w - 6.0, 2.0), top.lightened(0.55))
	draw_line(Vector2(3.0, 9.5), Vector2(w - 3.0, 9.5), Color(edge, 0.55), 2.0)

	if data.kind == SimConst.KIND_LANDMARK:
		_draw_landmark(w, h, accent, edge)
	elif data.kind == SimConst.KIND_GROUND:
		_draw_ground(w, accent)


# ---------------------------------------------------------------------------
# Special platforms
# ---------------------------------------------------------------------------
func _draw_landmark(w: float, h: float, accent: Color, edge: Color) -> void:
	# lamps at both ends and the floor number in the middle
	for x in [14.0, w - 14.0]:
		draw_circle(Vector2(x, h * 0.55), 7.0, Color(accent, 0.35))
		draw_circle(Vector2(x, h * 0.55), 4.0, accent)
	var font: Font = ThemeDB.fallback_font
	var txt: String = str(data.floor_index)
	draw_string_outline(font, Vector2(0.0, h - 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 22, 5, Color(edge, 0.9))
	draw_string(font, Vector2(0.0, h - 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color.WHITE)


func _draw_ground(w: float, accent: Color) -> void:
	# a heavy foundation slab with a glowing seam
	draw_rect(Rect2(0.0, 40.0, w, 6.0), Color(accent, 0.6))
	for i in range(int(w / 64.0) + 1):
		draw_line(Vector2(float(i) * 64.0, 46.0), Vector2(float(i) * 64.0, 240.0), Color(0, 0, 0, 0.25), 3.0)


# ---------------------------------------------------------------------------
# Per-theme decoration (details live inside the body, y in [3 .. h])
# ---------------------------------------------------------------------------
func _detail_stone(w: float, h: float, rng: SimRng, edge: Color, deco: Color) -> void:
	var mortar: Color = Color(edge, 0.40)
	draw_line(Vector2(5, h * 0.58), Vector2(w - 5, h * 0.58), mortar, 2.0)
	var x: float = 22.0 + rng.range_f(0.0, 26.0)
	while x < w - 16.0:
		draw_line(Vector2(x, 10.0), Vector2(x, h * 0.58), mortar, 2.0)
		x += 44.0 + rng.range_f(0.0, 26.0)
	x = 40.0 + rng.range_f(0.0, 26.0)
	while x < w - 16.0:
		draw_line(Vector2(x, h * 0.58), Vector2(x, h - 4.0), mortar, 2.0)
		x += 44.0 + rng.range_f(0.0, 26.0)
	for i in range(int(w / 60.0) + 1):
		draw_circle(Vector2(rng.range_f(8.0, w - 8.0), 9.0), rng.range_f(2.5, 5.0), Color(deco, 0.95))


func _detail_girder(w: float, h: float, rng: SimRng, edge: Color, deco: Color) -> void:
	var brace: Color = Color(edge, 0.45)
	var x: float = 14.0
	while x < w - 30.0:
		draw_line(Vector2(x, 10.0), Vector2(x + 28.0, h - 4.0), brace, 2.0)
		draw_line(Vector2(x + 28.0, 10.0), Vector2(x, h - 4.0), brace, 2.0)
		x += 28.0
	x = 8.0
	while x < w - 6.0:
		draw_circle(Vector2(x, h * 0.5 + 3.0), 2.6, Color(deco, 0.9))
		x += 28.0
	if rng.next_float() < 0.6:
		draw_rect(Rect2(rng.range_f(20.0, maxf(w - 60.0, 21.0)), h - 9.0, 34.0, 5.0), Color(deco, 0.8))


func _detail_neon(w: float, h: float, accent: Color, deco: Color) -> void:
	draw_rect(Rect2(3.0, h - 9.0, w - 6.0, 3.0), Color(accent, 0.35))
	draw_rect(Rect2(3.0, h - 8.0, w - 6.0, 1.5), accent)
	var x: float = 12.0
	while x < w - 20.0:
		draw_rect(Rect2(x, 13.0, 14.0, 4.0), Color(deco, 0.85))
		x += 30.0
	draw_rect(Rect2(0.0, 2.0, w, 3.0), Color(accent, 0.35))


func _detail_vine(w: float, h: float, rng: SimRng, edge: Color, deco: Color) -> void:
	var leaf: Color = Color("4cae4f")
	var x: float = 10.0
	while x < w - 10.0:
		var s: float = rng.range_f(5.0, 9.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, 9.0), Vector2(x + s, 2.0), Vector2(x + s * 2.0, 9.0)]), leaf)
		x += rng.range_f(18.0, 34.0)
	for i in range(int(w / 90.0) + 1):
		var vx: float = rng.range_f(10.0, w - 10.0)
		draw_line(Vector2(vx, h - 3.0), Vector2(vx + rng.range_f(-4.0, 4.0), h + 10.0), Color(leaf, 0.9), 2.5)
		draw_circle(Vector2(vx, h + 10.0), 3.0, deco)
	draw_line(Vector2(6, h * 0.6), Vector2(w - 6, h * 0.6), Color(edge, 0.3), 2.0)


func _detail_crystal(w: float, h: float, rng: SimRng, body: Color, deco: Color) -> void:
	var x: float = 3.0
	var up: bool = true
	while x < w - 8.0:
		var seg: float = rng.range_f(22.0, 40.0)
		var x2: float = minf(x + seg, w - 3.0)
		var pts: PackedVector2Array
		if up:
			pts = PackedVector2Array([Vector2(x, h - 3.0), Vector2((x + x2) * 0.5, 10.0), Vector2(x2, h - 3.0)])
		else:
			pts = PackedVector2Array([Vector2(x, 10.0), Vector2(x2, 10.0), Vector2((x + x2) * 0.5, h - 3.0)])
		draw_colored_polygon(pts, Color(body.lightened(0.25 if up else 0.05), 0.65))
		x = x2
		up = not up
	for i in range(int(w / 70.0) + 1):
		var sx: float = rng.range_f(10.0, w - 10.0)
		draw_circle(Vector2(sx, rng.range_f(12.0, h - 6.0)), 1.8, Color(deco, 0.95))


func _detail_brass(w: float, h: float, _rng: SimRng, edge: Color, deco: Color) -> void:
	var seam: Color = Color(edge, 0.4)
	var x: float = 46.0
	while x < w - 20.0:
		draw_line(Vector2(x, 10.0), Vector2(x, h - 4.0), seam, 2.0)
		x += 46.0
	x = 10.0
	while x < w - 6.0:
		draw_circle(Vector2(x, 14.0), 2.4, Color(deco, 0.9))
		draw_circle(Vector2(x, h - 8.0), 2.4, Color(deco, 0.9))
		x += 23.0
	# gear teeth along the bottom edge
	var tx: float = 6.0
	while tx < w - 10.0:
		draw_rect(Rect2(tx, h - 3.0, 6.0, 5.0), Color(edge, 0.85))
		tx += 12.0


func _detail_storm(w: float, h: float, rng: SimRng, edge: Color, deco: Color) -> void:
	var x: float = 10.0
	var up: bool = true
	var pts: PackedVector2Array = PackedVector2Array()
	while x < w - 6.0:
		pts.append(Vector2(x, 13.0 if up else h - 6.0))
		x += rng.range_f(10.0, 20.0)
		up = not up
	if pts.size() >= 2:
		draw_polyline(pts, Color(deco, 0.9), 2.5, true)
	var rx: float = 6.0
	while rx < w:
		draw_circle(Vector2(rx, h - 5.0), 1.8, Color(edge, 0.8))
		rx += 34.0


func _detail_glass(w: float, h: float, _edge: Color, deco: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.15, h - 4.0), Vector2(w * 0.27, 10.0), Vector2(w * 0.36, 10.0), Vector2(w * 0.24, h - 4.0)]), Color(1, 1, 1, 0.22))
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.55, h - 4.0), Vector2(w * 0.63, 10.0), Vector2(w * 0.68, 10.0), Vector2(w * 0.60, h - 4.0)]), Color(1, 1, 1, 0.16))
	draw_rect(Rect2(3.0, h - 8.0, w - 6.0, 2.0), Color(deco, 0.7))


func _detail_marble(w: float, h: float, rng: SimRng, edge: Color, deco: Color) -> void:
	for i in range(int(w / 50.0) + 1):
		var vx: float = rng.range_f(10.0, w - 10.0)
		draw_line(Vector2(vx, 11.0), Vector2(vx + rng.range_f(-14.0, 14.0), h - 4.0), Color(edge, 0.22), 1.6)
	draw_rect(Rect2(3.0, h - 7.0, w - 6.0, 2.0), Color(deco, 0.55))
	draw_rect(Rect2(0.0, 0.0, 6.0, h), Color(edge, 0.35))
	draw_rect(Rect2(w - 6.0, 0.0, 6.0, h), Color(edge, 0.35))


func _detail_star(w: float, h: float, rng: SimRng, accent: Color, deco: Color) -> void:
	for i in range(int(w / 26.0) + 1):
		var sx: float = rng.range_f(8.0, w - 8.0)
		var sy: float = rng.range_f(12.0, h - 5.0)
		draw_circle(Vector2(sx, sy), rng.range_f(1.0, 2.2), Color(deco, rng.range_f(0.55, 1.0)))
	draw_rect(Rect2(3.0, h - 7.0, w - 6.0, 3.0), Color(accent, 0.35))


func _detail_gold(w: float, h: float, _edge: Color, deco: Color) -> void:
	draw_rect(Rect2(3.0, h * 0.5, w - 6.0, 2.0), Color(deco, 0.55))
	var x: float = 20.0
	while x < w - 20.0:
		draw_circle(Vector2(x, h * 0.5 + 1.0), 3.0, Color(deco, 0.8))
		x += 40.0
	draw_circle(Vector2(9.0, h * 0.5), 5.0, Color(deco, 0.9))
	draw_circle(Vector2(w - 9.0, h * 0.5), 5.0, Color(deco, 0.9))
