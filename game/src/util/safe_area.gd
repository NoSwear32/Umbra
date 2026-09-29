class_name SafeArea
extends RefCounted
## Converts the OS "safe area" (notches, punch-hole cameras, rounded corners, gesture bars)
## into insets in LOGICAL viewport units, so HUD and menus never sit under a cutout.
##
## The game window uses "keep height" scaling: the viewport is always 720 units tall and its
## width follows the device aspect ratio (16:9 ... 21:9 and tablets).

## Every UI gets at least this margin, cutout or not.
const MIN_MARGIN: float = 22.0


## Insets as Vector4(left, top, right, bottom) in viewport units (already >= MIN_MARGIN).
static func get_insets(viewport: Viewport) -> Vector4:
	return compute_insets(DisplayServer.window_get_size(), DisplayServer.window_get_position(), DisplayServer.get_display_safe_area(), viewport.get_visible_rect().size)


## Pure computation (unit tested): window/safe rectangles are in device pixels, `vp_size` is the
## logical viewport. Returns Vector4(left, top, right, bottom) in logical units, >= MIN_MARGIN.
static func compute_insets(win_size: Vector2i, win_pos: Vector2i, safe: Rect2i, vp_size: Vector2) -> Vector4:
	var left: float = 0.0
	var top: float = 0.0
	var right: float = 0.0
	var bottom: float = 0.0
	if win_size.x > 0 and win_size.y > 0 and vp_size.x > 0.0:
		var sx: float = vp_size.x / float(win_size.x)
		var sy: float = vp_size.y / float(win_size.y)
		if safe.size.x > 0 and safe.size.y > 0:
			left = maxf(0.0, float(safe.position.x - win_pos.x)) * sx
			top = maxf(0.0, float(safe.position.y - win_pos.y)) * sy
			right = maxf(0.0, float((win_pos.x + win_size.x) - (safe.position.x + safe.size.x))) * sx
			bottom = maxf(0.0, float((win_pos.y + win_size.y) - (safe.position.y + safe.size.y))) * sy
	return Vector4(maxf(left, MIN_MARGIN), maxf(top, MIN_MARGIN), maxf(right, MIN_MARGIN), maxf(bottom, MIN_MARGIN))


## Rectangle of the viewport inside the safe area.
static func get_rect(viewport: Viewport) -> Rect2:
	var vp: Vector2 = viewport.get_visible_rect().size
	var ins: Vector4 = get_insets(viewport)
	return Rect2(ins.x, ins.y, vp.x - ins.x - ins.z, vp.y - ins.y - ins.w)


## Applies the insets as margins of a MarginContainer.
static func apply_to(margin: MarginContainer, viewport: Viewport) -> void:
	var ins: Vector4 = get_insets(viewport)
	margin.add_theme_constant_override("margin_left", int(ins.x))
	margin.add_theme_constant_override("margin_top", int(ins.y))
	margin.add_theme_constant_override("margin_right", int(ins.z))
	margin.add_theme_constant_override("margin_bottom", int(ins.w))
