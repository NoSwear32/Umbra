class_name HUD
extends CanvasLayer
## In-game heads-up display, positioned inside the device safe area:
##   top-left   : SCORE and FLOOR (compact, outside the tower on wide screens)
##   below      : combo panel (count, floors, shrinking timer) while a combo is active
##   top-right  : small pause button (excluded from tap-to-jump)
##   centre-top : transient banners (combo praise, "SURGE" speed-up warning)
## Danger glow + edge flash live in a DangerOverlay underneath.

signal pause_pressed

const PAUSE_SIZE: float = 74.0
const BLOCK_ID: String = "hud_pause"

var root: Control
var danger: DangerOverlay

var _score_title: Label
var _score_label: Label
var _floor_label: Label
var _speed_label: Label
var _fps_label: Label
var _combo_panel: PanelContainer
var _combo_title: Label
var _combo_sub: Label
var _combo_bar: ProgressBar
var _pause_button: Button
var _banner: Label
var _banner_sub: Label
var _banner_tween: Tween = null
var _last_score: int = -1
var _last_floor: int = -1
var _last_combo_jumps: int = -1
var _last_combo_floors: int = -1
var _score_tween: Tween = null
var _next_danger_beep_ms: int = 0
var _tuning: GameTuning


func _init() -> void:
	layer = 10


