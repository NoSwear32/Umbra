class_name PlayerView
extends Node2D
## Visual representation of the player. It only READS the simulation (interpolating between the
## last two fixed ticks) and never influences it, so animation can never delay or change the
## physics response.
##
## Animation states (rows of the sprite sheet): idle, run, accel, jump_up, fall, fast_jump,
## wall, land, near_fall, gameover. Squash & stretch runs on a spring; a scarf chain trails
## behind and makes speed and direction readable at a glance.

const SCARF_POINTS: int = 10
const SCARF_SEGMENT: float = 8.5
## Distance above the bottom of the screen that triggers the "near fall" panic pose.
const NEAR_FALL_DISTANCE: float = 120.0

var run: RunManager = null
var def: CharacterDef = null
var tuning: GameTuning = null

var sprite: Sprite2D

var _anim: String = "idle"
var _anim_time: float = 0.0
var _override: String = ""
var _override_left: float = 0.0
var _squash: Vector2 = Vector2.ONE
var _squash_vel: Vector2 = Vector2.ZERO
var _lean: float = 0.0
var _facing: int = 1
var _dead: bool = false
var _dead_time: float = 0.0
var _time: float = 0.0
var _combo_level: int = 0
var _scarf: PackedVector2Array = PackedVector2Array()
var _scarf_old: PackedVector2Array = PackedVector2Array()
var _scarf_ready: bool = false
var _rendered_position: Vector2 = Vector2.ZERO


func _init() -> void:
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.region_enabled = true
	add_child(sprite)
	_scarf.resize(SCARF_POINTS)
	_scarf_old.resize(SCARF_POINTS)


func bind(r: RunManager, character: CharacterDef, t: GameTuning) -> void:
	run = r
	tuning = t
	set_character(character)
	_dead = false
	_dead_time = 0.0
	_override = ""
	_override_left = 0.0
	_squash = Vector2.ONE
	_squash_vel = Vector2.ZERO
	_scarf_ready = false
	_combo_level = 0
	rotation = 0.0
	visible = true
	if run != null:
		position = Vector2(run.player.x, -run.player.y)
		_rendered_position = position


func set_character(character: CharacterDef) -> void:
	def = character
	if def == null:
		return
	sprite.texture = def.get_texture()
	sprite.offset = -def.anchor
	sprite.region_rect = def.frame_rect("idle", 0)
	queue_redraw()


func rendered_position() -> Vector2:
	return _rendered_position


func facing() -> int:
	return _facing


# ---------------------------------------------------------------------------
# Events from the run (called by GameScene)
# ---------------------------------------------------------------------------
func on_jumped(speed_ratio: float) -> void:
	_squash_vel += Vector2(-1.6, 3.2 + 2.2 * speed_ratio)


func on_landed(impact_speed: float) -> void:
	var k: float = clampf(absf(impact_speed) / 1300.0, 0.0, 1.0)
	_squash_vel += Vector2(6.0 * k + 1.0, -9.0 * k - 1.5)
	if k > 0.25:
		_override = "land"
		_override_left = 0.13 + 0.06 * k
		_anim_time = 0.0


func on_wall(_direction: int, speed_ratio: float) -> void:
	_squash_vel += Vector2(-7.5 * speed_ratio - 2.0, 4.0 * speed_ratio)
	_override = "wall"
	_override_left = 0.16
	_anim_time = 0.0


func on_died() -> void:
	_dead = true
	_dead_time = 0.0
	_anim_time = 0.0


func set_combo_level(level: int) -> void:
	_combo_level = level


# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------
func update_view(alpha: float, delta: float, axis: float) -> void:
	if run == null or def == null:
		return
	_time += delta
	var p: PlayerController = run.player
	var px: float = lerpf(p.prev_x, p.x, alpha)
	var py: float = lerpf(p.prev_y, p.y, alpha)
	var pos: Vector2 = Vector2(px, -py)
	if _dead:
		_dead_time += delta
		# a small tumble downwards after the fatal fall
		pos.y += 260.0 * _dead_time * _dead_time
		rotation = 5.0 * _dead_time * float(_facing)
	else:
		rotation = 0.0
	position = pos
	_rendered_position = pos
	_facing = p.facing

	var ratio: float = p.speed_ratio()
	_choose_animation(p, ratio, axis)
	_advance_animation(delta, ratio)
	_update_squash(p, delta, ratio)
	_update_scarf(delta, ratio, Vector2(p.vx, -p.vy))
	queue_redraw()


func _choose_animation(p: PlayerController, ratio: float, axis: float) -> void:
	var wanted: String = "idle"
	var near_bottom: bool = (p.y - run.scroll.cam_bottom) < NEAR_FALL_DISTANCE and run.scroll.active
	if _dead:
		wanted = "gameover"
	elif _override_left > 0.0:
		wanted = _override
	elif not p.grounded:
		if near_bottom and p.vy <= 0.0:
			wanted = "near_fall"
		elif p.vy > 0.0:
			wanted = "fast_jump" if (ratio > 0.55 or p.vy > 1150.0) else "jump_up"
		else:
			wanted = "fall"
	else:
		if near_bottom:
			wanted = "near_fall"
		elif absf(p.vx) < 25.0 and absf(axis) < 0.05:
			wanted = "idle"
		elif ratio < 0.30 and absf(axis) > 0.05:
			wanted = "accel"
		else:
			wanted = "run"
	if wanted != _anim:
		# run <-> accel keeps the running phase so legs never "reset"
		var keep: bool = (wanted == "run" and _anim == "accel") or (wanted == "accel" and _anim == "run")
		_anim = wanted
		if not keep:
			_anim_time = 0.0


