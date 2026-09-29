extends Node
## Autoload "Events": global signal bus that keeps systems decoupled.
## Emit here, listen anywhere - nobody needs a reference to anybody else.

## A setting changed (key = settings key, or "*" when many changed at once).
signal settings_changed(key: String)
## The control scheme changed: "touch" or "tilt".
signal control_mode_changed(mode: String)

## Android lifecycle / focus (emitted by AndroidLifecycleManager).
signal app_backgrounded
signal app_foregrounded
## The Android back button / gesture (or Escape on desktop).
signal back_requested

## Gameplay flow.
signal run_started(is_replay: bool)
signal run_finished(summary: Dictionary)
signal pause_changed(paused: bool)

## Display safe area / window size changed.
signal layout_changed

## Short non-blocking message for the player.
signal toast(message: String)

signal character_changed(character_id: String)
signal character_unlocked(character_id: String)
signal save_completed
