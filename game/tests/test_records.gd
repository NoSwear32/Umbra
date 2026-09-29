extends RefCounted
## Local leaderboards (ranking, ties, trimming, record flags, persistence, provider interface)
## and lifetime statistics.


class Counter:
	extends RefCounted
	var changes: int = 0

	func on_changed() -> void:
		changes += 1


## A stand-in for a future online back end: offline it queues submissions and never blocks.
class FakeOnline:
	extends LeaderboardProvider
	var queue: Array = []
	var synced: int = 0

	func provider_id() -> String:
		return "fake_online"

	func is_online() -> bool:
		return true

	func submit(entry: Dictionary) -> Dictionary:
		queue.append(entry)
		return {}

	func pending_count() -> int:
		return queue.size()

	func sync() -> void:
		synced += queue.size()
		queue.clear()


func run(t: TestContext) -> void:
	_ranking(t)
	_records(t)
	_trimming(t)
	_persistence(t)
	_interface(t)
	_statistics(t)


func _entry(score: int, floor_index: int, combo: int, player_name: String = "Tester") -> Dictionary:
	return {
		"name": player_name,
		"score": score,
		"floor": floor_index,
		"combo": combo,
		"combo_jumps": 0,
		"date": 1700000000,
		"duration": 60.0,
		"replay_id": "",
		"character": "pip",
		"seed": 1,
		"control": "touch",
	}


