extends RefCounted
## Characters: the sprite sheet layout contract, animation fallbacks and the safety of
## custom character packs (.spirechar files are untrusted input).

const FRAME: int = 32


func run(t: TestContext) -> void:
	_layout(t)
	_valid_pack(t)
	_rejected_packs(t)
	_sanitising(t)
	_untrusted_fields(t)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
## A solid-colour PNG of the given size (tiny once compressed).
func _png(w: int, h: int) -> PackedByteArray:
	var img: Image = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.9, 1.0))
	return img.save_png_to_buffer()


func _b64(w: int, h: int) -> String:
	return Marshalls.raw_to_base64(_png(w, h))


func _animations() -> Dictionary:
	return {
		"idle": {"row": 0, "frames": 4, "fps": 5, "loop": true},
		"run": {"row": 1, "frames": 6, "fps": 14, "loop": true},
		"jump_up": {"row": 2, "frames": 2, "fps": 10, "loop": false},
		"fall": {"row": 3, "frames": 2, "fps": 8, "loop": true},
	}


## A complete, valid pack dictionary; `overrides` replace top-level fields.
func _pack(overrides: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"format": CharacterPack.FORMAT_ID,
		"format_version": CharacterPack.FORMAT_VERSION,
		"id": "test_hero",
		"name": "Test Hero",
		"author": "QA",
		"frame_size": [FRAME, FRAME],
		"anchor": [16, 30],
		"scale": 0.8,
		"scarf": ["#ff5a3c", "#ffd23c"],
		"animations": _animations(),
		"sheet_png_base64": _b64(6 * FRAME, 4 * FRAME),
	}
	for key in overrides:
		d[key] = overrides[key]
	return d


func _parse(d: Dictionary, reserved: Array = []) -> Dictionary:
	return CharacterPack.parse(JSON.stringify(d), reserved)


func _rejects(t: TestContext, d: Dictionary, message: String) -> void:
	var r: Dictionary = _parse(d)
	t.check(not bool(r["ok"]), message)
	t.check(not String(r["error"]).is_empty() or bool(r["ok"]), "%s (with a readable message)" % message)
	t.check(r["def"] == null or bool(r["ok"]), "%s (and no character object)" % message)


# ---------------------------------------------------------------------------
# Sheet layout of the built-in characters
# ---------------------------------------------------------------------------
func _layout(t: TestContext) -> void:
	t.suite("characters: sheet layout and fallbacks")
	var anims: Dictionary = CharacterDef.default_animations()
	t.eq(anims.size(), CharacterDef.ANIM_ORDER.size(), "every standard animation is defined")
	var rows_ok: bool = true
	var max_frames: int = 0
	for i in range(CharacterDef.ANIM_ORDER.size()):
		var anim_name: String = String(CharacterDef.ANIM_ORDER[i])
		var a: Dictionary = anims[anim_name]
		if int(a["row"]) != i:
			rows_ok = false
		max_frames = maxi(max_frames, int(a["frames"]))
	t.check(rows_ok, "sheet rows follow the standard animation order")
	t.check(max_frames <= 6, "no animation needs more than 6 columns (sheets are 768 px wide)")
	for req in CharacterDef.REQUIRED_ANIMS:
		t.check(anims.has(String(req)), "the standard set contains the required animation '%s'" % String(req))

	var def: CharacterDef = CharacterDef.new()
	def.animations = CharacterDef.default_animations()
	t.eq(def.frame_rect("idle", 0), Rect2(0.0, 0.0, 128.0, 128.0), "first frame of the first row")
	t.eq(def.frame_rect("run", 5), Rect2(640.0, 128.0, 128.0, 128.0), "last run frame")
	t.eq(def.frame_rect("gameover", 1), Rect2(128.0, 1152.0, 128.0, 128.0), "last row")
	t.eq(def.frame_rect("idle", 99), Rect2(384.0, 0.0, 128.0, 128.0), "frame numbers past the end are clamped")
	t.eq(def.frame_rect("idle", -3), Rect2(0.0, 0.0, 128.0, 128.0), "and negative ones too")
	t.eq(def.frame_count("run"), 6, "frame count")
	t.eq(def.frame_count("nonexistent"), 4, "an unknown animation resolves to idle")
	t.check(def.anim_loops("idle") and not def.anim_loops("jump_up"), "looping flags")
	t.near(def.anim_fps("run"), 14.0, 1e-9, "animation speed")

	# optional animations fall back to a required one
	var small: CharacterDef = CharacterDef.new()
	small.animations = {
		"idle": {"row": 0, "frames": 1, "fps": 5.0, "loop": true},
		"run": {"row": 1, "frames": 1, "fps": 5.0, "loop": true},
		"jump_up": {"row": 2, "frames": 1, "fps": 5.0, "loop": false},
		"fall": {"row": 3, "frames": 1, "fps": 5.0, "loop": true},
	}
	t.eq(small.resolve_anim("accel"), "run", "accel falls back to run")
	t.eq(small.resolve_anim("fast_jump"), "jump_up", "fast_jump falls back to jump_up")
	t.eq(small.resolve_anim("wall"), "jump_up", "wall falls back to jump_up")
	t.eq(small.resolve_anim("land"), "idle", "land falls back to idle")
	t.eq(small.resolve_anim("near_fall"), "fall", "near_fall falls back to fall")
	t.eq(small.resolve_anim("gameover"), "fall", "gameover falls back to fall")
	t.eq(small.resolve_anim("run"), "run", "defined animations are used as they are")
	var empty: CharacterDef = CharacterDef.new()
	t.eq(empty.resolve_anim("run"), "idle", "a character without animations never crashes")
	t.eq(empty.frame_count("run"), 1, "and reports one frame")
	t.check(empty.get_texture() == null, "no sheet, no texture")


