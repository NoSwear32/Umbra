class_name PlatformData
extends RefCounted
## One platform (= one floor) of the tower. Pure data, no node.

## Unique floor number. Floor 0 is the ground.
var floor_index: int = 0
## Horizontal centre in tower coordinates (0 .. tower_width).
var x: float = 0.0
## Altitude (upwards positive) of the walkable top surface.
var y: float = 0.0
var width: float = 0.0
var kind: int = SimConst.KIND_NORMAL
## Random 16-bit value drawn from the tower seed; views use it for decoration.
var variant: int = 0


func _init(p_floor: int = 0, p_x: float = 0.0, p_y: float = 0.0, p_width: float = 0.0, p_kind: int = 0, p_variant: int = 0) -> void:
	floor_index = p_floor
	x = p_x
	y = p_y
	width = p_width
	kind = p_kind
	variant = p_variant


func left() -> float:
	return x - width * 0.5


func right() -> float:
	return x + width * 0.5
