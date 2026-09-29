class_name CharacterPack
extends RefCounted
## Validation and loading of custom character packs (".spirechar" files).
##
## A pack is ONE JSON document with an embedded base64 PNG sprite sheet:
##
## {
##   "format": "spire-sprint-character", "format_version": 1,
##   "id": "my_hero", "name": "My Hero", "author": "Someone",
##   "frame_size": [128, 128], "anchor": [64, 120], "scale": 0.72,
##   "scarf": ["#ff5a3c", "#ffd23c"],
##   "animations": { "idle": {"row": 0, "frames": 4, "fps": 5, "loop": true}, ... },
##   "sheet_png_base64": "iVBORw0KGgo..."
## }
##
## SECURITY: a pack can never execute code. Only the fields above are read; the PNG is
## decoded by the engine's image decoder after its header has been checked against hard
## size limits; no resource, script or scene loader is ever used on pack data. Anything
## that does not validate is rejected with a readable message.

const FORMAT_ID: String = "spire-sprint-character"
const FORMAT_VERSION: int = 1
const MAX_TEXT_CHARS: int = 2600000
const MAX_PNG_BYTES: int = 1500000
const MAX_DIMENSION: int = 1536
const MIN_FRAME: int = 16
const MAX_FRAME: int = 256
const MAX_FRAMES_PER_ANIM: int = 16
const MAX_ROWS: int = 24
const MAX_FPS: float = 60.0
const ID_MIN_LENGTH: int = 3
const ID_MAX_LENGTH: int = 24
const PNG_SIGNATURE: Array = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]