# ---------------------------------------------------------------------------
# A valid pack
# ---------------------------------------------------------------------------
func _valid_pack(t: TestContext) -> void:
	t.suite("character packs: a valid pack loads")
	var r: Dictionary = _parse(_pack())
	t.check(bool(r["ok"]), "the pack validates: %s" % String(r["error"]))
	if not bool(r["ok"]):
		return
	var def: CharacterDef = r["def"]
	t.eq(def.id, "test_hero", "id")
	t.eq(def.display_name, "Test Hero", "name")
	t.eq(def.author, "QA", "author")
	t.eq(def.tagline, "Custom character by QA", "tagline")
	t.check(def.custom, "it is marked custom")
	t.eq(def.frame_size, Vector2i(FRAME, FRAME), "frame size")
	t.eq(def.anchor, Vector2(16.0, 30.0), "anchor")
	t.near(def.sprite_scale, 0.8, 1e-9, "scale")
	t.check(def.scarf_color.is_equal_approx(Color("ff5a3c")), "first scarf colour")
	t.check(def.scarf_color2.is_equal_approx(Color("ffd23c")), "second scarf colour")
	t.check(def.get_texture() != null, "the sprite sheet is decoded")
	if def.get_texture() != null:
		t.eq(def.get_texture().get_width(), 6 * FRAME, "sheet width")
		t.eq(def.get_texture().get_height(), 4 * FRAME, "sheet height")
	t.eq(def.frame_count("run"), 6, "run has six frames")
	t.eq(def.frame_rect("run", 3), Rect2(3.0 * FRAME, 1.0 * FRAME, float(FRAME), float(FRAME)), "the run frames come from the run row")
	t.eq(def.resolve_anim("wall"), "jump_up", "missing optional animations fall back")
	t.eq(def.unlock_stat, "", "custom characters need no unlock")

	# an author is optional
	var anon: Dictionary = _parse(_pack({"author": ""}))
	t.check(bool(anon["ok"]), "the author is optional")
	if bool(anon["ok"]):
		t.eq((anon["def"] as CharacterDef).tagline, "Custom character", "and the tagline adapts")

	# optional animations can be provided
	var anims: Dictionary = _animations()
	anims["wall"] = {"row": 0, "frames": 2, "fps": 12, "loop": false}
	var full: Dictionary = _parse(_pack({"animations": anims}))
	t.check(bool(full["ok"]) and (full["def"] as CharacterDef).resolve_anim("wall") == "wall", "provided optional animations are used")


