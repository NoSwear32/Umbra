extends Node
## Autoload "ReplayManager": stores, lists, renames, deletes, exports and imports replays.
##
## Replay bodies are separate JSON files (user://spire_sprint/replays/<id>.replay.json);
## the list shown in the UI comes from lightweight metadata kept in the profile, so
## opening the Replays screen never has to read every file.

signal list_changed

const AUTOSAVE_ID: String = "_autosave"
## Unprotected replays beyond this number are pruned (oldest first).
const MAX_REPLAYS: int = 40
const MAX_IMPORT_CHARS: int = 12000000


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func replay_path(id: String) -> String:
	return SaveManager.replay_dir + "/" + id + ".replay.json"


func _index() -> Array:
	return SaveManager.array_section("replays")


## Metadata of all replays, newest first.
func list_meta() -> Array:
	var out: Array = []
	for m in _index():
		if m is Dictionary and String((m as Dictionary).get("id", "")) != AUTOSAVE_ID:
			out.append(m)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("created", 0)) > int(b.get("created", 0)))
	return out


func find_meta(id: String) -> Dictionary:
	for m in _index():
		if m is Dictionary and String((m as Dictionary).get("id", "")) == id:
			return m
	return {}


func has_replay(id: String) -> bool:
	return not id.is_empty() and FileAccess.file_exists(replay_path(id))


static func make_id() -> String:
	return "r%d_%04x" % [int(Time.get_unix_time_from_system()), randi() & 0xFFFF]


## Writes a replay file and registers it. Returns the id ("" on failure).
func save_replay(r: ReplayData) -> String:
	if r.id.is_empty():
		r.id = make_id()
	if not _write_file(r):
		return ""
	var meta: Dictionary = r.meta()
	var idx: Array = _index()
	var replaced: bool = false
	for i in range(idx.size()):
		if idx[i] is Dictionary and String((idx[i] as Dictionary).get("id", "")) == r.id:
			idx[i] = meta
			replaced = true
	if not replaced:
		idx.append(meta)
	_prune()
	SaveManager.mark_dirty()
	list_changed.emit()
	return r.id


func _write_file(r: ReplayData) -> bool:
	DirAccess.make_dir_recursive_absolute(SaveManager.replay_dir)
	var path: String = replay_path(r.id)
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(r.to_dictionary(), "", true, true))
	f.flush()
	f.close()
	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return err == OK


## Loads a replay. Returns { "ok": bool, "error": String, "replay": ReplayData }.
func load_replay(id: String) -> Dictionary:
	var path: String = replay_path(id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "The replay file is missing.", "replay": null}
	var parsed: Variant = SaveManager.read_json_file(path)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "The replay file is unreadable.", "replay": null}
	var r: Dictionary = ReplayData.from_dictionary(parsed)
	if bool(r["ok"]):
		(r["replay"] as ReplayData).id = id
	return r


func rename_replay(id: String, new_name: String) -> void:
	var clean: String = new_name.strip_edges().substr(0, 40)
	var m: Dictionary = find_meta(id)
	if m.is_empty():
		return
	m["name"] = clean
	# keep the file header in sync so exported replays carry the name
	var loaded: Dictionary = load_replay(id)
	if bool(loaded["ok"]):
		var r: ReplayData = loaded["replay"]
		r.replay_name = clean
		_write_file(r)
	SaveManager.mark_dirty()
	list_changed.emit()


func delete_replay(id: String) -> void:
	DirAccess.remove_absolute(replay_path(id))
	var idx: Array = _index()
	for i in range(idx.size() - 1, -1, -1):
		if idx[i] is Dictionary and String((idx[i] as Dictionary).get("id", "")) == id:
			idx.remove_at(i)
	LeaderboardManager.forget_replay(id)
	SaveManager.mark_dirty()
	list_changed.emit()


func delete_all() -> void:
	for m in _index().duplicate():
		if m is Dictionary:
			DirAccess.remove_absolute(replay_path(String((m as Dictionary).get("id", ""))))
	SaveManager.data["replays"] = []
	SaveManager.mark_dirty()
	list_changed.emit()


func count() -> int:
	return list_meta().size()


## Replays that are kept forever unless deleted by hand: renamed ones and those linked to a high score.
func _is_protected(m: Dictionary) -> bool:
	if not String(m.get("name", "")).is_empty():
		return true
	var id: String = String(m.get("id", ""))
	for cat in LeaderboardProvider.CATEGORIES:
		for e in SaveManager.section("leaderboards").get(cat, []):
			if e is Dictionary and String((e as Dictionary).get("replay_id", "")) == id:
				return true
	return false


func _prune() -> void:
	var metas: Array = list_meta()
	var over: int = metas.size() - MAX_REPLAYS
	if over <= 0:
		return
	# oldest first
	for i in range(metas.size() - 1, -1, -1):
		if over <= 0:
			break
		var m: Dictionary = metas[i]
		if not _is_protected(m):
			delete_replay(String(m.get("id", "")))
			over -= 1


# ---------------------------------------------------------------------------
# Sharing
# ---------------------------------------------------------------------------
## The replay as one text blob (for the clipboard / share sheet).
func export_text(id: String) -> String:
	if not has_replay(id):
		return ""
	return FileAccess.get_file_as_string(replay_path(id))


## Imports a shared replay. Returns { "ok": bool, "error": String, "id": String }.
func import_text(text: String) -> Dictionary:
	if text.length() > MAX_IMPORT_CHARS:
		return {"ok": false, "error": "The text is too large to be a replay.", "id": ""}
	var json: JSON = JSON.new()
	if text.strip_edges().is_empty() or json.parse(text) != OK or not (json.data is Dictionary):
		return {"ok": false, "error": "The clipboard does not contain a replay.", "id": ""}
	var r: Dictionary = ReplayData.from_dictionary(json.data)
	if not bool(r["ok"]):
		return {"ok": false, "error": String(r["error"]), "id": ""}
	var rep: ReplayData = r["replay"]
	rep.id = make_id()
	rep.replay_name = rep.replay_name if not rep.replay_name.is_empty() else "Imported replay"
	var id: String = save_replay(rep)
	if id.is_empty():
		return {"ok": false, "error": "Could not store the replay.", "id": ""}
	return {"ok": true, "error": "", "id": id}


# ---------------------------------------------------------------------------
# Crash recovery autosave
# ---------------------------------------------------------------------------
func write_autosave(r: ReplayData) -> bool:
	r.id = AUTOSAVE_ID
	return _write_file(r)


func has_autosave() -> bool:
	return FileAccess.file_exists(replay_path(AUTOSAVE_ID))


func clear_autosave() -> void:
	if has_autosave():
		DirAccess.remove_absolute(replay_path(AUTOSAVE_ID))
