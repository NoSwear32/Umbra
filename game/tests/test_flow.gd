extends RefCounted
## Flows across the autoload managers: the end-of-run pipeline (records, statistics, unlocks,
## replay file), replay management, interrupted-run recovery and settings persistence.
##
## The real singletons are used, but inside SaveManager's sandbox (a scratch folder and a fresh
## profile), so a developer's or player's own data is never read or written.

const SANDBOX: String = "user://test_flow_scratch"

var _toasts: PackedStringArray = PackedStringArray()
var _unlocked: PackedStringArray = PackedStringArray()
var _finished: Array = []
var _setting_events: PackedStringArray = PackedStringArray()
var _list_changes: int = 0


func run(t: TestContext) -> void:
	SaveManager.enter_sandbox(SANDBOX)
	var previous_delay: float = GameManager.replay_save_delay
	GameManager.replay_save_delay = 0.0
	Events.toast.connect(_on_toast)
	Events.character_unlocked.connect(_on_unlocked)
	Events.run_finished.connect(_on_finished)
	Events.settings_changed.connect(_on_setting)
	ReplayManager.list_changed.connect(_on_list_changed)

	_first_launch(t)
	_run_pipeline(t)
	_ignored_runs(t)
	_leaderboard_flow(t)
	_unlock_flow(t)
	_replay_files(t)
	_replay_sharing(t)
	_replay_pruning(t)
	_recovery(t)
	_settings(t)
	_restart(t)

	Events.toast.disconnect(_on_toast)
	Events.character_unlocked.disconnect(_on_unlocked)
	Events.run_finished.disconnect(_on_finished)
	Events.settings_changed.disconnect(_on_setting)
	ReplayManager.list_changed.disconnect(_on_list_changed)
	GameManager.replay_save_delay = previous_delay
	SaveManager.leave_sandbox()
	_remove_tree(SANDBOX)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _on_toast(message: String) -> void:
	_toasts.append(message)


func _on_unlocked(character_id: String) -> void:
	_unlocked.append(character_id)


func _on_finished(summary: Dictionary) -> void:
	_finished.append(summary)


func _on_setting(key: String) -> void:
	_setting_events.append(key)


func _on_list_changed() -> void:
	_list_changes += 1


## Empty profile, no replay files, no recorded events.
func _fresh() -> void:
	for dir_path in [SaveManager.replay_dir, SaveManager.character_dir]:
		for f in DirAccess.get_files_at(String(dir_path)):
			DirAccess.remove_absolute(String(dir_path) + "/" + String(f))
	SaveManager.reset_all()
	_toasts.clear()
	_unlocked.clear()
	_finished.clear()
	_setting_events.clear()
	_list_changes = 0


func _remove_tree(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + String(f))
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + String(d))
	DirAccess.remove_absolute(path)


## A result dictionary shaped like RunManager.build_result().
func _result(score: int, top_floor: int, combo_floors: int = 0, jumps: int = 10, extra: Dictionary = {}) -> Dictionary:
	var r: Dictionary = {
		"score": score, "floor_points": score, "combo_points": 0, "highest_floor": top_floor,
		"best_combo_floors": combo_floors, "best_combo_jumps": combo_floors, "duration_ticks": 1200,
		"duration": 10.0, "jumps": jumps, "combo_jumps": combo_floors,
		"combos_completed": 1 if combo_floors > 0 else 0, "wall_rebounds": 2, "seed": 1234,
		"scroll_stage": 0, "debug_used": false, "practice": false,
	}
	for key in extra:
		r[key] = extra[key]
	return r


## A small valid replay (no need to be a real run).
func _replay(created: int, top_floor: int = 3, score: int = 30) -> ReplayData:
	var tuning: GameTuning = GameTuning.new()
	var r: ReplayData = ReplayData.new()
	r.seed_value = 99
	r.created = created
	r.highest_floor = top_floor
	r.score = score
	r.duration_ticks = 600
	r.game_version = "test"
	r.tuning_snapshot = tuning.to_sim_dict()
	r.tuning_hash = tuning.sim_hash()
	r.events = PackedInt32Array([10, 127, 0, 60, 0, 1])
	return r


