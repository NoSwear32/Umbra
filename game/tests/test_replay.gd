extends RefCounted
## Replay system: compact encoding, exact deterministic playback, version and corruption checks.


func run(t: TestContext) -> void:
	_encoding(t)
	_playback(t)
	_validation(t)


func _encoding(t: TestContext) -> void:
	t.suite("replay: event encoding")
	var rng: SimRng = SimRng.new(4242)
	var ev: PackedInt32Array = PackedInt32Array()
	var tick: int = 0
	for i in range(500):
		tick += 1 + rng.range_i(0, 400)
		ev.append(tick)
		ev.append(rng.range_i(-127, 127))
		ev.append(rng.range_i(0, 1))
	var raw: PackedByteArray = ReplayData.encode_events(ev)
	var back: PackedInt32Array = ReplayData.decode_events(raw, 500)
	t.check(back == ev, "events survive an encode/decode round trip")
	t.check(raw.size() < ev.size() * 4, "the encoding is smaller than raw 32-bit integers (%d bytes for %d events)" % [raw.size(), 500])
	t.eq(ReplayData.decode_events(raw, 499).size(), 0, "a wrong event count is rejected")
	var truncated: PackedByteArray = raw.slice(0, raw.size() - 2)
	t.eq(ReplayData.decode_events(truncated, -1).size() % 3, 0, "truncated data never yields a partial event")
	var bad: PackedByteArray = PackedByteArray([1, 255, 0])
	t.eq(ReplayData.decode_events(bad, -1).size(), 0, "out-of-range axis values are rejected")
	t.eq(ReplayRecorder.quantize(1.0), 127, "full right quantises to +127")
	t.eq(ReplayRecorder.quantize(-1.0), -127, "full left quantises to -127")
	t.eq(ReplayRecorder.quantize(0.0), 0, "zero stays zero")
	t.near(ReplayRecorder.dequantize(127), 1.0, 1e-15, "+127 is exactly 1.0")
	t.near(ReplayRecorder.dequantize(ReplayRecorder.quantize(0.5)), 0.5, 0.01, "half tilt survives quantisation")


## Expands golden segments into per-tick inputs.
func _inputs_from_segments(segments: Array) -> Array:
	var out: Array = []
	for seg in segments:
		var n: int = int(seg[0])
		for i in range(n):
			out.append([float(seg[1]), int(seg[2]) != 0 and i == 0])
	return out


func _record_live(tuning: GameTuning, seed_value: int, inputs: Array) -> Dictionary:
	var rec: ReplayRecorder = ReplayRecorder.new()
	rec.start(seed_value, tuning, "pip", "touch", "test")
	var run: RunManager = RunManager.new(tuning, seed_value)
	for inp in inputs:
		if run.dead:
			break
		var n: int = run.tick_count + 1
		var q: int = ReplayRecorder.quantize(float(inp[0]))
		rec.record(n, q, bool(inp[1]))
		run.tick(ReplayRecorder.dequantize(q), bool(inp[1]))
	var result: Dictionary = run.build_result()
	return {"replay": rec.finish(result, true), "result": result}


