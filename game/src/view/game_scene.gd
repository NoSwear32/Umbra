class_name GameScene
extends Node
## The playable game: owns the run, the fixed-step loop and every view of it.
##
## Loop: real frame time is accumulated and consumed in fixed 1/120 s simulation ticks
## (RunManager.tick). Rendering interpolates between the last two ticks, so 60 / 90 / 120 /
## 144 Hz displays all show smooth motion while the physics is identical everywhere.
##
## Modes: MENU (attract background only), LIVE (real run), TUTORIAL (practice run with
## guidance, no records), REPLAY (deterministic playback of a recorded run).

enum Mode { MENU, LIVE, REPLAY, TUTORIAL }

const MAX_STEPS_PER_FRAME: int = 10
const MAX_FRAME_TIME: float = 0.1
## Runs with at least this many floors / points ask before restarting from the pause menu.
const VALUABLE_FLOOR: int = 30
const VALUABLE_SCORE: int = 2000
const MIN_SAVED_FLOOR: int = 3

var tuning: GameTuning
var mode: int = Mode.MENU
var run: RunManager = null
var recorder: ReplayRecorder = ReplayRecorder.new()
var replay_player: ReplayPlayer = null
var paused: bool = false

var backdrop_layer: CanvasLayer
var backdrop: BackdropView
var world_root: Node2D
var tower_view: TowerView
var player_view: PlayerView
var fx: FxLayer
var camera: CameraController = CameraController.new()
var hud: HUD
var controls_layer: CanvasLayer
var touch_overlay: TouchControlsOverlay
var overlay_layer: CanvasLayer
var pause_menu: PauseMenu
var game_over: GameOverPanel
var replay_overlay: ReplayOverlay
var tutorial: TutorialOverlay

var _accum: float = 0.0
var _time_scale: float = 1.0
var _idle_cam: float = 0.0
var _menu_floor: float = 0.0
var _fx_timer: float = 0.0
var _line_timer: float = 0.0
var _combo_level: int = 0
var _last_summary: Dictionary = {}
var _last_replay: ReplayData = null
var _current_replay: ReplayData = null
var _replay_finished: bool = false
var _replay_return: String = "main_menu"
var _replay_back_to_game_over: bool = false
var _tutorial_from_play: bool = false
var _last_practice: bool = false
var _run_ended_handled: bool = false
var _music_state: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	tuning = TuningStore.get_tuning()
	_build_nodes()
	UIManager.game = self
	Events.app_backgrounded.connect(_on_app_backgrounded)
	Events.control_mode_changed.connect(_on_control_mode_changed)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_enter_menu_mode()


func _build_nodes() -> void:
	backdrop_layer = CanvasLayer.new()
	backdrop_layer.layer = -50
	add_child(backdrop_layer)
	backdrop = BackdropView.new()
	backdrop.tower_width = tuning.tower_width
	backdrop_layer.add_child(backdrop)

	world_root = Node2D.new()
	add_child(world_root)
	tower_view = TowerView.new()
	world_root.add_child(tower_view)
	fx = FxLayer.new()
	world_root.add_child(fx)
	player_view = PlayerView.new()
	world_root.add_child(player_view)

	hud = HUD.new()
	add_child(hud)
	hud.pause_pressed.connect(pause_game)

	controls_layer = CanvasLayer.new()
	controls_layer.layer = 12
	add_child(controls_layer)
	touch_overlay = TouchControlsOverlay.new()
	controls_layer.add_child(touch_overlay)

	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 20
	add_child(overlay_layer)
	tutorial = TutorialOverlay.new()
	overlay_layer.add_child(tutorial)
	replay_overlay = ReplayOverlay.new()
	overlay_layer.add_child(replay_overlay)
	pause_menu = PauseMenu.new()
	overlay_layer.add_child(pause_menu)
	game_over = GameOverPanel.new()
	overlay_layer.add_child(game_over)

	pause_menu.resume_pressed.connect(resume_game)
	pause_menu.restart_pressed.connect(_on_restart_pressed)
	pause_menu.settings_pressed.connect(_on_pause_settings)
	pause_menu.quit_pressed.connect(quit_to_menu)
	game_over.play_again_pressed.connect(restart_run)
	game_over.watch_replay_pressed.connect(_on_watch_last_replay)
	game_over.save_replay_pressed.connect(_on_save_replay)
	game_over.main_menu_pressed.connect(quit_to_menu)
	replay_overlay.exit_pressed.connect(_on_replay_exit)
	replay_overlay.speed_changed.connect(_on_replay_speed)
	replay_overlay.again_pressed.connect(_on_replay_again)
	tutorial.skipped.connect(_on_tutorial_skipped)
	tutorial.completed.connect(_on_tutorial_completed)
	tutorial.play_pressed.connect(_on_tutorial_play)
	tutorial.menu_pressed.connect(quit_to_menu)
	tutorial.enable_scroll.connect(_on_tutorial_enable_scroll)