## Plays a scripted run like the live game does: the recorder sees every tick first.
## plan: [[ticks, axis, jump_on_first_tick], ...]; stops early after `max_ticks` (0 = play it all).
## Returns { run, rec }.
func _live(plan: Array, seed_value: int, max_ticks: int = 0) -> Dictionary:
	var tuning: GameTuning = GameTuning.new()
	var run: RunManager = RunManager.new(tuning, seed_value)
	var rec: ReplayRecorder = ReplayRecorder.new()
	rec.start(seed_value, tuning, "pip", "touch", "test")
	for seg in plan:
		var count: int = int(seg[0])
		var axis: float = float(seg[1])
		var jump_first: bool = int(seg[2]) != 0
		for i in range(count):
			if run.dead or (max_ticks > 0 and run.tick_count >= max_ticks):
				break
			var jump: bool = jump_first and i == 0
			var q: int = ReplayRecorder.quantize(axis)
			rec.record(run.tick_count + 1, q, jump)
			run.tick(ReplayRecorder.dequantize(q), jump)
	return {"run": run, "rec": rec}


## The bot run of the golden vectors: a long climb with wall rebounds and chained combos.
func _bot() -> Dictionary:
	var golden: Variant = TestContext.load_golden("bot_run.json")
	var sc: Dictionary = (golden as Dictionary)["scenarios"][0]
	return {"plan": sc["segments"], "seed": int(sc["seed"])}


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _first_launch(t: TestContext) -> void:
	t.suite("flow: a fresh profile")
	_fresh()
	t.check(GameManager.is_first_launch(), "a fresh profile shows the control selector")
	SettingsManager.set_value("control_chosen", true)
	t.check(not GameManager.is_first_launch(), "choosing a control scheme ends the first launch")
	t.eq(CharacterManager.selected_id, "pip", "Pip is selected")
	t.check(CharacterManager.is_unlocked("pip"), "Pip is unlocked from the start")
	t.check(not CharacterManager.is_unlocked("bolt"), "the other characters are locked")
	t.eq(LeaderboardManager.get_entries("score").size(), 0, "no scores yet")
	t.eq(StatisticsManager.get_int("games_played"), 0, "no statistics yet")
	t.eq(ReplayManager.count(), 0, "no replays yet")
	t.check(SaveManager.in_sandbox(), "the tests run inside the sandbox")
	t.check(SaveManager.main_path.begins_with(SANDBOX), "the profile is redirected to the scratch folder")