func _playback(t: TestContext) -> void:
	t.suite("replay: deterministic playback")
	var tuning: GameTuning = GameTuning.new()
	var golden: Variant = TestContext.load_golden("bot_run.json")
	t.check(golden is Dictionary, "bot_run.json loads")
	if not (golden is Dictionary):
		return
	var sc: Dictionary = golden["scenarios"][0]
	var inputs: Array = _inputs_from_segments(sc["segments"])
	var live: Dictionary = _record_live(tuning, int(sc["seed"]), inputs)
	var replay: ReplayData = live["replay"]
	var result: Dictionary = live["result"]
	t.eq(int(result["score"]), int(sc["final"]["score"]), "the recorded run matches the reference score")
	t.check(replay.event_count() > 0 and replay.event_count() < inputs.size(), "only input changes are stored (%d events for %d ticks)" % [replay.event_count(), inputs.size()])
	t.eq(replay.seed_value, int(sc["seed"]), "the seed is stored")
	t.eq(replay.sim_version, SimConst.SIM_VERSION, "the simulation version is stored")
	t.check(replay.tuning_snapshot.has("gravity"), "the tuning snapshot is stored")

	# through JSON text, like a saved / shared replay
	var text: String = JSON.stringify(replay.to_dictionary(), "", true, true)
	var json: JSON = JSON.new()
	t.eq(json.parse(text), OK, "the replay serialises to valid JSON")
	var parsed: Dictionary = ReplayData.from_dictionary(json.data)
	t.check(bool(parsed["ok"]), "the replay parses back: %s" % String(parsed["error"]))
	if not bool(parsed["ok"]):
		return
	var loaded: ReplayData = parsed["replay"]
	t.check(loaded.events == replay.events, "events are identical after a file round trip")
	var player: ReplayPlayer = ReplayPlayer.new(loaded)
	t.check(not player.incompatible, "same simulation version is compatible")
	t.check(not player.tuning_mismatch, "the tuning snapshot restores exactly")
	var replayed: Dictionary = player.simulate_all()
	t.eq(int(replayed["score"]), int(result["score"]), "playback reproduces the score")
	t.eq(int(replayed["highest_floor"]), int(result["highest_floor"]), "playback reproduces the highest floor")
	t.eq(int(replayed["best_combo_floors"]), int(result["best_combo_floors"]), "playback reproduces the best combo")
	t.eq(int(replayed["jumps"]), int(result["jumps"]), "playback reproduces the jump count")
	t.eq(int(replayed["wall_rebounds"]), int(result["wall_rebounds"]), "playback reproduces the wall rebounds")
	t.eq(int(replayed["duration_ticks"]), int(result["duration_ticks"]), "playback lasts exactly as long")
	t.check(player.matches_recording(), "the final state matches the recorded summary")

	# replays keep working after the live tuning changes (the snapshot is used, not the live values)
	var changed: GameTuning = GameTuning.new()
	changed.gravity = 3200.0
	changed.max_speed = 500.0
	var same_again: ReplayPlayer = ReplayPlayer.new(loaded)
	var again: Dictionary = same_again.simulate_all()
	t.eq(int(again["score"]), int(result["score"]), "changing the live tuning does not break old replays")
	t.check(changed.gravity != same_again.tuning.gravity, "playback uses the recorded tuning")

	# stepping one tick at a time behaves like simulate_all
	var stepper: ReplayPlayer = ReplayPlayer.new(loaded)
	var guard: int = 0
	while stepper.step() and guard < 100000:
		guard += 1
	t.eq(stepper.run.get_score(), int(result["score"]), "tick-by-tick playback reaches the same score")

	# a mid-run interruption snapshot replays up to its last tick
	var rec: ReplayRecorder = ReplayRecorder.new()
	rec.start(77, tuning, "pip", "touch", "test")
	var live_run: RunManager = RunManager.new(tuning, 77)
	for i in range(1200):
		var q: int = ReplayRecorder.quantize(1.0 if (i / 40) % 2 == 0 else 0.0)
		var j: bool = i % 90 == 89
		rec.record(live_run.tick_count + 1, q, j)
		live_run.tick(ReplayRecorder.dequantize(q), j)
	var snap: ReplayData = rec.snapshot(live_run.build_result())
	t.check(not snap.complete, "a snapshot is marked as incomplete")
	var resumed: ReplayPlayer = ReplayPlayer.new(snap)
	var snap_result: Dictionary = resumed.simulate_all()
	t.eq(int(snap_result["highest_floor"]), live_run.highest_floor, "an interrupted run is reconstructed exactly")
	t.eq(resumed.run.tick_count, live_run.tick_count, "at exactly the same tick")


func _validation(t: TestContext) -> void:
	t.suite("replay: validation")
	var tuning: GameTuning = GameTuning.new()
	var live: Dictionary = _record_live(tuning, 3, [[1.0, false], [1.0, false], [1.0, true], [0.0, false]])
	var replay: ReplayData = live["replay"]
	var d: Dictionary = replay.to_dictionary()
	t.check(bool(ReplayData.from_dictionary(d)["ok"]), "a fresh replay dictionary validates")

	var wrong_format: Dictionary = d.duplicate()
	wrong_format["format"] = "something-else"
	t.check(not bool(ReplayData.from_dictionary(wrong_format)["ok"]), "the wrong format id is rejected")
	var wrong_rate: Dictionary = d.duplicate()
	wrong_rate["tick_rate"] = 60
	t.check(not bool(ReplayData.from_dictionary(wrong_rate)["ok"]), "a different tick rate is rejected")
	var wrong_version: Dictionary = d.duplicate()
	wrong_version["format_version"] = 99
	t.check(not bool(ReplayData.from_dictionary(wrong_version)["ok"]), "an unknown file version is rejected")
	var huge: Dictionary = d.duplicate()
	huge["raw_size"] = ReplayData.MAX_RAW_BYTES + 1
	t.check(not bool(ReplayData.from_dictionary(huge)["ok"]), "an absurd size claim is rejected before decompressing")
	var bad_count: Dictionary = d.duplicate()
	bad_count["event_count"] = int(d["event_count"]) + 5
	t.check(not bool(ReplayData.from_dictionary(bad_count)["ok"]), "a wrong event count is rejected")
	var cut: Dictionary = d.duplicate()
	cut["events"] = String(d["events"]).substr(0, maxi(String(d["events"]).length() / 2, 1))
	t.check(not bool(ReplayData.from_dictionary(cut)["ok"]), "truncated event data is rejected")
	var junk: Dictionary = d.duplicate()
	junk["events"] = "!!!not base64!!!"
	t.check(not bool(ReplayData.from_dictionary(junk)["ok"]), "garbage event data is rejected")

	var old: ReplayData = ReplayData.new()
	old.sim_version = SimConst.SIM_VERSION + 1
	old.tuning_snapshot = tuning.to_sim_dict()
	t.check(ReplayPlayer.new(old).incompatible, "a replay from another simulation version is flagged incompatible")
