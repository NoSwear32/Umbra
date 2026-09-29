class_name CameraController
extends RefCounted
## Presentation-only camera: screen shake ("trauma") and a subtle zoom pulse for big combos.
## The simulation's scrolling camera decides WHERE the view is; this class only adds juice and
## writes the final transform of the world root. It never influences gameplay.

## Trauma 0..1: shake amplitude grows with the square of it and decays quickly.
var trauma: float = 0.0
var pulse: float = 0.0
var offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0

const MAX_SHAKE: float = 16.0
const TRAUMA_DECAY: float = 1.9


func reset() -> void:
	trauma = 0.0
	pulse = 0.0
	offset = Vector2.ZERO
	zoom = 1.0


static func shake_allowed() -> bool:
	return SettingsManager.get_bool("screen_shake") and not SettingsManager.get_bool("reduced_effects")


func add_trauma(amount: float, tuning: GameTuning) -> void:
	if not shake_allowed():
		return
	trauma = minf(trauma + amount * tuning.screen_shake_scale, 1.0)


func add_pulse(amount: float) -> void:
	if not shake_allowed():
		return
	pulse = minf(pulse + amount, 0.05)


func update(delta: float) -> void:
	trauma = maxf(trauma - delta * TRAUMA_DECAY, 0.0)
	pulse = pulse * exp(-delta * 7.0)
	if trauma > 0.001:
		var amp: float = MAX_SHAKE * trauma * trauma
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp
	else:
		offset = Vector2.ZERO
	zoom = 1.0 + pulse


## Positions the world root so that altitude `cam_bottom` is at the bottom edge of the screen.
## `tower_left` is the screen x of the tower's left wall.
func apply_to(world_root: Node2D, cam_bottom: float, viewport_size: Vector2, tower_left: float) -> void:
	var base: Vector2 = Vector2(tower_left, viewport_size.y + cam_bottom)
	var center: Vector2 = viewport_size * 0.5
	world_root.scale = Vector2(zoom, zoom)
	world_root.position = center + (base - center) * zoom + offset
