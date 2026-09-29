class_name PlayerController
extends RefCounted
## Deterministic kinematic player (no physics engine involved).
##
## Coordinates: x grows to the right (0 .. tower_width), y is the ALTITUDE of the
## feet and grows upwards. All motion is integrated with a fixed 1/120 s step and
## only uses + - * / and sqrt, so replays are bit-identical on every device.
##
## Movement model
##  * Horizontal speed is built up progressively (acceleration falls off towards the
##    top speed), direction changes go through a strong-but-finite brake, and landing
##    never removes momentum: the only thing that slows you down is friction while
##    no direction is held.
##  * A jump is always intentional. Its power depends on the horizontal speed at the
##    moment of take-off (see jump_velocity()).
##  * Platforms are one-way: they are ignored while rising and only catch the feet
##    when they cross the top surface while moving down (swept test => no tunnelling).
##  * Side walls rebound the player and keep most of the momentum.
##
## Events of the last step are appended to `events` as small arrays:
##   [EV_JUMP, jump_velocity, speed_ratio]   [EV_LAND, PlatformData, impact_speed]
##   [EV_WALL, direction(+1 = pushed right), impact_speed]   [EV_LEFT_GROUND, floor_index]

var tuning: GameTuning
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var grounded: bool = true
var support: PlatformData = null
var takeoff_floor: int = 0
var coyote: int = 0
var jump_buf: int = 0
## Positions at the start of the last step (used by views to interpolate).
var prev_x: float = 0.0
var prev_y: float = 0.0
var facing: int = 1
var events: Array = []

var _coyote_ticks: int = 0
var _buffer_ticks: int = 0


func _init(p_tuning: GameTuning) -> void:
	tuning = p_tuning
	x = tuning.tower_width * 0.5
	y = 0.0
	prev_x = x
	prev_y = y
	_coyote_ticks = tuning.coyote_ticks()
	_buffer_ticks = tuning.buffer_ticks()


## Horizontal speed relative to the maximum (0 .. 1).
func speed_ratio() -> float:
	return minf(absf(vx) / tuning.max_speed, 1.0)


## Jump velocity for the current horizontal speed. Carefully tuned curve:
## multiplier = min + (max - min) * f(r), f(r) = r + (r*r - r) * bias, r = |vx| / max_speed.
func jump_velocity() -> float:
	var t: GameTuning = tuning
	var r: float = absf(vx) / t.max_speed
	if r > 1.0:
		r = 1.0
	var f: float = r + (r * r - r) * t.jump_curve_bias
	var m: float = t.jump_min_multiplier + (t.jump_max_multiplier - t.jump_min_multiplier) * f
	return t.base_jump_velocity * m


## Places the player standing on `platform` (used at run start and by debug tools).
func place_on(platform: PlatformData, px: float) -> void:
	x = px
	y = platform.y
	vx = 0.0
	vy = 0.0
	grounded = true
	support = platform
	takeoff_floor = platform.floor_index
	coyote = 0
	jump_buf = 0
	prev_x = x
	prev_y = y


func _horizontal(axis: float) -> float:
	var t: GameTuning = tuning
	var v: float = vx
	var acc0: float = 0.0
	var brake: float = 0.0
	var fric: float = 0.0
	if grounded:
		acc0 = t.accel_ground
		brake = t.brake_decel
		fric = t.ground_friction
	else:
		acc0 = t.air_accel
		brake = t.air_brake
		fric = t.air_friction
	if axis != 0.0:
		var sa: float = -1.0
		if axis > 0.0:
			sa = 1.0
		var target_speed: float = absf(axis * t.max_speed)
		if v == 0.0 or ((v > 0.0) == (axis > 0.0)):
			var av: float = absf(v)
			if av < target_speed:
				var ratio: float = av / t.max_speed
				var acc: float = acc0 * (1.0 + (t.accel_at_max_ratio - 1.0) * ratio)
				var dv: float = acc * SimConst.DT
				var gap: float = target_speed - av
				if dv > gap:
					dv = gap
				v = v + sa * dv
			elif av > target_speed:
				var dv2: float = fric * SimConst.DT
				var gap2: float = av - target_speed
				if dv2 > gap2:
					dv2 = gap2
				v = v - sa * dv2
		else:
			v = v + sa * brake * SimConst.DT
	else:
		var av3: float = absf(v)
		var dv3: float = fric * SimConst.DT
		if dv3 >= av3:
			v = 0.0
		elif v > 0.0:
			v = v - dv3
		else:
			v = v + dv3
	return v


