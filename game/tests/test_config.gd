extends RefCounted
## Project configuration (landscape, scaling, sensors), tuning invariants, safe-area maths,
## themes, the Android export preset and the shipped assets.

const ThemeScript = preload("res://src/autoload/theme_manager.gd")
const AudioScript = preload("res://src/autoload/audio_manager.gd")

## Tuning values that are NOT part of the deterministic simulation (never stored in replays).
## Every other exported value of GameTuning must be listed in GameTuning.SIM_KEYS.
const NON_SIM_KEYS: Array = [
	"praise_min_floors", "praise_texts",
	"touch_release_min_hold", "touch_release_min_hold_max",
	"tilt_dead_zone_deg", "tilt_full_deg_low", "tilt_full_deg_medium", "tilt_full_deg_high",
	"tilt_full_deg_min", "tilt_full_deg_max", "tilt_smoothing_time", "tilt_response_curve",
	"tilt_spike_deg_per_sec", "tilt_settle_samples",
	"camera_smooth_time", "screen_shake_scale", "speed_effect_ratio",
]

const AUTOLOADS: Array = [
	"Events", "SaveManager", "SettingsManager", "StatisticsManager", "LeaderboardManager",
	"CharacterManager", "ReplayManager", "ThemeManager", "AudioManager", "SensorManager",
	"InputManager", "AndroidLifecycleManager", "GameManager", "UIManager", "DebugManager",
]

const CLASSES: Array = [
	"RunManager", "PlayerController", "PlatformGenerator", "CameraController",
	"ScrollDifficultyManager", "ComboManager", "ScoreManager", "ReplayRecorder", "ReplayPlayer",
	"ReplayData", "TouchInputController", "TiltInputController", "GameTuning",
	"LeaderboardProvider", "LocalLeaderboardProvider", "StatsData", "CharacterPack",
	"CharacterDef", "SafeArea", "SimRng", "SimConst", "TuningStore",
]

const BUILTIN_CHARACTERS: Array = ["pip", "bolt", "moss", "nova", "wraith", "ember", "zenith"]
const PACKAGE_NAME: String = "io.github.noswear32.spiresprint"


func run(t: TestContext) -> void:
	_project(t)
	_architecture(t)
	_tuning_classification(t)
	_tuning_snapshots(t)
	_tuning_targets(t)
	_safe_area(t)
	_themes(t)
	_export(t)
	_assets(t)


# ---------------------------------------------------------------------------
# Project settings
# ---------------------------------------------------------------------------
func _setting(path: String, fallback: Variant) -> Variant:
	return ProjectSettings.get_setting(path, fallback)


func _project(t: TestContext) -> void:
	t.suite("project: orientation, display scaling, sensors")
	var tuning: GameTuning = GameTuning.new()
	t.eq(int(_setting("display/window/handheld/orientation", -1)), 4, "orientation is 'sensor landscape' (both landscape directions, follows the sensor)")
	t.eq(String(_setting("display/window/stretch/mode", "")), "canvas_items", "stretch mode: canvas_items")
	t.eq(String(_setting("display/window/stretch/aspect", "")), "keep_height", "aspect: keep_height (every device sees the same tower height)")
	var vw: int = int(_setting("display/window/size/viewport_width", 0))
	var vh: int = int(_setting("display/window/size/viewport_height", 0))
	t.eq(vh, int(tuning.view_height), "the viewport height equals the simulation's view height")
	t.check(vw > vh, "the base viewport is landscape (%d x %d)" % [vw, vh])
	t.check(tuning.tower_width <= float(vh), "even a square screen shows the whole tower width (%d <= %d)" % [int(tuning.tower_width), vh])
	t.check(bool(_setting("input_devices/sensors/enable_accelerometer", false)), "the accelerometer is enabled")
	t.check(bool(_setting("input_devices/sensors/enable_gravity", false)), "the gravity sensor is enabled")
	t.check(not bool(_setting("input_devices/sensors/enable_gyroscope", true)), "the gyroscope is not needed")
	t.check(not bool(_setting("input_devices/sensors/enable_magnetometer", true)), "the magnetometer is not needed")
	t.check(bool(_setting("display/window/energy_saving/keep_screen_on", false)), "the screen stays on while playing")
	t.eq(String(_setting("rendering/renderer/rendering_method", "")), "gl_compatibility", "the Compatibility renderer (widest device support)")
	t.check(bool(_setting("rendering/textures/vram_compression/import_etc2_astc", false)), "ETC2/ASTC texture import is enabled (required for Android export)")
	t.eq(String(_setting("application/config/name", "")), "Spire Sprint", "the game title")
	t.check(not String(_setting("application/config/version", "")).is_empty(), "the project has a version number")
	t.check(FileAccess.file_exists(String(_setting("application/config/icon", "res://missing"))), "the project icon exists")
	t.check(FileAccess.file_exists(String(_setting("application/run/main_scene", "res://missing"))), "the main scene exists")
	t.check(String(_setting("application/run/main_scene", "")).ends_with("main.tscn"), "the main scene is scenes/main.tscn")


