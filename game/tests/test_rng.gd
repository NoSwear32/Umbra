extends RefCounted
## Deterministic PRNG: must match the Python reference bit for bit.


func run(t: TestContext) -> void:
	t.suite("rng (golden vectors)")
	var golden: Variant = TestContext.load_golden("rng.json")
	t.check(golden is Dictionary, "rng.json loads")
	if not (golden is Dictionary):
		return
	for c in golden["cases"]:
		var seed_value: int = int(c["seed"])
		var r: SimRng = SimRng.new(seed_value)
		for i in range(8):
			t.eq(r.next_u32(), int(c["u32"][i]), "seed %d: u32[%d]" % [seed_value, i])
		r = SimRng.new(seed_value)
		for i in range(4):
			t.near(r.next_float(), float(c["floats"][i]), 1e-12, "seed %d: float[%d]" % [seed_value, i])
		for i in range(4):
			t.near(r.range_f(-5.0, 5.0), float(c["range_f"][i]), 1e-12, "seed %d: range_f[%d]" % [seed_value, i])
		for i in range(6):
			t.eq(r.range_i(3, 9), int(c["range_i"][i]), "seed %d: range_i[%d]" % [seed_value, i])

	t.suite("rng (properties)")
	var a: SimRng = SimRng.new(12345)
	var b: SimRng = SimRng.new(12345)
	var same: bool = true
	for i in range(1000):
		if a.next_u32() != b.next_u32():
			same = false
	t.check(same, "same seed gives the same sequence")
	var d1: SimRng = SimRng.new(1)
	var d2: SimRng = SimRng.new(2)
	t.check(d1.next_u32() != d2.next_u32(), "different seeds differ")
	var lo: float = 1.0
	var hi: float = 0.0
	var r2: SimRng = SimRng.new(99)
	for i in range(5000):
		var f: float = r2.next_float()
		lo = minf(lo, f)
		hi = maxf(hi, f)
	t.check(lo >= 0.0 and hi < 1.0, "next_float stays in [0, 1)")
	var counts: Array = [0, 0, 0, 0, 0]
	var r3: SimRng = SimRng.new(7)
	for i in range(5000):
		counts[r3.range_i(0, 4)] += 1
	var balanced: bool = true
	for c2 in counts:
		if c2 < 800 or c2 > 1200:
			balanced = false
	t.check(balanced, "range_i is roughly uniform")
