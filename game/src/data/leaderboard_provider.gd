class_name LeaderboardProvider
extends RefCounted
## Interface for leaderboard back ends.
##
## The game only talks to LeaderboardManager, which fans out to registered providers.
## The shipped LocalLeaderboardProvider stores everything on the device. An online
## provider (a subclass of this class) can be added later with
## `LeaderboardManager.register_provider(MyOnlineProvider.new())` without touching any
## gameplay code. Online connectivity is never required to play: providers must fail
## soft (queue the submission, return an empty list) when offline.

const CATEGORY_SCORE: String = "score"
const CATEGORY_FLOOR: String = "floor"
const CATEGORY_COMBO: String = "combo"
const CATEGORIES: Array = ["score", "floor", "combo"]


## Stable identifier, e.g. "local".
func provider_id() -> String:
	return "abstract"


## Human readable name for the UI.
func display_name() -> String:
	return provider_id()


## True if entries come from a remote service.
func is_online() -> bool:
	return false


## Entries of one category, best first. Each entry is a Dictionary:
## { name, score, floor, combo, combo_jumps, date, duration, replay_id, character, seed, control }
func get_entries(_category: String) -> Array:
	return []


## Submits a finished run. Returns { "score": rank, "floor": rank, "combo": rank,
## "records": { "score": bool, "floor": bool, "combo": bool } } where rank is 1-based
## (0 = did not place). Remote providers may return an empty dictionary.
func submit(_entry: Dictionary) -> Dictionary:
	return {}


## Number of submissions waiting for connectivity (online providers only).
func pending_count() -> int:
	return 0


## Try to flush queued submissions (online providers only).
func sync() -> void:
	pass


## Value of an entry for a category.
static func value_of(entry: Dictionary, category: String) -> int:
	match category:
		CATEGORY_SCORE:
			return int(entry.get("score", 0))
		CATEGORY_FLOOR:
			return int(entry.get("floor", 0))
		CATEGORY_COMBO:
			return int(entry.get("combo", 0))
	return 0
