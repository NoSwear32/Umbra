class_name ReplayData
extends RefCounted
## A recorded run. NOT a video: it stores the seed, the tuning snapshot and every input
## change with its exact simulation tick, so playback simply re-simulates the run.
##
## Input events are stored as flat triples in `events`:  [tick, axis_q, flags, tick, ...]
##   tick   : 1-based number of the simulation tick the input applies to
##   axis_q : quantised horizontal axis, -127 .. 127  (axis = axis_q / 127.0)
##   flags  : bit 0 = jump requested on this tick
## Only changes of the axis and jump presses are stored, so replays stay tiny.
##
## File format (JSON): see to_dictionary(). Events are delta/varint encoded, deflated and
## base64 encoded so a replay can also be shared as plain text.

const FORMAT_ID: String = "spire-sprint-replay"
const FORMAT_VERSION: int = 1
const MAX_EVENTS: int = 3000000
const MAX_RAW_BYTES: int = 24000000

var id: String = ""
## User supplied title (empty = automatic title).
var replay_name: String = ""
var created: int = 0
var game_version: String = ""
var sim_version: int = SimConst.SIM_VERSION
var seed_value: int = 0
var character: String = "pip"
var control: String = "touch"
var tuning_snapshot: Dictionary = {}
var tuning_hash: int = 0
var score: int = 0
var highest_floor: int = 0
var best_combo_floors: int = 0
var best_combo_jumps: int = 0
var duration_ticks: int = 0
## False for an autosave of a run that was interrupted (app killed / backgrounded).
var complete: bool = true
var events: PackedInt32Array = PackedInt32Array()


func duration_seconds() -> float:
	return float(duration_ticks) * SimConst.DT


func event_count() -> int:
	return int(events.size() / 3)


## Metadata for the replay list (kept in the profile so the list needs no file access).
func meta() -> Dictionary:
	return {
		"id": id,
		"name": replay_name,
		"created": created,
		"score": score,
		"floor": highest_floor,
		"combo": best_combo_floors,
		"duration": duration_seconds(),
		"character": character,
		"control": control,
		"sim_version": sim_version,
		"game_version": game_version,
		"complete": complete,
	}


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------
static func encode_events(ev: PackedInt32Array) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var prev_tick: int = 0
	var i: int = 0
	while i + 2 < ev.size():
		var delta: int = ev[i] - prev_tick
		prev_tick = ev[i]
		while delta >= 0x80:
			out.append((delta & 0x7F) | 0x80)
			delta = delta >> 7
		out.append(delta)
		out.append(ev[i + 1] + 127)
		out.append(ev[i + 2] & 0xFF)
		i += 3
	return out


## Returns an empty array on malformed data.
static func decode_events(raw: PackedByteArray, expected_count: int) -> PackedInt32Array:
	var ev: PackedInt32Array = PackedInt32Array()
	var pos: int = 0
	var tick: int = 0
	var n: int = raw.size()
	while pos < n:
		var delta: int = 0
		var shift: int = 0
		var guard: int = 0
		while true:
			if pos >= n or guard > 5:
				return PackedInt32Array()
			var b: int = raw[pos]
			pos += 1
			guard += 1
			delta = delta | ((b & 0x7F) << shift)
			if (b & 0x80) == 0:
				break
			shift += 7
		if pos + 2 > n:
			return PackedInt32Array()
		var aq: int = int(raw[pos]) - 127
		var flags: int = raw[pos + 1]
		pos += 2
		tick += delta
		if aq < -SimConst.AXIS_STEPS or aq > SimConst.AXIS_STEPS:
			return PackedInt32Array()
		ev.append(tick)
		ev.append(aq)
		ev.append(flags)
		if ev.size() > MAX_EVENTS * 3:
			return PackedInt32Array()
	if expected_count >= 0 and int(ev.size() / 3) != expected_count:
		return PackedInt32Array()
	return ev


func to_dictionary() -> Dictionary:
	var raw: PackedByteArray = encode_events(events)
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return {
		"format": FORMAT_ID,
		"format_version": FORMAT_VERSION,
		"game_version": game_version,
		"sim_version": sim_version,
		"tick_rate": SimConst.TICK_RATE,
		"id": id,
		"name": replay_name,
		"created": created,
		"seed": seed_value,
		"character": character,
		"control": control,
		"tuning": tuning_snapshot,
		"tuning_hash": tuning_hash,
		"score": score,
		"floor": highest_floor,
		"combo": best_combo_floors,
		"combo_jumps": best_combo_jumps,
		"duration_ticks": duration_ticks,
		"duration": duration_seconds(),
		"complete": complete,
		"event_count": event_count(),
		"raw_size": raw.size(),
		"events": Marshalls.raw_to_base64(packed),
	}


## Parses and validates a replay dictionary. Returns { "ok": bool, "error": String, "replay": ReplayData }.
static func from_dictionary(d: Dictionary) -> Dictionary:
	if String(d.get("format", "")) != FORMAT_ID:
		return _fail("This is not a Spire Sprint replay.")
	if int(d.get("format_version", 0)) != FORMAT_VERSION:
		return _fail("Unsupported replay file version.")
	if int(d.get("tick_rate", 0)) != SimConst.TICK_RATE:
		return _fail("The replay was recorded with a different simulation rate.")
	var r: ReplayData = ReplayData.new()
	r.id = String(d.get("id", ""))
	r.replay_name = String(d.get("name", "")).substr(0, 40)
	r.created = int(d.get("created", 0))
	r.game_version = String(d.get("game_version", ""))
	r.sim_version = int(d.get("sim_version", 0))
	r.seed_value = int(d.get("seed", 0)) & 0xFFFFFFFF
	r.character = String(d.get("character", "pip"))
	r.control = String(d.get("control", "touch"))
	var tun: Variant = d.get("tuning", {})
	r.tuning_snapshot = tun if tun is Dictionary else {}
	r.tuning_hash = int(d.get("tuning_hash", 0))
	r.score = int(d.get("score", 0))
	r.highest_floor = int(d.get("floor", 0))
	r.best_combo_floors = int(d.get("combo", 0))
	r.best_combo_jumps = int(d.get("combo_jumps", 0))
	r.duration_ticks = int(d.get("duration_ticks", 0))
	r.complete = bool(d.get("complete", true))
	var raw_size: int = int(d.get("raw_size", 0))
	var count: int = int(d.get("event_count", 0))
	if raw_size < 0 or raw_size > MAX_RAW_BYTES or count < 0 or count > MAX_EVENTS:
		return _fail("The replay data is invalid (size).")
	var b64: String = String(d.get("events", ""))
	if raw_size == 0:
		r.events = PackedInt32Array()
		return {"ok": true, "error": "", "replay": r}
	var packed: PackedByteArray = Marshalls.base64_to_raw(b64)
	var raw: PackedByteArray = packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return _fail("The replay data is corrupted.")
	r.events = decode_events(raw, count)
	if r.events.size() != count * 3:
		return _fail("The replay data is corrupted.")
	return {"ok": true, "error": "", "replay": r}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "replay": null}