func _run_pipeline(t: TestContext) -> void:
	t.suite("flow: a finished run becomes records, statistics and a replay")
	_fresh()
	var bot: Dictionary = _bot()
	var seed_value: int = int(bot["seed"])
	var live: Dictionary = _live(bot["plan"], seed_value)
	var result: Dictionary = (live["run"] as RunManager).abandon()
	var replay: ReplayData = (live["rec"] as ReplayRecorder).finish(result, true)
	t.check(GameManager.is_meaningful(result), "the scripted run reached a floor (floor %d, %d jumps)" % [int(result["highest_floor"]), int(result["jumps"])])
	t.check(int(result["best_combo_floors"]) >= 2, "and chained multi-floor jumps (%d floors)" % int(result["best_combo_floors"]))

	var summary: Dictionary = GameManager.finish_run(result, replay)
	t.check(not SaveManager.is_dirty(), "the profile was flushed at the end of the run")
	t.check(bool(summary["any_record"]), "the first run sets records")
	t.check(bool(summary["records"]["score"]), "score record")
	t.check(bool(summary["records"]["floor"]), "floor record")
	t.check(bool(summary["records"]["combo"]), "combo record")
	t.eq(int(summary["ranks"]["score"]), 1, "rank 1 on an empty board")
	var replay_id: String = String(summary["replay_id"])
	t.check(not replay_id.is_empty(), "the run gets a replay id")
	t.eq(replay.id, replay_id, "the replay carries that id")
	t.eq(_finished.size(), 1, "run_finished was emitted once")
	t.check(GameManager.last_summary == summary, "GameManager remembers the summary for the game-over screen")
	var unlocked_now: Array = summary["new_characters"]
	t.check(unlocked_now.has("bolt") and unlocked_now.has("ember") and unlocked_now.has("nova"), "a floor-%d run with %d points unlocks Bolt, Ember and Nova" % [int(result["highest_floor"]), int(result["score"])])

	t.check(ReplayManager.has_replay(replay_id), "the replay file was written")
	t.eq(ReplayManager.count(), 1, "and appears once in the list")

	var entries: Array = LeaderboardManager.get_entries("score")
	t.eq(entries.size(), 1, "the score board has the run")
	if entries.size() == 1:
		var e: Dictionary = entries[0]
		t.eq(int(e["score"]), int(result["score"]), "entry: score")
		t.eq(int(e["floor"]), int(result["highest_floor"]), "entry: floor")
		t.eq(int(e["combo"]), int(result["best_combo_floors"]), "entry: combo")
		t.eq(String(e["replay_id"]), replay_id, "entry: replay link")
		t.eq(String(e["character"]), "pip", "entry: character")
		t.eq(String(e["control"]), "touch", "entry: control scheme")
		t.eq(int(e["seed"]), seed_value, "entry: seed")
		t.eq(String(e["name"]), SettingsManager.get_string("player_name"), "entry: player name")
	t.eq(LeaderboardManager.get_entries("floor").size(), 1, "the floor board has the run")
	t.eq(LeaderboardManager.get_entries("combo").size(), 1, "the combo board has the run")

	t.eq(StatisticsManager.get_int("games_played"), 1, "statistics: games played")
	t.eq(StatisticsManager.get_int("total_jumps"), int(result["jumps"]), "statistics: jumps")
	t.eq(StatisticsManager.get_int("highest_floor"), int(result["highest_floor"]), "statistics: highest floor")
	t.eq(StatisticsManager.get_int("highest_score"), int(result["score"]), "statistics: highest score")
	t.eq(StatisticsManager.get_int("longest_combo"), int(result["best_combo_floors"]), "statistics: longest combo")
	t.eq(StatisticsManager.get_int("personal_records"), 3, "statistics: three records")

	SaveManager.flush()
	var disk: Variant = SaveManager.read_json_file(SaveManager.main_path)
	t.check(disk is Dictionary, "the profile file exists and parses")
	if disk is Dictionary:
		var boards: Dictionary = (disk as Dictionary)["leaderboards"]
		t.eq((boards["score"] as Array).size(), 1, "the score is on disk")
		t.eq(int(((disk as Dictionary)["stats"] as Dictionary)["games_played"]), 1, "the statistics are on disk")

	var loaded: Dictionary = ReplayManager.load_replay(replay_id)
	t.check(bool(loaded["ok"]), "the stored replay loads: %s" % String(loaded["error"]))
	if bool(loaded["ok"]):
		var back: ReplayData = loaded["replay"]
		var player: ReplayPlayer = ReplayPlayer.new(back)
		var replayed: Dictionary = player.simulate_all()
		t.eq(int(replayed["score"]), int(result["score"]), "playing the stored replay reproduces the score")
		t.eq(int(replayed["highest_floor"]), int(result["highest_floor"]), "and the floor")
		t.check(player.matches_recording(), "and matches the recorded summary")


func _ignored_runs(t: TestContext) -> void:
	t.suite("flow: practice, debug and empty runs leave no trace")
	_fresh()
	var cases: Array = [
		["a practice run", _result(500, 9, 3, 12, {"practice": true})],
		["a run that used debug tools", _result(500, 9, 3, 12, {"debug_used": true})],
		["a run that never left the ground", _result(0, 0, 0, 0)],
	]
	for c in cases:
		var label: String = String(c[0])
		var summary: Dictionary = GameManager.finish_run(c[1], _replay(1000))
		t.check(not bool(summary["any_record"]), "%s sets no record" % label)
		t.eq(String(summary["replay_id"]), "", "%s stores no replay" % label)
	t.eq(_finished.size(), 3, "the game-over screen is still told about each of them")
	t.eq(LeaderboardManager.get_entries("score").size(), 0, "no leaderboard entries")
	t.eq(StatisticsManager.get_int("games_played"), 0, "no statistics")
	t.eq(ReplayManager.count(), 0, "no replays")
	t.check(SaveManager.section("active_run").is_empty(), "the interrupted-run marker is cleared")


