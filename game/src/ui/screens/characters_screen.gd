extends UIScreen
## Character selection: unlocked characters can be picked, locked ones show their goal.
## Custom packs (.spirechar) can be imported from a file or from the clipboard.

var _grid: GridContainer
var _note: Label


func build() -> void:
	content.add_child(UIKit.header("CHARACTER", _on_back))
	var tools: HBoxContainer = UIKit.hbox(14)
	content.add_child(tools)
	_note = UIKit.label("Every character plays exactly the same. Only the looks differ.", UIKit.FS_SMALL, UIKit.C_DIM)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_child(_note)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		tools.add_child(UIKit.button("IMPORT FILE", _on_import_file, "secondary", Vector2(230, 64)))
	tools.add_child(UIKit.button("PASTE PACK", _on_import_clipboard, "secondary", Vector2(230, 64)))
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(UIKit.scroll(_grid))


func refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	# wider screens fit more cards per row
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_grid.columns = 5 if vp_w > 1500.0 else 4
	for id in CharacterManager.all_ids():
		_grid.add_child(_make_card(String(id)))


func _make_card(id: String) -> PanelContainer:
	var d: CharacterDef = CharacterManager.get_def(id)
	var unlocked: bool = CharacterManager.is_unlocked(id)
	var selected: bool = (id == CharacterManager.selected_id)
	var variation: String = "LockedCard"
	if selected:
		variation = "SelectedCard"
	elif unlocked:
		variation = "CardPanel"
	var card: PanelContainer = UIKit.panel(variation)
	card.custom_minimum_size = Vector2(250, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = UIKit.vbox(6)
	card.add_child(v)
	var pv: CharacterPreview = CharacterPreview.new(Vector2(140, 140))
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pv.set_character(d, "idle", not unlocked)
	v.add_child(pv)
	v.add_child(UIKit.label(d.display_name if unlocked else "???", UIKit.FS_H2, d.ui_color if unlocked else UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var info: String = d.tagline if unlocked else String(CharacterManager.unlock_progress(id)["text"])
	var info_label: Label = UIKit.wrap_label(info, UIKit.FS_SMALL, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	info_label.custom_minimum_size = Vector2(0, 62)
	v.add_child(info_label)
	if unlocked:
		if selected:
			v.add_child(UIKit.label("SELECTED", UIKit.FS_BODY, UIKit.C_GOOD, HORIZONTAL_ALIGNMENT_CENTER))
		else:
			v.add_child(UIKit.button("SELECT", _on_select.bind(id), "primary", Vector2(0, 60)))
		if d.custom:
			v.add_child(UIKit.button("REMOVE", _on_remove.bind(id), "ghost", Vector2(0, 50)))
	else:
		var prog: Dictionary = CharacterManager.unlock_progress(id)
		var bar: ProgressBar = ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = float(maxi(int(prog["target"]), 1))
		bar.value = float(mini(int(prog["current"]), int(prog["target"])))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 16)
		v.add_child(bar)
		v.add_child(UIKit.label("%s / %s" % [Fmt.number(int(prog["current"])), Fmt.number(int(prog["target"]))], UIKit.FS_SMALL, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	return card


func _on_select(id: String) -> void:
	CharacterManager.select(id)
	refresh()


func _on_remove(id: String) -> void:
	UIManager.confirm("Remove character?", "The custom character '%s' will be deleted from this device." % CharacterManager.get_def(id).display_name, "REMOVE", _do_remove.bind(id), true)


func _do_remove(id: String) -> void:
	CharacterManager.remove_custom(id)
	refresh()


func _on_import_file() -> void:
	var err: int = DisplayServer.file_dialog_show("Choose a character pack", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(), _on_file_chosen)
	if err != OK:
		UIManager.toast("The file picker is not available. Use PASTE PACK instead.")


func _on_file_chosen(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty():
		return
	_import_path.call_deferred(paths[0])


func _import_path(path: String) -> void:
	_finish_import(CharacterManager.import_pack_file(path))


func _on_import_clipboard() -> void:
	_finish_import(CharacterManager.import_pack_text(DisplayServer.clipboard_get()))


func _finish_import(result: Dictionary) -> void:
	if bool(result["ok"]):
		var id: String = String(result["id"])
		UIManager.toast("Imported '%s'" % CharacterManager.get_def(id).display_name)
		refresh()
	else:
		UIManager.info("Could not import", String(result["error"]))


func _on_back() -> void:
	UIManager.pop()
