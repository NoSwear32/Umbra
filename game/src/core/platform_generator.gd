class_name PlatformGenerator
extends RefCounted
## Deterministic, seeded, endless platform generator: builds the tower one floor at a time.
##
## * One platform per floor; `platforms[i].floor_index == i`.
## * The order of random draws is part of the replay contract - do not reorder them.
## * Reachability guarantee: the horizontal gap between two consecutive platforms never
##   exceeds a fraction of the distance a *standing start* + base jump can provably cover
##   (see max_gap). The vertical spacing is capped below the apex of a standing jump.
##   Difficulty rises through narrower platforms, larger allowed gaps and momentum needs.

var tuning: GameTuning
var seed_value: int = 0
var rng: SimRng
## Every platform generated so far (kept for the whole run; ~100 bytes each).
var platforms: Array = []

var _top_y: float = 0.0
var _pattern: int = SimConst.PATTERN_FREE
var _pattern_left: int = 0
var _dir: float = 1.0


func _init(p_tuning: GameTuning, p_seed: int) -> void:
	tuning = p_tuning
	seed_value = p_seed
	rng = SimRng.new(p_seed)
	var ground: PlatformData = PlatformData.new(0, tuning.tower_width * 0.5, 0.0, tuning.tower_width, SimConst.KIND_GROUND, 0)
	platforms.append(ground)
	_top_y = ground.y


## Generates platforms until the highest one is at or above `altitude`.
func ensure_up_to(altitude: float) -> void:
	while _top_y < altitude:
		_generate_next()


func platform_count() -> int:
	return platforms.size()


func get_platform(floor_index: int) -> PlatformData:
	if floor_index < 0:
		return platforms[0]
	while floor_index >= platforms.size():
		_generate_next()
	return platforms[floor_index]


## 0 (easy) .. 1 (full difficulty) for a floor.
func difficulty(floor_index: int) -> float:
	var d: float = float(floor_index) / float(tuning.difficulty_ramp_floors)
	if d > 1.0:
		d = 1.0
	return d


## Largest edge-to-edge horizontal gap that is guaranteed jumpable from a standstill
## on a platform of width `prev_w`, for a step of `spacing` up. Conservative on purpose.
func max_gap(prev_w: float, spacing: float, d: float) -> float:
	var t: GameTuning = tuning
	var run: float = prev_w - 2.0 * t.foot_half_width
	if run < 0.0:
		run = 0.0
	var v: float = sqrt(t.accel_ground * run)
	if v > t.max_speed:
		v = t.max_speed
	var v0: float = t.base_jump_velocity
	var disc: float = v0 * v0 - 2.0 * t.gravity * spacing
	if disc < 0.0:
		disc = 0.0
	var tair: float = (v0 + sqrt(disc)) / t.gravity
	var ratio: float = v / t.max_speed
	var a_eff: float = t.air_accel * (1.0 + (t.accel_at_max_ratio - 1.0) * ratio)
	var reach: float = v * tair + 0.5 * a_eff * tair * tair
	var factor: float = t.reach_factor_start + (t.reach_factor_end - t.reach_factor_start) * d
	return factor * reach


## Index of the highest platform whose top is at or below `altitude` (+ tiny slack).
func index_at_or_below(altitude: float) -> int:
	var lo: int = 0
	var hi: int = platforms.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		var p: PlatformData = platforms[mid]
		if p.y <= altitude + 0.01:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _choose_pattern() -> void:
	var t: GameTuning = tuning
	var r: float = rng.next_float()
	if r < t.pattern_stairs_chance:
		_pattern = SimConst.PATTERN_STAIRS
	elif r < t.pattern_stairs_chance + t.pattern_zigzag_chance:
		_pattern = SimConst.PATTERN_ZIGZAG
	else:
		_pattern = SimConst.PATTERN_FREE
	if rng.next_float() < 0.5:
		_dir = -1.0
	else:
		_dir = 1.0
	_pattern_left = rng.range_i(t.pattern_min_run, t.pattern_max_run)


func _generate_next() -> void:
	var t: GameTuning = tuning
	var k: int = platforms.size()
	var prev: PlatformData = platforms[k - 1]
	var d: float = difficulty(k)

	# vertical spacing
	var sp: float = t.platform_spacing_start + (t.platform_spacing_end - t.platform_spacing_start) * d
	sp = sp + rng.range_f(-t.platform_spacing_jitter, t.platform_spacing_jitter)
	var max_sp: float = t.base_apex() - t.platform_clearance
	if sp > max_sp:
		sp = max_sp
	if sp < t.platform_spacing_min:
		sp = t.platform_spacing_min

	# width
	var wmin: float = t.platform_width_start_min + (t.platform_width_end_min - t.platform_width_start_min) * d
	var wmax: float = t.platform_width_start_max + (t.platform_width_end_max - t.platform_width_start_max) * d
	var w: float = rng.range_f(wmin, wmax)
	var kind: int = SimConst.KIND_NORMAL
	if t.landmark_interval > 0 and (k % t.landmark_interval) == 0:
		kind = SimConst.KIND_LANDMARK
		if w < t.landmark_min_width:
			w = t.landmark_min_width
	if w > t.tower_width:
		w = t.tower_width

	# horizontal placement
	if _pattern_left <= 0:
		_choose_pattern()
	_pattern_left -= 1

	var reach: float = max_gap(prev.width, sp, d)
	var max_dx: float = (w + prev.width) * 0.5 + reach
	var lo: float = prev.x - max_dx
	if lo < w * 0.5:
		lo = w * 0.5
	var hi: float = prev.x + max_dx
	if hi > t.tower_width - w * 0.5:
		hi = t.tower_width - w * 0.5

	var x: float = 0.0
	if _pattern == SimConst.PATTERN_FREE:
		x = rng.range_f(lo, hi)
	elif _pattern == SimConst.PATTERN_STAIRS:
		var m: float = rng.range_f(0.5, 0.9)
		x = prev.x + _dir * m * max_dx
		if x < lo or x > hi:
			_dir = -_dir
			x = prev.x + _dir * m * max_dx
		if x < lo:
			x = lo
		if x > hi:
			x = hi
	else:
		_dir = -_dir
		var m2: float = rng.range_f(0.6, 1.0)
		x = prev.x + _dir * m2 * max_dx
		if x < lo:
			x = lo
		if x > hi:
			x = hi

	var variant: int = rng.next_u32() & 0xFFFF
	var y: float = prev.y + sp
	platforms.append(PlatformData.new(k, x, y, w, kind, variant))
	_top_y = y
