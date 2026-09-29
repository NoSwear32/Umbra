extends UIScreen
## Local leaderboards: highest score, highest floor, best combo (top 20 each).

const CATEGORIES: Array = ["score", "floor", "combo"]
const TAB_NAMES: Array = ["HIGHEST SCORE", "HIGHEST FLOOR", "BEST COMBO"]

var _tab: int = 0
var _list: VBoxContainer
var _tabs: Dictionary


func build() -> void:
	content.add_child(UIKit.header("HIGH SCORES", _on_back))
	_tabs = UIKit.segmented(TAB_NAMES, 0, _on_tab, 300.0)
	(_tabs["row"] as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(_tabs["row"])
	_list = UIKit.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(UIKit.scroll(_list))


func refresh() -> void:
	UIKit.set_segment(_tabs["buttons"], _tab)
	_populate()


func _on_tab(index: int) -> void:
	_tab = index
	_populate()


func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cat: String = CATEGORIES[_tab]
	var entries: Array = LeaderboardManager.get_entries(cat)
	if entries.is_empty():
		var empty: Label = UIKit.label("No runs yet - go climb!", UIKit.FS_H2, UIKit.C_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		empty.custom_minimum_size = Vector2(0, 160)
		_list.add_child(empty)
		return
	for i in range(entries.size()):
		_list.add_child(_make_row(i + 1, entries[i], cat))


func _make_row(rank: int, e: Dictionary, cat: String) -> PanelContainer:
	var card: PanelContainer = UIKit.panel("SelectedCard" if rank == 1 else "CardPanel")
	var h: HBoxContainer = UIKit.hbox(18)
	card.add_child(h)
	var rank_color: Color = UIKit.C_TEXT
	match rank:
		1:
			rank_color = UIKit.C_GOLD
		2:
			rank_color = Color("d8dee9")
		3:
			rank_color = Color("e0935a")
	var rk: Label = UIKit.label("#%d" % rank, UIKit.FS_H2, rank_color, HORIZONTAL_ALIGNMENT_CENTER)
	rk.custom_minimum_size = Vector2(90, 0)
	rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rk)
	var mid: VBoxContainer = UIKit.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	mid.add_child(UIKit.label(String(e["name"]), UIKit.FS_BODY + 2, UIKit.C_TEXT))
	var details: String = "Floor %d   Combo %d   %s   %s" % [int(e["floor"]), int(e["combo"]), Fmt.duration(float(e["duration"])), Fmt.date_only(int(e["date"]))]
	mid.add_child(UIKit.label(details, UIKit.FS_SMALL, UIKit.C_DIM))
	var value: int = LeaderboardProvider.value_of(e, cat)
	var vl: Label = UIKit.label(Fmt.number(value), UIKit.FS_H1, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size = Vector2(230, 0)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(vl)
	var rid: String = String(e["replay_id"])
	if not rid.is_empty() and ReplayManager.has_replay(rid):
		h.add_child(UIKit.button("WATCH", _on_watch.bind(rid), "secondary", Vector2(150, 64)))
	return card


func _on_watch(replay_id: String) -> void:
	var r: Dictionary = ReplayManager.load_replay(replay_id)
	if not bool(r["ok"]):
		UIManager.toast(String(r["error"]))
		return
	UIManager.game.start_replay(r["replay"])


func _on_back() -> void:
	UIManager.pop()