func _architecture(t: TestContext) -> void:
	t.suite("project: modules")
	for autoload_name in AUTOLOADS:
		var key: String = "autoload/%s" % String(autoload_name)
		t.check(ProjectSettings.has_setting(key), "autoload registered: %s" % String(autoload_name))
		if ProjectSettings.has_setting(key):
			var value: String = String(ProjectSettings.get_setting(key))
			t.check(value.begins_with("*"), "%s is a global singleton" % String(autoload_name))
			t.check(FileAccess.file_exists(value.trim_prefix("*")), "%s points at an existing script" % String(autoload_name))
	var known: Dictionary = {}
	for entry in ProjectSettings.get_global_class_list():
		var info: Dictionary = entry
		known[String(info["class"])] = true
	for cls in CLASSES:
		t.check(known.has(String(cls)), "class registered: %s" % String(cls))


# ---------------------------------------------------------------------------
# Tuning
# ---------------------------------------------------------------------------
func _tuning_classification(t: TestContext) -> void:
	t.suite("tuning: every value is classified")
	var tuning: GameTuning = GameTuning.new()
	var kind: Dictionary = {}
	for key in GameTuning.SIM_KEYS:
		kind[String(key)] = "sim"
	for key in NON_SIM_KEYS:
		t.check(not kind.has(String(key)), "'%s' is not listed as both simulation and presentation value" % String(key))
		kind[String(key)] = "other"
	var unclassified: PackedStringArray = PackedStringArray()
	for prop in tuning.get_property_list():
		var info: Dictionary = prop
		var usage: int = int(info["usage"])
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if not kind.has(String(info["name"])):
			unclassified.append(String(info["name"]))
	t.eq(unclassified.size(), 0, "each exported value is a simulation value (stored in replays) or a presentation value; unclassified: %s" % ", ".join(unclassified))
	var missing: PackedStringArray = PackedStringArray()
	for key in GameTuning.SIM_KEYS:
		if not (String(key) in tuning):
			missing.append(String(key))
	t.eq(missing.size(), 0, "every simulation key is a real property; missing: %s" % ", ".join(missing))


