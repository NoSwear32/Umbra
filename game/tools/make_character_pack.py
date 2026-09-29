#!/usr/bin/env python3
"""
Builds a Spire Sprint custom character pack (.spirechar) from a PNG sprite sheet.

    python3 tools/make_character_pack.py SHEET.png --id my_fox --name "My Fox" [--author "You"]

Sheet layout (same as the built-in characters): frames of --frame WxH pixels, ONE ROW per animation,
ONE COLUMN per frame. The character faces RIGHT (the game mirrors it for leftward movement) and its
feet touch y = anchor_y of every frame (default 120 of 128). Required animations: idle, run, jump_up,
fall. Optional ones fall back to those (accel -> run, fast_jump -> jump_up, wall -> jump_up,
land -> idle, near_fall -> fall, gameover -> fall). The default row order is:

    0 idle (4 frames)   1 run (6)   2 accel (2)   3 jump_up (2)   4 fall (2)
    5 fast_jump (2)     6 wall (2)  7 land (2)    8 near_fall (2) 9 gameover (2)

Use --rows to list only the rows your sheet really has. The pack is checked against the same limits the
game enforces (see src/data/character_pack.gd), so a pack that builds here will import there.
Pack files can never run code: they contain only JSON numbers, short strings and one PNG.
"""
import argparse
import base64
import json
import os
import re
import struct
import sys

FORMAT_ID = "spire-sprint-character"
FORMAT_VERSION = 1
MAX_DIMENSION = 1536
MAX_PNG_BYTES = 1500000
MIN_FRAME, MAX_FRAME = 16, 256
MAX_ROWS = 24
ID_RE = re.compile(r"^[a-z0-9_]{3,24}\Z")

# name: (row, frames, fps, loop)
STANDARD = {
    "idle": (0, 4, 5, True),
    "run": (1, 6, 14, True),
    "accel": (2, 2, 8, True),
    "jump_up": (3, 2, 10, False),
    "fall": (4, 2, 8, True),
    "fast_jump": (5, 2, 12, True),
    "wall": (6, 2, 12, False),
    "land": (7, 2, 14, False),
    "near_fall": (8, 2, 10, True),
    "gameover": (9, 2, 6, True),
}
REQUIRED = ("idle", "run", "jump_up", "fall")


def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise SystemExit("error: the sheet is not a PNG file")
    return struct.unpack(">II", data[16:24])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet", help="PNG sprite sheet")
    ap.add_argument("--id", required=True, help="3-24 characters a-z 0-9 _ (must differ from built-in ids)")
    ap.add_argument("--name", required=True, help="display name (max 20 characters)")
    ap.add_argument("--author", default="", help="optional author (max 32 characters)")
    ap.add_argument("--frame", nargs=2, type=int, default=[128, 128], metavar=("W", "H"))
    ap.add_argument("--anchor", nargs=2, type=float, default=None, metavar=("X", "Y"),
                    help="position of the feet inside a frame (default: W/2, H*0.94)")
    ap.add_argument("--scale", type=float, default=0.72, help="sprite scale in the game (default 0.72)")
    ap.add_argument("--scarf", nargs=2, default=["#21c4c4", "#ffd54a"], metavar=("C1", "C2"))
    ap.add_argument("--rows", nargs="*", default=None, help="animation names present, in row order (default: all ten)")
    ap.add_argument("--out", default=None, help="output file (default: ID.spirechar next to the sheet)")
    a = ap.parse_args()

    if not ID_RE.match(a.id):
        raise SystemExit("error: --id must be 3-24 characters of a-z, 0-9 and _")
    if not a.name.strip() or len(a.name) > 20:
        raise SystemExit("error: --name must be 1-20 characters")
    fw, fh = a.frame
    if not (MIN_FRAME <= fw <= MAX_FRAME and MIN_FRAME <= fh <= MAX_FRAME):
        raise SystemExit("error: frame size must be %d-%d pixels" % (MIN_FRAME, MAX_FRAME))
    data = open(a.sheet, "rb").read()
    if len(data) > MAX_PNG_BYTES:
        raise SystemExit("error: the PNG is larger than %d bytes" % MAX_PNG_BYTES)
    w, h = png_size(data)
    if w > MAX_DIMENSION or h > MAX_DIMENSION or w < fw or h < fh:
        raise SystemExit("error: sheet is %dx%d, must be between one frame and %d px" % (w, h, MAX_DIMENSION))

    names = a.rows if a.rows else list(STANDARD.keys())
    animations = {}
    for row, name in enumerate(names):
        if name not in STANDARD:
            raise SystemExit("error: unknown animation '%s' (known: %s)" % (name, ", ".join(STANDARD)))
        _, frames, fps, loop = STANDARD[name]
        if a.rows is None:
            row = STANDARD[name][0]
        if row >= MAX_ROWS or (row + 1) * fh > h or frames * fw > w:
            raise SystemExit("error: animation '%s' (row %d, %d frames) does not fit into the %dx%d sheet" % (name, row, frames, w, h))
        animations[name] = {"row": row, "frames": frames, "fps": fps, "loop": loop}
    for req in REQUIRED:
        if req not in animations:
            raise SystemExit("error: required animation '%s' is missing" % req)

    pack = {
        "format": FORMAT_ID,
        "format_version": FORMAT_VERSION,
        "id": a.id,
        "name": a.name.strip(),
        "author": a.author.strip()[:32],
        "frame_size": [fw, fh],
        "anchor": list(a.anchor) if a.anchor else [fw / 2.0, fh * 0.94],
        "scale": a.scale,
        "scarf": list(a.scarf),
        "animations": animations,
        "sheet_png_base64": base64.b64encode(data).decode("ascii"),
    }
    out = a.out or os.path.join(os.path.dirname(os.path.abspath(a.sheet)), a.id + ".spirechar")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(pack, f, separators=(",", ":"))
    print("wrote %s (%d bytes, %d animations, sheet %dx%d)" % (out, os.path.getsize(out), len(animations), w, h))
    return 0


if __name__ == "__main__":
    sys.exit(main())
