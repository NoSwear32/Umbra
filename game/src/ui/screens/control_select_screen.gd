extends UIScreen
## Quick control selector: shown before the first game and reachable from Settings.
## Two cards (Touch buttons / Tilt + tap); the choice is saved permanently.

var _selected: String = "touch"
var _cards: Dictionary = {}
var _diagrams: Dictionary = {}
var _continue_button: Button
var _hint: Label


func build() -> void:
	content.add_theme_constant_override("separation", 16)
	content.add_child(UIKit.label("CHOOSE YOUR CONTROLS", UIKit.FS_H1, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	content.add_child(UIKit.label("You can change this any time in Settings.", UIKit.FS_BODY, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var row: HBoxContainer = UIKit.hbox(34)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	row.add_child(_make_card("touch", "TOUCH BUTTONS", "Hold LEFT or RIGHT to run.\nRELEASE to jump.\nThe faster you run, the higher you jump."))
	row.add_child(_make_card("tilt", "TILT + TAP", "Tilt your device to run.\nTAP anywhere to jump.\nYou calibrate once for your grip."))
	_hint = UIKit.label("", UIKit.FS_SMALL, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(_hint)
	_continue_button = UIKit.button("CONTINUE", _on_continue, "primary", Vector2(0, 88))
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.custom_minimum_size = Vector2(460, 88)
	content.add_child(_continue_button)


func _make_card(mode: String, title: String, text: String) -> PanelContainer:
	var card: PanelContainer = UIKit.panel("CardPanel")
	card.custom_minimum_size = Vector2(500, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var body: VBoxContainer = UIKit.vbox(12)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(body)
	var diagram: ControlDiagram = ControlDiagram.new(mode)
	diagram.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(diagram)
	body.add_child(UIKit.label(title, UIKit.FS_H2, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.wrap_label(text, UIKit.FS_BODY, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	card.gui_input.connect(_on_card_input.bind(mode))
	_cards[mode] = card
	_diagrams[mode] = diagram
	return card


func _on_card_input(event: InputEvent, mode: String) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_select(mode)
			AudioManager.play_click()
			Haptics.tap()


func _select(mode: String) -> void:
	_selected = mode
	for m in _cards:
		var card: PanelContainer = _cards[m]
		card.theme_type_variation = "SelectedCard" if m == mode else "CardPanel"
		(_diagrams[m] as ControlDiagram).highlighted = (m == mode)
		(_diagrams[m] as ControlDiagram).queue_redraw()
	if mode == "tilt":
		_hint.text = "Tilt mode needs a quick calibration next."
	else:
		_hint.text = "Buttons sit in the lower corners. Their size and position can be adjusted in Settings."


func refresh() -> void:
	_select(SettingsManager.get_string("control_mode"))


func _on_continue() -> void:
	SettingsManager.set_value("control_mode", _selected)
	SettingsManager.set_value("control_chosen", true)
	var next: String = String(params.get("next", "main_menu"))
	if _selected == "tilt" and not SettingsManager.get_bool("tilt_calibrated"):
		UIManager.show_screen("calibrate", {"next": next})
	else:
		UIManager.show_screen(next)
