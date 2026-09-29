extends Node
## Autoload "GameManager": global game state and the end-of-run pipeline.
##
## finish_run() is the single place where a finished run is turned into persistent data:
## statistics -> leaderboards (with record detection) -> character unlocks -> replay file.
## It also recovers a run that was interrupted by the OS killing the app in the background.

signal state_changed(state: int)

enum State { MENU, PLAYING, PAUSED, GAME_OVER, REPLAY }

var tuning: GameTuning
var game_version: String = "1.0.0"
var state: int = State.MENU
var last_summary: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	tuning = TuningStore.get_tuning()
	game_version = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	call_deferred("recover_interrupted_run")


func set_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


## A fresh 32-bit seed for a new run.
func new_seed() -> int:
	return (randi() ^ (Time.get_ticks_usec() & 0xFFFFFFFF)) & 0xFFFFFFFF


func is_first_launch() -> bool:
	return not SettingsManager.get_bool("control_chosen")


# ---------------------------------------------------------------------------
# End of run
# ---------------------------------------------------------------------------
static func is_meaningful(result: Dictionary) -> bool:
	return int(result.get("highest_floor", 0)) > 0 or int(result.get("jumps", 0)) > 0


## Persists a finished (or abandoned) live run. Returns the summary shown on the game-over screen:
## { result, records{score,floor,combo}, ranks{...}, new_characters[], replay_id, any_record }
func finish_run(result: Dictionary, replay: ReplayData) -> Dictionary:
	var summary: Dictionary = {
		"result": result,
		"records": {"score": false, "floor": false, "combo": false},
		"ranks": {"score": 0, "floor": 0, "combo": 0},
		"new_characters": [],
		"replay_id": "",
		"any_record": false,
	}
	clear_active_run()
	if bool(result.get("practice", false)) or bool(result.get("debug_used", false)) or not is_meaningful(result):
		last_summary = summary
		Events.run_finished.emit(summary)
		return summary

	var replay_id: String = ""
	if replay != null:
		replay.id = ReplayManager.make_id()
		replay_id = replay.id
		_save_replay_later(replay)
	summary["replay_id"] = replay_id

	var placed: Dictionary = LeaderboardManager.submit_run(result, replay_id)
	var record_count: int = 0
	if placed.has("records"):
		summary["records"] = placed["records"]
		for cat in LeaderboardProvider.CATEGORIES:
			if bool(placed["records"].get(cat, false)):
				record_count += 1
		summary["ranks"] = {"score": int(placed.get("score", 0)), "floor": int(placed.get("floor", 0)), "combo": int(placed.get("combo", 0))}
	summary["any_record"] = record_count > 0

	StatisticsManager.record_run(result, record_count)
	summary["new_characters"] = CharacterManager.check_unlocks()
	SaveManager.flush()
	last_summary = summary
	Events.run_finished.emit(summary)
	return summary


## Replays are written a moment after the game-over screen appears, so the file write
## and compression never cause a hitch at the moment of death.
func _save_replay_later(replay: ReplayData) -> void:
	await get_tree().create_timer(0.45).timeout
	ReplayManager.save_replay(replay)


# ---------------------------------------------------------------------------
# Crash / kill recovery
# ---------------------------------------------------------------------------
## Called when the app goes to the background during a run: keeps enough data to rebuild the
## run if the OS kills the process while the app is in the background.
func write_interrupted_snapshot(snapshot: ReplayData) -> void:
	if snapshot == null:
		return
	if ReplayManager.write_autosave(snapshot):
		SaveManager.data["active_run"] = {
			"replay_id": ReplayManager.AUTOSAVE_ID,
			"saved_at": int(Time.get_unix_time_from_system()),
		}
		SaveManager.mark_dirty()
		SaveManager.flush()


func clear_active_run() -> void:
	var ar: Dictionary = SaveManager.section("active_run")
	if not ar.is_empty():
		SaveManager.data["active_run"] = {}
		SaveManager.mark_dirty()
	ReplayManager.clear_autosave()


## If the previous session was killed mid-run, re-simulates the autosaved inputs and credits
## the run (statistics, records, replay) exactly as if it had ended normally.
func recover_interrupted_run() -> void:
	var ar: Dictionary = SaveManager.section("active_run")
	if ar.is_empty() or not ReplayManager.has_autosave():
		if not ar.is_empty():
			clear_active_run()
		return
	var loaded: Dictionary = ReplayManager.load_replay(ReplayManager.AUTOSAVE_ID)
	if not bool(loaded["ok"]):
		clear_active_run()
		return
	var replay: ReplayData = loaded["replay"]
	var player: ReplayPlayer = ReplayPlayer.new(replay)
	if player.incompatible:
		clear_active_run()
		return
	var result: Dictionary = player.simulate_all()
	replay.score = int(result["score"])
	replay.highest_floor = int(result["highest_floor"])
	replay.best_combo_floors = int(result["best_combo_floors"])
	replay.best_combo_jumps = int(result["best_combo_jumps"])
	replay.duration_ticks = int(result["duration_ticks"])
	replay.complete = true
	var summary: Dictionary = finish_run(result, replay)
	if bool(summary["any_record"]) or is_meaningful(result):
		Events.toast.emit("Recovered your interrupted run: %s points" % Fmt.number(int(result["score"])))
