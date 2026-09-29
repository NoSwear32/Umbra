class_name ReplayPlayer
extends RefCounted
## Plays a ReplayData back by re-simulating the run.
##
## The tower is regenerated from the stored seed and the recorded inputs are fed to a
## fresh RunManager built from the replay's tuning snapshot, so playback is exact.
## A replay never touches statistics, records or leaderboards.

var replay: ReplayData
var tuning: GameTuning
var run: RunManager
## True if the replay was recorded by a different simulation version (cannot be trusted).
var incompatible: bool = false
## True if the tuning snapshot could not be applied exactly (playback may drift).
var tuning_mismatch: bool = false
var finished: bool = false

var _cursor: int = 0
var _axis_q: int = 0


func _init(p_replay: ReplayData) -> void:
	replay = p_replay
	incompatible = replay.sim_version != SimConst.SIM_VERSION
	tuning = GameTuning.from_sim_dict(replay.tuning_snapshot)
	if replay.tuning_hash != 0 and tuning.sim_hash() != replay.tuning_hash:
		tuning_mismatch = true
	run = RunManager.new(tuning, replay.seed_value)


## Advances the replay by exactly one tick. Returns false once the run has ended.
func step() -> bool:
	if run.dead:
		finished = true
		return false
	var n: int = run.tick_count + 1
	var jump: bool = false
	var ev: PackedInt32Array = replay.events
	while _cursor + 2 < ev.size() and ev[_cursor] <= n:
		if ev[_cursor] == n:
			_axis_q = ev[_cursor + 1]
			if (ev[_cursor + 2] & 1) != 0:
				jump = true
		elif ev[_cursor] < n:
			# an event for a tick that already passed (should not happen): apply the axis
			_axis_q = ev[_cursor + 1]
		_cursor += 3
	run.tick(ReplayRecorder.dequantize(_axis_q), jump)
	if run.dead:
		finished = true
		return false
	# a replay stops after its last recorded tick (death, quit or interruption)
	if replay.duration_ticks > 0 and n >= replay.duration_ticks:
		if not run.dead:
			run.abandon()  # settle a running combo exactly like the live game did
		finished = true
		return false
	return true


## The (quantised) horizontal input currently being applied - lets views animate the character.
func current_axis() -> float:
	return ReplayRecorder.dequantize(_axis_q)


## Simulates the whole replay instantly (used by tests and for crash recovery).
## Returns the final run result.
func simulate_all(max_ticks: int = 0) -> Dictionary:
	var limit: int = max_ticks
	if limit <= 0:
		limit = maxi(replay.duration_ticks, 1)
	while run.tick_count < limit:
		if not step():
			break
	return run.build_result()


## True when the final state of the run matches the summary stored in the replay.
func matches_recording() -> bool:
	return run.get_score() == replay.score and run.highest_floor == replay.highest_floor
