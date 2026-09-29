class_name ReplayRecorder
extends RefCounted
## Records the input of a live run tick by tick.
##
## Call record(tick, axis_q, jump) once per simulation tick BEFORE feeding the same
## values to RunManager.tick(). Only axis changes and jump presses create events.

var replay: ReplayData
var recording: bool = false

var _last_q: int = 0
var _last_tick: int = 0


## Starts a recording for a run with the given seed and tuning.
func start(p_seed: int, tuning: GameTuning, character_id: String, control_mode: String, game_version: String) -> void:
	replay = ReplayData.new()
	replay.seed_value = p_seed
	replay.character = character_id
	replay.control = control_mode
	replay.game_version = game_version
	replay.sim_version = SimConst.SIM_VERSION
	replay.created = int(Time.get_unix_time_from_system())
	replay.tuning_snapshot = tuning.to_sim_dict()
	replay.tuning_hash = tuning.sim_hash()
	replay.events = PackedInt32Array()
	_last_q = 0
	_last_tick = 0
	recording = true


## Quantises an axis value the same way for live play and replays.
static func quantize(axis: float) -> int:
	var v: float = clampf(axis, -1.0, 1.0) * float(SimConst.AXIS_STEPS)
	if v >= 0.0:
		return int(v + 0.5)
	return -int(-v + 0.5)


static func dequantize(q: int) -> float:
	return float(q) / float(SimConst.AXIS_STEPS)


func record(tick: int, axis_q: int, jump: bool) -> void:
	if not recording:
		return
	_last_tick = tick
	if axis_q != _last_q or jump:
		replay.events.append(tick)
		replay.events.append(axis_q)
		replay.events.append(1 if jump else 0)
		_last_q = axis_q


## Ends the recording and fills the summary fields. Returns the finished replay.
func finish(result: Dictionary, complete: bool = true) -> ReplayData:
	recording = false
	replay.score = int(result.get("score", 0))
	replay.highest_floor = int(result.get("highest_floor", 0))
	replay.best_combo_floors = int(result.get("best_combo_floors", 0))
	replay.best_combo_jumps = int(result.get("best_combo_jumps", 0))
	replay.duration_ticks = int(result.get("duration_ticks", _last_tick))
	replay.complete = complete
	return replay


## Snapshot for crash recovery (does not stop the recording).
func snapshot(result: Dictionary) -> ReplayData:
	var copy: ReplayData = ReplayData.new()
	copy.seed_value = replay.seed_value
	copy.character = replay.character
	copy.control = replay.control
	copy.game_version = replay.game_version
	copy.sim_version = replay.sim_version
	copy.created = replay.created
	copy.tuning_snapshot = replay.tuning_snapshot
	copy.tuning_hash = replay.tuning_hash
	copy.events = replay.events.duplicate()
	copy.score = int(result.get("score", 0))
	copy.highest_floor = int(result.get("highest_floor", 0))
	copy.best_combo_floors = int(result.get("best_combo_floors", 0))
	copy.best_combo_jumps = int(result.get("best_combo_jumps", 0))
	copy.duration_ticks = int(result.get("duration_ticks", _last_tick))
	copy.complete = false
	return copy
