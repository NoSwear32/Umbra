extends Node
## Autoload "CharacterManager": the roster of playable characters, unlocks and custom packs.
##
## All characters use identical physics; they only differ in looks, so leaderboards stay
## fair. Built-in characters unlock through lifetime statistics. Custom packs
## (.spirechar files, see CharacterPack) are always available once imported.

const SHEET_DIR: String = "res://assets/art/characters/"
const MAX_IMPORT_BYTES: int = 2600000

var selected_id: String = "pip"

var _defs: Dictionary = {}
var _order: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.loaded.connect(_reload)
	_reload()


func _reload() -> void:
	_defs.clear()
	_order.clear()
	_register_builtins()
	_load_custom_packs()
	var unlocked: Array = SaveManager.array_section("unlocked")
	if not unlocked.has("pip"):
		unlocked.append("pip")
	var wanted: String = String(SaveManager.data.get("selected_character", "pip"))
	if _defs.has(wanted) and is_unlocked(wanted):
		selected_id = wanted
	else:
		selected_id = "pip"


# ---------------------------------------------------------------------------
# Roster
# ---------------------------------------------------------------------------
func _add_builtin(id: String, display_name: String, tagline: String, stat: String, target: int, ui: Color, scarf1: Color, scarf2: Color) -> void:
	var d: CharacterDef = CharacterDef.new()
	d.id = id
	d.display_name = display_name
	d.tagline = tagline
	d.unlock_stat = stat
	d.unlock_target = target
	d.ui_color = ui
	d.scarf_color = scarf1
	d.scarf_color2 = scarf2
	d.animations = CharacterDef.default_animations()
	d.sheet_path = SHEET_DIR + id + ".png"
	_defs[id] = d
	_order.append(id)


func _register_builtins() -> void:
	_add_builtin("pip", "Pip", "A scrappy fox-kit courier. The scarf never stops.", "", 0,
		Color("ff8c42"), Color("21c4c4"), Color("ffd54a"))
	_add_builtin("bolt", "Bolt", "A clockwork robot running on spare parts and optimism.", "highest_floor", 50,
		Color("5aa9ff"), Color("ff5252"), Color("ffd54a"))
	_add_builtin("moss", "Moss", "A leaf-hatted frog from the overgrown ruins.", "games_played", 10,
		Color("6fd06f"), Color("f2e05c"), Color("ffffff"))
	_add_builtin("nova", "Nova", "A star-child who tumbled down from the upper terraces.", "highest_score", 10000,
		Color("ffd84a"), Color("ff6bd6"), Color("6be6ff"))
	_add_builtin("wraith", "Wraith", "A very polite ghost. Not haunted. Probably.", "longest_combo", 30,
		Color("b39bff"), Color("7a5cff"), Color("ffffff"))
	_add_builtin("ember", "Ember", "A flame-tailed lizard who hates falling behind.", "highest_floor", 200,
		Color("ff5a3c"), Color("ff9b3c"), Color("ffee7a"))
	_add_builtin("zenith", "Zenith", "Crowned by the storm. Reserved for tower legends.", "highest_floor", 1000,
		Color("fff2a6"), Color("ffd45a"), Color("ffffff"))


func builtin_ids() -> Array:
	var out: Array = []
	for id in _order:
		if not (_defs[id] as CharacterDef).custom:
			out.append(id)
	return out


func all_ids() -> Array:
	return _order.duplicate()


