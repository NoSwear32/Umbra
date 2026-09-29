extends RefCounted
## Save system: atomic writes, backup recovery, versioned migration, forward compatibility.

const DIR: String = "user://test_save_scratch"

var _script: GDScript = load("res://src/autoload/save_manager.gd")


func run(t: TestContext) -> void:
	_cleanup()
	_roundtrip(t)
	_recovery(t)
	_migration(t)
	_forward_compat(t)
	_cleanup()


func _make() -> Variant:
	var sm: Variant = _script.new()
	sm.dir_path = DIR
	sm.main_path = DIR + "/profile.json"
	sm.backup_path = DIR + "/profile.bak.json"
	sm.tmp_path = DIR + "/profile.tmp.json"
	return sm


func _cleanup() -> void:
	for f in ["profile.json", "profile.bak.json", "profile.tmp.json", "profile.corrupt.json"]:
		DirAccess.remove_absolute(DIR + "/" + String(f))
	DirAccess.remove_absolute(DIR)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _roundtrip(t: TestContext) -> void:
	t.suite("save: round trip and atomic writes")
	var sm: Variant = _make()
	sm.load_all()
	t.eq(sm.loaded_from, "new", "a fresh install starts with defaults")
	t.eq(int(sm.data["version"]), 1, "new saves carry the version number")
	t.check((sm.data["leaderboards"] as Dictionary).has("score"), "default leaderboards exist")
	sm.section("settings")["vol_master"] = 0.5
	sm.data["selected_character"] = "bolt"
	sm.array_section("unlocked").append("bolt")
	t.check(sm.save_now(), "saving succeeds")
	t.check(FileAccess.file_exists(DIR + "/profile.json"), "the profile file exists")
	t.check(not FileAccess.file_exists(DIR + "/profile.tmp.json"), "no temp file is left behind")

	var sm2: Variant = _make()
	sm2.load_all()
	t.eq(sm2.loaded_from, "main", "the saved profile is loaded")
	t.near(float(sm2.section("settings")["vol_master"]), 0.5, 1e-9, "settings survive")
	t.eq(String(sm2.data["selected_character"]), "bolt", "the selected character survives")
	t.check((sm2.array_section("unlocked") as Array).has("bolt"), "unlocked characters survive")

	# a second save keeps the previous version as a backup
	sm2.section("settings")["vol_master"] = 0.8
	t.check(sm2.save_now(), "second save succeeds")
	t.check(FileAccess.file_exists(DIR + "/profile.bak.json"), "the previous version is kept as a backup")

	# a failed verification must never touch the existing profile
	var before: String = FileAccess.get_file_as_string(DIR + "/profile.json")
	t.check(not sm2.write_atomic("this is not json"), "invalid data is refused")
	t.eq(FileAccess.get_file_as_string(DIR + "/profile.json"), before, "the profile is untouched by a refused write")


func _recovery(t: TestContext) -> void:
	t.suite("save: crash and corruption recovery")
	# main is corrupted (e.g. power loss during a write): the backup is used
	_write(DIR + "/profile.json", "{ this is broken")
	var sm: Variant = _make()
	sm.load_all()
	t.eq(sm.loaded_from, "backup", "a corrupted profile falls back to the backup")
	t.near(float(sm.section("settings")["vol_master"]), 0.5, 1e-9, "the backup contains the previous good data")
	t.check(FileAccess.file_exists(DIR + "/profile.corrupt.json"), "the corrupted file is kept for inspection")

	# both broken: fall back to defaults instead of crashing
	_write(DIR + "/profile.json", "###")
	_write(DIR + "/profile.bak.json", "###")
	var sm2: Variant = _make()
	sm2.load_all()
	t.eq(sm2.loaded_from, "new", "unreadable saves fall back to a clean profile")

	# crash between "temp written" and "renamed": the newer temp file wins over the older backup
	DirAccess.remove_absolute(DIR + "/profile.json")
	_write(DIR + "/profile.bak.json", JSON.stringify({"version": 1, "marker": "backup"}))
	_write(DIR + "/profile.tmp.json", JSON.stringify({"version": 1, "marker": "temp"}))
	var sm3: Variant = _make()
	sm3.load_all()
	t.eq(sm3.loaded_from, "tmp", "a complete temp file is recovered")
	t.eq(String(sm3.data.get("marker", "")), "temp", "with the newest data")


class Steps:
	extends RefCounted
	var log: PackedStringArray = PackedStringArray()

	func zero_to_one(d: Dictionary) -> void:
		log.append("0->1")
		d["migrated"] = true
		d["settings"] = {"upgraded": true}


func _migration(t: TestContext) -> void:
	t.suite("save: versioned migration")
	var sm: Variant = _make()
	var steps: Steps = Steps.new()
	sm.migrations[0] = steps.zero_to_one
	var old: Dictionary = {"version": 0, "stats": {"games_played": 12}}
	var upgraded: Dictionary = sm.migrate(old)
	t.eq(int(upgraded["version"]), 1, "the version number is advanced")
	t.check(bool(upgraded.get("migrated", false)), "the migration step ran")
	t.eq(steps.log.size(), 1, "each step runs exactly once")
	t.eq(int((upgraded["stats"] as Dictionary)["games_played"]), 12, "existing records are preserved by migration")
	var current: Dictionary = sm.migrate({"version": 1, "stats": {}})
	t.eq(steps.log.size(), 1, "current-version data is not migrated again")
	t.eq(int(current["version"]), 1, "current data keeps its version")
	# missing sections are filled without touching existing ones
	_write(DIR + "/profile.json", JSON.stringify({"version": 1, "stats": {"games_played": 7}, "leaderboards": {"score": [{"score": 500}]}}))
	var sm2: Variant = _make()
	sm2.load_all()
	t.eq(int((sm2.data["stats"] as Dictionary)["games_played"]), 7, "existing stats survive an update")
	t.check(sm2.data.has("unlocked") and sm2.data.has("replays") and sm2.data.has("custom_characters"), "new sections are added with defaults")
	t.eq(((sm2.data["leaderboards"] as Dictionary)["score"] as Array).size(), 1, "existing records survive an update")
	t.check((sm2.data["leaderboards"] as Dictionary).has("combo"), "missing leaderboard categories are created")


func _forward_compat(t: TestContext) -> void:
	t.suite("save: files from a newer game version")
	_write(DIR + "/profile.json", JSON.stringify({"version": 99, "future_feature": {"x": 1}, "stats": {"games_played": 3}}))
	var sm: Variant = _make()
	sm.load_all()
	t.check(sm.future_version, "a newer file is detected")
	t.eq(int(sm.data["version"]), 99, "its version number is not downgraded")
	t.check(sm.save_now(), "it can still be saved")
	var raw: Variant = sm.read_json_file(DIR + "/profile.json")
	t.check(raw is Dictionary and (raw as Dictionary).has("future_feature"), "unknown data is preserved (never wiped by an older build)")
	t.eq(int((raw as Dictionary)["version"]), 99, "and the version stays 99")
