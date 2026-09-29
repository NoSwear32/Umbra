extends Node
## Autoload "StatisticsManager": lifetime statistics of the player profile.
## The rules live in StatsData (unit tested); this node persists them with the profile.

signal changed

## Re-exported so callers can read the list of statistics.
const DEFAULTS: Dictionary = StatsData.DEFAULTS

var _data: StatsData = StatsData.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.loaded.connect(_on_save_loaded)
	_on_save_loaded()


func _on_save_loaded() -> void:
	_data = StatsData.new(SaveManager.section("stats"))
	changed.emit()


func get_stat(key: String) -> Variant:
	return _data.get_stat(key)


func get_int(key: String) -> int:
	return _data.get_int(key)


func get_float(key: String) -> float:
	return _data.get_float(key)


## Adds a finished run to the lifetime statistics.
## Practice runs and runs that used debug tools are ignored.
func record_run(result: Dictionary, new_record_count: int) -> void:
	if _data.record_run(result, new_record_count):
		SaveManager.mark_dirty()
		changed.emit()


func reset() -> void:
	_data.reset()
	SaveManager.mark_dirty()
	changed.emit()
