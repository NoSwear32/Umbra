class_name TuningStore
extends RefCounted
## Shared access to the game tuning resource.
##
## Every system that needs tuning values asks the store, so nothing depends on the load
## order of autoloads. The store loads `res://resources/game_tuning.tres` once (values
## edited in the inspector override the defaults declared in game_tuning.gd) and falls
## back to a plain GameTuning if the file is missing.

const TUNING_PATH: String = "res://resources/game_tuning.tres"

static var _tuning: GameTuning = null


static func get_tuning() -> GameTuning:
	if _tuning == null:
		if ResourceLoader.exists(TUNING_PATH):
			_tuning = load(TUNING_PATH) as GameTuning
		if _tuning == null:
			_tuning = GameTuning.new()
		_tuning.sanitize()
	return _tuning


## Replaces the shared tuning (debug menu / tests). Pass null to reload from disk.
static func set_tuning(t: GameTuning) -> void:
	_tuning = t
	if _tuning != null:
		_tuning.sanitize()
