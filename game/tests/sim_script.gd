class_name SimScript
extends RefCounted
## Helpers that drive a RunManager with scripted input, mirroring tools/reference/gen_golden.py.

## Runs `segments` ([[ticks, axis, jump_on_first_tick], ...]) on a fresh run and samples a
## trace row every `sample_every` ticks (plus a final row), exactly like the Python reference.
## Returns { trace, apex, final, run }.
static func run_segments(tuning: GameTuning, seed_value: int, segments: Array, sample_every: int) -> Dictionary:
	var run: RunManager = RunManager.new(tuning, seed_value)
	var trace: Array = []
	var apex: float = 0.0
	for seg in segments:
		var n: int = int(seg[0])
		var axis: float = float(seg[1])
		var jump_first: bool = int(seg[2]) != 0
		for i in range(n):
			if run.dead:
				break
			run.tick(axis, jump_first and i == 0)
			if run.player.y > apex:
				apex = run.player.y
			if run.tick_count % sample_every == 0:
				trace.append(trace_row(run))
	trace.append(trace_row(run))
	return {"trace": trace, "apex": apex, "run": run}


static func trace_row(run: RunManager) -> Array:
	var p: PlayerController = run.player
	return [run.tick_count, p.x, p.y, p.vx, p.vy, 1 if p.grounded else 0,
		run.highest_floor, run.get_score(), run.scroll.cam_bottom,
		1 if run.combo.active else 0, run.combo.jumps, run.combo.floors, 1 if run.dead else 0]


## Compares a GDScript trace with a golden trace. Returns "" when equal, else a description.
static func compare_traces(actual: Array, expected: Array, tolerance: float) -> String:
	if actual.size() != expected.size():
		return "trace length %d != %d" % [actual.size(), expected.size()]
	for i in range(expected.size()):
		var a: Array = actual[i]
		var e: Array = expected[i]
		for j in range(e.size()):
			var av: float = float(a[j])
			var ev: float = float(e[j])
			if absf(av - ev) > tolerance * maxf(1.0, absf(ev)):
				return "row %d column %d: got %.9f, expected %.9f" % [i, j, av, ev]
	return ""
