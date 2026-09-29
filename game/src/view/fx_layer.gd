class_name FxLayer
extends Node2D
## Pooled particle effects drawn in world space (dust, sparks, confetti, rings, trails, speed
## lines). One fixed set of arrays is reused - nothing is allocated while playing.
##
## Quality follows the settings: particles Low / Medium / High and "reduced effects mode"
## (which also removes speed lines and trails). All numbers are purely cosmetic.

const MAX_PARTICLES: int = 260
const KIND_CIRCLE: int = 0
const KIND_SQUARE: int = 1
const KIND_LINE: int = 2
const KIND_RING: int = 3
const KIND_SPARK: int = 4

var _pos: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _max_life: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _grav: PackedFloat32Array = PackedFloat32Array()
var _color: PackedColorArray = PackedColorArray()
var _kind: PackedByteArray = PackedByteArray()
var _count: int = 0
var _drawn_last: bool = false


func _init() -> void:
	_pos.resize(MAX_PARTICLES)
	_vel.resize(MAX_PARTICLES)
	_life.resize(MAX_PARTICLES)
	_max_life.resize(MAX_PARTICLES)
	_size.resize(MAX_PARTICLES)
	_grav.resize(MAX_PARTICLES)
	_color.resize(MAX_PARTICLES)
	_kind.resize(MAX_PARTICLES)


func clear() -> void:
	_count = 0
	queue_redraw()


## 0.0 .. 1.0 multiplier for particle counts.
static func quality() -> float:
	if SettingsManager.get_bool("reduced_effects"):
		return 0.15
	match SettingsManager.get_int("particles"):
		0:
			return 0.35
		1:
			return 0.7
	return 1.0


static func effects_enabled() -> bool:
	return not SettingsManager.get_bool("reduced_effects")


func _spawn(p: Vector2, v: Vector2, life: float, size: float, color: Color, kind: int, gravity: float = 0.0) -> void:
	var i: int = _count
	if i >= MAX_PARTICLES:
		i = randi() % MAX_PARTICLES  # overwrite a random old one
	else:
		_count += 1
	_pos[i] = p
	_vel[i] = v
	_life[i] = life
	_max_life[i] = life
	_size[i] = size
	_grav[i] = gravity
	_color[i] = color
	_kind[i] = kind


func _process(delta: float) -> void:
	if _count == 0:
		if _drawn_last:
			_drawn_last = false
			queue_redraw()
		return
	var i: int = 0
	while i < _count:
		_life[i] -= delta
		if _life[i] <= 0.0:
			# swap-remove
			_count -= 1
			if i != _count:
				_pos[i] = _pos[_count]
				_vel[i] = _vel[_count]
				_life[i] = _life[_count]
				_max_life[i] = _max_life[_count]
				_size[i] = _size[_count]
				_grav[i] = _grav[_count]
				_color[i] = _color[_count]
				_kind[i] = _kind[_count]
			continue
		var vv: Vector2 = _vel[i]
		vv.y += _grav[i] * delta
		_vel[i] = vv
		_pos[i] = _pos[i] + vv * delta
		if _kind[i] == KIND_RING:
			_size[i] = _size[i] + 170.0 * delta
		i += 1
	_drawn_last = true
	queue_redraw()


func _draw() -> void:
	for i in range(_count):
		var t: float = _life[i] / maxf(_max_life[i], 0.001)
		var c: Color = _color[i]
		c.a = c.a * clampf(t * 1.6, 0.0, 1.0)
		match _kind[i]:
			KIND_CIRCLE:
				draw_circle(_pos[i], _size[i] * (0.35 + 0.65 * t), c)
			KIND_SQUARE:
				var s: float = _size[i]
				draw_rect(Rect2(_pos[i] - Vector2(s, s) * 0.5, Vector2(s, s)), c)
			KIND_LINE, KIND_SPARK:
				draw_line(_pos[i], _pos[i] - _vel[i] * 0.045, c, _size[i], true)
			KIND_RING:
				draw_arc(_pos[i], _size[i], 0.0, TAU, 36, c, 3.5, true)