func _tuning_snapshots(t: TestContext) -> void:
	t.suite("tuning: replay snapshots and safety")
	var tuning: GameTuning = GameTuning.new()
	var snapshot: Dictionary = tuning.to_sim_dict()
	t.eq(snapshot.size(), GameTuning.SIM_KEYS.size(), "a snapshot holds every simulation value")
	var restored: GameTuning = GameTuning.from_sim_dict(snapshot)
	t.eq(restored.sim_hash(), tuning.sim_hash(), "a snapshot restores exactly")
	var json: JSON = JSON.new()
	t.eq(json.parse(JSON.stringify(snapshot)), OK, "the snapshot is valid JSON")
	var from_json: GameTuning = GameTuning.from_sim_dict(json.data)
	t.eq(from_json.sim_hash(), tuning.sim_hash(), "and restores exactly after a trip through JSON text")

	var changed: GameTuning = GameTuning.new()
	changed.gravity += 1.0
	t.check(changed.sim_hash() != tuning.sim_hash(), "a physics change alters the hash")
	var cosmetic: GameTuning = GameTuning.new()
	cosmetic.screen_shake_scale = 0.0
	cosmetic.tilt_full_deg_low = 40.0
	t.eq(cosmetic.sim_hash(), tuning.sim_hash(), "presentation values are not part of the hash")

	var damaged: GameTuning = GameTuning.from_sim_dict({"gravity": -5, "max_speed": 0.0, "bogus": 1, "tower_width": "wide"})
	t.check(damaged.gravity >= 100.0 and damaged.max_speed >= 50.0 and damaged.tower_width >= 320.0, "values from a damaged file are clamped into a safe range")
	t.eq(damaged.get("bogus"), null, "unknown keys are ignored")

	var bad: GameTuning = GameTuning.new()
	bad.tower_width = 10.0
	bad.gravity = 0.0
	bad.pattern_min_run = 5
	bad.pattern_max_run = 2
	bad.combo_bonus_exponent = 9
	bad.foot_half_width = 99.0
	bad.sanitize()
	t.near(bad.tower_width, 320.0, 1e-9, "a tiny tower width is raised")
	t.near(bad.gravity, 100.0, 1e-9, "zero gravity is raised (no division by zero)")
	t.check(bad.pattern_max_run >= bad.pattern_min_run, "the longest pattern run is never below the shortest")
	t.eq(bad.combo_bonus_exponent, 3, "the combo exponent is limited")
	t.check(bad.foot_half_width <= bad.player_half_width, "the feet are never wider than the body")

	var good: GameTuning = GameTuning.new()
	var before: int = good.sim_hash()
	good.sanitize()
	t.eq(good.sim_hash(), before, "the shipped tuning needs no clamping")
	var res: Resource = load("res://resources/game_tuning.tres")
	t.check(res is GameTuning, "the tuning resource loads as GameTuning")
	if res is GameTuning:
		t.eq((res as GameTuning).sim_hash(), before, "and holds no accidental overrides of the defaults")
	TuningStore.set_tuning(null)
	t.check(TuningStore.get_tuning() != null, "the tuning store always provides a tuning")
	TuningStore.set_tuning(null)


func _tuning_targets(t: TestContext) -> void:
	t.suite("tuning: design targets")
	var tuning: GameTuning = GameTuning.new()
	t.eq(tuning.scroll_start_floor, 5, "the tower starts to scroll at about floor 5")
	t.near(tuning.scroll_stage_seconds, 30.0, 1e-9, "a new speed stage about every 30 seconds")
	t.check(tuning.combo_timeout >= 2.5 and tuning.combo_timeout <= 3.5, "the combo timeout is about 3 seconds")
	t.eq(tuning.combo_min_floors, 2, "a combo needs jumps of two or more floors")
	t.eq(tuning.points_per_floor, 10, "10 points per floor")
	t.eq(tuning.combo_bonus_exponent, 2, "the combo bonus is floors squared")
	t.check(tuning.scroll_speed_max > tuning.scroll_speed_start * 4.0, "the scroll speed has room to grow")
	t.eq(SimConst.TICK_RATE, 120, "the simulation runs at a fixed 120 Hz")
	t.check(tuning.platform_spacing_start + tuning.platform_spacing_jitter < tuning.jump_apex_for_ratio(0.0), "a standing jump always reaches the next floor")
	t.check(tuning.jump_apex_for_ratio(1.0) / tuning.platform_spacing_start >= 4.0, "a full-speed jump crosses at least four floors")
	var previous: float = -1.0
	var rising: bool = true
	for i in range(0, 21):
		var apex: float = tuning.jump_apex_for_ratio(float(i) / 20.0)
		if apex <= previous:
			rising = false
		previous = apex
	t.check(rising, "the faster the run-up, the higher the jump")