## Advances the player by one tick.
## axis: -1 .. 1 (left .. right), jump: true on the tick a jump is requested.
func step(axis: float, jump: bool, tower: PlatformGenerator) -> void:
	var t: GameTuning = tuning
	events.clear()
	prev_x = x
	prev_y = y

	if jump:
		jump_buf = _buffer_ticks

	# ---- jump: uses the speed built up BEFORE this tick's input, so releasing
	# the direction (touch mode) never costs momentum.
	if jump_buf > 0 and (grounded or coyote > 0):
		var jv: float = jump_velocity()
		if grounded and support != null:
			takeoff_floor = support.floor_index
		vy = jv
		grounded = false
		support = null
		coyote = 0
		jump_buf = 0
		events.append([SimConst.EV_JUMP, jv, absf(vx) / t.max_speed])

	# ---- horizontal motion
	var vx_old: float = vx
	vx = _horizontal(axis)
	x = x + (vx_old + vx) * 0.5 * SimConst.DT
	if vx > 0.0:
		facing = 1
	elif vx < 0.0:
		facing = -1

	# ---- side walls
	var left_lim: float = t.player_half_width
	var right_lim: float = t.tower_width - t.player_half_width
	if x < left_lim:
		x = left_lim
		if vx < 0.0:
			_rebound(1)
	elif x > right_lim:
		x = right_lim
		if vx > 0.0:
			_rebound(-1)

	# ---- support check (walking off ledges)
	var fhw: float = t.foot_half_width
	if grounded:
		var sp: PlatformData = support
		if not (x + fhw > sp.left() and x - fhw < sp.right()):
			grounded = false
			takeoff_floor = sp.floor_index
			support = null
			coyote = _coyote_ticks
			vy = 0.0
			events.append([SimConst.EV_LEFT_GROUND, sp.floor_index])

	# ---- vertical motion + one-way landing
	if not grounded:
		var vy_old: float = vy
		var vy_new: float = vy_old - t.gravity * SimConst.DT
		if vy_new < -t.max_fall_speed:
			vy_new = -t.max_fall_speed
		var y_new: float = y + (vy_old + vy_new) * 0.5 * SimConst.DT
		var landed: PlatformData = null
		if y_new <= y:
			var plats: Array = tower.platforms
			var i: int = tower.index_at_or_below(y)
			var lo_i: int = i - 3
			if lo_i < 0:
				lo_i = 0
			var hi_i: int = i + 3
			if hi_i > plats.size() - 1:
				hi_i = plats.size() - 1
			var j: int = lo_i
			while j <= hi_i:
				var p: PlatformData = plats[j]
				var top: float = p.y
				# crossed the top surface while moving down, and the feet overlap it
				if y >= top - 0.01 and y_new <= top:
					if x + fhw > p.left() and x - fhw < p.right():
						if landed == null or top > landed.y:
							landed = p
				j += 1
		if landed != null:
			y = landed.y
			vy = 0.0
			grounded = true
			support = landed
			coyote = 0
			events.append([SimConst.EV_LAND, landed, vy_new])
		else:
			y = y_new
			vy = vy_new
			if coyote > 0:
				coyote -= 1

	if jump_buf > 0:
		jump_buf -= 1


func _rebound(direction: int) -> void:
	var t: GameTuning = tuning
	var speed: float = absf(vx)
	if speed >= t.wall_rebound_min_speed:
		vx = float(direction) * speed * t.wall_rebound_multiplier
		if not grounded:
			vy = vy + speed * t.wall_rebound_vertical_influence
		events.append([SimConst.EV_WALL, direction, speed])
	else:
		vx = 0.0
