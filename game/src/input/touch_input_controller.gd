class_name TouchInputController
extends RefCounted
## Control mode A: two touch zones (LEFT / RIGHT) with "release to jump".
##
## Pure logic - no nodes, no engine input - so it can be unit tested by feeding
## synthetic touch events with explicit timestamps.
##
## Rules
##  * Holding a zone accelerates in that direction (axis = -1 / +1).
##  * RELEASING the currently active zone requests exactly one jump, provided the
##    zone was held for at least `min_hold` seconds (filters accidental taps).
##  * If both zones are held, the zone pressed LAST is active. Releasing the active
##    zone jumps and hands the direction back to the other zone if it is still down.
##    Releasing the inactive zone never jumps.
##  * A finger sliding out of its zone (beyond `slop`) counts as a release.
##  * Multi-touch: every finger is tracked by its touch index.
##  * The controller never knows whether the character is airborne: the simulation
##    ignores jump requests in mid-air (except the tiny landing buffer), so releasing
##    in the air can never create a double jump.

signal jump_requested

enum Zone { NONE = 0, LEFT = 1, RIGHT = 2 }

## Hit rectangles in viewport (logical) coordinates.
var left_rect: Rect2 = Rect2()
var right_rect: Rect2 = Rect2()
## Extra margin around a zone that still counts as "inside" for a finger that is already down.
var slop: float = 40.0
## Minimum hold time (seconds) for a release to count as a jump.
var min_hold: float = 0.05
var enabled: bool = true

## Current horizontal input: -1, 0 or +1.
var axis: float = 0.0
## Currently active zone (for the on-screen button highlight).
var active_zone: int = Zone.NONE

# touch index -> {zone:int, start:float, seq:int}
var _touches: Dictionary = {}
var _seq: int = 0


func set_zones(p_left: Rect2, p_right: Rect2) -> void:
	left_rect = p_left
	right_rect = p_right


## True if the given zone currently has at least one finger on it.
func is_zone_held(zone: int) -> bool:
	for idx in _touches:
		var info: Dictionary = _touches[idx]
		if int(info["zone"]) == zone:
			return true
	return false


func touch_count() -> int:
	return _touches.size()


func zone_at(pos: Vector2, inflate: float = 0.0) -> int:
	if left_rect.grow(inflate).has_point(pos):
		return Zone.LEFT
	if right_rect.grow(inflate).has_point(pos):
		return Zone.RIGHT
	return Zone.NONE


func touch_down(index: int, pos: Vector2, time: float) -> void:
	if not enabled:
		return
	if _touches.has(index):
		return
	var z: int = zone_at(pos)
	if z == Zone.NONE:
		return
	_seq += 1
	_touches[index] = {"zone": z, "start": time, "seq": _seq}
	_recompute()


func touch_move(index: int, pos: Vector2, time: float) -> void:
	if not enabled or not _touches.has(index):
		return
	var info: Dictionary = _touches[index]
	var z: int = int(info["zone"])
	var still_inside: bool = false
	if z == Zone.LEFT:
		still_inside = left_rect.grow(slop).has_point(pos)
	elif z == Zone.RIGHT:
		still_inside = right_rect.grow(slop).has_point(pos)
	if not still_inside:
		# the finger left its button: behaves like a release
		touch_up(index, time)
		# ...and may have slid onto the other button, which is a fresh press
		touch_down(index, pos, time)


func touch_up(index: int, time: float) -> void:
	if not _touches.has(index):
		return
	var info: Dictionary = _touches[index]
	var was_active: bool = int(info["seq"]) == _active_seq()
	var held: float = time - float(info["start"])
	_touches.erase(index)
	_recompute()
	if enabled and was_active and held >= min_hold:
		jump_requested.emit()


## The system cancelled a touch (palm rejection, gesture takeover): release without a jump.
func touch_cancel(index: int) -> void:
	if _touches.has(index):
		_touches.erase(index)
		_recompute()


## Drops every touch without requesting jumps (pause, focus loss, mode change).
func cancel_all() -> void:
	_touches.clear()
	_recompute()


func set_enabled(value: bool) -> void:
	if enabled and not value:
		cancel_all()
	enabled = value


func _active_seq() -> int:
	var best: int = -1
	for idx in _touches:
		var s: int = int(_touches[idx]["seq"])
		if s > best:
			best = s
	return best


func _recompute() -> void:
	var best: int = -1
	var zone: int = Zone.NONE
	for idx in _touches:
		var info: Dictionary = _touches[idx]
		var s: int = int(info["seq"])
		if s > best:
			best = s
			zone = int(info["zone"])
	active_zone = zone
	if zone == Zone.LEFT:
		axis = -1.0
	elif zone == Zone.RIGHT:
		axis = 1.0
	else:
		axis = 0.0
