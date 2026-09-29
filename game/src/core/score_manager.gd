class_name ScoreManager
extends RefCounted
## Integer-safe score bookkeeping for one run.
##
## Base points are only awarded for floors above the highest floor already credited
## (the caller passes the number of NEWLY reached floors), so falling and re-climbing
## can never farm points. Combo bonuses are added when a valid combo ends.

signal score_changed(total: int)

## Scores saturate here instead of overflowing 64-bit integers.
const MAX_SCORE: int = 9000000000000000000

var total: int = 0
var floor_points: int = 0
var combo_points: int = 0


func add_floor_points(newly_reached_floors: int, points_per_floor: int) -> void:
	if newly_reached_floors <= 0 or points_per_floor <= 0:
		return
	var add: int = newly_reached_floors * points_per_floor
	floor_points = _sat_add(floor_points, add)
	_refresh()


func add_combo_bonus(bonus: int) -> void:
	if bonus <= 0:
		return
	combo_points = _sat_add(combo_points, bonus)
	_refresh()


func _refresh() -> void:
	total = _sat_add(floor_points, combo_points)
	score_changed.emit(total)


static func _sat_add(a: int, b: int) -> int:
	if b > MAX_SCORE - a:
		return MAX_SCORE
	return a + b