func _leaderboard_flow(t: TestContext) -> void:
	t.suite("flow: leaderboards over several runs")
	_fresh()
	var first: Dictionary = GameManager.finish_run(_result(500, 8, 3), null)
	var second: Dictionary = GameManager.finish_run(_result(300, 5, 0), null)
	var third: Dictionary = GameManager.finish_run(_result(900, 12, 4), null)
	t.eq(int(first["ranks"]["score"]), 1, "first run: rank 1")
	t.eq(int(second["ranks"]["score"]), 2, "a worse run ranks below")
	t.check(not bool(second["records"]["score"]), "and is no record")
	t.check(not bool(second["any_record"]), "so nothing is announced")
	t.eq(int(third["ranks"]["score"]), 1, "a better run takes rank 1")
	t.check(bool(third["records"]["score"]) and bool(third["records"]["floor"]) and bool(third["records"]["combo"]), "and counts as a record everywhere")
	var board: Array = LeaderboardManager.get_entries("score")
	t.eq(board.size(), 3, "three entries")
	t.eq(int((board[0] as Dictionary)["score"]), 900, "best first")
	t.eq(int((board[2] as Dictionary)["score"]), 300, "worst last")
	t.eq(int(StatisticsManager.get_int("personal_records")), 3 + 0 + 3, "personal records: 3 for the first run, 3 for the third")
	t.check(LeaderboardManager.would_be_record("score", 901), "901 would beat the best")
	t.check(not LeaderboardManager.would_be_record("score", 900), "a tie is not a record")
	t.check(not LeaderboardManager.would_be_record("score", 0), "zero is never a record")

	for i in range(25):
		GameManager.finish_run(_result(1000 + i, 3), null)
	t.eq(LeaderboardManager.get_entries("score").size(), 20, "boards keep the best 20")
	t.eq(int((LeaderboardManager.get_entries("score")[0] as Dictionary)["score"]), 1024, "the best of them all is on top")
	t.check(not SaveManager.is_dirty(), "every finished run is flushed")

	LeaderboardManager.clear_all()
	t.eq(LeaderboardManager.get_entries("score").size(), 0, "clearing empties the score board")
	t.eq(LeaderboardManager.get_entries("combo").size(), 0, "and the combo board")
	t.check(SaveManager.is_dirty(), "and marks the profile for saving")


func _unlock_flow(t: TestContext) -> void:
	t.suite("flow: character unlocks")
	_fresh()
	var summary: Dictionary = GameManager.finish_run(_result(12000, 60, 4), null)
	t.eq(JSON.stringify(summary["new_characters"]), JSON.stringify(["bolt", "nova"]), "floor 60 and 12000 points unlock Bolt and Nova")
	t.eq(",".join(_unlocked), "bolt,nova", "each unlock is announced on the event bus")
	t.check(CharacterManager.is_unlocked("bolt") and CharacterManager.is_unlocked("nova"), "both are usable")
	t.check(not CharacterManager.is_unlocked("ember"), "Ember needs floor 200")
	var progress: Dictionary = CharacterManager.unlock_progress("ember")
	t.eq(int(progress["current"]), 60, "progress towards Ember: current")
	t.eq(int(progress["target"]), 200, "progress towards Ember: target")
	var repeat: Dictionary = GameManager.finish_run(_result(100, 5), null)
	t.eq((repeat["new_characters"] as Array).size(), 0, "nothing is unlocked twice")
	t.eq(_unlocked.size(), 2, "and nothing is announced twice")

	t.check(CharacterManager.select("nova"), "an unlocked character can be selected")
	t.eq(CharacterManager.selected_id, "nova", "it is now selected")
	t.eq(String(SaveManager.data["selected_character"]), "nova", "and stored in the profile")
	t.check(not CharacterManager.select("zenith"), "a locked character cannot be selected")
	t.check(not CharacterManager.select("nobody"), "an unknown one neither")
	t.eq(CharacterManager.selected_id, "nova", "the selection is unchanged")

	# eight more runs make ten: Moss (10 runs) unlocks with the last one
	var moss_unlocked_at: int = 0
	for i in range(8):
		var s: Dictionary = GameManager.finish_run(_result(100, 5), null)
		if (s["new_characters"] as Array).has("moss"):
			moss_unlocked_at = StatisticsManager.get_int("games_played")
	t.eq(moss_unlocked_at, 10, "Moss unlocks with the tenth run")

	SaveManager.flush()
	SaveManager.load_all()
	t.eq(CharacterManager.selected_id, "nova", "the selection survives a restart")
	t.check(CharacterManager.is_unlocked("moss"), "so do the unlocks")

	SaveManager.data["selected_character"] = "zenith"
	SaveManager.loaded.emit()
	t.eq(CharacterManager.selected_id, "pip", "a locked character in the profile falls back to Pip")


