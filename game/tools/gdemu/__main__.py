"""
gdemu command line.

    python3 -m tools.gdemu test [suite ...]     run test suites (default: all engine-independent ones)
    python3 -m tools.gdemu dump res://src/x.gd  print the Python generated for one script
    python3 -m tools.gdemu check                transpile + load every script under src/ and report gaps
    python3 -m tools.gdemu smoke [--actions N] [--seed S]   boot the whole app on engine stubs and press buttons

Run from the project directory (the folder that contains project.godot).
gdemu executes the project's GDScript logic under CPython with an emulated runtime. It is NOT the
Godot engine: it is evidence about the logic, not about engine behaviour. See tools/gdemu/README.md.
"""
import os
import re
import sys
import time

from .loader import Loader
from .transpile import TranspileError, transpile_script
from . import runtime as rt

# Suites that need engine features gdemu does not emulate (none at the moment).
ENGINE_SUITES = set()


def suite_list(root):
    text = open(os.path.join(root, "tests", "run_tests.gd"), encoding="utf-8").read()
    return re.findall(r'"(res://tests/[a-z_]+\.gd)"', text)


def cmd_dump(loader, args):
    for path in args:
        src, _lmap, unresolved = transpile_script(loader.project, path)
        print(src)
        if unresolved:
            print("# unresolved names:", sorted(unresolved))
    return 0


def cmd_check(loader, args):
    bad = 0
    root = loader.root
    paths = []
    for base in ("src",):
        for dp, _dn, fn in os.walk(os.path.join(root, base)):
            for f in sorted(fn):
                if f.endswith(".gd"):
                    paths.append("res://" + os.path.relpath(os.path.join(dp, f), root).replace(os.sep, "/"))
    for p in sorted(paths):
        try:
            _src, _lm, unresolved = transpile_script(loader.project, p)
            status = "ok" if not unresolved else "unresolved: " + ", ".join(sorted(unresolved))
        except TranspileError as e:
            status = "TRANSPILE ERROR " + str(e)
            bad += 1
        print("%-60s %s" % (p, status))
    return 1 if bad else 0


def cmd_test(loader, args):
    suites = suite_list(loader.root)
    if args:
        wanted = [a if a.startswith("res://") else "res://tests/test_%s.gd" % a.replace("test_", "").replace(".gd", "") for a in args]
        suites = [s for s in suites if s in wanted]
    else:
        skipped = [s for s in suites if s in ENGINE_SUITES]
        suites = [s for s in suites if s not in ENGINE_SUITES]
        if skipped:
            print("(skipping engine-only suites: %s)" % ", ".join(os.path.basename(s) for s in skipped))
    loader.boot()          # the autoload singletons, as the engine creates them at start-up
    ctx = loader.instantiate("res://tests/test_context.gd")
    sim_const = loader.load_script("res://src/core/sim_constants.gd")
    print("Spire Sprint tests (gdemu) - simulation version %d" % sim_const.SIM_VERSION)
    crashed = 0
    for path in suites:
        t0 = time.time()
        before = (ctx.passed, ctx.failed)
        try:
            suite = loader.instantiate(path)
            suite.run(ctx)
        except Exception as e:                       # noqa: BLE001 - report and keep going
            crashed += 1
            print("CRASH in %s:\n%s" % (path, loader.format_exception(e)))
            if os.environ.get("GDEMU_TRACE"):
                raise
        print("  -> %s: %d passed, %d failed  (%.1fs)" % (os.path.basename(path), ctx.passed - before[0], ctx.failed - before[1], time.time() - t0))
    print("")
    print("passed: %d   failed: %d   crashed suites: %d" % (ctx.passed, ctx.failed, crashed))
    if loader.unresolved:
        print("names the transpiler could not resolve:", {k: v for k, v in loader.unresolved.items()})
    return 1 if (ctx.failed or crashed) else 0


def cmd_smoke(loader, args):
    from . import smoke
    actions, seed = 400, 1
    detail = None
    lines = "--lines" in args
    it = iter(args)
    for a in it:
        if a in ("--coverage", "--lines", "--seeded"):
            continue
        if a == "--detail":
            detail = next(it)
            continue
        if a == "--actions":
            actions = int(next(it))
        elif a == "--seed":
            seed = int(next(it))
    cov = smoke.LineCoverage(loader) if lines or detail else None
    m = smoke.run(loader, actions, seed, coverage=cov, seeded="--seeded" in args)
    print("actions: %d   frames: %d   screens visited: %s" % (m.actions, rt.TREE.frames, ", ".join(sorted(m.screens_seen)) or "-"))
    if "--coverage" in args:
        print("controls pressed (%d distinct):" % len(m.pressed))
        for k, v in m.pressed.most_common():
            print("   %4d  %s" % (v, k))
        print("game states seen:", dict(m.modes))
    if cov is not None:
        print(cov.report(40, detail))
    print("unique errors: %d" % len(m.errors))
    for sig, (count, trace, label) in m.errors.items():
        print("\n[%dx] first seen during: %s\n%s" % (count, label, trace))
    return 1 if m.errors else 0


def main(argv):
    if len(argv) < 2 or argv[1] not in ("test", "dump", "check", "smoke"):
        print(__doc__)
        return 2
    root = os.getcwd()
    if not os.path.isfile(os.path.join(root, "project.godot")):
        print("run this from the folder that contains project.godot")
        return 2
    os.environ.setdefault("GDEMU_TMP", os.path.join(root, ".gdemu_tmp"))
    loader = Loader(root, dump_dir=os.environ.get("GDEMU_DUMP"), permissive=(argv[1] == "smoke"))
    return {"test": cmd_test, "dump": cmd_dump, "check": cmd_check, "smoke": cmd_smoke}[argv[1]](loader, argv[2:])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
