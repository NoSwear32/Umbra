extends RefCounted
## Combos (tests F, G, H, I), scoring, floor numbering and the personal-best bookkeeping
## inside a run.


class Log:
	extends RefCounted
	var lines: PackedStringArray = PackedStringArray()
	var bonus_total: int = 0

	func on_started() -> void:
		lines.append("started")

	func on_progress(jumps: int, floors: int) -> void:
		lines.append("progress:%d:%d" % [jumps, floors])

	func on_ended(jumps: int, floors: int, bonus: int, reason: int, valid: bool) -> void:
		lines.append("ended:%d:%d:%d:%d:%d" % [jumps, floors, bonus, reason, 1 if valid else 0])
		bonus_total += bonus


func run(t: TestContext) -> void:
	var tuning: GameTuning = GameTuning.new()
	_combo_golden(t, tuning)
	_combo_rules(t, tuning)
	_score_rules(t, tuning)
	_floor_rules(t, tuning)


func _make_combo(tuning: GameTuning, log: Log) -> ComboManager:
	var c: ComboManager = ComboManager.new(tuning)
	c.combo_started.connect(log.on_started)
	c.combo_progressed.connect(log.on_progress)
	c.combo_ended.connect(log.on_ended)
	return c


func _combo_golden(t: TestContext, tuning: GameTuning) -> void:
	t.suite("combo (golden sequences)")
	var golden: Variant = TestContext.load_golden("combo.json")
	t.check(golden is Dictionary, "combo.json loads")
	if not (golden is Dictionary):
		return
	for case_data in golden["cases"]:
		var log: Log = Log.new()
		var c: ComboManager = _make_combo(tuning, log)
		for op in case_data["ops"]:
			match String(op[0]):
				"land":
					c.on_landing(int(op[1]), int(op[2]) != 0)
				"tick":
					for i in range(int(op[1])):
						c.tick()
				"end":
					c.end_now(int(op[1]))
		var expected: Array = case_data["log"]
		t.eq(log.lines.size(), expected.size(), "%s: number of events" % String(case_data["name"]))
		for i in range(mini(log.lines.size(), expected.size())):
			t.eq(log.lines[i], String(expected[i]), "%s: event %d" % [String(case_data["name"]), i])
		t.eq(log.bonus_total, int(case_data["bonus_total"]), "%s: total bonus" % String(case_data["name"]))
		t.eq(c.best_floors_run, int(case_data["best_floors"]), "%s: best combo floors" % String(case_data["name"]))
		t.eq(c.best_jumps_run, int(case_data["best_jumps"]), "%s: best combo jumps" % String(case_data["name"]))


func _combo_rules(t: TestContext, tuning: GameTuning) -> void:
	t.suite("combo rules (tests F, G, H, I)")
	# F: chained 2+ floor jumps start and continue a combo
	var log: Log = Log.new()
	var c: ComboManager = _make_combo(tuning, log)
	c.on_landing(1, true)
	t.check(not c.active, "a one-floor jump does not start a combo")
	c.on_landing(2, true)
	t.check(c.active and c.jumps == 1 and c.floors == 2, "F: the first 2+ floor jump starts the chain")
	c.on_landing(3, true)
	c.on_landing(4, true)
	t.check(c.jumps == 3 and c.floors == 9, "F: consecutive jumps continue it (3 jumps / 9 floors)")
	t.near(c.timer_ratio(), 1.0, 1e-9, "the timer is refilled by every combo landing")
	# G: a normal one-floor advancement ends the chain and pays floors^2
	c.on_landing(1, true)
	t.check(not c.active, "G: a one-floor landing ends the combo")
	t.eq(log.bonus_total, 81, "G: bonus is floors squared (9^2 = 81)")
	# H: timeout
	var log2: Log = Log.new()
	var c2: ComboManager = _make_combo(tuning, log2)
	c2.on_landing(3, true)
	c2.on_landing(3, true)
	var ticks_to_timeout: int = tuning.combo_ticks()
	for i in range(ticks_to_timeout - 1):
		c2.tick()
	t.check(c2.active, "H: still active one tick before the timeout")
	c2.tick()
	t.check(not c2.active, "H: the combo ends when the timer runs out")
	t.eq(log2.bonus_total, 36, "H: a timed-out combo still pays (6^2 = 36)")
	# I: dropping to a lower floor ends it
	var log3: Log = Log.new()
	var c3: ComboManager = _make_combo(tuning, log3)
	c3.on_landing(4, true)
	c3.on_landing(4, true)
	c3.on_landing(-2, false)
	t.check(not c3.active, "I: landing on a lower floor ends the combo")
	t.eq(log3.bonus_total, 64, "I: the earned bonus is paid (8^2 = 64)")
	# minimum requirements for a bonus
	var log4: Log = Log.new()
	var c4: ComboManager = _make_combo(tuning, log4)
	c4.on_landing(2, true)
	c4.on_landing(1, true)
	t.eq(log4.bonus_total, 0, "a single combo jump pays no bonus")
	# a valid combo is exactly at the minimums
	t.eq(c4.bonus_for(2, 4), 16, "2 jumps / 4 floors is the smallest paying combo")
	t.eq(c4.bonus_for(2, 3), 0, "too few total floors pays nothing")
	t.eq(c4.bonus_for(1, 10), 0, "one jump never pays")
	# integer safety on absurdly long chains
	t.eq(c4.bonus_for(500, 4000000000), ComboManager.MAX_BONUS, "absurdly long combos saturate instead of overflowing")
	t.eq(c4.bonus_for(500, 3000000), 9000000000000, "a 3-million-floor combo is still exact (integer maths)")