# ---------------------------------------------------------------------------
# Safe area
# ---------------------------------------------------------------------------
func _safe_area(t: TestContext) -> void:
	t.suite("safe area insets")
	var vp: Vector2 = Vector2(1600.0, 720.0)
	var win: Vector2i = Vector2i(2400, 1080)
	var m: float = SafeArea.MIN_MARGIN
	var minimum: Vector4 = Vector4(m, m, m, m)
	t.eq(SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(0, 0, 2400, 1080), vp), minimum, "a screen without cutouts still gets the minimum margin")

	var notch: Vector4 = SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(120, 0, 2280, 1080), vp)
	t.near(notch.x, 80.0, 1e-4, "a 120 px notch on the left becomes 80 logical units (scaled by 720/1080)")
	t.eq(notch.y, m, "nothing at the top")
	t.eq(notch.z, m, "nothing on the right")
	t.eq(notch.w, m, "nothing at the bottom")

	var both: Vector4 = SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(120, 0, 2160, 1050), vp)
	t.near(both.x, 80.0, 1e-4, "left cutout")
	t.near(both.z, 80.0, 1e-4, "right cutout")
	t.eq(both.w, m, "a thin gesture bar (20 units) is raised to the minimum margin")

	var bar: Vector4 = SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(0, 0, 2400, 900), vp)
	t.near(bar.w, 120.0, 1e-4, "a 180 px bottom bar becomes 120 units")

	# a window that does not start at the screen origin (split screen, freeform windows)
	var moved: Vector4 = SafeArea.compute_insets(Vector2i(2000, 1000), Vector2i(100, 50), Rect2i(160, 50, 1940, 1000), Vector2(1280.0, 720.0))
	t.near(moved.x, 38.4, 1e-4, "insets are measured from the window, not the screen")
	t.eq(moved.y, m, "top")
	t.eq(moved.z, m, "right")
	t.eq(moved.w, m, "bottom")

	t.eq(SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(), vp), minimum, "an unknown safe area falls back to the minimum margin")
	t.eq(SafeArea.compute_insets(Vector2i.ZERO, Vector2i.ZERO, Rect2i(0, 0, 10, 10), vp), minimum, "a window of size zero does not divide by zero")
	t.eq(SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(0, 0, 2400, 1080), Vector2.ZERO), minimum, "a viewport of size zero does not divide by zero")
	t.eq(SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(-50, -50, 2600, 1200), vp), minimum, "a safe area larger than the window never gives negative insets")

	# the insets always stay inside the viewport and never drop below the minimum
	var sane: bool = true
	for left_px in [0, 40, 130, 300]:
		for bottom_px in [0, 20, 90]:
			var ins: Vector4 = SafeArea.compute_insets(win, Vector2i.ZERO, Rect2i(int(left_px), 0, 2400 - int(left_px) * 2, 1080 - int(bottom_px)), vp)
			if ins.x < m or ins.y < m or ins.z < m or ins.w < m or ins.x + ins.z >= vp.x or ins.y + ins.w >= vp.y:
				sane = false
	t.check(sane, "every combination leaves a usable safe rectangle")