func _replay_files(t: TestContext) -> void:
	t.suite("flow: replay files")
	_fresh()
	var a: ReplayData = _replay(1000, 3, 30)
	var b: ReplayData = _replay(3000, 7, 70)
	var c: ReplayData = _replay(2000, 5, 50)
	a.id = "flow_a"
	b.id = "flow_b"
	c.id = "flow_c"
	for r in [a, b, c]:
		t.eq(ReplayManager.save_replay(r), (r as ReplayData).id, "saving returns the id")
	t.eq(ReplayManager.count(), 3, "three replays")
	var ids: PackedStringArray = PackedStringArray()
	for m in ReplayManager.list_meta():
		ids.append(String((m as Dictionary)["id"]))
	t.eq(",".join(ids), "flow_b,flow_c,flow_a", "the list is newest first")
	t.check(_list_changes >= 3, "every change tells the UI")

	var loaded: Dictionary = ReplayManager.load_replay("flow_b")
	t.check(bool(loaded["ok"]), "a stored replay loads")
	var back: ReplayData = loaded["replay"]
	t.check(back.events == b.events, "with identical events")
	t.eq(back.score, 70, "and identical summary values")

	ReplayManager.rename_replay("flow_c", "   The Great Escape   ")
	t.eq(String(ReplayManager.find_meta("flow_c")["name"]), "The Great Escape", "renaming strips whitespace")
	t.eq((ReplayManager.load_replay("flow_c")["replay"] as ReplayData).replay_name, "The Great Escape", "the file header is renamed too")
	ReplayManager.rename_replay("flow_c", "x".repeat(60))
	t.eq(String(ReplayManager.find_meta("flow_c")["name"]).length(), 40, "names are limited to 40 characters")
	ReplayManager.rename_replay("missing_id", "Nothing")
	t.eq(ReplayManager.count(), 3, "renaming an unknown replay changes nothing")

	# a replay linked to a high score loses the link when deleted
	LeaderboardManager.submit_run(_result(700, 7, 2), "flow_a")
	t.eq(String((LeaderboardManager.get_entries("score")[0] as Dictionary)["replay_id"]), "flow_a", "the entry links its replay")
	ReplayManager.delete_replay("flow_a")
	t.check(not ReplayManager.has_replay("flow_a"), "deleting removes the file")
	t.eq(ReplayManager.find_meta("flow_a").size(), 0, "and the list entry")
	t.eq(String((LeaderboardManager.get_entries("score")[0] as Dictionary)["replay_id"]), "", "and the leaderboard link")
	t.eq(ReplayManager.count(), 2, "two left")

	# damaged files are reported, never crash
	var f: FileAccess = FileAccess.open(ReplayManager.replay_path("flow_b"), FileAccess.WRITE)
	f.store_string("this is not json {")
	f.close()
	var broken: Dictionary = ReplayManager.load_replay("flow_b")
	t.check(not bool(broken["ok"]) and not String(broken["error"]).is_empty(), "an unreadable replay gives an error message")
	t.check(not bool(ReplayManager.load_replay("never_saved")["ok"]), "a missing replay gives an error message")

	ReplayManager.delete_all()
	t.eq(ReplayManager.count(), 0, "delete all")
	t.check(not ReplayManager.has_replay("flow_c"), "delete all removes the files")


func _replay_sharing(t: TestContext) -> void:
	t.suite("flow: sharing replays as text")
	_fresh()
	var original: ReplayData = _replay(5000, 9, 90)
	original.id = "share_me"
	original.replay_name = "For a friend"
	ReplayManager.save_replay(original)
	var text: String = ReplayManager.export_text("share_me")
	t.check(not text.is_empty(), "a stored replay exports as text")
	t.eq(ReplayManager.export_text("nothing"), "", "an unknown replay exports nothing")

	var imported: Dictionary = ReplayManager.import_text(text)
	t.check(bool(imported["ok"]), "the text imports again: %s" % String(imported["error"]))
	var new_id: String = String(imported["id"])
	t.check(new_id != "share_me" and not new_id.is_empty(), "under a new id (%s)" % new_id)
	t.eq(ReplayManager.count(), 2, "the list has both")
	var again: Dictionary = ReplayManager.load_replay(new_id)
	t.check(bool(again["ok"]), "the imported replay loads")
	if bool(again["ok"]):
		t.check((again["replay"] as ReplayData).events == original.events, "with the same events")
		t.eq((again["replay"] as ReplayData).replay_name, "For a friend", "and the same name")

	t.check(not bool(ReplayManager.import_text("")["ok"]), "empty text is rejected")
	t.check(not bool(ReplayManager.import_text("hello")["ok"]), "plain text is rejected")
	t.check(not bool(ReplayManager.import_text("[1, 2, 3]")["ok"]), "JSON that is not an object is rejected")
	t.check(not bool(ReplayManager.import_text("{\"format\": \"something-else\"}")["ok"]), "a foreign format is rejected")
	t.check(not bool(ReplayManager.import_text("x".repeat(ReplayManager.MAX_IMPORT_CHARS + 1))["ok"]), "oversized text is rejected")
	t.eq(ReplayManager.count(), 2, "rejected imports change nothing")