func has_character(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> CharacterDef:
	if _defs.has(id):
		return _defs[id]
	return _defs["pip"]


func selected_def() -> CharacterDef:
	return get_def(selected_id)


# ---------------------------------------------------------------------------
# Unlocks
# ---------------------------------------------------------------------------
func is_unlocked(id: String) -> bool:
	if not _defs.has(id):
		return false
	var d: CharacterDef = _defs[id]
	if d.custom or d.unlock_stat.is_empty():
		return true
	return SaveManager.array_section("unlocked").has(id)


## Progress towards the unlock: { "current": int, "target": int, "text": String }.
func unlock_progress(id: String) -> Dictionary:
	var d: CharacterDef = get_def(id)
	if d.unlock_stat.is_empty():
		return {"current": 1, "target": 1, "text": "Unlocked"}
	var cur: int = int(StatisticsManager.get_stat(d.unlock_stat))
	return {"current": cur, "target": d.unlock_target, "text": unlock_text(d)}


static func unlock_text(d: CharacterDef) -> String:
	match d.unlock_stat:
		"highest_floor":
			return "Reach floor %d" % d.unlock_target
		"highest_score":
			return "Score %s points in one run" % Fmt.number(d.unlock_target)
		"longest_combo":
			return "Pull off a %d-floor combo" % d.unlock_target
		"games_played":
			return "Play %d runs" % d.unlock_target
		"wall_rebounds":
			return "Rebound off walls %d times" % d.unlock_target
		"total_playtime_seconds":
			return "Climb for %d minutes in total" % int(float(d.unlock_target) / 60.0)
	return "Locked"


## Unlocks every character whose requirement is met. Returns the newly unlocked ids.
func check_unlocks() -> Array:
	var newly: Array = []
	var unlocked: Array = SaveManager.array_section("unlocked")
	for id in _order:
		var d: CharacterDef = _defs[id]
		if d.custom or d.unlock_stat.is_empty() or unlocked.has(id):
			continue
		if float(StatisticsManager.get_stat(d.unlock_stat)) >= float(d.unlock_target):
			unlocked.append(id)
			newly.append(id)
			Events.character_unlocked.emit(id)
	if not newly.is_empty():
		SaveManager.mark_dirty()
	return newly


func select(id: String) -> bool:
	if not _defs.has(id) or not is_unlocked(id):
		return false
	selected_id = id
	SaveManager.data["selected_character"] = id
	SaveManager.mark_dirty()
	Events.character_changed.emit(id)
	return true


# ---------------------------------------------------------------------------
# Custom packs
# ---------------------------------------------------------------------------
func _pack_path(id: String) -> String:
	return SaveManager.character_dir + "/" + id + ".spirechar"


func _load_custom_packs() -> void:
	var list: Array = SaveManager.array_section("custom_characters")
	var keep: Array = []
	var reserved: Array = builtin_ids()
	for entry in list:
		if not (entry is Dictionary):
			continue
		var id: String = String((entry as Dictionary).get("id", ""))
		var path: String = _pack_path(id)
		if id.is_empty() or not FileAccess.file_exists(path):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		var r: Dictionary = CharacterPack.parse(text, reserved)
		if bool(r["ok"]):
			var d: CharacterDef = r["def"]
			_defs[d.id] = d
			_order.append(d.id)
			keep.append(entry)
	SaveManager.data["custom_characters"] = keep


## Imports a pack from its text. Returns { "ok": bool, "error": String, "id": String }.
func import_pack_text(text: String) -> Dictionary:
	var r: Dictionary = CharacterPack.parse(text, builtin_ids())
	if not bool(r["ok"]):
		return {"ok": false, "error": String(r["error"]), "id": ""}
	var d: CharacterDef = r["def"]
	DirAccess.make_dir_recursive_absolute(SaveManager.character_dir)
	var f: FileAccess = FileAccess.open(_pack_path(d.id), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Could not store the character (storage error).", "id": ""}
	f.store_string(text)
	f.close()
	var replaced: bool = _defs.has(d.id)
	_defs[d.id] = d
	if not replaced:
		_order.append(d.id)
	var list: Array = SaveManager.array_section("custom_characters")
	var found: bool = false
	for e in list:
		if e is Dictionary and String((e as Dictionary).get("id", "")) == d.id:
			found = true
	if not found:
		list.append({"id": d.id, "name": d.display_name})
	SaveManager.mark_dirty()
	return {"ok": true, "error": "", "id": d.id}


## Imports a pack from a file path or content URI (e.g. returned by the system file picker).
func import_pack_file(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "The file could not be opened.", "id": ""}
	# read at most one byte more than allowed: never trust file sizes
	var bytes: PackedByteArray = f.get_buffer(MAX_IMPORT_BYTES + 1)
	f.close()
	if bytes.size() > MAX_IMPORT_BYTES:
		return {"ok": false, "error": "The file is too large.", "id": ""}
	return import_pack_text(bytes.get_string_from_utf8())


func remove_custom(id: String) -> void:
	if not _defs.has(id) or not (_defs[id] as CharacterDef).custom:
		return
	_defs.erase(id)
	_order.erase(id)
	DirAccess.remove_absolute(_pack_path(id))
	var list: Array = SaveManager.array_section("custom_characters")
	for i in range(list.size() - 1, -1, -1):
		var e: Variant = list[i]
		if e is Dictionary and String((e as Dictionary).get("id", "")) == id:
			list.remove_at(i)
	if selected_id == id:
		select("pip")
	SaveManager.mark_dirty()
