extends Node
## Autoload "UIManager": screen navigation, dialogs, toasts and transitions.
##
## Screens are UIScreen subclasses created lazily from the SCREENS table and cached.
## Layers: menus (30) < dialogs, toasts and the fade curtain (100).
##
## The table holds script PATHS that are loaded on first use (not preloaded): the screens talk to
## this autoload, so a compile-time dependency in the other direction would be a cycle.

const SCREENS: Dictionary = {
	"main_menu": "res://src/ui/screens/main_menu_screen.gd",
	"control_select": "res://src/ui/screens/control_select_screen.gd",
	"calibrate": "res://src/ui/screens/calibration_screen.gd",
	"characters": "res://src/ui/screens/characters_screen.gd",
	"high_scores": "res://src/ui/screens/high_scores_screen.gd",
	"replays": "res://src/ui/screens/replays_screen.gd",
	"statistics": "res://src/ui/screens/statistics_screen.gd",
	"settings": "res://src/ui/screens/settings_screen.gd",
	"about": "res://src/ui/screens/about_screen.gd",
	"help": "res://src/ui/screens/help_screen.gd",
}

## The running game (set by Main). Used for Android back handling and starting runs.
var game: GameScene = null

var _screen_layer: CanvasLayer
var _top_layer: CanvasLayer
var _curtain: ColorRect
var _toast_holder: Control
var _toast_queue: Array = []
var _toast_active: bool = false
var _dialog: Control = null

var _cache: Dictionary = {}
var _stack: Array = []
var _current: UIScreen = null
var _current_id: String = ""
## Called when the root screen of an "opened from the game" flow is closed (see open_from_game).
var _on_root_pop: Callable = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen_layer = CanvasLayer.new()
	_screen_layer.layer = 30
	add_child(_screen_layer)
	_top_layer = CanvasLayer.new()
	_top_layer.layer = 100
	add_child(_top_layer)

	_curtain = ColorRect.new()
	_curtain.color = Color(0.02, 0.03, 0.07, 1.0)
	_curtain.modulate.a = 0.0
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_layer.add_child(_curtain)
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_toast_holder = Control.new()
	_toast_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_layer.add_child(_toast_holder)
	_toast_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	Events.back_requested.connect(back)
	Events.toast.connect(toast)
	get_viewport().size_changed.connect(_on_size_changed)


func _on_size_changed() -> void:
	Events.layout_changed.emit()


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------
func current_id() -> String:
	return _current_id


func has_screen_open() -> bool:
	return _current != null and _current.visible


func _get_screen(id: String) -> UIScreen:
	if _cache.has(id):
		return _cache[id]
	if not SCREENS.has(id):
		push_error("UIManager: unknown screen '%s'" % id)
		return null
	var script: GDScript = load(String(SCREENS[id])) as GDScript
	if script == null:
		push_error("UIManager: cannot load screen '%s'" % id)
		return null
	var s: UIScreen = script.new() as UIScreen
	s.screen_id = id
	s.visible = false
	_screen_layer.add_child(s)
	_cache[id] = s
	return s


## Shows a screen. push=false replaces the whole stack (a new "root" screen); push=true keeps
## the previous screen so pop() returns to it.
func show_screen(id: String, p: Dictionary = {}, push: bool = false) -> void:
	var s: UIScreen = _get_screen(id)
	if s == null:
		return
	if _current != null and _current != s:
		_current.on_exit()
		_current.visible = false
	if not push:
		_stack.clear()
		_on_root_pop = Callable()
	_stack.append(id)
	_current = s
	_current_id = id
	s.visible = true
	s.on_enter(p)
	# keep the newest screen on top of any other screens
	_screen_layer.move_child(s, _screen_layer.get_child_count() - 1)


func push_screen(id: String, p: Dictionary = {}) -> void:
	show_screen(id, p, true)


## Opens a screen on top of a running (paused) game. When the player leaves it, the screen
## is hidden again and `on_close` is called (used by the pause menu -> settings).
func open_from_game(id: String, on_close: Callable, p: Dictionary = {}) -> void:
	show_screen(id, p, false)
	_on_root_pop = on_close


## Goes back to the previous screen (or the main menu when the stack is empty).
func pop() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		var prev: String = _stack.pop_back()
		show_screen(prev, {}, true)
	elif _on_root_pop.is_valid():
		var cb: Callable = _on_root_pop
		_on_root_pop = Callable()
		hide_screens()
		cb.call()
	else:
		show_screen("main_menu")


## Hides all menu screens (used while a run is being played).
func hide_screens() -> void:
	_on_root_pop = Callable()
	if _current != null:
		_current.on_exit()
		_current.visible = false
	_current = null
	_current_id = ""
	_stack.clear()


## Android back button / Escape. Priority: dialog > open menu screen > running game.
## A screen that is open always handles Back itself - also when it was opened over a paused game
## (Settings from the pause menu): the run must never resume behind it.
func back() -> void:
	if _dialog != null:
		close_dialog()
		AudioManager.play_back()
		return
	if has_screen_open():
		_back_in_screen()
		return
	if game != null:
		game.handle_back()


func _back_in_screen() -> void:
	if _current.on_back():
		return
	if _stack.size() > 1 or _on_root_pop.is_valid():
		AudioManager.play_back()
		pop()
	elif _current_id == "main_menu" or _current_id == "control_select":
		confirm("Leave the tower?", "Do you want to exit Spire Sprint?", "EXIT", AndroidLifecycleManager.quit_game, true)
	else:
		AudioManager.play_back()
		pop()  # a root screen without a caller goes back to the main menu