func _scores(p: LocalLeaderboardProvider, category: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for e in p.get_entries(category):
		out.append(LeaderboardProvider.value_of(e, category))
	return out


func _ranking(t: TestContext) -> void:
	t.suite("leaderboard: ranking and ties")
	var p: LocalLeaderboardProvider = LocalLeaderboardProvider.new({})
	t.eq(p.get_entries("score").size(), 0, "a new leaderboard is empty")
	t.eq(p.best_value("score"), 0, "and has no best value")
	t.eq(p.rank_for("score", 0), 0, "zero never ranks")
	t.eq(p.rank_for("score", -10), 0, "negative values never rank")
	t.eq(p.rank_for("score", 50), 1, "the first positive value takes rank 1")
	t.eq(p.get_entries("nonsense").size(), 0, "unknown categories are empty")

	var r1: Dictionary = p.submit(_entry(500, 12, 0, "A"))
	t.eq(int(r1["score"]), 1, "the first run is rank 1 by score")
	t.eq(int(r1["floor"]), 1, "and rank 1 by floor")
	t.eq(int(r1["combo"]), 0, "a run without a combo does not enter the combo list")
	p.submit(_entry(800, 20, 4, "B"))
	p.submit(_entry(300, 5, 2, "C"))
	t.eq(_scores(p, "score"), PackedInt32Array([800, 500, 300]), "scores are sorted best first")
	t.eq(_scores(p, "floor"), PackedInt32Array([20, 12, 5]), "floors are sorted best first")
	t.eq(_scores(p, "combo"), PackedInt32Array([4, 2]), "combos are sorted best first (zero excluded)")

	var r2: Dictionary = p.submit(_entry(500, 3, 0, "D"))
	t.eq(int(r2["score"]), 3, "a tie ranks behind the run that got there first")
	var names: PackedStringArray = PackedStringArray()
	for e in p.get_entries("score"):
		names.append(String(e["name"]))
	t.eq(",".join(names), "B,A,D,C", "the older run keeps its place on a tie")
	t.eq(p.best_value("score"), 800, "best value is the top entry")
	t.eq(p.best_value("floor"), 20, "best floor")
	t.eq(p.best_value("combo"), 4, "best combo")

	# the categories are independent
	var r3: Dictionary = p.submit(_entry(100, 30, 0, "E"))
	t.eq(int(r3["score"]), 5, "a low score still ranks in a short list")
	t.eq(int(r3["floor"]), 1, "but its floor tops the floor list")
	t.eq(int(r3["combo"]), 0, "and it has no combo")


func _records(t: TestContext) -> void:
	t.suite("leaderboard: personal record flags")
	var p: LocalLeaderboardProvider = LocalLeaderboardProvider.new({})
	var first: Dictionary = p.submit(_entry(400, 10, 3))
	var rec1: Dictionary = first["records"]
	t.check(bool(rec1["score"]) and bool(rec1["floor"]) and bool(rec1["combo"]), "the first run sets records in every category")
	var equal: Dictionary = p.submit(_entry(400, 10, 3))
	var rec2: Dictionary = equal["records"]
	t.check(not bool(rec2["score"]) and not bool(rec2["floor"]) and not bool(rec2["combo"]), "matching the best is not a new record")
	var mixed: Dictionary = p.submit(_entry(350, 14, 2))
	var rec3: Dictionary = mixed["records"]
	t.check(not bool(rec3["score"]), "a lower score is not a record")
	t.check(bool(rec3["floor"]), "a higher floor is a record")
	t.check(not bool(rec3["combo"]), "a shorter combo is not a record")
	t.eq(int(mixed["score"]), 3, "it still ranks (third by score)")
	var none: Dictionary = p.submit(_entry(0, 0, 0))
	var rec4: Dictionary = none["records"]
	t.check(not bool(rec4["score"]) and not bool(rec4["floor"]) and not bool(rec4["combo"]), "an empty run never sets a record")
	t.eq(p.get_entries("score").size(), 3, "and is not stored")

	var counter: Counter = Counter.new()
	p.on_changed = counter.on_changed
	p.submit(_entry(999, 1, 1))
	t.eq(counter.changes, 1, "a submission notifies the owner once (so the profile is saved)")
	p.clear()
	t.eq(counter.changes, 2, "clearing notifies as well")
	t.eq(p.get_entries("score").size() + p.get_entries("floor").size() + p.get_entries("combo").size(), 0, "clear empties every list")


func _trimming(t: TestContext) -> void:
	t.suite("leaderboard: list length")
	var p: LocalLeaderboardProvider = LocalLeaderboardProvider.new({})
	var order: Array = [7, 3, 12, 1, 25, 9, 18, 4, 22, 15, 6, 20, 2, 24, 11, 5, 19, 8, 23, 14, 10, 21, 13, 16, 17]
	for k in order:
		p.submit(_entry(int(k) * 100, int(k), 0))
	var scores: PackedInt32Array = _scores(p, "score")
	t.eq(scores.size(), LocalLeaderboardProvider.MAX_ENTRIES, "the list keeps only the best %d runs" % LocalLeaderboardProvider.MAX_ENTRIES)
	t.eq(scores[0], 2500, "the best run leads")
	t.eq(scores[scores.size() - 1], 600, "the weakest surviving run is the 20th best")
	var sorted_ok: bool = true
	for i in range(1, scores.size()):
		if scores[i] > scores[i - 1]:
			sorted_ok = false
	t.check(sorted_ok, "the trimmed list is still sorted")
	var below: Dictionary = p.submit(_entry(50, 1, 0))
	t.eq(int(below["score"]), 0, "a run below the cut does not place")
	t.eq(_scores(p, "score").size(), LocalLeaderboardProvider.MAX_ENTRIES, "and nothing changes")
	var tie_cut: Dictionary = p.submit(_entry(600, 1, 0))
	t.eq(int(tie_cut["score"]), 0, "tying the last place does not displace it")
	var enter: Dictionary = p.submit(_entry(700, 1, 0))
	t.eq(int(enter["score"]), 20, "a run just above the cut takes the last place")
	var after: PackedInt32Array = _scores(p, "score")
	t.eq(after[after.size() - 1], 700, "and pushes the old last place out")
	t.eq(after.size(), LocalLeaderboardProvider.MAX_ENTRIES, "the length stays at the limit")


func _persistence(t: TestContext) -> void:
	t.suite("leaderboard: persistence and damaged data")
	var storage: Dictionary = {}
	var p: LocalLeaderboardProvider = LocalLeaderboardProvider.new(storage)
	p.submit(_entry(1234, 21, 5, "Saved"))
	p.submit(_entry(999, 30, 7, "Second"))
	var text: String = JSON.stringify(storage)
	var json: JSON = JSON.new()
	t.eq(json.parse(text), OK, "the leaderboard serialises to JSON")
	var loaded: Dictionary = json.data
	var p2: LocalLeaderboardProvider = LocalLeaderboardProvider.new(loaded)
	var top: Dictionary = p2.get_entries("score")[0]
	t.eq(typeof(top["score"]), TYPE_INT, "scores are integers again after loading JSON")
	t.eq(typeof(top["seed"]), TYPE_INT, "seeds are integers again after loading JSON")
	t.eq(int(top["score"]), 1234, "the best score survives")
	t.eq(String(top["name"]), "Saved", "and the player name")
	t.eq(_scores(p2, "floor"), PackedInt32Array([30, 21]), "the floor list survives")
	t.eq(p2.rank_for("score", 1000), 2, "ranking works on loaded data")

	# damaged / hand-edited profile: nothing crashes and the lists are repaired
	var damaged: Dictionary = {
		"score": [5, "x", null, {"score": 12}, {"score": 40, "name": "Ok"}, {"score": -3}, {"score": 0}],
		"floor": "not a list",
	}
	var p3: LocalLeaderboardProvider = LocalLeaderboardProvider.new(damaged)
	t.eq(_scores(p3, "score"), PackedInt32Array([40, 12]), "junk entries are dropped and the rest is sorted")
	t.eq(p3.get_entries("floor").size(), 0, "a non-list category is reset")
	t.eq(p3.get_entries("combo").size(), 0, "missing categories are created")
	var repaired: Dictionary = p3.get_entries("score")[1]
	t.eq(String(repaired["name"]), "Climber", "entries without a name get the default")
	p3.submit(_entry(20, 2, 0))
	t.eq(_scores(p3, "score"), PackedInt32Array([40, 20, 12]), "new runs slot into the repaired list")

	# an overlong list from a build with a different limit is trimmed on load
	var long_list: Array = []
	for i in range(30):
		long_list.append({"score": 100 + i})
	var p4: LocalLeaderboardProvider = LocalLeaderboardProvider.new({"score": long_list})
	t.eq(_scores(p4, "score").size(), LocalLeaderboardProvider.MAX_ENTRIES, "an oversized list is trimmed")
	t.eq(_scores(p4, "score")[0], 129, "keeping the best entries")

	# callers can never edit the stored data by accident
	var view: Array = p2.get_entries("score")
	(view[0] as Dictionary)["score"] = 1
	t.eq(int(p2.get_entries("score")[0]["score"]), 1234, "get_entries returns copies")


func _interface(t: TestContext) -> void:
	t.suite("leaderboard: provider interface")
	var base: LeaderboardProvider = LeaderboardProvider.new()
	t.eq(base.provider_id(), "abstract", "the base provider is abstract")
	t.check(not base.is_online(), "the base provider is offline")
	t.eq(base.get_entries("score").size(), 0, "and has no entries")
	t.check(base.submit(_entry(1, 1, 1)).is_empty(), "submitting to it is harmless")
	t.eq(base.pending_count(), 0, "and nothing is pending")
	var local: LocalLeaderboardProvider = LocalLeaderboardProvider.new({})
	t.eq(local.provider_id(), "local", "the local provider identifies itself")
	t.check(not local.is_online(), "the local provider works fully offline")
	t.eq(LeaderboardProvider.value_of({"score": 5, "floor": 6, "combo": 7}, "score"), 5, "value_of score")
	t.eq(LeaderboardProvider.value_of({"score": 5, "floor": 6, "combo": 7}, "floor"), 6, "value_of floor")
	t.eq(LeaderboardProvider.value_of({"score": 5, "floor": 6, "combo": 7}, "combo"), 7, "value_of combo")
	t.eq(LeaderboardProvider.value_of({"score": 5}, "other"), 0, "value_of an unknown category")
	t.eq(LeaderboardProvider.CATEGORIES.size(), 3, "score, floor and combo boards exist")

	# an online provider can be added later without touching the local one
	var online: FakeOnline = FakeOnline.new()
	var providers: Array = [local, online]
	var local_result: Dictionary = {}
	for prov in providers:
		var p: LeaderboardProvider = prov
		var r: Dictionary = p.submit(_entry(700, 9, 2))
		if p == local:
			local_result = r
	t.eq(int(local_result["score"]), 1, "the local result is unaffected by other providers")
	t.eq(online.pending_count(), 1, "the online provider queued the submission")
	online.sync()
	t.eq(online.pending_count(), 0, "and flushes it when connectivity returns")
	t.eq(online.synced, 1, "exactly once")


func _statistics(t: TestContext) -> void:
	t.suite("statistics")
	var shared: Dictionary = {}
	var s: StatsData = StatsData.new(shared)
	for key in StatsData.DEFAULTS:
		t.check(shared.has(key), "default stat exists: %s" % String(key))
	t.eq(typeof(shared["games_played"]), TYPE_INT, "counters are integers")
	t.eq(typeof(shared["total_playtime_seconds"]), TYPE_FLOAT, "durations are floats")

	var from_json: StatsData = StatsData.new({"games_played": 3.0, "highest_floor": 12.0, "longest_run_seconds": 90, "unknown_future_stat": 5})
	t.eq(typeof(from_json.values["games_played"]), TYPE_INT, "loaded counters are integers again")
	t.eq(typeof(from_json.values["longest_run_seconds"]), TYPE_FLOAT, "loaded durations are floats again")
	t.eq(from_json.get_int("highest_floor"), 12, "loaded values survive")
	t.eq(int(from_json.values["unknown_future_stat"]), 5, "unknown stats are left alone")
	t.eq(from_json.get_int("no_such_stat"), 0, "unknown stats read as zero")

	var run1: Dictionary = {
		"jumps": 40, "highest_floor": 20, "combo_jumps": 5, "combos_completed": 2, "wall_rebounds": 7,
		"duration": 65.5, "score": 1200, "best_combo_floors": 9, "best_combo_jumps": 3,
	}
	t.check(s.record_run(run1, 1), "a normal run is recorded")
	t.eq(shared["games_played"], 1, "games played")
	t.eq(shared["total_jumps"], 40, "total jumps")
	t.eq(shared["total_floors_climbed"], 20, "total floors")
	t.eq(shared["total_combo_jumps"], 5, "combo jumps")
	t.eq(shared["combos_completed"], 2, "combos completed")
	t.eq(shared["wall_rebounds"], 7, "wall rebounds")
	t.eq(shared["personal_records"], 1, "personal records")
	t.eq(shared["highest_floor"], 20, "highest floor")
	t.eq(shared["highest_score"], 1200, "highest score")
	t.eq(shared["longest_combo"], 9, "longest combo")
	t.eq(shared["longest_combo_jumps"], 3, "longest combo jumps")
	t.near(float(shared["longest_run_seconds"]), 65.5, 1e-9, "longest run")
	t.near(float(shared["total_playtime_seconds"]), 65.5, 1e-9, "playtime")

	var run2: Dictionary = {
		"jumps": 10, "highest_floor": 8, "combo_jumps": 0, "combos_completed": 0, "wall_rebounds": 1,
		"duration": 30.0, "score": 300, "best_combo_floors": 0, "best_combo_jumps": 0,
	}
	s.record_run(run2, 0)
	t.eq(shared["games_played"], 2, "the second run is counted")
	t.eq(shared["total_jumps"], 50, "totals accumulate")
	t.eq(shared["total_floors_climbed"], 28, "floors accumulate")
	t.eq(shared["highest_floor"], 20, "a weaker run does not lower the maximum")
	t.eq(shared["highest_score"], 1200, "nor the best score")
	t.eq(shared["longest_combo"], 9, "nor the longest combo")
	t.near(float(shared["longest_run_seconds"]), 65.5, 1e-9, "nor the longest run")
	t.near(float(shared["total_playtime_seconds"]), 95.5, 1e-9, "playtime accumulates")
	t.eq(shared["personal_records"], 1, "no new record, no new count")
	var run3: Dictionary = {"jumps": 1, "highest_floor": 45, "duration": 200.0, "score": 5000, "best_combo_floors": 14, "best_combo_jumps": 4}
	s.record_run(run3, 3)
	t.eq(shared["highest_floor"], 45, "a stronger run raises the maximum")
	t.near(float(shared["longest_run_seconds"]), 200.0, 1e-9, "and the longest run")
	t.eq(shared["personal_records"], 4, "new records are added up")

	var before: String = JSON.stringify(shared, "", true)
	var practice: Dictionary = run3.duplicate()
	practice["practice"] = true
	t.check(not s.record_run(practice, 3), "practice runs are not recorded")
	var debug_run: Dictionary = run3.duplicate()
	debug_run["debug_used"] = true
	t.check(not s.record_run(debug_run, 3), "runs that used debug tools are not recorded")
	t.eq(JSON.stringify(shared, "", true), before, "ignored runs leave every statistic untouched")

	s.reset()
	t.eq(shared["games_played"], 0, "reset clears the counters")
	t.eq(shared["highest_score"], 0, "and the maxima")
	t.near(float(shared["total_playtime_seconds"]), 0.0, 1e-12, "and the durations")