# ---------------------------------------------------------------------------
# Public API (used by the menus)
# ---------------------------------------------------------------------------
func is_running() -> bool:
	return mode != Mode.MENU


## PLAY button: tutorial on the very first play, a real run afterwards.
func begin_from_menu() -> void:
	if SettingsManager.is_tilt_mode() and not SettingsManager.get_bool("tilt_calibrated"):
		UIManager.toast("Calibrate your tilt controls first.")
		UIManager.push_screen("calibrate", {"next": "main_menu"})
		return
	if not SettingsManager.get_bool("tutorial_done"):
		begin_tutorial(true)
	else:
		start_run()


func start_run() -> void:
	_begin_run(Mode.LIVE, GameManager.new_seed(), null)


## Starts a live run with a specific seed (debug menu: repeat the same tower).
func restart_with_seed(seed_value: int) -> void:
	_begin_run(Mode.LIVE, seed_value, null)


## Interactive practice run. `from_play`: started by the very first PLAY (skipping it then
## continues into a real run instead of returning to the menu).
func begin_tutorial(from_play: bool = false) -> void:
	_tutorial_from_play = from_play
	_begin_run(Mode.TUTORIAL, GameManager.new_seed(), null)


func start_replay(replay: ReplayData, back_to_game_over: bool = false) -> void:
	_replay_return = UIManager.current_id() if not UIManager.current_id().is_empty() else "main_menu"
	_replay_back_to_game_over = back_to_game_over
	_current_replay = replay
	_begin_run(Mode.REPLAY, replay.seed_value, replay)


func restart_run() -> void:
	game_over.close()
	pause_menu.close()
	if mode == Mode.TUTORIAL:
		begin_tutorial(_tutorial_from_play)
	else:
		start_run()


## Android back button / Escape. Returns true if the game consumed it.
func handle_back() -> bool:
	match mode:
		Mode.MENU:
			return false
		Mode.LIVE, Mode.TUTORIAL:
			if game_over.visible:
				quit_to_menu()
			elif paused:
				resume_game()
			elif tutorial.visible and tutorial.is_finished_panel_visible():
				quit_to_menu()
			elif run != null and not run.dead:
				pause_game()
			return true
		Mode.REPLAY:
			_on_replay_exit()
			return true
	return false


# ---------------------------------------------------------------------------
# Run setup
# ---------------------------------------------------------------------------
func _enter_menu_mode() -> void:
	mode = Mode.MENU
	paused = false
	world_root.visible = false
	hud.visible = false
	controls_layer.visible = false
	overlay_layer.visible = false
	InputManager.set_gameplay_enabled(false)
	InputManager.unregister_block_rect(HUD.BLOCK_ID)
	GameManager.set_state(GameManager.State.MENU)
	_menu_floor = float(randi() % 10) * 100.0 + 5.0
	_idle_cam = 0.0
	ThemeManager.update_preload(int(_menu_floor))


