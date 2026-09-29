extends RefCounted
## Run-level rules: scrolling start, staged speed-ups, camera follow, frame-rate independence.


class Watcher:
	extends RefCounted
	var scroll_started: int = 0
	var stages: PackedInt32Array = PackedInt32Array()

	func on_scroll_started() -> void:
		scroll_started += 1

	func on_stage(stage: int) -> void:
		stages.append(stage)


func run(t: TestContext) -> void:
	var tuning: GameTuning = GameTuning.new()

	t.suite("scrolling start and staged speed-ups")
	var r: RunManager = RunManager.new(tuning, 1)
	var ev: Watcher = Watcher.new()
	r.scroll_started.connect(ev.on_scroll_started)
	r.speed_stage_changed.connect(ev.on_stage)
	for i in range(240):
		r.tick(0.0, false)
	t.check(not r.scroll.active, "the tower is calm at the start (no scrolling below the start floor)")
	t.near(r.scroll.cam_bottom, tuning.camera_start_bottom, 1e-9, "the camera has not moved yet")
	r.debug_teleport_to_floor(tuning.scroll_start_floor)
	var before: float = r.scroll.cam_bottom
	r.tick(0.0, false)
	t.check(r.scroll.active, "scrolling starts when the start floor is reached")
	t.eq(ev.scroll_started, 1, "scroll_started fires once")
	# ramp: speed eases in
	var early_speed: float = 0.0
	for i in range(30):
		r.tick(0.0, false)
	early_speed = r.scroll.speed
	for i in range(400):
		r.tick(0.0, false)
	t.check(r.scroll.speed > early_speed, "the scroll speed eases in")
	t.check(r.scroll.cam_bottom > before, "the view rises")

	# stage every ~30 s
	var target_ticks: int = tuning.stage_ticks() - r.scroll.ticks_since_start
	var ok: bool = true
	var last_cam: float = r.scroll.cam_bottom
	r.invincible = true  # keep the run alive for the timing test
	for i in range(target_ticks - 1):
		r.tick(0.0, false)
		if r.scroll.cam_bottom < last_cam:
			ok = false
		last_cam = r.scroll.cam_bottom
	t.check(ok, "the camera bottom never moves down")
	t.eq(r.scroll.stage, 0, "still stage 0 one tick before the interval")
	r.tick(0.0, false)
	t.eq(r.scroll.stage, 1, "stage 1 after %.0f seconds of scrolling" % tuning.scroll_stage_seconds)
	t.eq(ev.stages.size(), 1, "one speed-up notification")
	t.check(ev.stages[0] == 1, "the notification carries the stage number")
	var s0: float = r.scroll.stage_speed(0)
	var s1: float = r.scroll.stage_speed(1)
	t.check(s1 > s0, "each stage is faster than the previous one")
	var monotonic: bool = true
	var prev: float = 0.0
	for st in range(0, 300):
		var v: float = r.scroll.stage_speed(st)
		if v <= prev and st > 0:
			monotonic = false
		prev = v
	t.check(monotonic, "stage speeds strictly increase")
	t.check(r.scroll.stage_speed(100000) < tuning.scroll_speed_max and r.scroll.stage_speed(100000) > tuning.scroll_speed_max * 0.98, "speeds approach the maximum asymptotically")

	t.suite("camera follow")
	var r2: RunManager = RunManager.new(tuning, 2)
	r2.debug_teleport_to_floor(40)
	var cam0: float = r2.scroll.cam_bottom
	var head_target: float = r2.player.y + tuning.player_height - tuning.camera_follow_line * tuning.view_height
	t.check(absf(cam0 - (r2.tower.platforms[40] as PlatformData).y + tuning.view_height * tuning.camera_follow_line) < 1e-6, "teleport places the camera on the follow line")
	t.check(head_target > cam0 - 1.0, "the player head is at the follow line")
	# a big leap upwards pulls the camera up smoothly (never past the target, never down)
	r2.player.y += 600.0
	var target: float = r2.player.y + tuning.player_height - tuning.camera_follow_line * tuning.view_height
	var ok2: bool = true
	var last: float = r2.scroll.cam_bottom
	for i in range(200):
		r2.scroll.step(r2.player.y + tuning.player_height, r2.highest_floor)
		if r2.scroll.cam_bottom < last - 1e-9 or r2.scroll.cam_bottom > target + r2.scroll.speed * SimConst.DT * 200.0 + 1.0:
			ok2 = false
		last = r2.scroll.cam_bottom
	t.check(ok2, "the camera follows upwards smoothly")
	t.check(absf(r2.scroll.cam_bottom - target) < 60.0 + r2.scroll.speed, "and converges on the follow line")

	t.suite("frame-rate independence")
	# the simulation only depends on the tick sequence, never on how frames are grouped
	var segs: Array = [[50, 1, 0], [1, 1, 1], [80, 1, 0], [60, -1, 0], [1, 0, 1], [200, 1, 0]]
	var a: Dictionary = SimScript.run_segments(tuning, 33, segs, 7)
	var b: Dictionary = SimScript.run_segments(tuning, 33, segs, 100)
	var ra: RunManager = a["run"]
	var rb: RunManager = b["run"]
	t.check(ra.player.x == rb.player.x and ra.player.y == rb.player.y and ra.get_score() == rb.get_score(), "identical inputs give identical state regardless of sampling")
	# 60 Hz and 144 Hz frame patterns consume the same number of fixed ticks per second
	t.eq(SimConst.TICK_RATE, 120, "fixed simulation rate")
	var ticks_60: int = int((1.0 / 60.0) / SimConst.DT + 0.5)
	t.eq(ticks_60, 2, "a 60 Hz frame is exactly two ticks")
