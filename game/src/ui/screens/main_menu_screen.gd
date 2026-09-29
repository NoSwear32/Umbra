extends UIScreen
## Main menu: PLAY, CHARACTER, HIGH SCORES, REPLAYS, STATISTICS, SETTINGS, ABOUT, EXIT.

var _best_label: Label
var _preview: CharacterPreview
var _name_label: Label
var _play_button: Button


func build() -> void:
	var root: HBoxContainer = UIKit.hbox(40)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(root)

	# ---- left: title, best result, character
	var left: VBoxContainer = UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(left)
	var t1: Label = UIKit.label("SPIRE", UIKit.FS_TITLE + 16, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	t1.add_theme_constant_override("outline_size", 12)
	left.add_child(t1)
	var t2: Label = UIKit.label("SPRINT", UIKit.FS_TITLE + 16, UIKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	t2.add_theme_constant_override("outline_size", 12)
	left.add_child(t2)
	left.add_child(UIKit.label("Build speed. Leap floors. Chain combos.", UIKit.FS_BODY, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	left.add_child(UIKit.spacer(10))
	_preview = CharacterPreview.new(Vector2(230, 230))
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(_preview)
	_name_label = UIKit.label("", UIKit.FS_H2, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_name_label)
	_best_label = UIKit.label("", UIKit.FS_BODY, UIKit.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_best_label)

	# ---- right: buttons
	var right: VBoxContainer = UIKit.vbox(14)
	right.custom_minimum_size = Vector2(520, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(right)
	_play_button = UIKit.button("PLAY", _on_play, "primary", Vector2(0, 124))
	_play_button.add_theme_font_size_override("font_size", 56)
	right.add_child(_play_button)
	right.add_child(_row("CHARACTER", func() -> void: UIManager.push_screen("characters"), "HIGH SCORES", func() -> void: UIManager.push_screen("high_scores")))
	right.add_child(_row("REPLAYS", func() -> void: UIManager.push_screen("replays"), "STATISTICS", func() -> void: UIManager.push_screen("statistics")))
	right.add_child(_row("SETTINGS", func() -> void: UIManager.push_screen("settings"), "ABOUT", func() -> void: UIManager.push_screen("about")))
	right.add_child(UIKit.button("EXIT", _on_exit, "ghost", Vector2(0, 60)))


func _row(text_a: String, cb_a: Callable, text_b: String, cb_b: Callable) -> HBoxContainer:
	var h: HBoxContainer = UIKit.hbox(14)
	var a: Button = UIKit.button(text_a, cb_a, "secondary", Vector2(0, 78))
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b: Button = UIKit.button(text_b, cb_b, "secondary", Vector2(0, 78))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	h.add_child(b)
	return h


func refresh() -> void:
	var d: CharacterDef = CharacterManager.selected_def()
	_preview.set_character(d, "idle")
	_name_label.text = d.display_name
	var best: int = LeaderboardManager.best_value("score")
	var floor_best: int = LeaderboardManager.best_value("floor")
	if best > 0:
		_best_label.text = "BEST  %s     FLOOR  %d" % [Fmt.number(best), floor_best]
	else:
		_best_label.text = "Reach the top. Whatever that means."
	AudioManager.play_music("music_menu")


func on_back() -> bool:
	return false


func _on_play() -> void:
	UIManager.game.begin_from_menu()


func _on_exit() -> void:
	UIManager.confirm("Leave the tower?", "Do you want to exit Spire Sprint?", "EXIT", AndroidLifecycleManager.quit_game, true)
