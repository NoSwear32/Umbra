extends SceneTree
## Headless test runner.
##
##   cd game
##   godot --headless --import                       # once: builds the class cache (.godot/)
##   godot --headless -s tests/run_tests.gd          # run everything
##
## Exit code 0 = all passed, 1 = at least one failure. See tools/run_tests.sh.

const SUITES: Array = [
	"res://tests/test_rng.gd",
	"res://tests/test_tower.gd",
	"res://tests/test_physics.gd",
	"res://tests/test_combo_score.gd",
	"res://tests/test_run.gd",
	"res://tests/test_replay.gd",
	"res://tests/test_save.gd",
	"res://tests/test_records.gd",
	"res://tests/test_input.gd",
	"res://tests/test_config.gd",
	"res://tests/test_characters.gd",
]


## _initialize() (not _init()) so the autoload singletons already exist when a suite runs.
func _initialize() -> void:
	var ctx: TestContext = TestContext.new()
	print("Spire Sprint tests - simulation version %d" % SimConst.SIM_VERSION)
	for path in SUITES:
		var script: GDScript = load(String(path))
		if script == null:
			ctx.fail("cannot load %s" % String(path))
			continue
		var suite: Variant = script.new()
		suite.run(ctx)
	print("")
	print("passed: %d   failed: %d" % [ctx.passed, ctx.failed])
	if ctx.failed > 0:
		printerr("SOME TESTS FAILED")
	else:
		print("ALL TESTS PASSED")
	quit(1 if ctx.failed > 0 else 0)
