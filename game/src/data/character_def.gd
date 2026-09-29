class_name CharacterDef
extends RefCounted
## Description of a playable character (appearance only - all characters share the
## exact same physics so scores stay fair).
##
## Sprite sheets use a fixed grid: one ROW per animation, one COLUMN per frame.
## Built-in characters ship as PNG sheets in res://assets/art/characters/<id>.png;
## custom characters (.spirechar packs, see CharacterPack) carry their own grid.

## Animation names in the order of the standard sheet rows.
const ANIM_ORDER: Array = ["idle", "run", "accel", "jump_up", "fall", "fast_jump", "wall", "land", "near_fall", "gameover"]
## Animations every custom pack must define; missing optional ones fall back to these.
const REQUIRED_ANIMS: Array = ["idle", "run", "jump_up", "fall"]
## Fallback chain for optional animations that a pack does not provide.
const FALLBACKS: Dictionary = {
	"accel": "run",
	"fast_jump": "jump_up",
	"wall": "jump_up",
	"land": "idle",
	"near_fall": "fall",
	"gameover": "fall",
}

var id: String = ""
var display_name: String = ""
var tagline: String = ""
var author: String = ""
var custom: bool = false
## Statistic (see StatisticsManager) that unlocks this character; "" = available from the start.
var unlock_stat: String = ""
var unlock_target: int = 0
var frame_size: Vector2i = Vector2i(128, 128)
## Position of the feet inside a frame (pixels). The node origin of the player is the feet.
var anchor: Vector2 = Vector2(64.0, 120.0)
## Scale applied to the sprite so the art matches the physics body.
var sprite_scale: float = 0.72
var animations: Dictionary = {}
var scarf_color: Color = Color(0.13, 0.75, 0.75, 1.0)
var scarf_color2: Color = Color(1.0, 0.85, 0.3, 1.0)
var ui_color: Color = Color(0.13, 0.75, 0.75, 1.0)
var sheet_path: String = ""
var texture: Texture2D = null


static func default_animations() -> Dictionary:
	return {
		"idle": {"row": 0, "frames": 4, "fps": 5.0, "loop": true},
		"run": {"row": 1, "frames": 6, "fps": 14.0, "loop": true},
		"accel": {"row": 2, "frames": 2, "fps": 8.0, "loop": true},
		"jump_up": {"row": 3, "frames": 2, "fps": 10.0, "loop": false},
		"fall": {"row": 4, "frames": 2, "fps": 8.0, "loop": true},
		"fast_jump": {"row": 5, "frames": 2, "fps": 12.0, "loop": true},
		"wall": {"row": 6, "frames": 2, "fps": 12.0, "loop": false},
		"land": {"row": 7, "frames": 2, "fps": 14.0, "loop": false},
		"near_fall": {"row": 8, "frames": 2, "fps": 10.0, "loop": true},
		"gameover": {"row": 9, "frames": 2, "fps": 6.0, "loop": true},
	}


## Resolves an animation name to one this character actually has.
func resolve_anim(anim: String) -> String:
	var name: String = anim
	var guard: int = 0
	while not animations.has(name) and guard < 4:
		name = String(FALLBACKS.get(name, "idle"))
		guard += 1
	if not animations.has(name):
		name = "idle"
	return name


func frame_count(anim: String) -> int:
	var a: Dictionary = animations.get(resolve_anim(anim), {})
	return maxi(int(a.get("frames", 1)), 1)


func anim_fps(anim: String) -> float:
	var a: Dictionary = animations.get(resolve_anim(anim), {})
	return float(a.get("fps", 8.0))


func anim_loops(anim: String) -> bool:
	var a: Dictionary = animations.get(resolve_anim(anim), {})
	return bool(a.get("loop", true))


## Source rectangle (in the sheet texture) of one frame.
func frame_rect(anim: String, frame: int) -> Rect2:
	var a: Dictionary = animations.get(resolve_anim(anim), {})
	var row: int = int(a.get("row", 0))
	var count: int = maxi(int(a.get("frames", 1)), 1)
	var col: int = clampi(frame, 0, count - 1)
	return Rect2(float(col * frame_size.x), float(row * frame_size.y), float(frame_size.x), float(frame_size.y))


## The sheet texture (built-in sheets are loaded lazily; null if the file is missing).
func get_texture() -> Texture2D:
	if texture == null and not custom and not sheet_path.is_empty():
		if ResourceLoader.exists(sheet_path):
			texture = load(sheet_path) as Texture2D
	return texture
