class_name UIKit
extends RefCounted
## Shared look & widgets. The whole UI is built in code from these helpers so every screen
## has the same touch-friendly style (large hit areas, rounded cards, readable outlines).

const C_BG: Color = Color("0b0e1b")
const C_PANEL: Color = Color("151a33")
const C_PANEL_2: Color = Color("1f2650")
const C_PANEL_3: Color = Color("2b3470")
const C_ACCENT: Color = Color("ffb347")
const C_ACCENT_DARK: Color = Color("c97a1a")
const C_CYAN: Color = Color("35d0ff")
const C_TEXT: Color = Color("f4f6ff")
const C_DIM: Color = Color("9aa3c7")
const C_GOOD: Color = Color("6be38a")
const C_BAD: Color = Color("ff5a5a")
const C_GOLD: Color = Color("ffd84a")

const FS_TITLE: int = 72
const FS_H1: int = 44
const FS_H2: int = 34
const FS_BODY: int = 26
const FS_SMALL: int = 21

const BUTTON_H: float = 76.0

static var _theme: Theme = null


# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


static func _box(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), border_w: int = 0, pad_h: int = 22, pad_v: int = 10) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = true
	return sb


static func _icon_circle(diameter: int, fill: Color, border: Color, border_w: float) -> ImageTexture:
	var img: Image = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c: float = float(diameter - 1) * 0.5
	var r: float = float(diameter) * 0.5
	for y in range(diameter):
		for x in range(diameter):
			var d: float = Vector2(float(x) - c, float(y) - c).length()
			var a: float = clampf(r - d, 0.0, 1.0)
			var col: Color = fill
			if d > r - border_w:
				col = border
			col.a = col.a * a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _button_variation(t: Theme, type_name: String, bg: Color, border: Color, text_color: Color) -> void:
	t.set_type_variation(type_name, "Button")
	t.set_stylebox("normal", type_name, _box(bg, 20, border, 3, 26, 12))
	t.set_stylebox("hover", type_name, _box(bg.lightened(0.10), 20, border.lightened(0.15), 3, 26, 12))
	t.set_stylebox("pressed", type_name, _box(bg.darkened(0.18), 20, border, 3, 26, 14))
	t.set_stylebox("disabled", type_name, _box(bg.darkened(0.5), 20, border.darkened(0.4), 3, 26, 12))
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
	t.set_color("font_color", type_name, text_color)
	t.set_color("font_hover_color", type_name, text_color)
	t.set_color("font_pressed_color", type_name, text_color)
	t.set_color("font_focus_color", type_name, text_color)
	t.set_color("font_disabled_color", type_name, text_color.darkened(0.5))
	t.set_color("font_outline_color", type_name, Color(0, 0, 0, 0.35))
	t.set_constant("outline_size", type_name, 3)
	t.set_font_size("font_size", type_name, FS_BODY + 2)


