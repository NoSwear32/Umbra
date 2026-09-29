extends Node
## Autoload "StatisticsManager": lifetime statistics of the player profile.

signal changed

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

var _stats: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.loaded.connect(_on_save_loaded)
	_on_save_loaded()


func _on_save_loaded() -> void:
	_stats = SaveManager.section("stats")
	for key in DEFAULTS:
		var def: Variant = DEFAULTS[key]
		if not _stats.has(key):
			_stats[key] = def
		elif typeof(def) == TYPE_INT:
			_stats[key] = int(_stats[key])
		else:
			_stats[key] = float(_stats[key])
	changed.emit()


func get_stat(key: String) -> Variant:
	if _stats.has(key):
		return _stats[key]
	return DEFAULTS.get(key, 0)


func get_int(key: String) -> int:
	return int(get_stat(key))


func get_float(key: String) -> float:
	return float(get_stat(key))


## Adds a finished run to the lifetime statistics.
## Practice runs and runs that used debug tools are ignored.
func record_run(result: Dictionary, new_record_count: int) -> void:
	if bool(result.get("practice", false)) or bool(result.get("debug_used", false)):
		return
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
	SaveManager.mark_dirty()
	changed.emit()


func reset() -> void:
	for key in DEFAULTS:
		_stats[key] = DEFAULTS[key]
	SaveManager.mark_dirty()
	changed.emit()


func _add(key: String, amount: Variant) -> void:
	if typeof(DEFAULTS[key]) == TYPE_INT:
		_stats[key] = int(_stats[key]) + int(amount)
	else:
		_stats[key] = float(_stats[key]) + float(amount)


func _max(key: String, value: Variant) -> void:
	if typeof(DEFAULTS[key]) == TYPE_INT:
		_stats[key] = maxi(int(_stats[key]), int(value))
	else:
		_stats[key] = maxf(float(_stats[key]), float(value))