func _advance_animation(delta: float, ratio: float) -> void:
	if _override_left > 0.0:
		_override_left -= delta
	var speed_scale: float = 1.0
	if _anim == "run":
		speed_scale = 0.55 + 1.15 * ratio
	_anim_time += delta * speed_scale
	var frames: int = def.frame_count(_anim)
	var frame: int = int(_anim_time * def.anim_fps(_anim))
	if def.anim_loops(_anim):
		frame = frame % frames
	else:
		frame = mini(frame, frames - 1)
	sprite.region_rect = def.frame_rect(_anim, frame)


func _update_squash(p: PlayerController, delta: float, _ratio: float) -> void:
	var target: Vector2 = Vector2.ONE
	if not p.grounded:
		var s: float = minf(absf(p.vy) / 3300.0, 0.2)
		target = Vector2(1.0 - s * 0.55, 1.0 + s)
	# critically-damped-ish spring: snappy with a little wobble
	var accel: Vector2 = (target - _squash) * 240.0 - _squash_vel * 15.0
	_squash_vel += accel * delta
	_squash += _squash_vel * delta
	_squash.x = clampf(_squash.x, 0.55, 1.5)
	_squash.y = clampf(_squash.y, 0.55, 1.6)
	var lean_target: float = clampf(p.vx / tuning.max_speed, -1.0, 1.0) * 0.20
	if not p.grounded:
		lean_target = clampf(p.vx / tuning.max_speed, -1.0, 1.0) * 0.12
	_lean += (lean_target - _lean) * (1.0 - exp(-delta * 14.0))
	var base: float = def.sprite_scale
	sprite.scale = Vector2(base * _squash.x * float(_facing), base * _squash.y)
	sprite.rotation = 0.0 if _dead else _lean


func _update_scarf(delta: float, ratio: float, _vel: Vector2) -> void:
	var anchor: Vector2 = position + Vector2(-float(_facing) * 4.0, -tuning.player_height * 0.68)
	if not _scarf_ready:
		for i in range(SCARF_POINTS):
			_scarf[i] = anchor + Vector2(-float(_facing) * float(i) * SCARF_SEGMENT * 0.6, 0.0)
			_scarf_old[i] = _scarf[i]
		_scarf_ready = true
	var d: float = clampf(delta, 0.0, 0.05)
	_scarf[0] = anchor
	_scarf_old[0] = anchor
	for i in range(1, SCARF_POINTS):
		var cur: Vector2 = _scarf[i]
		var v: Vector2 = (cur - _scarf_old[i]) * 0.90
		_scarf_old[i] = cur
		var flutter: Vector2 = Vector2(0.0, sin(_time * 15.0 + float(i) * 0.9) * 26.0 * ratio)
		cur += v + (Vector2(0.0, 620.0) + flutter) * d * d
		_scarf[i] = cur
	for pass_i in range(2):
		for i in range(1, SCARF_POINTS):
			var diff: Vector2 = _scarf[i] - _scarf[i - 1]
			var dist: float = diff.length()
			if dist > SCARF_SEGMENT:
				_scarf[i] = _scarf[i - 1] + diff / dist * SCARF_SEGMENT


# ---------------------------------------------------------------------------
# Drawing (scarf + aura behind the sprite; placeholder figure when there is no sheet)
# ---------------------------------------------------------------------------
func _draw() -> void:
	if def == null:
		return
	# combo aura
	if _combo_level > 0:
		var aura: Color = def.scarf_color2 if _combo_level < 3 else Color("fff2a6")
		var pulse: float = 1.0 + 0.08 * sin(_time * 9.0)
		for k in range(_combo_level):
			draw_arc(Vector2(0.0, -31.0), (40.0 + float(k) * 9.0) * pulse, 0.0, TAU, 40, Color(aura, 0.30 - 0.06 * float(k)), 3.0, true)
	# scarf
	if _scarf_ready:
		for i in range(1, SCARF_POINTS):
			var a: Vector2 = _scarf[i - 1] - position
			var b: Vector2 = _scarf[i] - position
			var w: float = lerpf(9.0, 3.0, float(i) / float(SCARF_POINTS - 1))
			var c: Color = def.scarf_color if (i % 2 == 0) else def.scarf_color2
			draw_line(a, b, Color(0, 0, 0, 0.35), w + 3.0, true)
			draw_line(a, b, c, w, true)
	# placeholder when the sprite sheet is not available
	if def.get_texture() == null:
		_draw_placeholder()


func _draw_placeholder() -> void:
	var s: Vector2 = Vector2(_squash.x, _squash.y)
	var body: Color = def.ui_color
	var f: float = float(_facing)
	draw_set_transform(Vector2.ZERO, 0.0, s)
	draw_circle(Vector2(0.0, -20.0), 17.0, body.darkened(0.25))
	draw_circle(Vector2(0.0, -20.0), 15.0, body)
	draw_circle(Vector2(0.0, -44.0), 15.0, body.lightened(0.1))
	draw_circle(Vector2(5.0 * f, -46.0), 3.0, Color.WHITE)
	draw_circle(Vector2(6.0 * f, -46.0), 1.6, Color(0.1, 0.1, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
