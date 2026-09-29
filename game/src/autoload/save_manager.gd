extends Node
## Autoload "SaveManager": versioned, crash-safe persistence of the whole profile.
##
## Everything (settings, statistics, leaderboards, unlocks, replay index...) lives in
## one JSON document `user://spire_sprint/profile.json`.
##
## Safety
##  * Atomic writes: write `profile.tmp.json` -> read it back and validate -> copy the
##    current profile to `profile.bak.json` -> rename tmp over the profile.
##  * Loading tries profile -> tmp -> backup, so a crash at any point loses at most the
##    last few seconds and never the whole profile.
##  * Versioned with a migration chain (`MIGRATIONS`). Unknown keys are preserved, so
##    a downgrade or a newer file never wipes records.
##  * Saves are debounced (dirty flag + timer) so gameplay never hitches on disk I/O.

signal loaded
signal saved
signal save_failed(reason: String)

const SAVE_VERSION: int = 1
const DIR_PATH: String = "user://spire_sprint"
const MAIN_PATH: String = "user://spire_sprint/profile.json"
const BACKUP_PATH: String = "user://spire_sprint/profile.bak.json"
const TMP_PATH: String = "user://spire_sprint/profile.tmp.json"
const REPLAY_DIR: String = "user://spire_sprint/replays"
const CHARACTER_DIR: String = "user://spire_sprint/characters"
const SAVE_DEBOUNCE_SECONDS: float = 1.0

## The live profile document. Managers read/write their own sections.
var data: Dictionary = {}
## Where the profile came from at startup: "new", "main", "tmp" or "backup".
var loaded_from: String = "new"
## True if the file on disk was written by a newer version of the game.
var future_version: bool = false

## Migration steps: key = version to migrate FROM, value = Callable(data: Dictionary) -> void
## that upgrades the dictionary in place to key + 1. Example for a future version 2:
##   MIGRATIONS[1] = _migrate_1_to_2
var migrations: Dictionary = {}

## File locations (instance variables so tests can point them at a scratch folder).
var dir_path: String = DIR_PATH
var main_path: String = MAIN_PATH
var backup_path: String = BACKUP_PATH
var tmp_path: String = TMP_PATH

var _dirty: bool = false
var _timer: float = 0.0
var _last_error: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_all()


func _process(delta: float) -> void:
	if _dirty:
		_timer -= delta
		if _timer <= 0.0:
			save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		flush()


# ---------------------------------------------------------------------------
# Defaults / sections
# ---------------------------------------------------------------------------
func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"created": Time.get_unix_time_from_system(),
		"settings": {},
		"stats": {},
		"leaderboards": {"score": [], "floor": [], "combo": []},
		"unlocked": ["pip"],
		"selected_character": "pip",
		"replays": [],
		"custom_characters": [],
		"active_run": {},
		"misc": {},
	}


## Returns (and creates when missing) a top-level dictionary section.
func section(key: String) -> Dictionary:
	if not data.has(key) or not (data[key] is Dictionary):
		data[key] = {}
	return data[key]


## Returns (and creates when missing) a top-level array section.
func array_section(key: String) -> Array:
	if not data.has(key) or not (data[key] is Array):
		data[key] = []
	return data[key]


func mark_dirty() -> void:
	if not _dirty:
		_timer = SAVE_DEBOUNCE_SECONDS
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## Saves immediately when there are pending changes (pause / quit / game over).
func flush() -> void:
	if _dirty:
		save_now()


func last_error() -> String:
	return _last_error


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------
func load_all() -> void:
	DirAccess.make_dir_recursive_absolute(dir_path)
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	DirAccess.make_dir_recursive_absolute(CHARACTER_DIR)
	var candidates: Array = [["main", main_path], ["tmp", tmp_path], ["backup", backup_path]]
	var found: Dictionary = {}
	var source: String = "new"
	for c in candidates:
		var parsed: Variant = read_json_file(String(c[1]))
		if parsed is Dictionary and _is_valid_profile(parsed):
			found = parsed
			source = String(c[0])
			break
		elif FileAccess.file_exists(String(c[1])) and String(c[0]) == "main":
			# keep the unreadable file for post-mortem instead of overwriting it silently
			DirAccess.copy_absolute(String(c[1]), dir_path + "/profile.corrupt.json")
	loaded_from = source
	if source == "new":
		data = default_data()
		_dirty = true
		_timer = 0.0
	else:
		data = migrate(found)
		_fill_missing_sections()
		if source != "main":
			# recovered from a fallback: write a clean main file soon
			_dirty = true
			_timer = 0.0
	loaded.emit()


func _is_valid_profile(d: Dictionary) -> bool:
	if not d.has("version"):
		return false
	var v: Variant = d["version"]
	return (v is int or v is float) and int(v) >= 1


func _fill_missing_sections() -> void:
	var defaults: Dictionary = default_data()
	for key in defaults:
		if not data.has(key):
			data[key] = defaults[key]
	# leaderboards need all three categories
	var lb: Dictionary = section("leaderboards")
	for cat in ["score", "floor", "combo"]:
		if not lb.has(cat) or not (lb[cat] is Array):
			lb[cat] = []


## Upgrades a profile dictionary to SAVE_VERSION using the registered migration steps.
func migrate(d: Dictionary) -> Dictionary:
	var v: int = int(d.get("version", 1))
	if v > SAVE_VERSION:
		future_version = true
		return d
	while v < SAVE_VERSION:
		if migrations.has(v):
			var step: Callable = migrations[v]
			step.call(d)
		v += 1
		d["version"] = v
	return d


static func read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	if text.is_empty():
		return null
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


# ---------------------------------------------------------------------------
# Saving
# ---------------------------------------------------------------------------
func save_now() -> bool:
	_dirty = false
	if not future_version:
		data["version"] = SAVE_VERSION
	var text: String = JSON.stringify(data, "", true)
	var ok: bool = write_atomic(text)
	if ok:
		saved.emit()
		if is_inside_tree():
			Events.save_completed.emit()
	else:
		_dirty = true
		_timer = 5.0
		save_failed.emit(_last_error)
	return ok


## Crash-safe write of `text` to main_path (tmp -> verify -> backup -> rename).
func write_atomic(text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		_last_error = "cannot open temp file (error %d)" % FileAccess.get_open_error()
		return false
	f.store_string(text)
	f.flush()
	f.close()
	var check: Variant = read_json_file(tmp_path)
	if not (check is Dictionary) or not _is_valid_profile(check):
		_last_error = "verification of the temp file failed"
		return false
	if FileAccess.file_exists(main_path):
		DirAccess.copy_absolute(main_path, backup_path)
	var err: int = DirAccess.rename_absolute(tmp_path, main_path)
	if err != OK:
		# some platforms refuse to overwrite: remove the old file and retry
		DirAccess.remove_absolute(main_path)
		err = DirAccess.rename_absolute(tmp_path, main_path)
	if err != OK:
		_last_error = "rename failed (error %d)" % err
		return false
	return true


# ---------------------------------------------------------------------------
# Reset helpers (Settings > Data)
# ---------------------------------------------------------------------------
func reset_section(key: String, default_value: Variant) -> void:
	data[key] = default_value
	mark_dirty()


## Wipes everything (settings, records, stats, unlocks, replay index) and saves.
func reset_all() -> void:
	data = default_data()
	future_version = false
	save_now()
	loaded.emit()