## Fades to black, runs `action` while the screen is hidden, then fades back in.
func transition(action: Callable, duration: float = 0.16) -> void:
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw: Tween = create_tween()
	tw.tween_property(_curtain, "modulate:a", 1.0, duration)
	tw.tween_callback(action)
	tw.tween_property(_curtain, "modulate:a", 0.0, duration)
	tw.tween_callback(_release_curtain)


func _release_curtain() -> void:
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ---------------------------------------------------------------------------
# Toasts
# ---------------------------------------------------------------------------
func toast(message: String, seconds: float = 2.4) -> void:
	_toast_queue.append([message, seconds])
	if not _toast_active:
		_show_next_toast()


func _show_next_toast() -> void:
	if _toast_queue.is_empty():
		_toast_active = false
		return
	_toast_active = true
	var item: Array = _toast_queue.pop_front()
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = UIKit.get_theme()
	panel.theme_type_variation = "BannerPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = UIKit.label(String(item[0]), UIKit.FS_BODY, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	panel.add_child(l)
	_toast_holder.add_child(panel)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ins: Vector4 = SafeArea.get_insets(get_viewport())
	panel.reset_size()
	panel.position = Vector2((vp.x - panel.size.x) * 0.5, ins.y)
	panel.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
	tw.tween_interval(float(item[1]))
	tw.tween_property(panel, "modulate:a", 0.0, 0.25)
	tw.tween_callback(_finish_toast.bind(panel))


func _finish_toast(panel: Control) -> void:
	panel.queue_free()
	_show_next_toast()


# ---------------------------------------------------------------------------
# Dialogs
# ---------------------------------------------------------------------------
func is_dialog_open() -> bool:
	return _dialog != null


func close_dialog() -> void:
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


func _make_dialog(title: String) -> Dictionary:
	close_dialog()
	var root: Control = Control.new()
	root.theme = UIKit.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_top_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center: CenterContainer = CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = UIKit.panel()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var body: VBoxContainer = UIKit.vbox(18)
	panel.add_child(body)
	body.add_child(UIKit.label(title, UIKit.FS_H2, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_dialog = root
	return {"root": root, "body": body}


## Modal yes/no dialog. `on_confirm` runs only when the player accepts.
func confirm(title: String, message: String, confirm_text: String, on_confirm: Callable, danger: bool = false, cancel_text: String = "CANCEL") -> void:
	var d: Dictionary = _make_dialog(title)
	var body: VBoxContainer = d["body"]
	body.add_child(UIKit.wrap_label(message, UIKit.FS_BODY, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.spacer(6))
	var row: HBoxContainer = UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button(cancel_text, close_dialog, "secondary", Vector2(250, 72)))
	row.add_child(UIKit.button(confirm_text, _accept_dialog.bind(on_confirm), "danger" if danger else "primary", Vector2(250, 72)))
	body.add_child(row)


func _accept_dialog(on_confirm: Callable) -> void:
	close_dialog()
	if on_confirm.is_valid():
		on_confirm.call()


## Modal text prompt (rename replay / player name). on_ok(text)
func prompt_text(title: String, initial: String, max_length: int, on_ok: Callable) -> void:
	var d: Dictionary = _make_dialog(title)
	var body: VBoxContainer = d["body"]
	var edit: LineEdit = LineEdit.new()
	edit.text = initial
	edit.max_length = max_length
	edit.custom_minimum_size = Vector2(0, 72)
	edit.select_all_on_focus = true
	edit.context_menu_enabled = false
	body.add_child(edit)
	body.add_child(UIKit.spacer(6))
	var row: HBoxContainer = UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button("CANCEL", close_dialog, "secondary", Vector2(250, 72)))
	row.add_child(UIKit.button("SAVE", _accept_prompt.bind(edit, on_ok), "primary", Vector2(250, 72)))
	body.add_child(row)
	edit.text_submitted.connect(_submit_prompt.bind(on_ok))
	edit.grab_focus.call_deferred()


func _accept_prompt(edit: LineEdit, on_ok: Callable) -> void:
	var text: String = edit.text
	close_dialog()
	if on_ok.is_valid():
		on_ok.call(text)


func _submit_prompt(text: String, on_ok: Callable) -> void:
	close_dialog()
	if on_ok.is_valid():
		on_ok.call(text)


## Simple information dialog with one button.
func info(title: String, message: String, button_text: String = "OK") -> void:
	var d: Dictionary = _make_dialog(title)
	var body: VBoxContainer = d["body"]
	body.add_child(UIKit.wrap_label(message, UIKit.FS_BODY, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.spacer(6))
	var row: HBoxContainer = UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button(button_text, close_dialog, "primary", Vector2(280, 72)))
	body.add_child(row)


## Scrollable text (licences and other long documents), dismissed with one button.
func text_viewer(title: String, message: String, button_text: String = "CLOSE") -> void:
	var d: Dictionary = _make_dialog(title)
	var body: VBoxContainer = d["body"]
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var label: Label = UIKit.wrap_label(message, UIKit.FS_SMALL, UIKit.C_TEXT)
	scroll.add_child(label)
	var row: HBoxContainer = UIKit.hbox(18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UIKit.button(button_text, close_dialog, "primary", Vector2(280, 72)))
	body.add_child(row)
