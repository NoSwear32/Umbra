extends UIScreen
## "How to play": the short control tutorial for both control schemes, plus a shortcut to the
## interactive practice run.

const TOUCH_STEPS: Array = [
	"Hold LEFT or RIGHT to run.",
	"Keep holding to build speed.",
	"RELEASE the direction to jump.",
	"More speed = a higher jump.",
	"Bounce off the walls to keep your speed.",
	"Skip several floors in one jump to start a combo.",
	"Never fall below the bottom of the screen!",
]
const TILT_STEPS: Array = [
	"Tilt your device left or right to run.",
	"TAP the screen to jump.",
	"More speed = a higher jump.",
	"Bounce off the walls to keep your speed.",
	"Skip several floors in one jump to chain combos.",
	"Stay ahead of the rising tower.",
]


func build() -> void:
	content.add_child(UIKit.header("HOW TO PLAY", _on_back))
	var row: HBoxContainer = UIKit.hbox(24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	row.add_child(_steps_card("TOUCH BUTTONS", TOUCH_STEPS, "touch"))
	row.add_child(_steps_card("TILT + TAP", TILT_STEPS, "tilt"))
	var practice: Button = UIKit.button("START PRACTICE RUN", _on_practice, "primary", Vector2(520, 84))
	practice.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(practice)


func _steps_card(title: String, steps: Array, mode: String) -> PanelContainer:
	var card: PanelContainer = UIKit.panel("CardPanel")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = UIKit.vbox(10)
	card.add_child(v)
	v.add_child(UIKit.label(title, UIKit.FS_H2, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.separator())
	for i in range(steps.size()):
		var h: HBoxContainer = UIKit.hbox(14)
		var n: Label = UIKit.label("%d" % (i + 1), UIKit.FS_H2, UIKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		n.custom_minimum_size = Vector2(44, 0)
		h.add_child(n)
		h.add_child(UIKit.wrap_label(String(steps[i]), UIKit.FS_BODY, UIKit.C_TEXT))
		v.add_child(h)
	card.set_meta("mode", mode)
	return card


func _on_practice() -> void:
	UIManager.game.begin_tutorial()


func _on_back() -> void:
	UIManager.pop()