func _begin_run(new_mode: int, seed_value: int, replay: ReplayData) -> void:
	game_over.close()
	pause_menu.close()
	replay_overlay.close()
	tutorial.stop()
	UIManager.hide_screens()
	UIManager.close_dialog()
	mode = new_mode
	paused = false
	_accum = 0.0
	_time_scale = 1.0
	_replay_finished = false
	_run_ended_handled = false
	_combo_level = 0
	_last_replay = null

	var run_tuning: GameTuning = tuning
	var character: CharacterDef = CharacterManager.selected_def()
	if new_mode == Mode.REPLAY:
		replay_player = ReplayPlayer.new(replay)
		run = replay_player.run
		run_tuning = replay_player.tuning
		if CharacterManager.has_character(replay.character):
			character = CharacterManager.get_def(replay.character)
	else:
		replay_player = null
		if new_mode == Mode.TUTORIAL:
			run_tuning = tuning.duplicate() as GameTuning
			run_tuning.scroll_start_floor = 1000000  # the tower only rises at the last tutorial step
		run = RunManager.new(run_tuning, seed_value)
		run.practice = (new_mode == Mode.TUTORIAL)
		recorder.start(seed_value, run_tuning, CharacterManager.selected_id, SettingsManager.get_string("control_mode"), GameManager.game_version)
	_connect_run(run)

	backdrop.tower_width = run_tuning.tower_width
	tower_view.bind_run(run)
	player_view.bind(run, character, run_tuning)
	fx.clear()
	camera.reset()
	hud.reset()
	world_root.visible = true
	hud.visible = true
	overlay_layer.visible = true
	var interactive: bool = (new_mode == Mode.LIVE or new_mode == Mode.TUTORIAL)
	hud.set_pause_visible(interactive)
	controls_layer.visible = interactive
	touch_overlay.relayout()
	if new_mode == Mode.REPLAY:
		replay_overlay.open()
		replay_overlay.set_info("REPLAY  %s" % Fmt.number(replay.score))
	if new_mode == Mode.TUTORIAL:
		tutorial.start(not SettingsManager.is_tilt_mode())
	InputManager.clear_state()
	InputManager.set_gameplay_enabled(interactive)
	GameManager.set_state(GameManager.State.PLAYING if interactive else GameManager.State.REPLAY)
	GameManager.clear_active_run()
	_set_music("music_game")
	Events.run_started.emit(new_mode == Mode.REPLAY)


func _connect_run(r: RunManager) -> void:
	r.jumped.connect(_on_jumped)
	r.landed.connect(_on_landed)
	r.wall_rebounded.connect(_on_wall)
	r.new_floor_reached.connect(_on_new_floor)
	r.combo_started.connect(_on_combo_started)
	r.combo_progressed.connect(_on_combo_progressed)
	r.combo_ended.connect(_on_combo_ended)
	r.scroll_started.connect(_on_scroll_started)
	r.speed_stage_changed.connect(_on_speed_stage)
	r.run_ended.connect(_on_run_ended)


func _set_music(track: String) -> void:
	if _music_state != track:
		_music_state = track
		AudioManager.play_music(track)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if mode == Mode.MENU:
		_process_menu(delta)
		return
	if run == null:
		return
	if not paused and not run.dead and not _replay_finished:
		_accum += minf(delta, MAX_FRAME_TIME) * _time_scale
		var steps: int = 0
		while _accum >= SimConst.DT and steps < MAX_STEPS_PER_FRAME:
			_sim_tick()
			_accum -= SimConst.DT
			steps += 1
			if run.dead or _replay_finished:
				break
		if steps >= MAX_STEPS_PER_FRAME:
			_accum = 0.0  # never spiral: drop the backlog after a long stall
	_update_visuals(delta)


func _sim_tick() -> void:
	if mode == Mode.REPLAY:
		if not replay_player.step():
			_on_replay_finished()
		return
	var n: int = run.tick_count + 1
	var q: int = ReplayRecorder.quantize(InputManager.sample_axis())
	var jump: bool = InputManager.consume_jump()
	recorder.record(n, q, jump)
	run.tick(ReplayRecorder.dequantize(q), jump)