static func _build_theme() -> Theme:
	var t: Theme = Theme.new()
	t.set_default_font_size(FS_BODY)

	# Labels
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("outline_size", "Label", 4)
	t.set_font_size("font_size", "Label", FS_BODY)

	# Buttons
	t.set_stylebox("normal", "Button", _box(C_PANEL_2, 20, C_PANEL_3, 3, 26, 12))
	t.set_stylebox("hover", "Button", _box(C_PANEL_3, 20, C_CYAN, 3, 26, 12))
	t.set_stylebox("pressed", "Button", _box(C_PANEL, 20, C_CYAN, 3, 26, 14))
	t.set_stylebox("disabled", "Button", _box(C_PANEL, 20, C_PANEL_2, 3, 26, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", C_TEXT)
	t.set_color("font_disabled_color", "Button", C_DIM)
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.35))
	t.set_constant("outline_size", "Button", 3)
	t.set_font_size("font_size", "Button", FS_BODY + 2)
	_button_variation(t, "PrimaryButton", C_ACCENT, C_ACCENT_DARK, Color("2a1400"))
	t.set_color("font_outline_color", "PrimaryButton", Color(1, 1, 1, 0.25))
	_button_variation(t, "SecondaryButton", C_PANEL_2, C_CYAN, C_TEXT)
	_button_variation(t, "DangerButton", Color("7a1f2b"), C_BAD, C_TEXT)
	_button_variation(t, "GhostButton", Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.18), C_TEXT)
	_button_variation(t, "ToggleOn", Color("1f6f5a"), C_GOOD, C_TEXT)
	_button_variation(t, "ToggleOff", Color("3a2a3f"), Color("7d5a87"), C_DIM)
	_button_variation(t, "SegmentOn", C_CYAN.darkened(0.35), C_CYAN, C_TEXT)
	_button_variation(t, "SegmentOff", C_PANEL, C_PANEL_3, C_DIM)

	# Panels
	t.set_stylebox("panel", "PanelContainer", _box(Color(C_PANEL, 0.94), 26, C_PANEL_3, 3, 28, 22))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", _box(Color(C_PANEL_2, 0.92), 22, C_PANEL_3, 2, 22, 16))
	t.set_type_variation("SelectedCard", "PanelContainer")
	t.set_stylebox("panel", "SelectedCard", _box(Color(C_PANEL_3, 0.96), 22, C_ACCENT, 4, 22, 16))
	t.set_type_variation("LockedCard", "PanelContainer")
	t.set_stylebox("panel", "LockedCard", _box(Color(C_PANEL, 0.9), 22, Color(1, 1, 1, 0.08), 2, 22, 16))
	t.set_type_variation("BannerPanel", "PanelContainer")
	t.set_stylebox("panel", "BannerPanel", _box(Color(0, 0, 0, 0.55), 18, Color(1, 1, 1, 0.2), 2, 26, 10))
	t.set_stylebox("panel", "Panel", _box(Color(C_PANEL, 0.94), 26, C_PANEL_3, 3, 20, 20))

	# Sliders (big grabber for fingers)
	var track: StyleBoxFlat = _box(Color(1, 1, 1, 0.14), 8, Color(0, 0, 0, 0), 0, 0, 5)
	var filled: StyleBoxFlat = _box(C_CYAN, 8, Color(0, 0, 0, 0), 0, 0, 5)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", _icon_circle(48, C_TEXT, C_ACCENT, 5.0))
	t.set_icon("grabber_highlight", "HSlider", _icon_circle(52, Color("ffffff"), C_ACCENT, 5.0))
	t.set_icon("grabber_disabled", "HSlider", _icon_circle(48, C_DIM, C_PANEL_3, 5.0))

	# Text fields
	t.set_stylebox("normal", "LineEdit", _box(Color(0, 0, 0, 0.45), 14, C_PANEL_3, 2, 18, 12))
	t.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0.55), 14, C_CYAN, 3, 18, 12))
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("caret_color", "LineEdit", C_ACCENT)
	t.set_font_size("font_size", "LineEdit", FS_BODY)

	# Progress bars
	t.set_stylebox("background", "ProgressBar", _box(Color(1, 1, 1, 0.12), 10, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(C_ACCENT, 10, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_font_size("font_size", "ProgressBar", FS_SMALL)
	return t


# ---------------------------------------------------------------------------
# Widgets
# ---------------------------------------------------------------------------
static func label(text: String, size: int = FS_BODY, color: Color = C_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func wrap_label(text: String, size: int = FS_BODY, color: Color = C_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = label(text, size, color, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _on_pressed(cb: Callable) -> void:
	AudioManager.play_click()
	Haptics.tap()
	if cb.is_valid():
		cb.call()


## kind: "primary", "secondary", "danger", "ghost"
static func button(text: String, cb: Callable, kind: String = "secondary", min_size: Vector2 = Vector2(0, BUTTON_H)) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.theme_type_variation = _variation_for(kind)
	b.pressed.connect(_on_pressed.bind(cb))
	return b


static func _variation_for(kind: String) -> String:
	match kind:
		"primary":
			return "PrimaryButton"
		"danger":
			return "DangerButton"
		"ghost":
			return "GhostButton"
		"secondary":
			return "SecondaryButton"
	return ""


static func hbox(separation: int = 14) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func vbox(separation: int = 14) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func spacer(height: float = 12.0) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func fill_spacer() -> Control:
	var c: Control = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func panel(variation: String = "") -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	if not variation.is_empty():
		p.theme_type_variation = variation
	return p


static func margin_box(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m


static func scroll(child: Control) -> ScrollContainer:
	var s: ScrollContainer = ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func separator(color: Color = Color(1, 1, 1, 0.12)) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Screen header: back button on the left, big title, optional right-hand widget.
static func header(title: String, on_back: Callable) -> HBoxContainer:
	var h: HBoxContainer = hbox(18)
	var back: Button = button("<  BACK", on_back, "ghost", Vector2(190, 68))
	h.add_child(back)
	var t: Label = label(title, FS_H1, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var balance: Control = Control.new()
	balance.custom_minimum_size = Vector2(190, 1)
	h.add_child(balance)
	return h


## Label + slider + value text. `fmt` is a Callable(float) -> String for the value label.
static func slider_row(text: String, min_v: float, max_v: float, step: float, value: float, on_change: Callable, fmt: Callable = Callable()) -> Dictionary:
	var row: HBoxContainer = hbox(18)
	row.custom_minimum_size = Vector2(0, 64)
	var name_l: Label = label(text, FS_BODY, C_TEXT)
	name_l.custom_minimum_size = Vector2(330, 0)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
	var s: HSlider = HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(300, 56)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var val_l: Label = label(_fmt_value(fmt, value), FS_BODY, C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	val_l.custom_minimum_size = Vector2(130, 0)
	val_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val_l)
	s.value_changed.connect(_on_slider_changed.bind(val_l, fmt, on_change))
	return {"row": row, "slider": s, "value_label": val_l}


static func _fmt_value(fmt: Callable, v: float) -> String:
	if fmt.is_valid():
		return String(fmt.call(v))
	return "%.2f" % v


static func _on_slider_changed(v: float, val_l: Label, fmt: Callable, on_change: Callable) -> void:
	val_l.text = _fmt_value(fmt, v)
	if on_change.is_valid():
		on_change.call(v)


## Label on the left, ON/OFF toggle on the right.
static func toggle_row(text: String, value: bool, on_change: Callable) -> Dictionary:
	var row: HBoxContainer = hbox(18)
	row.custom_minimum_size = Vector2(0, 64)
	var name_l: Label = label(text, FS_BODY, C_TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
	var b: Button = Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 60)
	b.button_pressed = value
	style_toggle(b)
	b.toggled.connect(_on_toggle.bind(b, on_change))
	row.add_child(b)
	return {"row": row, "button": b}


static func style_toggle(b: Button) -> void:
	b.text = "ON" if b.button_pressed else "OFF"
	b.theme_type_variation = "ToggleOn" if b.button_pressed else "ToggleOff"


static func _on_toggle(pressed: bool, b: Button, on_change: Callable) -> void:
	AudioManager.play_click()
	Haptics.tap()
	style_toggle(b)
	if on_change.is_valid():
		on_change.call(pressed)


## A row of mutually exclusive buttons. Returns { row, buttons }. on_change(index)
static func segmented(items: Array, selected: int, on_change: Callable, min_w: float = 140.0) -> Dictionary:
	var row: HBoxContainer = hbox(10)
	var group: ButtonGroup = ButtonGroup.new()
	var buttons: Array = []
	for i in range(items.size()):
		var b: Button = Button.new()
		b.text = String(items[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(min_w, 60)
		b.button_pressed = (i == selected)
		b.theme_type_variation = "SegmentOn" if i == selected else "SegmentOff"
		b.pressed.connect(_on_segment.bind(i, buttons, on_change))
		row.add_child(b)
		buttons.append(b)
	return {"row": row, "buttons": buttons}


static func _on_segment(index: int, buttons: Array, on_change: Callable) -> void:
	AudioManager.play_click()
	Haptics.tap()
	for i in range(buttons.size()):
		(buttons[i] as Button).theme_type_variation = "SegmentOn" if i == index else "SegmentOff"
	if on_change.is_valid():
		on_change.call(index)


static func set_segment(buttons: Array, index: int) -> void:
	for i in range(buttons.size()):
		var b: Button = buttons[i]
		b.set_pressed_no_signal(i == index)
		b.theme_type_variation = "SegmentOn" if i == index else "SegmentOff"


## A titled card (panel + heading) whose body you fill. Returns { card, body }.
static func section_card(title: String) -> Dictionary:
	var card: PanelContainer = panel("CardPanel")
	var body: VBoxContainer = vbox(12)
	card.add_child(body)
	if not title.is_empty():
		body.add_child(label(title, FS_H2, C_ACCENT))
		body.add_child(separator())
	return {"card": card, "body": body}
