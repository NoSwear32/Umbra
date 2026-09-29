extends Node
## Autoload "ThemeManager": the 11 tower environments and everything needed to draw them.
##
## floors   0-99   theme 0 ... floors 900-999 theme 9, floors 1000+ theme 10 (endless).
## Background colours blend smoothly during the last 12 floors before a boundary; textures
## are preloaded on a background thread when the player approaches a boundary so a theme
## change never causes a hitch.
##
## Platform "styles" (how PlatformView draws): see PlatformView.STYLE_*.

const THEME_COUNT: int = 11
const FLOORS_PER_THEME: int = 100
## Number of floors before a boundary over which colours blend.
const BLEND_FLOORS: float = 12.0
## Start preloading the next theme this many floors before its boundary.
const PRELOAD_FLOORS: int = 25
const ART_DIR: String = "res://assets/art/"

var _themes: Array = []
var _texture_cache: Dictionary = {}
var _pending: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_themes()


func _add(theme_name: String, subtitle: String, bg_top: String, bg_bottom: String, wall_a: String, wall_b: String, plat_top: String, plat_body: String, plat_edge: String, plat_deco: String, accent: String, style: int, panel_alpha: float) -> void:
	_themes.append({
		"name": theme_name,
		"subtitle": subtitle,
		"bg_top": Color(bg_top),
		"bg_bottom": Color(bg_bottom),
		"wall_a": Color(wall_a),
		"wall_b": Color(wall_b),
		"plat_top": Color(plat_top),
		"plat_body": Color(plat_body),
		"plat_edge": Color(plat_edge),
		"plat_deco": Color(plat_deco),
		"accent": Color(accent),
		"style": style,
		"panel_alpha": panel_alpha,
	})


func _build_themes() -> void:
	_themes.clear()
	#   name              subtitle                       bg_top    bg_bottom wall_a    wall_b    plat_top  plat_body plat_edge plat_deco accent    style alpha
	_add("Moss Vaults", "Old masonry by lantern light", "1b2433", "2d3b3a", "4a4f56", "3b6b3f", "e8d9a8", "8f7b5a", "2a2118", "5da05a", "ffb347", 0, 0.30)
	_add("Forge Deck", "Riveted iron and rising steam", "23181a", "40241c", "7a4a32", "b5652d", "ffd08a", "7d8794", "1c1f24", "e0793a", "ff8a3d", 1, 0.30)
	_add("Neon Grid", "Circuits humming in the dark", "0a0f24", "17103a", "1b2247", "2ef2ff", "35f2ff", "1c2a5a", "071026", "ff3df2", "ff3df2", 2, 0.34)
	_add("Overgrown Spire", "Ruins swallowed by the garden", "14261c", "2a4a2d", "8e9b8a", "4a8f3e", "d7f0a8", "7b8a6a", "1f2c19", "ff8fb1", "ffe066", 3, 0.28)
	_add("Prism Cavern", "A chamber of singing crystal", "1a1233", "21204f", "3b2e6b", "7fe3ff", "c9f6ff", "6f6ad8", "140e2c", "ff9be8", "7fe3ff", 4, 0.32)
	_add("Clockwork Hall", "Brass gears that never rest", "2b1d10", "47311b", "8a6a3a", "c9a24d", "ffe6a1", "a37b3a", "26180a", "d9d0c2", "ffcf5a", 5, 0.30)
	_add("Tempest Deck", "Storm clouds and crackling air", "10151f", "2a3444", "3d4a5c", "7fa0c8", "dfe9f5", "56657a", "0b0f16", "ffe86b", "9ad1ff", 6, 0.32)
	_add("Lumen Lattice", "Light folded into geometry", "6f86c9", "9a8bd6", "eaf0ff", "b7c6ff", "ffffff", "3a4a8f", "141b45", "ffd3f0", "ffffff", 7, 0.22)
	_add("Auroral Terrace", "Marble arches under green fire", "081428", "10305a", "cfd8e8", "7de3c1", "f4f7ff", "9aa8c4", "101a30", "7de3c1", "7dffc8", 8, 0.30)
	_add("Starwell", "Columns adrift among the stars", "0a0620", "241247", "3a2a70", "ffdf7a", "ffe9a8", "4a3a92", "0b0724", "ffdf7a", "ffdf7a", 9, 0.34)
	_add("Zenith", "Where the tower meets the sun", "2a1b5c", "ff8f5a", "fff1c9", "ffcf5a", "fffbe6", "d4a23a", "3a2200", "ffffff", "fff2a6", 10, 0.20)


