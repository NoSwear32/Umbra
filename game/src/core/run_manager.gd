class_name RunManager
extends RefCounted
## One run of the game: owns the tower, the player, scrolling, combo and score.
##
## The run is advanced with `tick(axis, jump)` at a fixed 120 Hz. It is completely
## free of nodes and engine state, so the very same class drives live play, replay
## playback, the debug bots and the unit tests. Presentation code listens to the
## signals below.

signal jumped(jump_velocity: float, speed_ratio: float)
signal landed(platform: PlatformData, impact_speed: float, floors_advanced: int, is_new_floor: bool)
signal left_ground(floor_index: int)
signal wall_rebounded(direction: int, speed: float)
signal new_floor_reached(floor_index: int, gained: int)
signal combo_started
signal combo_progressed(jumps: int, floors: int)
signal combo_ended(jumps: int, floors: int, bonus: int, reason: int, valid: bool)
signal scroll_started
signal speed_stage_changed(stage: int)
signal score_changed(total: int)
signal run_ended(result: Dictionary)

var tuning: GameTuning
var seed_value: int = 0
var tick_count: int = 0
var dead: bool = false

var tower: PlatformGenerator
var player: PlayerController
var scroll: ScrollDifficultyManager
var combo: ComboManager
var scoring: ScoreManager

## Highest floor reached during this run. Never decreases.
var highest_floor: int = 0
## Floor the player currently stands on (or last stood on).
var current_floor: int = 0
var total_jumps: int = 0
var wall_rebounds: int = 0
## Set by debug tools; such runs are excluded from records and leaderboards.
var debug_used: bool = false
## Tutorial / practice runs never touch records or statistics.
var practice: bool = false
## Invincibility (debug only).
var invincible: bool = false


func _init(p_tuning: GameTuning, p_seed: int) -> void:
	tuning = p_tuning
	seed_value = p_seed
	tower = PlatformGenerator.new(tuning, seed_value)
	player = PlayerController.new(tuning)
	scroll = ScrollDifficultyManager.new(tuning)
	combo = ComboManager.new(tuning)
	scoring = ScoreManager.new()
	tower.ensure_up_to(scroll.cam_bottom + tuning.view_height + tuning.generate_ahead)
	player.support = tower.platforms[0]

	combo.combo_started.connect(_on_combo_started)
	combo.combo_progressed.connect(_on_combo_progressed)
	combo.combo_ended.connect(_on_combo_ended)
	scroll.scroll_started.connect(_on_scroll_started)
	scroll.stage_changed.connect(_on_stage_changed)
	scoring.score_changed.connect(_on_score_changed)


func get_score() -> int:
	return scoring.total


func duration_seconds() -> float:
	return float(tick_count) * SimConst.DT


## Advance the run by one fixed step. axis: -1..1, jump: jump requested this tick.
func tick(axis: float, jump: bool) -> void:
	if dead:
		return
	var t: GameTuning = tuning
	tick_count += 1
	tower.ensure_up_to(scroll.cam_bottom + t.view_height + t.generate_ahead + 400.0)

	player.step(axis, jump, tower)

	# react to what the player did during this step (same order as the reference sim)
	var evs: Array = player.events
	var i: int = 0
	while i < evs.size():
		var e: Array = evs[i]
		var kind: int = e[0]
		if kind == SimConst.EV_JUMP:
			total_jumps += 1
			jumped.emit(e[1], e[2])
		elif kind == SimConst.EV_WALL:
			wall_rebounds += 1
			wall_rebounded.emit(e[1], e[2])
		elif kind == SimConst.EV_LEFT_GROUND:
			left_ground.emit(e[1])
		elif kind == SimConst.EV_LAND:
			_on_land(e[1], e[2])
		i += 1

	scroll.step(player.y + t.player_height, highest_floor)
	combo.tick()

	if not invincible and player.y + t.player_height < scroll.cam_bottom - t.death_margin:
		_die()


func _on_land(plat: PlatformData, impact: float) -> void:
	var adv: int = plat.floor_index - player.takeoff_floor
	var is_new: bool = plat.floor_index > highest_floor
	current_floor = plat.floor_index
	var gained: int = 0
	if is_new:
		gained = plat.floor_index - highest_floor
		scoring.add_floor_points(gained, tuning.points_per_floor)
		highest_floor = plat.floor_index
	landed.emit(plat, impact, adv, is_new)
	if is_new:
		new_floor_reached.emit(highest_floor, gained)
	combo.on_landing(adv, is_new)


func _die() -> void:
	combo.end_now(SimConst.COMBO_END_DEATH)
	dead = true
	run_ended.emit(build_result())


## Ends the run without dying (quit / restart). Awards a running combo like a death would.
func abandon() -> Dictionary:
	if not dead:
		combo.end_now(SimConst.COMBO_END_DEATH)
		dead = true
	return build_result()


func build_result() -> Dictionary:
	return {
		"score": scoring.total,
		"floor_points": scoring.floor_points,
		"combo_points": scoring.combo_points,
		"highest_floor": highest_floor,
		"best_combo_floors": combo.best_floors_run,
		"best_combo_jumps": combo.best_jumps_run,
		"duration_ticks": tick_count,
		"duration": duration_seconds(),
		"jumps": total_jumps,
		"combo_jumps": combo.total_combo_jumps,
		"combos_completed": combo.valid_combos,
		"wall_rebounds": wall_rebounds,
		"seed": seed_value,
		"scroll_stage": scroll.stage,
		"debug_used": debug_used,
		"practice": practice,
	}


# ---------------------------------------------------------------------------
# Debug helpers (only reachable from the debug menu in development builds)
# ---------------------------------------------------------------------------
func debug_teleport_to_floor(target_floor: int) -> void:
	debug_used = true
	var plat: PlatformData = tower.get_platform(maxi(target_floor, 0))
	var half: float = tuning.player_half_width
	player.place_on(plat, clampf(plat.x, half, tuning.tower_width - half))
	highest_floor = maxi(highest_floor, plat.floor_index)
	current_floor = plat.floor_index
	tower.ensure_up_to(plat.y + tuning.view_height + tuning.generate_ahead + 400.0)
	scroll.cam_bottom = plat.y - tuning.view_height * tuning.camera_follow_line
	scroll.prev_cam_bottom = scroll.cam_bottom


func debug_force_game_over() -> void:
	debug_used = true
	invincible = false
	if not dead:
		_die()


func debug_set_stage(new_stage: int) -> void:
	debug_used = true
	scroll.debug_set_stage(new_stage)


# ---------------------------------------------------------------------------
# Signal forwarding
# ---------------------------------------------------------------------------
func _on_combo_started() -> void:
	combo_started.emit()


func _on_combo_progressed(jumps: int, floors: int) -> void:
	combo_progressed.emit(jumps, floors)


func _on_combo_ended(jumps: int, floors: int, bonus: int, reason: int, valid: bool) -> void:
	scoring.add_combo_bonus(bonus)
	combo_ended.emit(jumps, floors, bonus, reason, valid)


func _on_scroll_started() -> void:
	scroll_started.emit()


func _on_stage_changed(stage: int) -> void:
	speed_stage_changed.emit(stage)


func _on_score_changed(total: int) -> void:
	score_changed.emit(total)
