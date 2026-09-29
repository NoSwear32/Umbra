#!/usr/bin/env python3
"""
Generates all bitmap art of Spire Sprint from code (no stock images, nothing traced or borrowed):

    python3 tools/gen_art.py                 # everything
    python3 tools/gen_art.py themes          # only the 11 tower themes
    python3 tools/gen_art.py characters      # only the seven character sheets
    python3 tools/gen_art.py ui              # logo, project icon, launcher icons
    python3 tools/gen_art.py --preview DIR   # additionally write contact sheets for review

Requires: python3, numpy, Pillow.  Output goes to assets/art/... and icon.svg.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = os.path.abspath(os.path.join(HERE, ".."))
ART = os.path.join(ROOT, "assets", "art")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", nargs="*", default=["themes", "characters", "ui"], help="themes / characters / ui")
    ap.add_argument("--preview", metavar="DIR", help="write contact sheets for visual review")
    ap.add_argument("--only", type=int, action="append", help="theme index(es) to render (themes only)")
    ap.add_argument("--char", action="append", help="character id(s) to render (characters only)")
    args = ap.parse_args()
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)

    if "themes" in args.what:
        from art import themes, preview
        os.makedirs(os.path.join(ART, "themes"), exist_ok=True)
        pals = themes.load_palettes(os.path.join(ROOT, "src", "autoload", "theme_manager.gd"))
        assert len(pals) == 11, "expected 11 theme rows in theme_manager.gd, found %d" % len(pals)
        for i, pal in enumerate(pals):
            if args.only and i not in args.only:
                continue
            imgs = themes.render_theme(i, pal, os.path.join(ART, "themes"))
            print("theme %02d %-16s done" % (i, pal.name))
            if args.preview:
                shot = preview.compose_theme(pal, *imgs)
                shot.save(os.path.join(args.preview, "theme_%02d.png" % i))
    if "characters" in args.what:
        from art import characters
        os.makedirs(os.path.join(ART, "characters"), exist_ok=True)
        characters.render_all(os.path.join(ART, "characters"), args.preview, args.char)
    if "ui" in args.what:
        from art import ui_art
        ui_art.render_all(ROOT, args.preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