func _replay_pruning(t: TestContext) -> void:
	t.suite("flow: old replays are pruned, precious ones are not")
	_fresh()
	for i in range(ReplayManager.MAX_REPLAYS):
		var r: ReplayData = _replay(1000 + i)
		r.id = "old_%03d" % i
		ReplayManager.save_replay(r)
	t.eq(ReplayManager.count(), ReplayManager.MAX_REPLAYS, "the limit is reached")
	ReplayManager.rename_replay("old_000", "Keep me")
	LeaderboardManager.submit_run(_result(800, 8, 2), "old_001")
	for i in range(3):
		var extra: ReplayData = _replay(5000 + i)
		extra.id = "new_%03d" % i
		ReplayManager.save_replay(extra)
	t.eq(ReplayManager.count(), ReplayManager.MAX_REPLAYS, "the count stays at the limit")
	t.check(ReplayManager.has_replay("old_000"), "a renamed replay is kept")
	t.check(ReplayManager.has_replay("old_001"), "a replay linked to a record is kept")
	t.check(not ReplayManager.has_replay("old_002") and not ReplayManager.has_replay("old_003") and not ReplayManager.has_replay("old_004"), "the oldest plain replays went first")
	t.check(ReplayManager.has_replay("old_005"), "the next oldest is still there")
	t.check(ReplayManager.has_replay("new_002"), "the newest replay is there")
	t.eq(ReplayManager.find_meta("old_002").size(), 0, "pruned replays leave the list")


func _recovery(t: TestContext) -> void:
	t.suite("flow: a run interrupted by the OS is credited on the next launch")
	_fresh()
	var bot: Dictionary = _bot()
	var seed_value: int = int(bot["seed"])
	var live: Dictionary = _live(bot["plan"], seed_value, 2600)
	var run: RunManager = live["run"]
	t.check(not run.dead and run.tick_count == 2600, "the run was still going when the app was interrupted")
	var rec: ReplayRecorder = live["rec"]
	var snapshot: ReplayData = rec.snapshot(run.build_result())
	# what playback of that snapshot will produce (the combo still running is settled like a quit)
	var expected: Dictionary = ReplayPlayer.new(rec.snapshot(run.build_result())).simulate_all()

	GameManager.write_interrupted_snapshot(snapshot)
	t.check(ReplayManager.has_autosave(), "the app going to the background stores an autosave")
	t.check(not SaveManager.section("active_run").is_empty(), "and marks a run as active in the profile")
	t.check(not SaveManager.is_dirty(), "the profile was flushed immediately")
	t.eq(LeaderboardManager.get_entries("score").size(), 0, "nothing is credited yet")

	GameManager.recover_interrupted_run()
	t.check(not ReplayManager.has_autosave(), "recovery consumes the autosave")
	t.check(SaveManager.section("active_run").is_empty(), "and clears the marker")
	t.eq(StatisticsManager.get_int("games_played"), 1, "the run counts as played")
	var entries: Array = LeaderboardManager.get_entries("score")
	t.eq(entries.size(), 1, "and appears on the leaderboard")
	if entries.size() == 1:
		t.eq(int((entries[0] as Dictionary)["score"]), int(expected["score"]), "with the score the recorded inputs produce")
		t.eq(int((entries[0] as Dictionary)["seed"]), seed_value, "and its seed")
	t.eq(ReplayManager.count(), 1, "the replay is kept")
	t.check(_toasts.size() == 1 and _toasts[0].begins_with("Recovered your interrupted run"), "the player is told (%s)" % ("; ".join(_toasts)))

	# nothing to recover
	_toasts.clear()
	GameManager.recover_interrupted_run()
	t.eq(StatisticsManager.get_int("games_played"), 1, "with no marker nothing happens")
	t.eq(_toasts.size(), 0, "and nobody is told")

	# a marker without a file, a damaged autosave and a replay from another simulation version are dropped quietly
	SaveManager.data["active_run"] = {"replay_id": ReplayManager.AUTOSAVE_ID, "saved_at": 1}
	GameManager.recover_interrupted_run()
	t.check(SaveManager.section("active_run").is_empty(), "a marker without an autosave file is cleared")

	var f: FileAccess = FileAccess.open(ReplayManager.replay_path(ReplayManager.AUTOSAVE_ID), FileAccess.WRITE)
	f.store_string("{ damaged")
	f.close()
	SaveManager.data["active_run"] = {"replay_id": ReplayManager.AUTOSAVE_ID, "saved_at": 1}
	GameManager.recover_interrupted_run()
	t.check(SaveManager.section("active_run").is_empty() and not ReplayManager.has_autosave(), "a damaged autosave is discarded")

	var stale: ReplayData = rec.snapshot(run.build_result())
	stale.sim_version = SimConst.SIM_VERSION + 1
	GameManager.write_interrupted_snapshot(stale)
	GameManager.recover_interrupted_run()
	t.check(SaveManager.section("active_run").is_empty() and not ReplayManager.has_autosave(), "an autosave from another simulation version is discarded")
	t.eq(StatisticsManager.get_int("games_played"), 1, "none of these credited anything")
	t.eq(_toasts.size(), 0, "or showed a message")