func _process_menu(delta: float) -> void:
	_idle_cam += 46.0 * delta
	_menu_floor += delta * 2.2
	if _menu_floor > 1099.0:
		_menu_floor = 5.0
	ThemeManager.update_preload(int(_menu_floor))
	backdrop.update_view(_idle_cam, ThemeManager.blended_at(_menu_floor))


func _update_visuals(delta: float) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var run_tuning: GameTuning = run.tuning
	var tower_left: float = (vp.x - run_tuning.tower_width) * 0.5
	var alpha: float = 1.0
	if not paused and not run.dead and not _replay_finished:
		alpha = clampf(_accum / SimConst.DT, 0.0, 1.0)
	var cam_bottom: float = lerpf(run.scroll.prev_cam_bottom, run.scroll.cam_bottom, alpha)
	camera.update(delta)
	camera.apply_to(world_root, cam_bottom, vp, tower_left)
	tower_view.update_view(cam_bottom, vp.y)
	backdrop.update_view(cam_bottom, ThemeManager.blended_at(float(run.highest_floor)))
	var axis: float = 0.0
	if mode == Mode.REPLAY:
		axis = replay_player.current_axis()
	else:
		axis = InputManager.sample_axis()
	player_view.update_view(alpha, delta, axis)
	if not paused:
		_update_continuous_fx(delta)
	hud.update_from_run(run)
	if tutorial.active:
		tutorial.update_view(delta, run)


func _theme_now() -> Dictionary:
	return ThemeManager.theme_for_floor(run.current_floor)


func _update_continuous_fx(delta: float) -> void:
	if run.dead:
		return
	var p: PlayerController = run.player
	var ratio: float = p.speed_ratio()
	var pos: Vector2 = player_view.rendered_position()
	var th: Dictionary = _theme_now()
	_fx_timer -= delta
	if _fx_timer <= 0.0:
		_fx_timer = 0.055
		if p.grounded and ratio > 0.3:
			var dust: Color = th["plat_top"]
			fx.run_dust(pos, 1.0 if p.vx > 0.0 else -1.0, ratio, Color(dust, 0.9))
		if ratio > tuning.speed_effect_ratio:
			fx.trail(pos + Vector2(0.0, -30.0), player_view.def.ui_color, 11.0 + 6.0 * ratio)
	_line_timer -= delta
	if _line_timer <= 0.0:
		_line_timer = 0.045
		if ratio > tuning.speed_effect_ratio + 0.05:
			var back: Vector2 = Vector2(-signf(p.vx), 0.0)
			if not p.grounded and absf(p.vy) > absf(p.vx):
				back = Vector2(0.0, signf(p.vy))
			fx.speed_line(pos + Vector2(randf_range(-40.0, 40.0), randf_range(-70.0, 10.0)), -back, ratio)
	# combo aura level follows the chain length
	var level: int = 0
	if run.combo.active:
		level = 1
		if run.combo.jumps >= 3:
			level = 2
		if run.combo.jumps >= 6:
			level = 3
	if level != _combo_level:
		_combo_level = level
		player_view.set_combo_level(level)


# ---------------------------------------------------------------------------
# Run events -> feedback
# ---------------------------------------------------------------------------
func _feet_position() -> Vector2:
	return player_view.rendered_position()


func _live() -> bool:
	return mode == Mode.LIVE or mode == Mode.TUTORIAL


func _on_jumped(_velocity: float, speed_ratio: float) -> void:
	AudioManager.play_jump(speed_ratio)
	player_view.on_jumped(speed_ratio)
	var dust_color: Color = _theme_now()["plat_top"]
	fx.jump_puff(_feet_position(), speed_ratio, dust_color)
	if _live():
		Haptics.tap()
		tutorial.notify_jump(speed_ratio)


