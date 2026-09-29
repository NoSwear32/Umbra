class_name LocalLeaderboardProvider
extends LeaderboardProvider
## On-device leaderboards: the top N runs of every category, stored in the profile.

## Entries kept per category.
const MAX_ENTRIES: int = 20

## Where the lists live. Defaults to the profile section of SaveManager; tests pass their own.
var storage: Dictionary = {}
## Called after every change so the owner can persist the profile.
var on_changed: Callable = Callable()


func _init(p_storage: Dictionary = {}) -> void:
	storage = p_storage
	for cat in CATEGORIES:
		_sanitize_category(String(cat))


## Repairs one list of the (possibly hand-edited or damaged) profile: drops junk, restores the
## number types JSON loses, drops entries that could never have ranked, keeps the order
## best-first (ties keep their stored order) and trims to MAX_ENTRIES.
func _sanitize_category(cat: String) -> void:
	var cleaned: Array = []
	var source: Variant = storage.get(cat, [])
	if source is Array:
		for e in source:
			if not (e is Dictionary):
				continue
			var n: Dictionary = _normalize(e)
			var value: int = value_of(n, cat)
			if value <= 0:
				continue
			var pos: int = cleaned.size()
			while pos > 0 and value_of(cleaned[pos - 1], cat) < value:
				pos -= 1
			cleaned.insert(pos, n)
	while cleaned.size() > MAX_ENTRIES:
		cleaned.pop_back()
	storage[cat] = cleaned


func provider_id() -> String:
	return "local"


func display_name() -> String:
	return "This device"


func get_entries(category: String) -> Array:
	if not storage.has(category):
		return []
	var out: Array = []
	for e in storage[category]:
		if e is Dictionary:
			out.append(_normalize(e))
	return out


func best_value(category: String) -> int:
	var list: Array = get_entries(category)
	if list.is_empty():
		return 0
	return value_of(list[0], category)


## Rank (1-based) a value would take, or 0 if it would not make the list.
func rank_for(category: String, value: int) -> int:
	if value <= 0:
		return 0
	var list: Array = get_entries(category)
	var rank: int = 1
	for e in list:
		if value_of(e, category) >= value:
			rank += 1
		else:
			break
	if rank > MAX_ENTRIES:
		return 0
	return rank


func submit(entry: Dictionary) -> Dictionary:
	var e: Dictionary = _normalize(entry)
	var result: Dictionary = {"records": {}}
	for cat in CATEGORIES:
		var value: int = value_of(e, cat)
		var previous_best: int = best_value(cat)
		var rank: int = rank_for(cat, value)
		result[cat] = rank
		result["records"][cat] = value > 0 and value > previous_best
		if rank == 0:
			continue
		var list: Array = storage[cat]
		list.insert(rank - 1, e.duplicate())
		while list.size() > MAX_ENTRIES:
			list.pop_back()
	if on_changed.is_valid():
		on_changed.call()
	return result


func clear() -> void:
	for cat in CATEGORIES:
		storage[cat] = []
	if on_changed.is_valid():
		on_changed.call()


## JSON stores every number as float: restore the proper types.
static func _normalize(e: Dictionary) -> Dictionary:
	return {
		"name": String(e.get("name", "Climber")),
		"score": int(e.get("score", 0)),
		"floor": int(e.get("floor", 0)),
		"combo": int(e.get("combo", 0)),
		"combo_jumps": int(e.get("combo_jumps", 0)),
		"date": int(e.get("date", 0)),
		"duration": float(e.get("duration", 0.0)),
		"replay_id": String(e.get("replay_id", "")),
		"character": String(e.get("character", "pip")),
		"seed": int(e.get("seed", 0)),
		"control": String(e.get("control", "touch")),
	}
