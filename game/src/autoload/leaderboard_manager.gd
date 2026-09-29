extends Node
## Autoload "LeaderboardManager": local high scores (+ optional online providers).
##
## Gameplay code only calls submit_run(); which back ends receive the run is decided here.
## The local provider is always present. Additional providers can be registered at runtime.

signal entries_changed

var local: LocalLeaderboardProvider
var providers: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.loaded.connect(_on_save_loaded)
	_on_save_loaded()


func _on_save_loaded() -> void:
	local = LocalLeaderboardProvider.new(SaveManager.section("leaderboards"))
	local.on_changed = _on_local_changed
	providers.clear()
	providers.append(local)
	entries_changed.emit()


func _on_local_changed() -> void:
	SaveManager.mark_dirty()
	entries_changed.emit()


## Adds an additional (for example online) provider. Local scores keep working without it.
func register_provider(provider: LeaderboardProvider) -> void:
	if not providers.has(provider):
		providers.append(provider)


func get_entries(category: String) -> Array:
	return local.get_entries(category)


func best_value(category: String) -> int:
	return local.best_value(category)


func would_be_record(category: String, value: int) -> bool:
	return value > 0 and value > local.best_value(category)


## Builds a leaderboard entry from a finished run and submits it to every provider.
## Returns the local placement/record information (see LeaderboardProvider.submit()).
func submit_run(result: Dictionary, replay_id: String = "") -> Dictionary:
	var entry: Dictionary = {
		"name": SettingsManager.get_string("player_name"),
		"score": int(result.get("score", 0)),
		"floor": int(result.get("highest_floor", 0)),
		"combo": int(result.get("best_combo_floors", 0)),
		"combo_jumps": int(result.get("best_combo_jumps", 0)),
		"date": int(Time.get_unix_time_from_system()),
		"duration": float(result.get("duration", 0.0)),
		"replay_id": replay_id,
		"character": CharacterManager.selected_id,
		"seed": int(result.get("seed", 0)),
		"control": SettingsManager.get_string("control_mode"),
	}
	var local_result: Dictionary = {}
	for p in providers:
		var provider: LeaderboardProvider = p
		var r: Dictionary = provider.submit(entry)
		if provider == local:
			local_result = r
	return local_result


## Removes the replay reference from entries when a replay file is deleted.
func forget_replay(replay_id: String) -> void:
	var changed_any: bool = false
	for cat in LeaderboardProvider.CATEGORIES:
		for e in SaveManager.section("leaderboards").get(cat, []):
			if e is Dictionary and String(e.get("replay_id", "")) == replay_id:
				e["replay_id"] = ""
				changed_any = true
	if changed_any:
		SaveManager.mark_dirty()
		entries_changed.emit()


func clear_all() -> void:
	local.clear()