func _on_landed(platform: PlatformData, impact_speed: float, _floors_advanced: int, _is_new: bool) -> void:
	AudioManager.play_land(impact_speed)
	player_view.on_landed(impact_speed)
	var strength: float = clampf(absf(impact_speed) / 1300.0, 0.0, 1.0)
	var at: Vector2 = Vector2(run.player.x, -platform.y)
	var land_color: Color = ThemeManager.theme_for_floor(platform.floor_index)["plat_top"]
	fx.land_dust(at, strength, land_color)
	if strength > 0.5:
		camera.add_trauma(0.10 + 0.12 * strength, tuning)


func _on_wall(direction: int, speed: float) -> void:
	var ratio: float = clampf(speed / run.tuning.max_speed, 0.0, 1.0)
	AudioManager.play_wall(ratio)
	player_view.on_wall(direction, ratio)
	var contact: Vector2 = _feet_position() + Vector2(-float(direction) * run.tuning.player_half_width, -28.0)
	var spark_color: Color = _theme_now()["accent"]
	fx.wall_sparks(contact, direction, ratio, spark_color)
	if ratio > 0.4:
		camera.add_trauma(0.10 + 0.24 * ratio, tuning)
	if _live():
		Haptics.rebound(ratio)
		tutorial.notify_wall(speed)


func _on_new_floor(floor_index: int, _gained: int) -> void:
	ThemeManager.update_preload(floor_index)
	if floor_index % ThemeManager.FLOORS_PER_THEME == 0 and floor_index > 0 and _live() and mode == Mode.LIVE:
		var theme_name: String = String(ThemeManager.theme_for_floor(floor_index)["name"])
		hud.show_banner("FLOOR %d" % floor_index, UIKit.C_ACCENT, theme_name, 1.5, 60)


func _on_combo_started() -> void:
	if _live():
		tutorial.notify_combo_started()


func _on_combo_progressed(jumps: int, _floors: int) -> void:
	AudioManager.play_combo_step(jumps)
	camera.add_pulse(0.004 + 0.002 * float(mini(jumps, 8)))
	if jumps >= 2:
		var cols: Array = [player_view.def.scarf_color, player_view.def.scarf_color2]
		fx.combo_burst(_feet_position() + Vector2(0.0, -30.0), 0, cols)


func _on_combo_ended(_jumps: int, floors: int, bonus: int, _reason: int, valid: bool) -> void:
	if not valid or run.dead:
		return
	var tier: int = _praise_tier(floors)
	var index: int = _praise_index(floors)
	if index < 0:
		return
	hud.show_praise(String(run.tuning.praise_texts[index]), tier, floors, bonus)
	AudioManager.play_combo_end(tier)
	var cols: Array = [player_view.def.scarf_color, player_view.def.scarf_color2, Color("ffffff")]
	fx.combo_burst(_feet_position() + Vector2(0.0, -30.0), tier, cols)
	camera.add_trauma(0.12 + 0.10 * float(tier), tuning)
	camera.add_pulse(0.012 * float(tier))
	if _live() and tier >= 2:
		Haptics.celebrate()


func _praise_index(floors: int) -> int:
	var mins: PackedInt32Array = run.tuning.praise_min_floors
	var best: int = -1
	for i in range(mins.size()):
		if floors >= mins[i] and i < run.tuning.praise_texts.size():
			best = i
	return best


func _praise_tier(floors: int) -> int:
	var idx: int = _praise_index(floors)
	if idx >= 6:
		return 3
	if idx >= 3:
		return 2
	return 1


func _on_scroll_started() -> void:
	if mode == Mode.LIVE:
		hud.show_banner("KEEP CLIMBING!", Color("ffffff"), "", 0.9, 52)


func _on_speed_stage(stage: int) -> void:
	hud.show_surge(stage)
	AudioManager.play_sfx("speed_up", 1.0, 0.0)
	camera.add_trauma(0.22, tuning)
	if _live():
		Haptics.pulse(60, 0.7)


