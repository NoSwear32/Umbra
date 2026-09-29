extends UIScreen
## About / credits. In development builds, tapping the version 7 times opens the debug menu.

var _tap_count: int = 0
var _tap_timer: float = 0.0
var _version_button: Button


func build() -> void:
	content.add_child(UIKit.header("ABOUT", _on_back))
	var box: VBoxContainer = UIKit.vbox(14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(UIKit.scroll(box))

	var card: PanelContainer = UIKit.panel()
	box.add_child(card)
	var v: VBoxContainer = UIKit.vbox(10)
	card.add_child(v)
	var title: Label = UIKit.label("SPIRE SPRINT", UIKit.FS_TITLE, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("outline_size", 10)
	v.add_child(title)
	_version_button = UIKit.button("Version %s" % GameManager.game_version, _on_version_tap, "ghost", Vector2(360, 56))
	_version_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_version_button)
	v.add_child(UIKit.wrap_label("A momentum-driven, endless tower climber. Run to build speed, jump to leap several floors at once, rebound off the walls and chain combos before the rising tower catches you.", UIKit.FS_BODY, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))

	var credits: Dictionary = UIKit.section_card("Credits")
	box.add_child(credits["card"])
	var cb: VBoxContainer = credits["body"]
	cb.add_child(UIKit.wrap_label("Game design, programming, artwork, animation, sound effects and music: original work created for this project.", UIKit.FS_BODY, UIKit.C_TEXT))
	cb.add_child(UIKit.wrap_label("Engine: Godot Engine 4 (MIT licence) - godotengine.org", UIKit.FS_BODY, UIKit.C_TEXT))
	cb.add_child(UIKit.wrap_label("Characters: Pip, Bolt, Moss, Nova, Wraith, Ember and Zenith are original creations.", UIKit.FS_BODY, UIKit.C_TEXT))

	var orig: Dictionary = UIKit.section_card("Originality and privacy")
	box.add_child(orig["card"])
	var ob: VBoxContainer = orig["body"]
	ob.add_child(UIKit.wrap_label("This game is inspired only by the general genre of momentum-based vertical tower jumpers. It contains no characters, artwork, music, sounds, fonts or code from any other game.", UIKit.FS_BODY, UIKit.C_TEXT))
	ob.add_child(UIKit.wrap_label("Everything works fully offline. No account is required and no data ever leaves your device.", UIKit.FS_BODY, UIKit.C_TEXT))


func refresh() -> void:
	_tap_count = 0


func _process(delta: float) -> void:
	if _tap_timer > 0.0:
		_tap_timer -= delta
		if _tap_timer <= 0.0:
			_tap_count = 0


func _on_version_tap() -> void:
	if not OS.is_debug_build():
		return
	_tap_count += 1
	_tap_timer = 2.0
	if _tap_count >= 7:
		_tap_count = 0
		DebugManager.toggle_menu()


func _on_back() -> void:
	UIManager.pop()