# ---------------------------------------------------------------------------
# Rejected packs
# ---------------------------------------------------------------------------
func _rejected_packs(t: TestContext) -> void:
	t.suite("character packs: invalid files are rejected")
	t.check(not bool(CharacterPack.parse("")["ok"]), "an empty file")
	t.check(not bool(CharacterPack.parse("   \n\t ")["ok"]), "a file with only whitespace")
	t.check(not bool(CharacterPack.parse("{ not json")["ok"]), "broken JSON")
	t.check(not bool(CharacterPack.parse("[1, 2, 3]")["ok"]), "JSON that is not an object")
	t.check(not bool(CharacterPack.parse("\"just a string\"")["ok"]), "a bare string")
	t.check(not bool(CharacterPack.parse("x".repeat(CharacterPack.MAX_TEXT_CHARS + 1))["ok"]), "an oversized file is refused before parsing")

	_rejects(t, _pack({"format": "something-else"}), "the wrong format id")
	_rejects(t, _pack({"format_version": 2}), "an unknown pack version")
	_rejects(t, _pack({"format_version": 0}), "a missing pack version")

	for bad_id in ["AB", "ab", "Has Space", "UPPER_CASE", "with-dash", "x".repeat(25), "", "../escape", "a.b.c", "trailing\n", "newline\nid", "caf\u00e9_x"]:
		_rejects(t, _pack({"id": bad_id}), "the invalid id '%s'" % bad_id)
	var reserved: Dictionary = _parse(_pack({"id": "pip"}), ["pip", "bolt"])
	t.check(not bool(reserved["ok"]), "an id that belongs to a built-in character")
	t.check(String(reserved["error"]).contains("pip"), "and the message names it")
	var free: Dictionary = _parse(_pack({"id": "pipette"}), ["pip", "bolt"])
	t.check(bool(free["ok"]), "similar ids are fine")

	_rejects(t, _pack({"name": ""}), "an empty name")
	_rejects(t, _pack({"name": "\u0001\u0002\u0003"}), "a name made of control characters only")

	_rejects(t, _pack({"frame_size": [32]}), "a frame size with one number")
	_rejects(t, _pack({"frame_size": "32x32"}), "a frame size that is not a list")
	_rejects(t, _pack({"frame_size": [8, 8]}), "frames smaller than the minimum")
	_rejects(t, _pack({"frame_size": [512, 32]}), "frames larger than the maximum")

	_rejects(t, _pack({"animations": "run"}), "animations that are not a dictionary")
	var missing_fall: Dictionary = _animations()
	missing_fall.erase("fall")
	_rejects(t, _pack({"animations": missing_fall}), "a missing required animation")
	var not_dict: Dictionary = _animations()
	not_dict["run"] = 5
	_rejects(t, _pack({"animations": not_dict}), "an animation that is not a dictionary")
	var neg_row: Dictionary = _animations()
	neg_row["idle"]["row"] = -1
	_rejects(t, _pack({"animations": neg_row}), "a negative row")
	var far_row: Dictionary = _animations()
	far_row["idle"]["row"] = CharacterPack.MAX_ROWS
	_rejects(t, _pack({"animations": far_row}), "a row beyond the limit")
	var zero_frames: Dictionary = _animations()
	zero_frames["idle"]["frames"] = 0
	_rejects(t, _pack({"animations": zero_frames}), "an animation without frames")
	var many_frames: Dictionary = _animations()
	many_frames["idle"]["frames"] = CharacterPack.MAX_FRAMES_PER_ANIM + 1
	_rejects(t, _pack({"animations": many_frames}), "too many frames")
	var slow: Dictionary = _animations()
	slow["idle"]["fps"] = 0.5
	_rejects(t, _pack({"animations": slow}), "an animation slower than 1 fps")
	var fast: Dictionary = _animations()
	fast["idle"]["fps"] = 500
	_rejects(t, _pack({"animations": fast}), "an unreasonably fast animation")
	var wide: Dictionary = _animations()
	wide["run"]["frames"] = 7
	_rejects(t, _pack({"animations": wide}), "frames that run past the right edge of the sheet")
	var tall: Dictionary = _animations()
	tall["fall"]["row"] = 4
	_rejects(t, _pack({"animations": tall}), "a row below the bottom edge of the sheet")

	# sprite sheets
	var no_sheet: Dictionary = _pack()
	no_sheet.erase("sheet_png_base64")
	_rejects(t, no_sheet, "a missing sprite sheet")
	_rejects(t, _pack({"sheet_png_base64": ""}), "an empty sprite sheet")
	_rejects(t, _pack({"sheet_png_base64": 12345}), "a sprite sheet that is not text")
	_rejects(t, _pack({"sheet_png_base64": Marshalls.raw_to_base64("GIF89a this is not a png image at all!!".to_utf8_buffer())}), "an image in another format")
	_rejects(t, _pack({"sheet_png_base64": Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4]))}), "a few random bytes")
	t.check(CharacterPack.is_valid_id("abc") and CharacterPack.is_valid_id("a_1") and CharacterPack.is_valid_id("x".repeat(24)), "ids of 3-24 characters a-z, 0-9 and _ are valid")
	print("  (the next check makes the engine log a PNG decode error - that is expected)")
	var truncated: PackedByteArray = _png(6 * FRAME, 4 * FRAME).slice(0, 41)
	_rejects(t, _pack({"sheet_png_base64": Marshalls.raw_to_base64(truncated)}), "a PNG cut off after its header")
	_rejects(t, _pack({"sheet_png_base64": _b64(CharacterPack.MAX_DIMENSION + 64, FRAME * 4)}), "a sheet wider than the limit")
	_rejects(t, _pack({"sheet_png_base64": _b64(6 * FRAME, CharacterPack.MAX_DIMENSION + 64)}), "a sheet taller than the limit")
	_rejects(t, _pack({"sheet_png_base64": _b64(FRAME - 8, FRAME)}), "a sheet smaller than one frame")