# ---------------------------------------------------------------------------
# Themes
# ---------------------------------------------------------------------------
func _themes(t: TestContext) -> void:
	t.suite("themes")
	var tm: Variant = ThemeScript.new()
	tm._build_themes()
	t.eq(ThemeScript.THEME_COUNT, 11, "eleven tower environments")
	t.eq(tm._themes.size(), ThemeScript.THEME_COUNT, "every one is defined")
	var names: Dictionary = {}
	var styles: Dictionary = {}
	for i in range(ThemeScript.THEME_COUNT):
		var th: Dictionary = tm.get_theme(i)
		names[String(th["name"])] = true
		styles[int(th["style"])] = true
	t.eq(names.size(), ThemeScript.THEME_COUNT, "with unique names")
	t.eq(styles.size(), ThemeScript.THEME_COUNT, "and unique platform styles")

	t.eq(tm.theme_index_for_floor(0), 0, "floor 0 is the first theme")
	t.eq(tm.theme_index_for_floor(99), 0, "floors 0-99 share it")
	t.eq(tm.theme_index_for_floor(100), 1, "a new theme every 100 floors")
	t.eq(tm.theme_index_for_floor(999), 9, "floor 999 is the tenth theme")
	t.eq(tm.theme_index_for_floor(1000), 10, "floor 1000 starts the final theme")
	t.eq(tm.theme_index_for_floor(987654), 10, "which lasts forever")
	t.eq(tm.theme_index_for_floor(-5), 0, "negative floors are safe")
	t.eq(String(tm.get_theme(99)["name"]), String(tm.get_theme(10)["name"]), "out-of-range indices clamp to the last theme")

	var mid: Dictionary = tm.blended_at(50.0)
	t.eq(int(mid["from"]), 0, "inside a theme nothing blends: from")
	t.eq(int(mid["to"]), 0, "inside a theme nothing blends: to")
	t.near(float(mid["t"]), 0.0, 1e-9, "inside a theme nothing blends: t")
	var edge: Dictionary = tm.blended_at(99.0)
	t.eq(int(edge["to"]), 1, "one floor before the boundary the next theme fades in")
	t.check(float(edge["t"]) > 0.5 and float(edge["t"]) < 1.0, "and is mostly there (t=%.2f)" % float(edge["t"]))
	var after: Dictionary = tm.blended_at(100.0)
	t.eq(int(after["from"]), 1, "at the boundary the next theme has taken over")
	t.near(float(after["t"]), 0.0, 1e-9, "without a blend")
	var last: Dictionary = tm.blended_at(5000.0)
	t.check(int(last["from"]) == 10 and int(last["to"]) == 10, "the final theme never blends")
	# no visible jump at a boundary
	var before_top: Color = (tm.blended_at(99.9999)["bg_top"] as Color)
	var after_top: Color = (tm.blended_at(100.0)["bg_top"] as Color)
	t.check(absf(before_top.r - after_top.r) < 0.01 and absf(before_top.g - after_top.g) < 0.01 and absf(before_top.b - after_top.b) < 0.01, "the background colour is continuous across a theme boundary")
	var monotone: bool = true
	var prev_t: float = 0.0
	for k in range(0, 200):
		var f: float = 80.0 + float(k) * 0.1
		var b: Dictionary = tm.blended_at(f)
		var cur_t: float = float(b["t"]) if int(b["from"]) == 0 else 0.0
		if int(b["from"]) == 0 and cur_t < prev_t - 1e-9:
			monotone = false
		prev_t = cur_t
	t.check(monotone, "the blend factor only grows towards the boundary")
	tm.free()


