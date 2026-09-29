extends RefCounted
## Movement physics: golden scenarios from the reference sim plus the manual test cases A-E,
## J and the one-way platform / anti-tunnelling guarantees.


class Counter:
	extends RefCounted
	var n: int = 0
	var last: Dictionary = {}

	func on_ended(result: Dictionary) -> void:
		n += 1
		last = result


func run(t: TestContext) -> void:
	var tuning: GameTuning = GameTuning.new()
	_golden(t, tuning)
	_test_a_to_c(t, tuning)
	_test_d_wall(t, tuning)
	_test_e_one_way(t, tuning)
	_test_no_tunnelling(t, tuning)
	_test_j_single_death(t, tuning)
	_test_jump_and_input_rules(t, tuning)


func _golden(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics (golden scenarios)")
	var files: Array = ["physics.json", "chaos.json", "bot_run.json"]
	for f in files:
		var data: Variant = TestContext.load_golden(String(f))
		t.check(data is Dictionary, "%s loads" % String(f))
		if not (data is Dictionary):
			continue
		for sc in data["scenarios"]:
			var res: Dictionary = SimScript.run_segments(tuning, int(sc["seed"]), sc["segments"], int(sc["sample_every"]))
			var msg: String = SimScript.compare_traces(res["trace"], sc["trace"], 1e-7)
			t.check(msg.is_empty(), "%s trace matches the reference %s" % [String(sc["name"]), msg])
			t.near(float(res["apex"]), float(sc["apex"]), 1e-7, "%s apex" % String(sc["name"]))
			var run: RunManager = res["run"]
			t.eq(run.get_score(), int(sc["final"]["score"]), "%s final score" % String(sc["name"]))
			t.eq(run.highest_floor, int(sc["final"]["highest"]), "%s highest floor" % String(sc["name"]))
			t.eq(run.tick_count, int(sc["final"]["ticks"]), "%s ticks" % String(sc["name"]))
			t.eq(run.total_jumps, int(sc["final"]["jumps"]), "%s jumps" % String(sc["name"]))
			t.eq(run.wall_rebounds, int(sc["final"]["walls"]), "%s wall rebounds" % String(sc["name"]))
			t.eq(run.dead, int(sc["final"]["dead"]) != 0, "%s dead flag" % String(sc["name"]))

	t.suite("physics (curves)")
	var curves: Variant = TestContext.load_golden("curves.json")
	if curves is Dictionary:
		for row in curves["jump"]:
			var p: PlayerController = PlayerController.new(tuning)
			p.vx = tuning.max_speed * float(row[0]) / 100.0
			t.near(p.jump_velocity(), float(row[1]), 1e-12, "jump velocity at %d%% speed" % int(row[0]))
		var s: ScrollDifficultyManager = ScrollDifficultyManager.new(tuning)
		for row in curves["stage_speed"]:
			t.near(s.stage_speed(int(row[0])), float(row[1]), 1e-12, "scroll speed of stage %d" % int(row[0]))
		t.near(tuning.base_apex(), float(curves["base_apex"]), 1e-12, "standing jump apex")


## TEST A / B / C: jump height grows with speed on a carefully tuned (not exponential) curve.
func _test_a_to_c(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics: speed-dependent jumps (tests A, B, C)")
	var apex_still: float = _jump_apex_after_run(tuning, 0)
	var apex_medium: float = _jump_apex_after_run(tuning, 32)
	var apex_fast: float = _jump_apex_after_run(tuning, 80)
	var spacing: float = tuning.platform_spacing_start
	t.check(apex_still > spacing and apex_still < spacing * 2.0, "A: a standing jump reaches about one floor (%.0f px)" % apex_still)
	t.check(apex_medium > apex_still * 1.5 and apex_medium >= spacing * 2.0, "B: a medium-speed jump is noticeably higher (%.0f px)" % apex_medium)
	t.check(apex_fast > apex_medium * 1.5 and apex_fast >= spacing * 5.0, "C: a full-speed jump skips many floors (%.0f px)" % apex_fast)
	t.check(apex_fast <= tuning.base_apex() * tuning.jump_max_multiplier * tuning.jump_max_multiplier + 1.0, "C: the curve is bounded by the maximum multiplier")
	# monotonic and smooth: no jump of speed ratio r can exceed one of a higher ratio
	var last: float = 0.0
	var monotonic: bool = true
	var p: PlayerController = PlayerController.new(tuning)
	for pct in range(0, 101, 5):
		p.vx = tuning.max_speed * float(pct) / 100.0
		var v: float = p.jump_velocity()
		if v < last:
			monotonic = false
		last = v
	t.check(monotonic, "jump velocity never decreases with speed")


func _jump_apex_after_run(tuning: GameTuning, run_ticks: int) -> float:
	var segs: Array = [[run_ticks, 1, 0], [1, 1, 1], [140, 0, 0]]
	if run_ticks == 0:
		segs = [[1, 0, 1], [140, 0, 0]]
	var res: Dictionary = SimScript.run_segments(tuning, 2, segs, 1000)
	return float(res["apex"])


## TEST D: hitting a side wall reverses the velocity and keeps most of the momentum.
func _test_d_wall(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics: wall rebounds (test D)")
	var tower: PlatformGenerator = PlatformGenerator.new(tuning, 3)
	var p: PlayerController = PlayerController.new(tuning)
	p.support = tower.platforms[0]
	p.x = tuning.player_half_width + 2.0
	p.vx = -700.0
	p.step(0.0, false, tower)
	t.check(p.vx > 0.0, "velocity is reversed after hitting the left wall")
	t.check(p.vx > 700.0 * 0.85, "most of the momentum is kept (%.0f of 700)" % p.vx)
	t.check(p.vx < 700.0, "a rebound never adds speed with the default multiplier")
	var evs: int = 0
	for e in p.events:
		if int((e as Array)[0]) == SimConst.EV_WALL:
			evs += 1
	t.eq(evs, 1, "exactly one wall event")
	p.x = tuning.tower_width - tuning.player_half_width - 2.0
	p.vx = 650.0
	p.step(0.0, false, tower)
	t.check(p.vx < -650.0 * 0.85, "the right wall rebounds too (%.0f)" % p.vx)
	# slow contact just stops (no jitter bouncing)
	p.x = tuning.player_half_width + 0.05
	p.vx = -20.0
	p.step(0.0, false, tower)
	t.near(p.vx, 0.0, 1e-9, "a very slow contact does not bounce")
	# airborne rebound: vertical influence adds a little lift
	var q: PlayerController = PlayerController.new(tuning)
	q.support = tower.platforms[0]
	q.grounded = false
	q.support = null
	q.y = 300.0
	q.vy = 0.0
	q.x = tuning.player_half_width + 1.0
	q.vx = -720.0
	var vy_before: float = q.vy
	q.step(0.0, false, tower)
	t.check(q.vy > vy_before - tuning.gravity * SimConst.DT, "an airborne rebound adds a little vertical lift")


## TEST E: platforms are one-way. Rise through them, land on top while descending.
func _test_e_one_way(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics: one-way platforms (test E)")
	var tower: PlatformGenerator = PlatformGenerator.new(tuning, 11)
	tower.ensure_up_to(4000.0)
	var target: PlatformData = tower.platforms[3]
	var p: PlayerController = PlayerController.new(tuning)
	p.grounded = false
	p.support = null
	p.x = clampf(target.x, tuning.player_half_width, tuning.tower_width - tuning.player_half_width)
	p.y = target.y - 60.0
	p.vy = 1150.0
	p.vx = 0.0
	var landed_ticks: int = 0
	var grounded_while_rising: bool = false
	var max_y: float = p.y
	for i in range(600):
		p.step(0.0, false, tower)
		if p.vy > 0.0 and p.grounded:
			grounded_while_rising = true
		max_y = maxf(max_y, p.y)
		if p.grounded:
			landed_ticks = i
			break
	t.check(max_y > target.y, "the player rose through the platform (max %.1f > %.1f)" % [max_y, target.y])
	t.check(not grounded_while_rising, "the underside of a platform never blocks or catches the player")
	t.check(p.grounded, "the player lands eventually")
	t.check(p.support != null and absf(p.y - (p.support as PlatformData).y) < 1e-9, "the player ends exactly on a platform surface")
	t.check(landed_ticks > 0, "landing happens while descending")


## High-speed falls must never pass through a platform.
func _test_no_tunnelling(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics: no tunnelling at maximum fall speed")
	var tower: PlatformGenerator = PlatformGenerator.new(tuning, 21)
	tower.ensure_up_to(6000.0)
	var ok: bool = true
	for start_floor in range(3, 40):
		var top: PlatformData = tower.platforms[start_floor]
		var p: PlayerController = PlayerController.new(tuning)
		p.grounded = false
		p.support = null
		p.x = clampf(top.x, tuning.player_half_width, tuning.tower_width - tuning.player_half_width)
		p.y = top.y + 420.0
		p.vy = -tuning.max_fall_speed
		# the platform the player must land on: highest overlapping platform below the start
		var expected: PlatformData = null
		var i: int = start_floor + 6
		while i >= 0:
			var c: PlatformData = tower.platforms[i]
			if c.y <= p.y and p.x + tuning.foot_half_width > c.left() and p.x - tuning.foot_half_width < c.right():
				expected = c
				break
			i -= 1
		for step_i in range(400):
			p.step(0.0, false, tower)
			if p.grounded:
				break
		if expected == null or not p.grounded or p.support != expected:
			ok = false
	t.check(ok, "falling at terminal velocity always lands on the first platform below")


## TEST J: falling below the screen ends the run exactly once.
func _test_j_single_death(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics: game over happens exactly once (test J)")
	var run: RunManager = RunManager.new(tuning, 5)
	var counter: Counter = Counter.new()
	run.run_ended.connect(counter.on_ended)
	# climb to the scroll start floor without moving, then stand still and let the tower rise
	run.debug_teleport_to_floor(tuning.scroll_start_floor)
	var ticks: int = 0
	while not run.dead and ticks < 120 * 60:
		run.tick(0.0, false)
		ticks += 1
	t.check(run.dead, "standing still eventually lets the rising tower carry the player out")
	t.eq(counter.n, 1, "run_ended fires once")
	var after: int = run.tick_count
	for i in range(240):
		run.tick(0.0, false)
	t.eq(counter.n, 1, "no second run_ended after death")
	t.eq(run.tick_count, after, "the simulation stops advancing once the run is over")
	t.check(run.player.y + tuning.player_height < run.scroll.cam_bottom, "the player died fully below the screen")
	t.check(bool(counter.last.get("debug_used", false)), "teleporting marks the run as a debug run")


func _test_jump_and_input_rules(t: TestContext, tuning: GameTuning) -> void:
	t.suite("physics: jump rules")
	var tower: PlatformGenerator = PlatformGenerator.new(tuning, 4)
	# no automatic bouncing: landing keeps the player on the platform
	var p: PlayerController = PlayerController.new(tuning)
	p.support = tower.platforms[0]
	for i in range(240):
		p.step(0.0, false, tower)
	t.check(p.grounded and p.vy == 0.0, "standing on a platform stays there (no auto bounce)")
	# exactly one jump per request, no double jump
	p.step(0.0, true, tower)
	t.check(not p.grounded and p.vy > 0.0, "a jump request lifts the player")
	var vy_after_jump: float = p.vy
	p.step(0.0, true, tower)
	t.check(p.vy < vy_after_jump, "a second request in mid-air does nothing (no double jump)")
	# airborne acceleration is weaker than ground acceleration
	var g: PlayerController = PlayerController.new(tuning)
	g.support = tower.platforms[0]
	g.step(1.0, false, tower)
	var ground_gain: float = g.vx
	var a: PlayerController = PlayerController.new(tuning)
	a.support = null
	a.grounded = false
	a.y = 500.0
	a.step(1.0, false, tower)
	t.check(a.vx < ground_gain, "air control is weaker than ground acceleration (%.1f < %.1f)" % [a.vx, ground_gain])
	# momentum: speed builds up progressively and reversing takes time
	var m: PlayerController = PlayerController.new(tuning)
	m.support = tower.platforms[0]
	m.x = tuning.tower_width * 0.5
	for i in range(6):
		m.step(1.0, false, tower)
	t.check(m.vx > 0.0 and m.vx < tuning.max_speed * 0.5, "the character does not reach full speed instantly (%.0f)" % m.vx)
	for i in range(60):
		m.step(1.0, false, tower)
	var fast: float = m.vx
	m.step(-1.0, false, tower)
	t.check(m.vx > 0.0 and m.vx > fast * 0.9, "changing direction at speed does not reverse instantly")