func _settings(t: TestContext) -> void:
	t.suite("flow: settings")
	_fresh()
	t.eq(SettingsManager.get_string("control_mode"), "touch", "touch is the default control scheme")
	t.near(SettingsManager.get_float("vol_master"), 1.0, 1e-9, "default master volume")
	t.eq(SettingsManager.get_int("touch_min_hold_ms"), 50, "default minimum hold")
	t.check(SettingsManager.get_bool("haptics"), "haptics are on by default")

	SettingsManager.set_value("vol_master", 5.0)
	t.near(SettingsManager.get_float("vol_master"), 1.0, 1e-9, "volume is clamped to 1")
	SettingsManager.set_value("vol_music", -3)
	t.near(SettingsManager.get_float("vol_music"), 0.0, 1e-9, "and to 0")
	SettingsManager.set_value("touch_min_hold_ms", 9999)
	t.eq(SettingsManager.get_int("touch_min_hold_ms"), 300, "the minimum hold is limited")
	SettingsManager.set_value("control_mode", "banana")
	t.eq(SettingsManager.get_string("control_mode"), "touch", "an unknown control scheme falls back to touch")
	SettingsManager.set_value("tilt_preset", "ludicrous")
	t.eq(SettingsManager.get_string("tilt_preset"), "medium", "an unknown tilt preset falls back to medium")
	SettingsManager.set_value("player_name", "   ")
	t.eq(SettingsManager.get_string("player_name"), "Climber", "an empty name falls back to the default")
	SettingsManager.set_value("player_name", "  Ada Lovelace The Very Long  ")
	t.eq(SettingsManager.get_string("player_name"), "Ada Lovelace T", "names are trimmed and limited to 14 characters")
	SettingsManager.set_value("haptics", 0)
	t.check(not SettingsManager.get_bool("haptics"), "numbers convert to booleans")
	SettingsManager.set_value("vol_sfx", "loud")
	t.near(SettingsManager.get_float("vol_sfx"), 1.0, 1e-9, "a wrong type keeps the default")

	_setting_events.clear()
	SettingsManager.set_value("vol_sfx", 0.4)
	SettingsManager.set_value("vol_sfx", 0.4)
	t.eq(",".join(_setting_events), "vol_sfx", "a change is announced once (setting the same value again is silent)")

	SettingsManager.set_value("tilt_calibrated", true)
	SettingsManager.set_value("tilt_neutral_deg", 12.5)
	SettingsManager.reset_calibration()
	t.check(not SettingsManager.get_bool("tilt_calibrated"), "resetting the calibration clears the flag")
	t.near(SettingsManager.get_float("tilt_neutral_deg"), 0.0, 1e-9, "and the neutral angle")

	var tuning: GameTuning = GameTuning.new()
	SettingsManager.set_value("tilt_preset", "low")
	t.near(SettingsManager.tilt_full_degrees(tuning), tuning.tilt_full_deg_low, 1e-9, "the tilt preset selects the sensitivity")
	SettingsManager.set_value("tilt_preset", "custom")
	SettingsManager.set_value("tilt_custom_deg", 30.0)
	t.near(SettingsManager.tilt_full_degrees(tuning), 30.0, 1e-9, "custom sensitivity")

	SettingsManager.reset_to_defaults()
	t.near(SettingsManager.get_float("vol_sfx"), 1.0, 1e-9, "reset restores the defaults")
	t.eq(SettingsManager.get_string("tilt_preset"), "medium", "including the tilt preset")

	# damaged values in the profile are sanitised on load
	SaveManager.data["settings"] = {"vol_master": "very loud", "control_mode": 42, "touch_scale": 99.0, "player_name": 7}
	SaveManager.loaded.emit()
	t.near(SettingsManager.get_float("vol_master"), 1.0, 1e-9, "a text volume becomes the default")
	t.eq(SettingsManager.get_string("control_mode"), "touch", "a number as control scheme becomes the default")
	t.near(SettingsManager.get_float("touch_scale"), 1.6, 1e-9, "an absurd scale is clamped")
	t.eq(SettingsManager.get_string("player_name"), "Climber", "a number as name becomes the default")


