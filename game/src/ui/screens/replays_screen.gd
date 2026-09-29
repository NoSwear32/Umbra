extends UIScreen
## Replay list: watch, rename, delete and share recorded runs. Replays are deterministic
## input recordings, so playback re-simulates the exact run (and never submits scores).

var _list: VBoxContainer
var _count_label: Label


func build() -> void:
	content.add_child(UIKit.header("REPLAYS", _on_back))
	var tools: HBoxContainer = UIKit.hbox(14)
	content.add_child(tools)
	_count_label = UIKit.label("", UIKit.FS_SMALL, UIKit.C_DIM)
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_child(_count_label)
	tools.add_child(UIKit.button("PASTE REPLAY", _on_paste, "secondary", Vector2(260, 64)))
	_list = UIKit.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(UIKit.scroll(_list))
	ReplayManager.list_changed.connect(_populate)


func refresh() -> void:
	_populate()


func _populate() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var metas: Array = ReplayManager.list_meta()
	_count_label.text = "%d replay(s) saved. Older unnamed replays are removed automatically; rename one to keep it." % metas.size()
	if metas.is_empty():
		var empty: Label = UIKit.label("No replays yet. Finish a run and it shows up here.", UIKit.FS_H2, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		empty.custom_minimum_size = Vector2(0, 160)
		_list.add_child(empty)
		return
	for m in metas:
		_list.add_child(_make_row(m))


func _make_row(m: Dictionary) -> PanelContainer:
	var id: String = String(m["id"])
	var card: PanelContainer = UIKit.panel("CardPanel")
	var h: HBoxContainer = UIKit.hbox(14)
	card.add_child(h)
	var info: VBoxContainer = UIKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var title: String = String(m.get("name", ""))
	if title.is_empty():
		title = "Run  %s" % Fmt.date_time(int(m.get("created", 0)))
	info.add_child(UIKit.label(title, UIKit.FS_BODY + 2, UIKit.C_TEXT))
	var detail: String = "Score %s   Floor %d   Combo %d   %s" % [Fmt.number(int(m.get("score", 0))), int(m.get("floor", 0)), int(m.get("combo", 0)), Fmt.duration(float(m.get("duration", 0.0)))]
	info.add_child(UIKit.label(detail, UIKit.FS_SMALL, UIKit.C_GOLD))
	var sub: String = "%s  /  %s controls" % [CharacterManager.get_def(String(m.get("character", "pip"))).display_name, String(m.get("control", "touch"))]
	var compatible: bool = int(m.get("sim_version", 0)) == SimConst.SIM_VERSION
	if not compatible:
		sub += "   -   recorded with an older game version (cannot be played)"
	elif not bool(m.get("complete", true)):
		sub += "   -   interrupted run"
	info.add_child(UIKit.label(sub, UIKit.FS_SMALL, UIKit.C_DIM if compatible else UIKit.C_BAD))
	var watch: Button = UIKit.button("WATCH", _on_watch.bind(id), "primary", Vector2(150, 64))
	watch.disabled = not compatible
	h.add_child(watch)
	var rename: Button = UIKit.button("RENAME", _on_rename.bind(id), "secondary", Vector2(140, 64))
	rename.add_theme_font_size_override("font_size", 22)
	h.add_child(rename)
	var share: Button = UIKit.button("SHARE", _on_share.bind(id), "secondary", Vector2(130, 64))
	share.add_theme_font_size_override("font_size", 22)
	h.add_child(share)
	var del: Button = UIKit.button("DELETE", _on_delete.bind(id), "danger", Vector2(140, 64))
	del.add_theme_font_size_override("font_size", 22)
	h.add_child(del)
	return card


func _on_watch(id: String) -> void:
	var r: Dictionary = ReplayManager.load_replay(id)
	if not bool(r["ok"]):
		UIManager.toast(String(r["error"]))
		return
	UIManager.game.start_replay(r["replay"])


func _on_rename(id: String) -> void:
	var m: Dictionary = ReplayManager.find_meta(id)
	UIManager.prompt_text("Name this replay", String(m.get("name", "")), 40, _apply_rename.bind(id))


func _apply_rename(text: String, id: String) -> void:
	ReplayManager.rename_replay(id, text)


func _on_share(id: String) -> void:
	var text: String = ReplayManager.export_text(id)
	if text.is_empty():
		UIManager.toast("The replay file is missing.")
		return
	var opened: bool = ShareUtil.share_text("Spire Sprint replay", text)
	UIManager.toast("Replay copied to the clipboard" if not opened else "Replay ready to share")


func _on_delete(id: String) -> void:
	UIManager.confirm("Delete replay?", "This replay will be removed from the device.", "DELETE", ReplayManager.delete_replay.bind(id), true)


func _on_paste() -> void:
	var r: Dictionary = ReplayManager.import_text(DisplayServer.clipboard_get())
	if bool(r["ok"]):
		UIManager.toast("Replay imported")
	else:
		UIManager.info("Could not import", String(r["error"]))


func _on_back() -> void:
	UIManager.pop()