func _ready() -> void:
	_tuning = TuningStore.get_tuning()
	root = Control.new()
	root.theme = UIKit.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	danger = DangerOverlay.new()
	root.add_child(danger)

	_score_title = UIKit.label("SCORE", UIKit.FS_SMALL, UIKit.C_DIM)
	root.add_child(_score_title)
	_score_label = UIKit.label("0", 50, UIKit.C_TEXT)
	root.add_child(_score_label)
	_floor_label = UIKit.label("FLOOR 0", 32, UIKit.C_ACCENT)
	root.add_child(_floor_label)
	_speed_label = UIKit.label("", UIKit.FS_SMALL, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	root.add_child(_speed_label)
	_fps_label = UIKit.label("", 20, UIKit.C_DIM)
	root.add_child(_fps_label)

	_combo_panel = UIKit.panel("BannerPanel")
	_combo_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_combo_panel)
	var cv: VBoxContainer = UIKit.vbox(2)
	_combo_panel.add_child(cv)
	_combo_title = UIKit.label("COMBO x2", 38, UIKit.C_GOLD)
	cv.add_child(_combo_title)
	_combo_sub = UIKit.label("", UIKit.FS_SMALL, UIKit.C_TEXT)
	cv.add_child(_combo_sub)
	_combo_bar = ProgressBar.new()
	_combo_bar.min_value = 0.0
	_combo_bar.max_value = 1.0
	_combo_bar.show_percentage = false
	_combo_bar.custom_minimum_size = Vector2(230, 12)
	cv.add_child(_combo_bar)
	_combo_panel.visible = false

	_banner = UIKit.label("", 64, UIKit.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_banner_sub = UIKit.label("", UIKit.FS_BODY, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.modulate.a = 0.0
	root.add_child(_banner_sub)

	_pause_button = UIKit.button("II", _on_pause, "ghost", Vector2(PAUSE_SIZE, PAUSE_SIZE))
	_pause_button.add_theme_font_size_override("font_size", 34)
	_pause_button.modulate.a = 0.7
	root.add_child(_pause_button)

	Events.layout_changed.connect(_layout)
	Events.settings_changed.connect(_on_settings_changed)
	_layout.call_deferred()


func _on_pause() -> void:
	pause_pressed.emit()


func _on_settings_changed(_key: String) -> void:
	_fps_label.visible = SettingsManager.get_bool("show_fps")


## Positions everything inside the current safe area.
func _layout() -> void:
	if root == null:
		return
	var vp: Vector2 = root.get_viewport().get_visible_rect().size
	var ins: Vector4 = SafeArea.get_insets(root.get_viewport())
	_score_title.position = Vector2(ins.x, ins.y - 4.0)
	_score_label.position = Vector2(ins.x, ins.y + 18.0)
	_floor_label.position = Vector2(ins.x, ins.y + 78.0)
	_combo_panel.position = Vector2(ins.x, ins.y + 132.0)
	_pause_button.position = Vector2(vp.x - ins.z - PAUSE_SIZE, ins.y)
	_speed_label.size = Vector2(220, 30)
	_speed_label.position = Vector2(vp.x - ins.z - 220.0, ins.y + PAUSE_SIZE + 6.0)
	_fps_label.position = Vector2(ins.x, vp.y - ins.w - 26.0)
	_fps_label.visible = SettingsManager.get_bool("show_fps")
	_banner.size = Vector2(vp.x, 90)
	_banner.position = Vector2(0.0, ins.y + 34.0)
	_banner_sub.size = Vector2(vp.x, 40)
	_banner_sub.position = Vector2(0.0, ins.y + 112.0)
	InputManager.register_block_rect(BLOCK_ID, Rect2(_pause_button.position, Vector2(PAUSE_SIZE, PAUSE_SIZE)))


func set_pause_visible(value: bool) -> void:
	_pause_button.visible = value
	if not value:
		InputManager.unregister_block_rect(BLOCK_ID)
	else:
		_layout()


func reset() -> void:
	_last_score = -1
	_last_floor = -1
	_last_combo_jumps = -1
	_last_combo_floors = -1
	_combo_panel.visible = false
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	danger.set_danger(0.0)
	_next_danger_beep_ms = 0
	_layout()


## Refreshes the values shown (called every frame while a run is on screen).
func update_from_run(run: RunManager) -> void:
	var score: int = run.get_score()
	if score != _last_score:
		var grew: bool = score > _last_score and _last_score >= 0
		_last_score = score
		_score_label.text = Fmt.number(score)
		if grew:
			_pop(_score_label)
	if run.highest_floor != _last_floor:
		_last_floor = run.highest_floor
		_floor_label.text = "FLOOR %d" % run.highest_floor
	if run.scroll.active:
		_speed_label.text = "SURGE %d" % run.scroll.stage
	else:
		_speed_label.text = ""

	var combo: ComboManager = run.combo
	if combo.active:
		_combo_panel.visible = true
		if combo.jumps != _last_combo_jumps or combo.floors != _last_combo_floors:
			_last_combo_jumps = combo.jumps
			_last_combo_floors = combo.floors
			_combo_title.text = "COMBO x%d" % combo.jumps
			var preview: int = combo.bonus_for(combo.jumps, combo.floors)
			_combo_sub.text = "%d floors%s" % [combo.floors, ("   +%s" % Fmt.number(preview)) if preview > 0 else ""]
			_pop(_combo_title)
		var ratio: float = combo.timer_ratio()
		_combo_bar.value = ratio
		var bar_color: Color = UIKit.C_CYAN
		if ratio < 0.25:
			bar_color = UIKit.C_BAD
		elif ratio < 0.5:
			bar_color = UIKit.C_ACCENT
		var fill: StyleBoxFlat = _combo_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if fill != null and not fill.bg_color.is_equal_approx(bar_color):
			var copy: StyleBoxFlat = fill.duplicate() as StyleBoxFlat
			copy.bg_color = bar_color
			_combo_bar.add_theme_stylebox_override("fill", copy)
	else:
		_combo_panel.visible = false
		_last_combo_jumps = -1

	# danger glow when the kill line is close
	var d: float = 0.0
	if run.scroll.active or run.player.y - run.scroll.cam_bottom < 90.0:
		var gap: float = run.player.y - run.scroll.cam_bottom
		d = clampf(1.0 - gap / 230.0, 0.0, 1.0)
	danger.set_danger(d)
	if d > 0.5:
		# warning beeps that get faster, higher and louder the closer the kill line is
		var now_ms: int = Time.get_ticks_msec()
		if now_ms >= _next_danger_beep_ms:
			_next_danger_beep_ms = now_ms + int(lerpf(750.0, 320.0, d))
			AudioManager.play_sfx("danger", lerpf(0.95, 1.2, d), lerpf(-16.0, -7.0, d))
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % int(Engine.get_frames_per_second())


func _pop(label: Label) -> void:
	label.pivot_offset = Vector2(0.0, label.size.y * 0.5)
	label.scale = Vector2(1.18, 1.18)
	var tw: Tween = create_tween()
	tw.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Banners
# ---------------------------------------------------------------------------
## Big centred message that pops in, holds and fades out.
func show_banner(text: String, color: Color, sub: String = "", hold: float = 1.1, size: int = 64) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", size)
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2(0.6, 0.6)
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.10)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not sub.is_empty():
		_banner_tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.16)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.35)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.35)


func show_surge(stage: int) -> void:
	show_banner("SURGE!", Color("ff7a45"), "The tower is rising faster  (level %d)" % stage, 1.3, 72)
	danger.trigger_flash(Color("ff5a2a"))


func show_praise(text: String, tier: int, floors: int, bonus: int) -> void:
	var colors: Array = [Color("7fe3ff"), UIKit.C_GOLD, Color("ff8fd8")]
	var color: Color = colors[clampi(tier - 1, 0, colors.size() - 1)]
	show_banner(text, color, "%d floors   +%s points" % [floors, Fmt.number(bonus)], 1.35, 58 + tier * 6)
