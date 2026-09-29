class_name StatsData
extends RefCounted
## Lifetime statistics as plain data + rules (StatisticsManager wraps this and persists it).

## All tracked statistics with their default value (the default's type is the stat's type).
const DEFAULTS: Dictionary = {
	"games_played": 0,
	"total_jumps": 0,
	"total_floors_climbed": 0,
	"total_combo_jumps": 0,
	"combos_completed": 0,
	"highest_floor": 0,
	"highest_score": 0,
	"longest_combo": 0,
	"longest_combo_jumps": 0,
	"longest_run_seconds": 0.0,
	"total_playtime_seconds": 0.0,
	"wall_rebounds": 0,
	"personal_records": 0,
}

## The live dictionary (shared with the save file).
var values: Dictionary = {}


func _init(p_values: Dictionary = {}) -> void:
	values = p_values
	normalize()


## Adds missing keys and restores the proper number types after loading from JSON.
func normalize() -> void:
	for key in DEFAULTS:
		var def: Variant = DEFAULTS[key]
		if not values.has(key):
			values[key] = def
		elif typeof(def) == TYPE_INT:
			values[key] = int(values[key])
		else:
			values[key] = float(values[key])


func get_stat(key: String) -> Variant:
	if values.has(key):
		return values[key]
	return DEFAULTS.get(key, 0)


func get_int(key: String) -> int:
	return int(get_stat(key))


func get_float(key: String) -> float:
	return float(get_stat(key))


## Adds a finished run. Practice runs and runs that used debug tools are ignored (returns false).
func record_run(result: Dictionary, new_record_count: int) -> bool:
	if bool(result.get("practice", false)) or bool(result.get("debug_used", false)):
		return false
	_add("games_played", 1)
	_add("total_jumps", int(result.get("jumps", 0)))
	_add("total_floors_climbed", int(result.get("highest_floor", 0)))
	_add("total_combo_jumps", int(result.get("combo_jumps", 0)))
	_add("combos_completed", int(result.get("combos_completed", 0)))
	_add("wall_rebounds", int(result.get("wall_rebounds", 0)))
	_add("total_playtime_seconds", float(result.get("duration", 0.0)))
	_add("personal_records", new_record_count)
	_max("highest_floor", int(result.get("highest_floor", 0)))
	_max("highest_score", int(result.get("score", 0)))
	_max("longest_combo", int(result.get("best_combo_floors", 0)))
	_max("longest_combo_jumps", int(result.get("best_combo_jumps", 0)))
	_max("longest_run_seconds", float(result.get("duration", 0.0)))
	return true


func reset() -> void:
	for key in DEFAULTS:
		values[key] = DEFAULTS[key]


func _add(key: String, amount: Variant) -> void:
	if typeof(DEFAULTS[key]) == TYPE_INT:
		values[key] = int(values[key]) + int(amount)
	else:
		values[key] = float(values[key]) + float(amount)


func _max(key: String, value: Variant) -> void:
	if typeof(DEFAULTS[key]) == TYPE_INT:
		values[key] = maxi(int(values[key]), int(value))
	else:
		values[key] = maxf(float(values[key]), float(value))
