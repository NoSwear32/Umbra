class_name ScrollDifficultyManager
extends RefCounted
## Automatic vertical scrolling (the rising "kill line") plus the staged speed-ups.
##
## The camera bottom is expressed as an altitude. Once the player reaches
## `scroll_start_floor` the bottom rises continuously; every `scroll_stage_seconds`
## the speed increases (asymptotically towards `scroll_speed_max`). The bottom also
## follows the player upwards, so big jumps never leave the screen.

signal scroll_started
signal stage_changed(stage: int)

var tuning: GameTuning
## Altitude of the bottom edge of the view (the player dies when the head is below it).
var cam_bottom: float = 0.0
var prev_cam_bottom: float = 0.0
var active: bool = false
var ticks_since_start: int = 0
var stage: int = 0
## Current automatic scroll speed in px/s (0 before scrolling starts).
var speed: float = 0.0

var _local_ticks: int = 0
var _stage_ticks: int = 3600
var _blend_ticks: int = 180
var _ramp_ticks: int = 240


func _init(p_tuning: GameTuning) -> void:
	tuning = p_tuning
	cam_bottom = tuning.camera_start_bottom
	prev_cam_bottom = cam_bottom
	_stage_ticks = tuning.stage_ticks()
	_blend_ticks = tuning.blend_ticks()
	_ramp_ticks = tuning.ramp_ticks()


## Target scroll speed (px/s) of a stage: start + (max - start) * s / (s + halfpoint).
func stage_speed(stage_number: int) -> float:
	var t: GameTuning = tuning
	var s: float = float(stage_number)
	return t.scroll_speed_start + (t.scroll_speed_max - t.scroll_speed_start) * (s / (s + t.scroll_stage_halfpoint))


## Seconds until the next speed-up (for HUD/debug).
func seconds_to_next_stage() -> float:
	return float(_stage_ticks - _local_ticks) * SimConst.DT


func step(head_y: float, highest_floor: int) -> void:
	var t: GameTuning = tuning
	prev_cam_bottom = cam_bottom
	if not active and highest_floor >= t.scroll_start_floor:
		active = true
		scroll_started.emit()
	if active:
		ticks_since_start += 1
		_local_ticks += 1
		if _local_ticks >= _stage_ticks:
			_local_ticks = 0
			stage += 1
			stage_changed.emit(stage)
		var cur: float = stage_speed(stage)
		var spd: float = cur
		if stage > 0 and _local_ticks < _blend_ticks:
			var prev_speed: float = stage_speed(stage - 1)
			spd = prev_speed + (cur - prev_speed) * (float(_local_ticks) / float(_blend_ticks))
		if ticks_since_start < _ramp_ticks:
			spd = spd * (float(ticks_since_start) / float(_ramp_ticks))
		speed = spd
		cam_bottom = cam_bottom + spd * SimConst.DT
	var target: float = head_y - t.camera_follow_line * t.view_height
	if target > cam_bottom:
		cam_bottom = cam_bottom + (target - cam_bottom) * t.camera_follow_gain


## Debug helper: jump straight to a stage (keeps timers consistent).
func debug_set_stage(new_stage: int) -> void:
	stage = maxi(new_stage, 0)
	_local_ticks = 0
	ticks_since_start = maxi(ticks_since_start, _ramp_ticks)
	active = true
	stage_changed.emit(stage)
