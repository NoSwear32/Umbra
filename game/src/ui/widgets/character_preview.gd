class_name CharacterPreview
extends Control
## Animated preview of a character (used on menu cards and the game-over screen).
## Draws the current frame of the sprite sheet; falls back to a simple placeholder
## figure when the sheet is missing. `locked` draws a dark silhouette.

var def: CharacterDef = null
var anim: String = "idle"
var locked: bool = false
var flip: bool = false

var _time: float = 0.0


func _init(p_size: Vector2 = Vector2(160, 160)) -> void:
	custom_minimum_size = p_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_character(d: CharacterDef, p_anim: String = "idle", p_locked: bool = false) -> void:
	def = d
	anim = p_anim
	locked = p_locked
	_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if def == null or not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if def == null:
		return
	var tint: Color = Color(0.06, 0.07, 0.12, 0.92) if locked else Color(1, 1, 1, 1)
	var tex: Texture2D = def.get_texture()
	if tex != null:
		var fps: float = def.anim_fps(anim)
		var count: int = def.frame_count(anim)
		var frame: int = int(_time * fps) % count
		if not def.anim_loops(anim):
			frame = mini(int(_time * fps), count - 1)
		var src: Rect2 = def.frame_rect(anim, frame)
		var k: float = minf(size.x / float(def.frame_size.x), size.y / float(def.frame_size.y))
		var dst_size: Vector2 = Vector2(float(def.frame_size.x), float(def.frame_size.y)) * k
		var dst: Rect2 = Rect2((size - dst_size) * 0.5, dst_size)
		if flip:
			dst = Rect2(dst.position + Vector2(dst.size.x, 0.0), Vector2(-dst.size.x, dst.size.y))
		draw_texture_rect_region(tex, dst, src, tint)
	else:
		_draw_placeholder(tint)


## Simple stand-in figure (used when a sprite sheet is not available).
func _draw_placeholder(tint: Color) -> void:
	var c: Color = def.ui_color
	if locked:
		c = tint
	var cx: float = size.x * 0.5
	var base: float = size.y * 0.92
	var bob: float = sin(_time * 4.0) * 2.0
	draw_circle(Vector2(cx, base - size.y * 0.30 + bob), size.y * 0.24, c)
	draw_circle(Vector2(cx, base - size.y * 0.66 + bob), size.y * 0.20, c.lightened(0.15))
	draw_circle(Vector2(cx - size.y * 0.07, base - size.y * 0.68 + bob), size.y * 0.035, Color(0.1, 0.1, 0.2))
	draw_circle(Vector2(cx + size.y * 0.07, base - size.y * 0.68 + bob), size.y * 0.035, Color(0.1, 0.1, 0.2))
