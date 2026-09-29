extends Node
## Autoload "AndroidLifecycleManager": turns platform lifecycle notifications into game events.
##
## Handled: Home button, recent-apps switching, incoming call / notification overlays,
## screen lock and any other loss of focus (all arrive as PAUSED / FOCUS_OUT), returning to
## the app, the Android back button/gesture, and window close (desktop).
##
## On focus loss: the sensor is stopped immediately (stale accelerometer data can never move
## the character), audio pauses, the profile is flushed to disk and `Events.app_backgrounded`
## fires so the running game pauses itself. Returning does NOT resume the run automatically:
## the pause menu is shown and the player continues when ready.

var app_active: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# we decide when to quit (so the profile is always saved)
	get_tree().set_auto_accept_quit(false)
	get_tree().quit_on_go_back = false
	apply_display_settings()


## Extra safety on top of the manifest/project settings: landscape only (both directions),
## screen kept on while the game is running.
func apply_display_settings() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	DisplayServer.screen_set_keep_on(true)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_set_active(false)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_set_active(true)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			Events.back_requested.emit()
		NOTIFICATION_WM_CLOSE_REQUEST:
			SaveManager.flush()
			get_tree().quit()


func _set_active(active: bool) -> void:
	if active == app_active:
		return
	app_active = active
	if active:
		apply_display_settings()
		AudioManager.set_paused(false)
		Events.app_foregrounded.emit()
	else:
		SensorManager.set_active(false)
		InputManager.touch.cancel_all()
		AudioManager.set_paused(true)
		Events.app_backgrounded.emit()
		SaveManager.flush()


## Quit the application (Main menu > Exit). Saves first.
func quit_game() -> void:
	SaveManager.flush()
	get_tree().quit()
