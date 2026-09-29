"""
Loads GDScript files of the project into one Python namespace (transpiling them on demand).

Global names (class_name classes, autoload singletons, engine classes) are resolved lazily through
`NS.__missing__`, so scripts can reference each other in any order.
"""
import os
import re
import sys
import traceback

from . import engine, media
from . import runtime as rt
from .transpile import Project, TranspileError, transpile_script


class NS(dict):
    def __init__(self, loader):
        dict.__init__(self)
        self._loader = loader

    def __missing__(self, key):
        v = self._loader.resolve_global(key)
        if v is _MISSING:
            raise KeyError(key)
        self[key] = v
        return v


_MISSING = object()


class Loader:
    def __init__(self, root, dump_dir=None, permissive=False):
        self.root = os.path.abspath(root)
        rt.PROJECT_ROOT = self.root
        rt.SCRIPT_LOADER = self.load_script
        rt.RESOURCE_LOADER = self.load_resource
        self.project = Project(self.root)
        media.install(rt)
        engine.install(rt, permissive)
        rt.GLOBAL_CLASS_LIST = self.project.class_paths
        self.ns = NS(self)
        for name in dir(rt):
            if not name.startswith("__"):
                self.ns[name] = getattr(rt, name)
        self.ns["__name__"] = "gdemu_project"
        self.classes = {}       # script path -> top-level class
        self.sources = {}       # python filename -> (source, linemap)
        self.autoloads = {}
        self.dump_dir = dump_dir
        self.unresolved = {}
        self._loading = set()

    # ---- scripts
    def load_script(self, path):
        cls = self.classes.get(path)
        if cls is not None:
            return cls
        ci = self.project.script(path)
        gname = ci.py_name if ci.cname is None else ci.cname
        if path in self._loading:
            raise rt.GDError("gdemu: cyclic script loading at %s" % path)
        self._loading.add(path)
        try:
            src, lmap, unresolved = transpile_script(self.project, path)
            if unresolved:
                self.unresolved[path] = sorted(unresolved)
            fname = "<gd:%s>" % path
            self.sources[fname] = (src, lmap)
            if self.dump_dir:
                os.makedirs(self.dump_dir, exist_ok=True)
                with open(os.path.join(self.dump_dir, re.sub(r"\W", "_", path[6:]) + ".py"), "w", encoding="utf-8") as fh:
                    fh.write(src)
            code = compile(src, fname, "exec")
            before = set(self.ns.keys())
            exec(code, self.ns)
            created = [k for k in self.ns.keys() if k not in before]
            cls = self.ns[gname]
            self.classes[path] = cls
            # static initialisation: inner classes first, then the script class itself
            inner = [self.ns[k] for k in created if isinstance(self.ns.get(k), type) and k != gname and self.ns[k].__dict__.get("_gd_path") == path]
            for c in inner + [cls]:
                c._gd_static_init()
        finally:
            self._loading.discard(path)
        return cls

    def load_resource(self, path):
        real = self.project.real_path(path)
        if not os.path.isfile(real):
            return None
        if path.endswith(".tres"):
            return self._load_tres(real)
        return media.load_media(real)

    def _load_tres(self, real):
        ext = {}
        props = {}
        in_res = False
        with open(real, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                m = re.match(r'\[ext_resource .*path="([^"]+)" .*id="([^"]+)"', line)
                if m:
                    ext[m.group(2)] = m.group(1)
                    continue
                if line == "[resource]":
                    in_res = True
                    continue
                if in_res and "=" in line:
                    k, v = line.split("=", 1)
                    props[k.strip()] = v.strip()
        script_ref = props.pop("script", None)
        if script_ref is None:
            return None
        sid = re.search(r'"([^"]+)"', script_ref).group(1)
        cls = self.load_script(ext[sid])
        obj = cls()
        for k, v in props.items():
            val = rt.ProjectSettings._parse(v)
            rt._setattr(obj, rt._mangle(k), val)
        return obj

    # ---- globals
    def resolve_global(self, name):
        p = self.project
        path = p.class_paths.get(name)
        if path is not None:
            self.load_script(path)
            return self.ns[name]
        path = p.pyname_paths.get(name)
        if path is not None:
            self.load_script(path)
            return self.ns[name]
        if name in p.autoloads:
            cls = self.load_script(p.autoloads[name])
            inst = cls()
            self.autoloads[name] = inst
            return inst
        found = engine.lookup(name)
        if found is not None:
            return found
        return _MISSING

    def instantiate(self, path, *args):
        return self.load_script(path)(*args)

    # ---- autoload boot (mirrors Main::start: construct all, then add to the tree in project order)
    DEFAULT_REAL = ("Events", "SaveManager", "SettingsManager", "StatisticsManager", "LeaderboardManager",
                    "CharacterManager", "ReplayManager", "GameManager")

    def boot(self, real=None):
        """Creates the autoload singletons. `real` names come from their scripts (their _ready() runs in
        project order); every other autoload is a recording stub. real="all" boots everything."""
        names = list(self.project.autoloads)
        if real == "all":
            real = names
        real = set(real if real is not None else self.DEFAULT_REAL)
        for name in names:
            if name in real:
                inst = self.load_script(self.project.autoloads[name])()
                inst.name = name
            else:
                inst = rt.AutoStub(name)
            self.ns[name] = inst
            self.autoloads[name] = inst
        for name in names:
            if name in real:
                rt.TREE.root.add_child(self.autoloads[name])      # runs _enter_tree / _ready
        rt.run_deferred()
        return self.autoloads

    # ---- diagnostics
    def format_exception(self, exc):
        """Traceback with GDScript file:line for frames that come from transpiled code."""
        out = []
        tb = exc.__traceback__
        frames = traceback.extract_tb(tb)
        for fr in frames:
            entry = self.sources.get(fr.filename)
            if entry is not None:
                src, lmap = entry
                gd_line = lmap[fr.lineno - 1] if 0 < fr.lineno <= len(lmap) else 0
                path = fr.filename[4:-1]
                line = src.splitlines()[fr.lineno - 1].strip() if fr.lineno <= len(src.splitlines()) else ""
                out.append("  at %s:%d (%s)   py: %s" % (path, gd_line, fr.name, line[:160]))
            elif "gdemu" in fr.filename and fr.filename.endswith("runtime.py"):
                out.append("  in runtime %s (%s)" % (fr.name, fr.lineno))
        return "%s: %s\n%s" % (type(exc).__name__, exc, "\n".join(out[-14:]))