# ---------------------------------------------------------------------------
# Effect recipes
# ---------------------------------------------------------------------------
func jump_puff(at: Vector2, ratio: float, color: Color) -> void:
	var n: int = int((4.0 + 8.0 * ratio) * quality())
	for i in range(n):
		var dir: float = randf_range(-1.0, 1.0)
		_spawn(at + Vector2(dir * 10.0, 0.0), Vector2(dir * randf_range(40.0, 150.0), randf_range(-30.0, -5.0)), randf_range(0.25, 0.45), randf_range(4.0, 8.0), Color(color, 0.75), KIND_CIRCLE, 60.0)


func land_dust(at: Vector2, strength: float, color: Color) -> void:
	var n: int = int((5.0 + 12.0 * strength) * quality())
	for i in range(n):
		var dir: float = 1.0 if i % 2 == 0 else -1.0
		_spawn(at + Vector2(randf_range(-10.0, 10.0), 0.0), Vector2(dir * randf_range(50.0, 210.0 * (0.4 + strength)), randf_range(-70.0, -15.0)), randf_range(0.28, 0.5), randf_range(4.0, 9.0), Color(color, 0.8), KIND_CIRCLE, 240.0)
	if strength > 0.55 and effects_enabled():
		_spawn(at, Vector2.ZERO, 0.32, 14.0, Color(color, 0.5), KIND_RING)


func run_dust(at: Vector2, dir: float, ratio: float, color: Color) -> void:
	if randf() > quality():
		return
	_spawn(at + Vector2(-dir * 8.0, -1.0), Vector2(-dir * randf_range(20.0, 70.0), randf_range(-45.0, -10.0)), randf_range(0.2, 0.38), randf_range(3.0, 6.0 + 3.0 * ratio), Color(color, 0.55), KIND_CIRCLE, 90.0)


func wall_sparks(at: Vector2, side: int, ratio: float, color: Color) -> void:
	var n: int = int((6.0 + 14.0 * ratio) * quality())
	for i in range(n):
		var ang: float = randf_range(-1.2, 1.2)
		var speed: float = randf_range(120.0, 340.0 + 300.0 * ratio)
		var v: Vector2 = Vector2(float(side) * cos(ang), sin(ang)) * speed
		_spawn(at, v, randf_range(0.18, 0.36), randf_range(2.0, 4.0), Color(color, 0.95), KIND_SPARK, 320.0)
	if effects_enabled():
		_spawn(at, Vector2.ZERO, 0.28, 10.0, Color(color, 0.6), KIND_RING)


func combo_burst(at: Vector2, tier: int, colors: Array) -> void:
	var n: int = int(float(14 + tier * 12) * quality())
	for i in range(n):
		var c: Color = colors[i % colors.size()]
		var ang: float = randf_range(-PI, 0.0)
		var speed: float = randf_range(140.0, 380.0 + 90.0 * float(tier))
		_spawn(at, Vector2(cos(ang), sin(ang)) * speed, randf_range(0.5, 0.95), randf_range(4.0, 8.0), c, KIND_SQUARE, 520.0)
	if effects_enabled():
		_spawn(at, Vector2.ZERO, 0.5, 20.0, Color(colors[0], 0.7), KIND_RING)
		if tier >= 2:
			_spawn(at, Vector2.ZERO, 0.7, 10.0, Color(colors[colors.size() - 1], 0.5), KIND_RING)


func trail(at: Vector2, color: Color, size: float) -> void:
	if not effects_enabled():
		return
	_spawn(at, Vector2.ZERO, 0.22, size, Color(color, 0.35), KIND_CIRCLE)


func speed_line(at: Vector2, dir: Vector2, ratio: float) -> void:
	if not effects_enabled() or randf() > quality():
		return
	_spawn(at, dir * (500.0 + 700.0 * ratio), randf_range(0.10, 0.18), 2.0, Color(1, 1, 1, 0.42), KIND_LINE)


func sparkle(at: Vector2, color: Color) -> void:
	_spawn(at, Vector2(randf_range(-30.0, 30.0), randf_range(-70.0, -20.0)), randf_range(0.4, 0.8), randf_range(2.0, 4.0), color, KIND_CIRCLE, 20.0)