func _score_rules(t: TestContext, tuning: GameTuning) -> void:
	t.suite("scoring")
	var s: ScoreManager = ScoreManager.new()
	s.add_floor_points(5, tuning.points_per_floor)
	t.eq(s.total, 50, "10 points per newly reached floor")
	s.add_combo_bonus(81)
	t.eq(s.total, 131, "combo bonus is added on top")
	t.eq(s.floor_points, 50, "floor points are tracked separately")
	t.eq(s.combo_points, 81, "combo points are tracked separately")
	s.add_floor_points(-3, 10)
	s.add_floor_points(0, 10)
	s.add_combo_bonus(-5)
	t.eq(s.total, 131, "negative or zero awards are ignored")
	var big: ScoreManager = ScoreManager.new()
	big.add_combo_bonus(ScoreManager.MAX_SCORE - 10)
	big.add_combo_bonus(500)
	t.eq(big.total, ScoreManager.MAX_SCORE, "the total saturates instead of overflowing")

	# base points are never awarded twice for the same floor
	var run: RunManager = RunManager.new(tuning, 9)
	_land(run, 3, 0)
	t.eq(run.get_score(), 30, "reaching floor 3 credits 3 floors")
	_land(run, 2, 3)
	t.eq(run.get_score(), 30, "falling to a lower floor gives no points")
	_land(run, 3, 2)
	t.eq(run.get_score(), 30, "re-climbing credited floors gives no points again")
	_land(run, 4, 3)
	t.eq(run.get_score(), 40, "only the floor above the previous best counts")
	_land(run, 9, 4)
	t.eq(run.get_score(), 90, "skipping floors credits every skipped floor (5 more)")


func _floor_rules(t: TestContext, tuning: GameTuning) -> void:
	t.suite("floor numbering")
	var run: RunManager = RunManager.new(tuning, 10)
	t.eq(run.highest_floor, 0, "the run starts on floor 0")
	_land(run, 5, 0)
	t.eq(run.highest_floor, 5, "highest floor follows landings")
	t.eq(run.current_floor, 5, "current floor follows landings")
	_land(run, 2, 5)
	t.eq(run.current_floor, 2, "current floor can go down")
	t.eq(run.highest_floor, 5, "highest floor never decreases")
	_land(run, 3, 2)
	t.eq(run.highest_floor, 5, "highest floor stays until surpassed")
	_land(run, 8, 3)
	t.eq(run.highest_floor, 8, "and grows again after a new best")
	# combo interaction inside a run (jump of 5 floors then 3 floors)
	var run2: RunManager = RunManager.new(tuning, 12)
	_land(run2, 5, 0)
	_land(run2, 8, 5)
	t.check(run2.combo.active and run2.combo.jumps == 2 and run2.combo.floors == 8, "consecutive multi-floor landings build the combo inside a run")
	_land(run2, 9, 8)
	t.check(not run2.combo.active, "a one-floor landing ends the run's combo")
	t.eq(run2.combo.best_floors_run, 8, "the run remembers its best combo")
	t.eq(run2.get_score(), 90 + 64, "score = 9 floors * 10 + 8^2 combo bonus")


## Simulates landing on `floor_index` after taking off from `from_floor`.
func _land(run: RunManager, floor_index: int, from_floor: int) -> void:
	run.tower.get_platform(floor_index)
	run.player.takeoff_floor = from_floor
	run._on_land(run.tower.platforms[floor_index], 0.0)