# ---------------------------------------------------------------------------
# Android export
# ---------------------------------------------------------------------------
func _export(t: TestContext) -> void:
	t.suite("Android export presets")
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load("res://export_presets.cfg")
	t.eq(err, OK, "export_presets.cfg exists and parses")
	if err != OK:
		return
	var presets: Dictionary = {}
	for section in cfg.get_sections():
		var s: String = String(section)
		if s.begins_with("preset.") and not s.ends_with(".options"):
			presets[String(cfg.get_value(s, "name", ""))] = s
	t.check(presets.size() >= 2, "an APK preset and an AAB preset are defined (%d found)" % presets.size())
	var has_apk: bool = false
	var has_aab: bool = false
	for preset_name in presets:
		var s2: String = String(presets[preset_name])
		var o: String = s2 + ".options"
		var label: String = String(preset_name)
		t.eq(String(cfg.get_value(s2, "platform", "")), "Android", "%s: platform" % label)
		t.eq(String(cfg.get_value(o, "package/unique_name", "")), PACKAGE_NAME, "%s: package name" % label)
		t.check(bool(cfg.get_value(o, "architectures/arm64-v8a", false)), "%s: 64-bit ARM is included" % label)
		t.check(bool(cfg.get_value(o, "screen/immersive_mode", false)), "%s: immersive fullscreen" % label)
		t.check(bool(cfg.get_value(o, "permissions/vibrate", false)), "%s: vibration permission (haptics)" % label)
		t.check(not bool(cfg.get_value(o, "permissions/internet", false)), "%s: no network permission (the game is fully offline)" % label)
		t.check(int(cfg.get_value(o, "version/code", 0)) >= 1, "%s: version code" % label)
		t.check(not String(cfg.get_value(o, "version/name", "")).is_empty(), "%s: version name" % label)
		t.check(bool(cfg.get_value(o, "screen/support_large", false)) and bool(cfg.get_value(o, "screen/support_xlarge", false)), "%s: tablets are supported" % label)
		if bool(cfg.get_value(o, "gradle_build/use_gradle_build", false)) and int(cfg.get_value(o, "gradle_build/export_format", 0)) == 1:
			has_aab = true
		elif not bool(cfg.get_value(o, "gradle_build/use_gradle_build", false)):
			has_apk = true
	t.check(has_apk, "a preset that builds an APK without Gradle (sideloading)")
	t.check(has_aab, "a Gradle preset that builds an AAB (Google Play)")


# ---------------------------------------------------------------------------
# Assets
# ---------------------------------------------------------------------------
func _assets(t: TestContext) -> void:
	t.suite("shipped assets")
	for i in range(ThemeScript.THEME_COUNT):
		for kind in ["bg_far", "bg_near", "wall"]:
			var path: String = "res://assets/art/themes/%s_%02d.png" % [String(kind), i]
			var exists: bool = ResourceLoader.exists(path)
			t.check(exists, "theme art exists: %s" % path)
			if exists:
				var tex: Texture2D = load(path) as Texture2D
				t.check(tex != null and tex.get_width() >= 16 and tex.get_height() >= 16, "theme art loads: %s" % path)
	for id in BUILTIN_CHARACTERS:
		var sheet: String = "res://assets/art/characters/%s.png" % String(id)
		var found: bool = ResourceLoader.exists(sheet)
		t.check(found, "character sheet exists: %s" % sheet)
		if found:
			var sheet_tex: Texture2D = load(sheet) as Texture2D
			t.check(sheet_tex != null and sheet_tex.get_width() == 768 and sheet_tex.get_height() == 1280, "character sheet is 768x1280: %s" % sheet)
	for sfx in AudioScript.SFX_NAMES:
		var sound: String = "res://assets/audio/%s.wav" % String(sfx)
		var sound_found: bool = ResourceLoader.exists(sound)
		t.check(sound_found, "sound effect exists: %s" % sound)
		if sound_found:
			var stream: AudioStreamWAV = load(sound) as AudioStreamWAV
			t.check(stream != null and stream.get_length() > 0.02 and stream.get_length() < 6.0, "sound effect has a sensible length: %s" % sound)
	for track in ["music_menu", "music_game"]:
		var music: String = "res://assets/audio/%s.wav" % String(track)
		var music_found: bool = ResourceLoader.exists(music)
		t.check(music_found, "music track exists: %s" % music)
		if music_found:
			var loop: AudioStreamWAV = load(music) as AudioStreamWAV
			t.check(loop != null and loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music loops seamlessly: %s" % music)
			t.check(loop != null and loop.get_length() > 15.0, "music is long enough not to feel repetitive: %s" % music)