func _restart(t: TestContext) -> void:
	t.suite("flow: everything survives an app restart")
	_fresh()
	SettingsManager.set_value("vol_music", 0.25)
	SettingsManager.set_value("player_name", "Restarter")
	SettingsManager.set_value("touch_swap", true)
	var bot: Dictionary = _bot()
	var live: Dictionary = _live(bot["plan"], int(bot["seed"]), 3000)
	var result: Dictionary = (live["run"] as RunManager).abandon()
	var replay: ReplayData = (live["rec"] as ReplayRecorder).finish(result, true)
	var summary: Dictionary = GameManager.finish_run(result, replay)
	ReplayManager.save_replay(replay)
	ReplayManager.rename_replay(String(summary["replay_id"]), "Before the restart")
	SaveManager.flush()

	SaveManager.load_all()
	t.eq(SaveManager.loaded_from, "main", "the profile is read from the main file")
	t.near(SettingsManager.get_float("vol_music"), 0.25, 1e-9, "settings survive")
	t.eq(SettingsManager.get_string("player_name"), "Restarter", "the player name survives")
	t.check(SettingsManager.get_bool("touch_swap"), "booleans survive")
	t.eq(StatisticsManager.get_int("games_played"), 1, "statistics survive")
	t.eq(StatisticsManager.get_int("highest_floor"), int(result["highest_floor"]), "including the highest floor")
	var entries: Array = LeaderboardManager.get_entries("score")
	t.eq(entries.size(), 1, "the leaderboard survives")
	if entries.size() == 1:
		t.eq(int((entries[0] as Dictionary)["score"]), int(result["score"]), "with the exact score")
		t.check(typeof((entries[0] as Dictionary)["score"]) == TYPE_INT, "as an integer (JSON only knows floats)")
	t.eq(ReplayManager.count(), 1, "the replay list survives")
	t.eq(String(ReplayManager.list_meta()[0]["name"]), "Before the restart", "with its name")
	t.check(ReplayManager.has_replay(String(summary["replay_id"])), "and the replay file")

	# a restart with a damaged main file recovers from the backup
	SettingsManager.set_value("vol_music", 0.5)
	SaveManager.flush()
	var f: FileAccess = FileAccess.open(SaveManager.main_path, FileAccess.WRITE)
	f.store_string("not a profile")
	f.close()
	SaveManager.load_all()
	t.eq(SaveManager.loaded_from, "backup", "a damaged main file falls back to the backup")
	t.eq(StatisticsManager.get_int("games_played"), 1, "the records are not lost")
	t.check(FileAccess.file_exists(SaveManager.dir_path + "/profile.corrupt.json"), "the damaged file is kept for inspection")

	# wiping everything
	SaveManager.reset_all()
	t.eq(StatisticsManager.get_int("games_played"), 0, "reset: statistics")
	t.eq(LeaderboardManager.get_entries("score").size(), 0, "reset: leaderboards")
	t.eq(CharacterManager.selected_id, "pip", "reset: character")