# ---------------------------------------------------------------------------
# Clamping and cleaning
# ---------------------------------------------------------------------------
func _sanitising(t: TestContext) -> void:
	t.suite("character packs: values are cleaned")
	var messy: Dictionary = _parse(_pack({"name": "  Hero\n\tName  ", "author": "A".repeat(80)}))
	t.check(bool(messy["ok"]), "control characters in text fields do not invalidate a pack")
	if bool(messy["ok"]):
		var def: CharacterDef = messy["def"]
		t.eq(def.display_name, "HeroName", "control characters are stripped from the name")
		t.check(def.author.length() <= 32, "the author is limited to 32 characters")
	var long_name: Dictionary = _parse(_pack({"name": "N".repeat(60)}))
	t.check(bool(long_name["ok"]) and (long_name["def"] as CharacterDef).display_name.length() == 20, "long names are cut to 20 characters")

	var scale_hi: Dictionary = _parse(_pack({"scale": 50}))
	t.check(bool(scale_hi["ok"]) and is_equal_approx((scale_hi["def"] as CharacterDef).sprite_scale, 2.0), "the scale is limited to 2.0")
	var scale_lo: Dictionary = _parse(_pack({"scale": -3}))
	t.check(bool(scale_lo["ok"]) and is_equal_approx((scale_lo["def"] as CharacterDef).sprite_scale, 0.1), "and to 0.1")

	var anchor_out: Dictionary = _parse(_pack({"anchor": [999, -5]}))
	t.check(bool(anchor_out["ok"]) and (anchor_out["def"] as CharacterDef).anchor == Vector2(float(FRAME), 0.0), "the anchor is clamped into the frame")
	var no_anchor: Dictionary = _pack()
	no_anchor.erase("anchor")
	var anchor_default: Dictionary = _parse(no_anchor)
	t.check(bool(anchor_default["ok"]) and (anchor_default["def"] as CharacterDef).anchor.is_equal_approx(Vector2(float(FRAME) * 0.5, float(FRAME) * 0.94)), "a missing anchor defaults to the bottom centre")

	var bad_colours: Dictionary = _parse(_pack({"scarf": ["not a colour", 12]}))
	t.check(bool(bad_colours["ok"]), "invalid scarf colours do not invalidate a pack")
	if bool(bad_colours["ok"]):
		var d2: CharacterDef = bad_colours["def"]
		t.check(d2.scarf_color.is_equal_approx(Color(0.13, 0.75, 0.75, 1.0)), "the first colour falls back to the default")
		t.check(d2.scarf_color2.is_equal_approx(Color(1.0, 0.85, 0.3, 1.0)), "the second colour falls back to the default")
	var long_colour: Dictionary = _parse(_pack({"scarf": ["#ff0000" + "0".repeat(200), "#00ff00"]}))
	t.check(bool(long_colour["ok"]) and (long_colour["def"] as CharacterDef).scarf_color.is_equal_approx(Color(0.13, 0.75, 0.75, 1.0)), "an absurdly long colour string is ignored")


# ---------------------------------------------------------------------------
# Untrusted fields
# ---------------------------------------------------------------------------
func _untrusted_fields(t: TestContext) -> void:
	t.suite("character packs: nothing in a pack can run code")
	var anims: Dictionary = _animations()
	anims["exec_me"] = {"row": 0, "frames": 1, "fps": 1, "loop": false}
	var hostile: Dictionary = _pack({
		"script": "res://src/autoload/save_manager.gd",
		"extends": "Node",
		"resource_path": "res://evil.tres",
		"class_name": "Hacked",
		"sheet_path": "res://assets/art/characters/pip.png",
		"unlock_stat": "games_played",
		"unlock_target": 0,
		"custom": false,
		"animations": anims,
	})
	var r: Dictionary = _parse(hostile)
	t.check(bool(r["ok"]), "unknown fields are ignored rather than trusted")
	if bool(r["ok"]):
		var def: CharacterDef = r["def"]
		t.check(def.custom, "a pack cannot claim to be a built-in character")
		t.eq(def.unlock_stat, "", "a pack cannot set unlock rules")
		t.eq(def.sheet_path, "", "a pack cannot point at files")
		t.check(not def.animations.has("exec_me"), "unknown animation names are dropped")
		t.check(def.get_script() == load("res://src/data/character_def.gd"), "the result is always a plain CharacterDef")
		t.eq(def.id, "test_hero", "identity comes only from the validated fields")