# ---------------------------------------------------------------------------
# End of run
# ---------------------------------------------------------------------------
func _on_run_ended(result: Dictionary) -> void:
	if mode == Mode.REPLAY:
		_on_replay_finished()
		return
	if _run_ended_handled:
		return
	_run_ended_handled = true
	InputManager.set_gameplay_enabled(false)
	controls_layer.visible = false
	hud.set_pause_visible(false)
	player_view.on_died()
	AudioManager.play_sfx("game_over", 1.0, 0.0)
	camera.add_trauma(0.55, tuning)
	if SettingsManager.get_bool("haptics"):
		Haptics.pulse(180, 1.0)
	var replay: ReplayData = recorder.finish(result, true)
	_last_replay = replay
	var practice: bool = (mode == Mode.TUTORIAL)
	_last_practice = practice
	var summary: Dictionary = GameManager.finish_run(result, null if practice else replay)
	_last_summary = summary
	GameManager.set_state(GameManager.State.GAME_OVER)
	_show_game_over_later(run, summary, practice)


func _show_game_over_later(finished_run: RunManager, summary: Dictionary, practice: bool) -> void:
	await get_tree().create_timer(0.85).timeout
	if run != finished_run or mode == Mode.REPLAY or mode == Mode.MENU:
		return  # the player already restarted / left
	if practice:
		SettingsManager.set_value("tutorial_done", true)
	game_over.show_summary(summary, not practice and _last_replay != null, "PRACTICE OVER" if practice else "GAME OVER")
	if bool(summary.get("any_record", false)):
		AudioManager.play_sfx("record", 1.0, 0.0)
		Haptics.celebrate()
	elif not (summary.get("new_characters", []) as Array).is_empty():
		AudioManager.play_sfx("unlock", 1.0, 0.0)
	_set_music("")


## Ends the current live run without dying (quit / restart). Meaningful runs are still saved.
func _abandon_current_run() -> void:
	if run == null or mode == Mode.REPLAY or _run_ended_handled:
		return
	_run_ended_handled = true
	var result: Dictionary = run.abandon()
	var replay: ReplayData = recorder.finish(result, true)
	if mode == Mode.LIVE and int(result.get("highest_floor", 0)) >= MIN_SAVED_FLOOR:
		GameManager.finish_run(result, replay)
		Events.toast.emit("Run saved: %s points" % Fmt.number(int(result.get("score", 0))))
	else:
		GameManager.clear_active_run()


func quit_to_menu() -> void:
	_abandon_current_run()
	game_over.close()
	pause_menu.close()
	replay_overlay.close()
	tutorial.stop()
	InputManager.set_gameplay_enabled(false)
	AudioManager.set_music_paused(false)
	UIManager.transition(_finish_quit_to_menu)


func _finish_quit_to_menu() -> void:
	run = null
	replay_player = null
	_enter_menu_mode()
	_music_state = ""
	UIManager.show_screen("main_menu")


# ---------------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------------
func pause_game() -> void:
	if not _live() or paused or run == null or run.dead or _run_ended_handled:
		return
	paused = true
	InputManager.set_gameplay_enabled(false)
	pause_menu.open(run.get_score(), run.highest_floor, run.duration_seconds())
	AudioManager.set_music_paused(true)
	touch_overlay.visible = false
	Events.pause_changed.emit(true)
	GameManager.set_state(GameManager.State.PAUSED)


func resume_game() -> void:
	if not paused:
		return
	paused = false
	pause_menu.close()
	touch_overlay.visible = true
	_accum = 0.0
	InputManager.clear_state()
	InputManager.set_gameplay_enabled(true)
	AudioManager.set_music_paused(false)
	GameManager.clear_active_run()
	Events.pause_changed.emit(false)
	GameManager.set_state(GameManager.State.PLAYING)


func _on_restart_pressed() -> void:
	var valuable: bool = run != null and mode == Mode.LIVE and (run.highest_floor >= VALUABLE_FLOOR or run.get_score() >= VALUABLE_SCORE)
	if valuable:
		UIManager.confirm("Restart?", "Your current run (%s points) is saved to your records first." % Fmt.number(run.get_score()), "RESTART", _do_restart)
	else:
		_do_restart()


func _do_restart() -> void:
	_abandon_current_run()
	restart_run()