# ---------------------------------------------------------------------------
# Lookup
# ---------------------------------------------------------------------------
func theme_index_for_floor(floor_index: int) -> int:
	return mini(maxi(floor_index, 0) / FLOORS_PER_THEME, THEME_COUNT - 1)


func get_theme(index: int) -> Dictionary:
	return _themes[clampi(index, 0, THEME_COUNT - 1)]


func theme_for_floor(floor_index: int) -> Dictionary:
	return get_theme(theme_index_for_floor(floor_index))


## Colours for the background/panel at a (fractional) floor with smooth transitions.
## Returns { from, to, t, bg_top, bg_bottom, accent, panel_alpha }.
func blended_at(floor_f: float) -> Dictionary:
	var f: float = maxf(floor_f, 0.0)
	var idx: int = mini(int(f / float(FLOORS_PER_THEME)), THEME_COUNT - 1)
	var to_idx: int = idx
	var t: float = 0.0
	if idx < THEME_COUNT - 1:
		var local: float = f - float(idx * FLOORS_PER_THEME)
		var start: float = float(FLOORS_PER_THEME) - BLEND_FLOORS
		if local > start:
			to_idx = idx + 1
			t = smoothstep(0.0, 1.0, (local - start) / BLEND_FLOORS)
	var a: Dictionary = get_theme(idx)
	var b: Dictionary = get_theme(to_idx)
	return {
		"from": idx,
		"to": to_idx,
		"t": t,
		"bg_top": (a["bg_top"] as Color).lerp(b["bg_top"], t),
		"bg_bottom": (a["bg_bottom"] as Color).lerp(b["bg_bottom"], t),
		"accent": (a["accent"] as Color).lerp(b["accent"], t),
		"panel_alpha": lerpf(float(a["panel_alpha"]), float(b["panel_alpha"]), t),
	}


## Texture for a theme. kind: "bg_far", "bg_near", "wall". Null if the file is missing.
func get_texture(kind: String, index: int) -> Texture2D:
	var path: String = _path(kind, index)
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if _pending.has(path):
		var status: int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			tex = ResourceLoader.load_threaded_get(path) as Texture2D
			_pending.erase(path)
		elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# still loading: block briefly rather than showing nothing
			tex = ResourceLoader.load_threaded_get(path) as Texture2D
			_pending.erase(path)
		else:
			_pending.erase(path)
	if tex == null and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_texture_cache[path] = tex
	return tex


func _path(kind: String, index: int) -> String:
	return "%s%s/%s_%02d.png" % [ART_DIR, "themes", kind, clampi(index, 0, THEME_COUNT - 1)]


## Starts loading a theme's textures on a background thread (no-op when cached).
func request_preload(index: int) -> void:
	if index < 0 or index >= THEME_COUNT:
		return
	for kind in ["bg_far", "bg_near", "wall"]:
		var path: String = _path(String(kind), index)
		if _texture_cache.has(path) or _pending.has(path):
			continue
		if ResourceLoader.exists(path):
			ResourceLoader.load_threaded_request(path)
			_pending[path] = true


## Called by the game each time the highest floor changes: preloads the upcoming theme.
func update_preload(highest_floor: int) -> void:
	var idx: int = theme_index_for_floor(highest_floor)
	request_preload(idx)
	var into: int = highest_floor - idx * FLOORS_PER_THEME
	if into >= FLOORS_PER_THEME - PRELOAD_FLOORS and idx < THEME_COUNT - 1:
		request_preload(idx + 1)
