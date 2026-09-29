extends Node
## Autoload "DebugManager": development-only tools.
##
## Everything here is gated by OS.is_debug_build(): in release exports the manager does
## nothing, builds no UI and ignores every call, so ordinary players can never reach it.
## Open it in a debug build by tapping the version in ABOUT seven times, or press F3.
##
## Any command that changes the run marks it as "debug used": such runs never reach the
## leaderboards, statistics or records.

const REFRESH_SECONDS: float = 0.15

var _layer: CanvasLayer
var _panel: PanelContainer
var _info: Label
var _menu_open: bool = false
var _overlay_visible: bool = false
var _timer: float = 0.0
var _low_fps: bool = false
var _last_seed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		set_process(false)
		set_process_input(false)
		return
	_layer = CanvasLayer.new()
	_layer.layer = 95
	add_child(_layer)


func available() -> bool:
	return OS.is_debug_build()


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.physical_keycode == KEY_F3:
			toggle_menu()


func toggle_menu() -> void:
	if not OS.is_debug_build():
		return
	_menu_open = not _menu_open
	if _panel == null:
		_build_panel()
	_panel.visible = _menu_open
	_overlay_visible = _menu_open
	_refresh()


func _game() -> GameScene:
	return UIManager.game


func _run() -> RunManager:
	var g: GameScene = _game()
	if g == null:
		return null
	return g.run


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme = UIKit.get_theme()
	_layer.add_child(_panel)
	_panel.position = Vector2(20.0, 20.0)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var v: VBoxContainer = UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	v.add_child(UIKit.label("DEBUG (development build)", 24, UIKit.C_ACCENT))
	_info = UIKit.label("", 17, UIKit.C_TEXT)
	v.add_child(_info)
	v.add_child(UIKit.separator())
	var row1: HBoxContainer = UIKit.hbox(6)
	row1.add_child(_btn("Floor 100", _goto_floor.bind(100)))
	row1.add_child(_btn("Floor 500", _goto_floor.bind(500)))
	row1.add_child(_btn("Floor 1000", _goto_floor.bind(1000)))
	v.add_child(row1)
	var row2: HBoxContainer = UIKit.hbox(6)
	row2.add_child(_btn("Next theme", _next_theme))
	row2.add_child(_btn("Stage +", _stage.bind(1)))
	row2.add_child(_btn("Stage -", _stage.bind(-1)))
	v.add_child(row2)
	var row3: HBoxContainer = UIKit.hbox(6)
	row3.add_child(_btn("New seed", _new_seed))
	row3.add_child(_btn("Same seed", _same_seed))
	row3.add_child(_btn("Invincible", _toggle_invincible))
	v.add_child(row3)
	var row4: HBoxContainer = UIKit.hbox(6)
	row4.add_child(_btn("Force game over", _force_game_over))
	row4.add_child(_btn("Low FPS (15)", _toggle_low_fps))
	row4.add_child(_btn("Close", toggle_menu))
	v.add_child(row4)
	_panel.visible = false


func _btn(text: String, cb: Callable) -> Button:
	var b: Button = UIKit.button(text, cb, "secondary", Vector2(0, 52))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	return b


func _process(delta: float) -> void:
	if not _overlay_visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_SECONDS
		_refresh()


func _refresh() -> void:
	if _info == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("FPS: %d   control: %s" % [int(Engine.get_frames_per_second()), SettingsManager.get_string("control_mode")])
	var r: RunManager = _run()
	if r != null:
		var p: PlayerController = r.player
		lines.append("vx: %.1f   vy: %.1f   grounded: %s" % [p.vx, p.vy, str(p.grounded)])
		lines.append("floor: %d   highest: %d   score: %d" % [r.current_floor, r.highest_floor, r.get_score()])
		lines.append("combo: %s  jumps %d  floors %d  timer %.2f s" % [str(r.combo.active), r.combo.jumps, r.combo.floors, r.combo.timer_ratio() * r.tuning.combo_timeout])
		lines.append("scroll: %.1f px/s  stage %d  active %s" % [r.scroll.speed, r.scroll.stage, str(r.scroll.active)])
		lines.append("theme: %s" % String(ThemeManager.theme_for_floor(r.highest_floor)["name"]))
		lines.append("seed: %d   tick: %d   invincible: %s" % [r.seed_value, r.tick_count, str(r.invincible)])
	var s: TiltInputController = SensorManager.tilt
	lines.append("tilt raw: %+.2f deg   filtered: %+.2f deg   axis: %+.2f" % [s.raw_deg, s.filtered_deg, s.axis])
	lines.append("sensor: %s   sample: (%.1f, %.1f, %.1f)" % [str(SensorManager.sensor_available), SensorManager.raw_sample.x, SensorManager.raw_sample.y, SensorManager.raw_sample.z])
	_info.text = "\n".join(lines)


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
func _with_run(action: Callable) -> void:
	var r: RunManager = _run()
	if r == null or r.dead:
		UIManager.toast("No active run.")
		return
	action.call(r)


func _goto_floor(floor_index: int) -> void:
	_with_run(_do_teleport.bind(floor_index))


func _do_teleport(r: RunManager, floor_index: int) -> void:
	r.debug_teleport_to_floor(floor_index)


func _next_theme() -> void:
	_with_run(_do_next_theme)


func _do_next_theme(r: RunManager) -> void:
	var next_index: int = ThemeManager.theme_index_for_floor(r.highest_floor) + 1
	r.debug_teleport_to_floor(next_index * ThemeManager.FLOORS_PER_THEME)


func _stage(step: int) -> void:
	_with_run(_do_stage.bind(step))


func _do_stage(r: RunManager, step: int) -> void:
	r.debug_set_stage(r.scroll.stage + step)


func _toggle_invincible() -> void:
	_with_run(_do_invincible)


func _do_invincible(r: RunManager) -> void:
	r.debug_used = true
	r.invincible = not r.invincible


func _force_game_over() -> void:
	_with_run(_do_force_game_over)


func _do_force_game_over(r: RunManager) -> void:
	r.debug_force_game_over()


func _new_seed() -> void:
	var g: GameScene = _game()
	if g != null:
		g.start_run()


func _same_seed() -> void:
	var g: GameScene = _game()
	if g == null or g.run == null:
		return
	_last_seed = g.run.seed_value
	g.restart_with_seed(_last_seed)


func _toggle_low_fps() -> void:
	_low_fps = not _low_fps
	if _low_fps:
		Engine.max_fps = 15
	else:
		SettingsManager.apply_engine_settings()
