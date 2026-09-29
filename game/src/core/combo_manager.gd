class_name ComboManager
extends RefCounted
## Combo chains.
##
## A landing that advanced `combo_min_floors` (default 2) or more floors is a combo
## jump. Another combo jump within `combo_timeout` continues the chain. A landing
## that advances fewer floors (one floor, the same floor, or a lower floor) or a
## timeout ends it. A chain only pays a bonus when it has at least
## `combo_min_jumps_for_bonus` jumps and `combo_min_total_floors_for_bonus` floors:
##     bonus = floors ^ combo_bonus_exponent * combo_bonus_multiplier
## The timer is measured in simulation ticks, so it pauses with the game.

signal combo_started
signal combo_progressed(jumps: int, floors: int)
signal combo_ended(jumps: int, floors: int, bonus: int, reason: int, valid: bool)

const MAX_BONUS: int = 9000000000000000000

var tuning: GameTuning
var active: bool = false
var jumps: int = 0
var floors: int = 0
## Remaining ticks until the chain times out.
var timer: int = 0
var best_floors_run: int = 0
var best_jumps_run: int = 0
var total_combo_jumps: int = 0
## Number of completed combos that paid a bonus.
var valid_combos: int = 0

var _timeout_ticks: int = 360


func _init(p_tuning: GameTuning) -> void:
	tuning = p_tuning
	_timeout_ticks = tuning.combo_ticks()


## 1.0 right after a combo landing, shrinking to 0.0 at the timeout.
func timer_ratio() -> float:
	if _timeout_ticks <= 0:
		return 0.0
	return float(timer) / float(_timeout_ticks)


## Bonus a chain of `p_jumps` jumps / `p_floors` floors would pay (0 = not a valid combo).
func bonus_for(p_jumps: int, p_floors: int) -> int:
	var t: GameTuning = tuning
	if p_jumps < t.combo_min_jumps_for_bonus or p_floors < t.combo_min_total_floors_for_bonus:
		return 0
	var v: int = 1
	var i: int = 0
	while i < t.combo_bonus_exponent:
		if float(v) * float(p_floors) > 9.0e18:
			return MAX_BONUS
		v = v * p_floors
		i += 1
	if float(v) * float(t.combo_bonus_multiplier) > 9.0e18:
		return MAX_BONUS
	return v * t.combo_bonus_multiplier


## Called for every landing. `floors_advanced` = landed floor - take-off floor.
func on_landing(floors_advanced: int, is_new_floor: bool) -> void:
	var t: GameTuning = tuning
	var qualifies: bool = floors_advanced >= t.combo_min_floors
	if t.combo_only_new_floors and not is_new_floor:
		qualifies = false
	if qualifies:
		if not active:
			active = true
			jumps = 0
			floors = 0
			combo_started.emit()
		jumps += 1
		floors += floors_advanced
		timer = _timeout_ticks
		total_combo_jumps += 1
		combo_progressed.emit(jumps, floors)
	elif active:
		_end(SimConst.COMBO_END_LOWER)


## Advances the timeout by one simulation tick.
func tick() -> void:
	if active:
		timer -= 1
		if timer <= 0:
			_end(SimConst.COMBO_END_TIMEOUT)


## Force the chain to end now (death, restart...).
func end_now(reason: int) -> void:
	if active:
		_end(reason)


func _end(reason: int) -> void:
	var bonus: int = bonus_for(jumps, floors)
	var valid: bool = bonus > 0
	if valid:
		valid_combos += 1
		if floors > best_floors_run:
			best_floors_run = floors
		if jumps > best_jumps_run:
			best_jumps_run = jumps
	var j: int = jumps
	var f: int = floors
	active = false
	jumps = 0
	floors = 0
	timer = 0
	combo_ended.emit(j, f, bonus, reason, valid)