## Validates pack text. Returns:
## { "ok": bool, "error": String, "def": CharacterDef (when ok) }
static func parse(text: String, reserved_ids: Array = []) -> Dictionary:
	if text.length() > MAX_TEXT_CHARS:
		return _fail("The file is too large (limit %d KB)." % int(MAX_TEXT_CHARS / 1024))
	if text.strip_edges().is_empty():
		return _fail("The file is empty.")
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _fail("This is not a valid character pack (unreadable JSON).")
	if not (json.data is Dictionary):
		return _fail("This is not a valid character pack (unexpected structure).")
	var d: Dictionary = json.data

	if String(d.get("format", "")) != FORMAT_ID:
		return _fail("This is not a Spire Sprint character pack.")
	if int(d.get("format_version", 0)) != FORMAT_VERSION:
		return _fail("Unsupported pack version.")

	# ---- identity
	var id: String = String(d.get("id", ""))
	if not is_valid_id(id):
		return _fail("Invalid id: use %d-%d characters a-z, 0-9 and _." % [ID_MIN_LENGTH, ID_MAX_LENGTH])
	if reserved_ids.has(id):
		return _fail("The id '%s' is already used by a built-in character." % id)
	var display_name: String = _clean_text(String(d.get("name", "")), 20)
	if display_name.is_empty():
		return _fail("The character needs a name (1-20 characters).")
	var author: String = _clean_text(String(d.get("author", "")), 32)

	# ---- geometry
	var fs: Variant = d.get("frame_size", null)
	if not (fs is Array) or (fs as Array).size() != 2:
		return _fail("frame_size must be [width, height].")
	var fw: int = int(fs[0])
	var fh: int = int(fs[1])
	if fw < MIN_FRAME or fh < MIN_FRAME or fw > MAX_FRAME or fh > MAX_FRAME:
		return _fail("frame_size must be between %d and %d pixels." % [MIN_FRAME, MAX_FRAME])
	var anchor: Vector2 = Vector2(float(fw) * 0.5, float(fh) * 0.94)
	var an: Variant = d.get("anchor", null)
	if an is Array and (an as Array).size() == 2:
		anchor = Vector2(clampf(float(an[0]), 0.0, float(fw)), clampf(float(an[1]), 0.0, float(fh)))
	var scl: float = clampf(float(d.get("scale", 0.72)), 0.1, 2.0)

	# ---- colours
	var c1: Color = Color(0.13, 0.75, 0.75, 1.0)
	var c2: Color = Color(1.0, 0.85, 0.3, 1.0)
	var sc: Variant = d.get("scarf", null)
	if sc is Array and (sc as Array).size() == 2:
		if String(sc[0]).length() <= 9 and Color.html_is_valid(String(sc[0])):
			c1 = Color.html(String(sc[0]))
		if String(sc[1]).length() <= 9 and Color.html_is_valid(String(sc[1])):
			c2 = Color.html(String(sc[1]))

	# ---- animations
	var anims_in: Variant = d.get("animations", null)
	if not (anims_in is Dictionary):
		return _fail("animations are missing.")
	var anims: Dictionary = {}
	for key in anims_in:
		var anim_name: String = String(key)
		if not CharacterDef.ANIM_ORDER.has(anim_name):
			continue  # unknown animation names are ignored, never used
		var a: Variant = anims_in[key]
		if not (a is Dictionary):
			return _fail("Animation '%s' is malformed." % anim_name)
		var row: int = int(a.get("row", -1))
		var frames: int = int(a.get("frames", 0))
		var fps: float = float(a.get("fps", 8.0))
		if row < 0 or row >= MAX_ROWS:
			return _fail("Animation '%s': row out of range." % anim_name)
		if frames < 1 or frames > MAX_FRAMES_PER_ANIM:
			return _fail("Animation '%s': frames must be 1-%d." % [anim_name, MAX_FRAMES_PER_ANIM])
		if fps < 1.0 or fps > MAX_FPS:
			return _fail("Animation '%s': fps must be 1-%d." % [anim_name, int(MAX_FPS)])
		anims[anim_name] = {"row": row, "frames": frames, "fps": fps, "loop": bool(a.get("loop", true))}
	for req in CharacterDef.REQUIRED_ANIMS:
		if not anims.has(req):
			return _fail("Required animation '%s' is missing." % req)

	# ---- sprite sheet
	var b64: Variant = d.get("sheet_png_base64", null)
	if not (b64 is String) or String(b64).is_empty():
		return _fail("The sprite sheet is missing.")
	if String(b64).length() > int(MAX_PNG_BYTES * 4 / 3) + 16:
		return _fail("The sprite sheet is too large.")
	var png: PackedByteArray = Marshalls.base64_to_raw(String(b64))
	if png.size() < 33 or png.size() > MAX_PNG_BYTES:
		return _fail("The sprite sheet has an invalid size.")
	for i in range(PNG_SIGNATURE.size()):
		if png[i] != int(PNG_SIGNATURE[i]):
			return _fail("The sprite sheet is not a PNG image.")
	var img_w: int = _be32(png, 16)
	var img_h: int = _be32(png, 20)
	if img_w < fw or img_h < fh or img_w > MAX_DIMENSION or img_h > MAX_DIMENSION:
		return _fail("The sprite sheet dimensions are out of range (max %d px)." % MAX_DIMENSION)
	for key2 in anims:
		var a2: Dictionary = anims[key2]
		if int(a2["frames"]) * fw > img_w or (int(a2["row"]) + 1) * fh > img_h:
			return _fail("Animation '%s' does not fit into the sprite sheet." % String(key2))
	var img: Image = Image.new()
	if img.load_png_from_buffer(png) != OK:
		return _fail("The sprite sheet could not be decoded.")

	var def: CharacterDef = CharacterDef.new()
	def.id = id
	def.display_name = display_name
	def.author = author
	def.tagline = "Custom character" if author.is_empty() else "Custom character by %s" % author
	def.custom = true
	def.frame_size = Vector2i(fw, fh)
	def.anchor = anchor
	def.sprite_scale = scl
	def.animations = anims
	def.scarf_color = c1
	def.scarf_color2 = c2
	def.ui_color = c1
	def.texture = ImageTexture.create_from_image(img)
	return {"ok": true, "error": "", "def": def}


## True for 3-24 characters of a-z, 0-9 and "_" (checked character by character: no pattern
## quirks such as "$" matching before a trailing newline).
static func is_valid_id(id: String) -> bool:
	if id.length() < ID_MIN_LENGTH or id.length() > ID_MAX_LENGTH:
		return false
	for i in range(id.length()):
		var code: int = id.unicode_at(i)
		var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95
		if not ok:
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "def": null}


## Strips control characters and clamps the length (names are shown in the UI).
static func _clean_text(s: String, max_len: int) -> String:
	var out: String = ""
	for i in range(s.length()):
		var code: int = s.unicode_at(i)
		if code >= 32 and code != 127:
			out += s[i]
	return out.strip_edges().substr(0, max_len)


static func _be32(b: PackedByteArray, offset: int) -> int:
	return (int(b[offset]) << 24) | (int(b[offset + 1]) << 16) | (int(b[offset + 2]) << 8) | int(b[offset + 3])
