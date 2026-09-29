extends RefCounted
## Procedural tower: deterministic, matches the reference, numbering and reachability rules.


func run(t: TestContext) -> void:
	var tuning: GameTuning = GameTuning.new()

	t.suite("tower (golden vectors)")
	var golden: Variant = TestContext.load_golden("tower.json")
	t.check(golden is Dictionary, "tower.json loads")
	if golden is Dictionary:
		for c in golden["cases"]:
			var seed_value: int = int(c["seed"])
			var tw: PlatformGenerator = PlatformGenerator.new(tuning, seed_value)
			tw.ensure_up_to(1010.0 * 125.0)
			for row in c["platforms"]:
				var idx: int = int(row[0])
				var p: PlatformData = tw.platforms[idx]
				var tag: String = "seed %d floor %d" % [seed_value, idx]
				t.eq(p.floor_index, idx, tag + " index")
				t.near(p.x, float(row[1]), 1e-9, tag + " x")
				t.near(p.y, float(row[2]), 1e-9, tag + " y")
				t.near(p.width, float(row[3]), 1e-9, tag + " width")
				t.eq(p.kind, int(row[4]), tag + " kind")
				t.eq(p.variant, int(row[5]), tag + " variant")

	t.suite("tower (determinism and numbering)")
	var a: PlatformGenerator = PlatformGenerator.new(tuning, 555)
	var b: PlatformGenerator = PlatformGenerator.new(tuning, 555)
	a.ensure_up_to(200000.0)
	# b is generated in many small increments: order of requests must not matter
	var alt: float = 0.0
	while alt < 200000.0:
		alt += 350.0
		b.ensure_up_to(alt)
	b.ensure_up_to(200000.0)
	var count: int = mini(a.platform_count(), b.platform_count())
	var identical: bool = true
	for i in range(count):
		var pa: PlatformData = a.platforms[i]
		var pb: PlatformData = b.platforms[i]
		if pa.x != pb.x or pa.y != pb.y or pa.width != pb.width or pa.variant != pb.variant:
			identical = false
			break
	t.check(identical, "generation does not depend on when platforms are requested")
	var other: PlatformGenerator = PlatformGenerator.new(tuning, 556)
	other.ensure_up_to(5000.0)
	var differs: bool = false
	for i in range(1, 30):
		if (other.platforms[i] as PlatformData).x != (a.platforms[i] as PlatformData).x:
			differs = true
	t.check(differs, "a different seed builds a different tower")

	var numbering_ok: bool = true
	var landmark_ok: bool = true
	var bounds_ok: bool = true
	var spacing_ok: bool = true
	var order_ok: bool = true
	var max_spacing: float = tuning.base_apex() - tuning.platform_clearance
	for i in range(count):
		var p: PlatformData = a.platforms[i]
		if p.floor_index != i:
			numbering_ok = false
		if i > 0:
			if p.left() < -0.001 or p.right() > tuning.tower_width + 0.001:
				bounds_ok = false
			var prev: PlatformData = a.platforms[i - 1]
			var gap_y: float = p.y - prev.y
			if gap_y > max_spacing + 0.0001 or gap_y < tuning.platform_spacing_min - 0.0001:
				spacing_ok = false
			if gap_y <= 0.0:
				order_ok = false
			if i % tuning.landmark_interval == 0 and p.kind != SimConst.KIND_LANDMARK:
				landmark_ok = false
			if i % tuning.landmark_interval != 0 and p.kind == SimConst.KIND_LANDMARK:
				landmark_ok = false
	t.check(numbering_ok, "every platform has a unique floor number equal to its index")
	t.check(bounds_ok, "platforms stay inside the tower walls")
	t.check(spacing_ok, "vertical spacing never exceeds what a standing jump can climb")
	t.check(order_ok, "platforms are strictly ascending")
	t.check(landmark_ok, "landmark platforms appear exactly every %d floors" % tuning.landmark_interval)
	t.eq((a.platforms[0] as PlatformData).kind, SimConst.KIND_GROUND, "floor 0 is the ground")
	t.near((a.platforms[0] as PlatformData).width, tuning.tower_width, 1e-9, "the ground spans the tower")

	t.suite("tower (difficulty progression)")
	var early: float = 0.0
	var late: float = 0.0
	for i in range(1, 60):
		if i % tuning.landmark_interval != 0:
			early += (a.platforms[i] as PlatformData).width
	early /= 54.0
	var n_late: int = 0
	for i in range(1200, 1500):
		if i % tuning.landmark_interval != 0 and i < a.platform_count():
			late += (a.platforms[i] as PlatformData).width
			n_late += 1
	late /= float(maxi(n_late, 1))
	t.check(late < early * 0.7, "late platforms are much narrower than early ones (%.0f vs %.0f)" % [late, early])

	t.suite("tower (reachability guarantee)")
	# every consecutive pair must be within the provable jump reach of a standing start
	var reach_ok: bool = true
	for i in range(1, count):
		var prev2: PlatformData = a.platforms[i - 1]
		var cur: PlatformData = a.platforms[i]
		var sp: float = cur.y - prev2.y
		var d: float = a.difficulty(i)
		var allowed: float = a.max_gap(prev2.width, sp, d)
		var gap: float = maxf(0.0, absf(cur.x - prev2.x) - (cur.width + prev2.width) * 0.5)
		if gap > allowed + 0.001:
			reach_ok = false
			break
	t.check(reach_ok, "the horizontal gap between neighbours never exceeds the provable reach")
	var jump: PlayerController = PlayerController.new(tuning)
	t.check(tuning.base_apex() >= tuning.platform_spacing_end + tuning.platform_clearance - 1.0, "a standing jump clears the tallest normal step")
	t.check(jump.jump_velocity() > 0.0, "standing jump has positive velocity")
