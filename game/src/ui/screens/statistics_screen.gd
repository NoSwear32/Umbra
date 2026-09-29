extends UIScreen
## Lifetime statistics of the player profile.

var _grid: GridContainer


func build() -> void:
	content.add_child(UIKit.header("STATISTICS", _on_back))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(UIKit.scroll(_grid))
	StatisticsManager.changed.connect(refresh)


func refresh() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var rows: Array = [
		["Games played", Fmt.number(StatisticsManager.get_int("games_played"))],
		["Highest score", Fmt.number(StatisticsManager.get_int("highest_score"))],
		["Highest floor", Fmt.number(StatisticsManager.get_int("highest_floor"))],
		["Longest combo (floors)", Fmt.number(StatisticsManager.get_int("longest_combo"))],
		["Longest combo (jumps)", Fmt.number(StatisticsManager.get_int("longest_combo_jumps"))],
		["Combos completed", Fmt.number(StatisticsManager.get_int("combos_completed"))],
		["Total jumps", Fmt.number(StatisticsManager.get_int("total_jumps"))],
		["Combo jumps", Fmt.number(StatisticsManager.get_int("total_combo_jumps"))],
		["Total floors climbed", Fmt.number(StatisticsManager.get_int("total_floors_climbed"))],
		["Wall rebounds", Fmt.number(StatisticsManager.get_int("wall_rebounds"))],
		["Longest run", Fmt.duration(StatisticsManager.get_float("longest_run_seconds"))],
		["Total playtime", Fmt.playtime(StatisticsManager.get_float("total_playtime_seconds"))],
		["Personal records", Fmt.number(StatisticsManager.get_int("personal_records"))],
	]
	for r in rows:
		_grid.add_child(_make_cell(String(r[0]), String(r[1])))


func _make_cell(title: String, value: String) -> PanelContainer:
	var card: PanelContainer = UIKit.panel("CardPanel")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(300, 0)
	var v: VBoxContainer = UIKit.vbox(2)
	card.add_child(v)
	v.add_child(UIKit.label(title, UIKit.FS_SMALL, UIKit.C_DIM))
	v.add_child(UIKit.label(value, UIKit.FS_H1, UIKit.C_ACCENT))
	return card


func _on_back() -> void:
	UIManager.pop()
