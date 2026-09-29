class_name Haptics
extends RefCounted
## Vibration feedback. Respects the Haptics setting and silently does nothing on
## devices without a vibrator (and on desktop).


static func pulse(duration_ms: int, amplitude: float = 0.5) -> void:
	if not SettingsManager.get_bool("haptics"):
		return
	if not OS.has_feature("mobile"):
		return
	Input.vibrate_handheld(duration_ms, clampf(amplitude, 0.0, 1.0))


## Light tick for UI/jumps.
static func tap() -> void:
	pulse(14, 0.35)


## Stronger pulse for wall rebounds; scales with the impact speed ratio (0..1).
static func rebound(strength: float) -> void:
	pulse(int(lerpf(18.0, 42.0, clampf(strength, 0.0, 1.0))), lerpf(0.4, 0.9, clampf(strength, 0.0, 1.0)))


## Combo completion / records.
static func celebrate() -> void:
	pulse(70, 0.8)