func _on_pause_settings() -> void:
	pause_menu.close()
	UIManager.open_from_game("settings", _on_settings_closed)


func _on_settings_closed() -> void:
	if paused:
		pause_menu.open(run.get_score(), run.highest_floor, run.duration_seconds())
	touch_overlay.relayout()


func _on_app_backgrounded() -> void:
	if _live() and run != null and not run.dead and not _run_ended_handled:
		if not paused:
			pause_game()
		if mode == Mode.LIVE:
			GameManager.write_interrupted_snapshot(recorder.snapshot(run.build_result()))


func _on_control_mode_changed(_mode_name: String) -> void:
	touch_overlay.relayout()


func _on_viewport_resized() -> void:
	touch_overlay.relayout()


# ---------------------------------------------------------------------------
# Replays
# ---------------------------------------------------------------------------
func _on_replay_finished() -> void:
	if _replay_finished:
		return
	_replay_finished = true
	replay_overlay.show_finished()


func _on_replay_exit() -> void:
	replay_overlay.close()
	replay_player = null
	_current_replay = null
	if _replay_back_to_game_over and not _last_summary.is_empty():
		_replay_back_to_game_over = false
		UIManager.transition(_finish_replay_to_results)
	else:
		UIManager.transition(_finish_replay_exit)


func _finish_replay_to_results() -> void:
	# back to the results of the run that was just watched (over the attract background)
	run = null
	_enter_menu_mode()
	overlay_layer.visible = true
	tutorial.stop()
	_music_state = ""
	game_over.show_summary(_last_summary, _last_replay != null and not _last_practice, "PRACTICE OVER" if _last_practice else "GAME OVER")


func _finish_replay_exit() -> void:
	run = null
	_enter_menu_mode()
	_music_state = ""
	var target: String = _replay_return
	if target.is_empty() or not UIManager.SCREENS.has(target):
		target = "main_menu"
	UIManager.show_screen(target)


func _on_replay_speed(factor: float) -> void:
	_time_scale = factor


func _on_replay_again() -> void:
	if _current_replay != null:
		var keep_return: String = _replay_return
		var keep_flag: bool = _replay_back_to_game_over
		_begin_run(Mode.REPLAY, _current_replay.seed_value, _current_replay)
		_replay_return = keep_return
		_replay_back_to_game_over = keep_flag


func _on_watch_last_replay() -> void:
	if _last_replay == null:
		return
	game_over.close()
	start_replay(_last_replay, true)


func _on_save_replay() -> void:
	var id: String = String(_last_summary.get("replay_id", ""))
	if id.is_empty():
		return
	# make sure the file exists (it is normally written a moment after the run ended)
	if not ReplayManager.has_replay(id) and _last_replay != null:
		_last_replay.id = id
		ReplayManager.save_replay(_last_replay)
	var current: Dictionary = ReplayManager.find_meta(id)
	UIManager.prompt_text("Name this replay", String(current.get("name", "")), 40, _apply_replay_name.bind(id))


func _apply_replay_name(text: String, id: String) -> void:
	var name_text: String = text.strip_edges()
	if name_text.is_empty():
		name_text = "Saved run %s" % Fmt.date_only(int(Time.get_unix_time_from_system()))
	ReplayManager.rename_replay(id, name_text)
	UIManager.toast("Replay saved")


# ---------------------------------------------------------------------------
# Tutorial
# ---------------------------------------------------------------------------
func _on_tutorial_enable_scroll() -> void:
	if run != null:
		run.tuning.scroll_start_floor = 0


func _on_tutorial_skipped() -> void:
	SettingsManager.set_value("tutorial_done", true)
	_abandon_current_run()
	tutorial.stop()
	if _tutorial_from_play:
		start_run()  # first PLAY: skipping continues straight into a real run
	else:
		quit_to_menu()


func _on_tutorial_completed() -> void:
	SettingsManager.set_value("tutorial_done", true)


func _on_tutorial_play() -> void:
	_abandon_current_run()
	start_run()
