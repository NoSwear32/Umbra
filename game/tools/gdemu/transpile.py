"""
GDScript -> Python transpiler for the gdemu harness.

It handles the GDScript subset the engine-independent scripts of this project use (classes, inner
classes, typed members, signals, enums, constants, statics, if/while/for/match, calls, operators,
casts, type tests). Every construct it does not know raises TranspileError with the script line, so
gaps are loud.

The generated Python relies on `runtime.py` for GDScript's numeric semantics (integer division, `%`,
implicit int -> float conversion of typed float variables) and for the engine types.
"""
import builtins
import keyword
import os
import re

from gdtoolkit.parser import parser as gdparser
from lark import Token, Tree

from . import runtime as rt
from .gd_utils import UTILITY_FUNCTIONS


class TranspileError(Exception):
    pass


PY_RESERVED = set(keyword.kwlist) | set(dir(builtins)) | {"self", "cls"}
DEFAULTS = {
    "int": "0", "float": "0.0", "bool": "False", "String": "''", "StringName": "''",
    "Array": "Array()", "Dictionary": "Dictionary()", "Vector2": "Vector2()", "Vector2i": "Vector2i()",
    "Vector3": "Vector3()", "Color": "Color()", "Rect2": "Rect2()", "Callable": "Callable()",
    "PackedStringArray": "PackedStringArray()", "PackedByteArray": "PackedByteArray()",
    "PackedInt32Array": "PackedInt32Array()", "PackedInt64Array": "PackedInt64Array()",
    "PackedFloat32Array": "PackedFloat32Array()", "PackedFloat64Array": "PackedFloat64Array()",
}
SCALAR_TYPES = {"int", "float", "bool", "String", "StringName", "Variant"}
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
EXTRA_FUNCS = {"load": "load_", "preload": "preload_", "is_instance_valid": "is_instance_valid"}


def mangle_attr(name):
    """Member / method names that are Python keywords."""
    return name + "_" if keyword.iskeyword(name) else name


def mangle_local(name):
    if name in PY_RESERVED or hasattr(rt, name) or name.startswith("__"):
        return name + "_l"
    return name


def norm(name):
    return name[7:] if name.startswith("asless_") else name


def unescape(s):
    out = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch != "\\" or i + 1 >= len(s):
            out.append(ch)
            i += 1
            continue
        nxt = s[i + 1]
        if nxt == "u":
            out.append(chr(int(s[i + 2:i + 6], 16)))
            i += 6
        elif nxt == "U":
            out.append(chr(int(s[i + 2:i + 8], 16)))
            i += 8
        elif nxt in ESCAPES:
            out.append(ESCAPES[nxt])
            i += 2
        else:
            out.append(nxt)
            i += 2
    return "".join(out)


def string_value(tok):
    s = str(tok)
    raw = False
    if s[:1] in "rR" and s[1:2] in "\"'":
        raw = True
        s = s[1:]
    body = s[3:-3] if s[:3] in ('"""', "'''") else s[1:-1]
    return body if raw else unescape(body)


def number_value(tok):
    s = str(tok).replace("_", "")
    low = s.lower()
    if low.startswith(("0x", "-0x", "+0x")):
        return int(s, 16)
    if low.startswith(("0b", "-0b", "+0b")):
        return int(s, 2)
    if re.search(r"[.eE]", s):
        return float(s)
    return int(s)


def literal(v):
    if isinstance(v, float):
        if v != v:
            return "NAN"
        if v in (float("inf"), float("-inf")):
            return "INF" if v > 0 else "(-INF)"
        return "(%r)" % v if v < 0 else repr(v)
    if isinstance(v, int):
        return "(%d)" % v if v < 0 else str(v)
    return repr(v)


def line_of(n):
    if isinstance(n, Token):
        return getattr(n, "line", 0) or 0
    meta = getattr(n, "meta", None)
    return getattr(meta, "line", 0) if meta is not None and not getattr(meta, "empty", True) else 0


# ---------------------------------------------------------------------------------------- model
class Member:
    __slots__ = ("kind", "name", "type", "owner", "infer", "value_node", "params")

    def __init__(self, kind, name, type_=None, owner=None, infer=False, value_node=None, params=None):
        self.kind, self.name, self.type, self.owner = kind, name, type_, owner
        self.infer, self.value_node, self.params = infer, value_node, params


class ClassInfo:
    def __init__(self, path, lname, outer, py_name):
        self.path = path
        self.lname = lname            # local name (inner class name / script class_name)
        self.cname = None             # declared global class_name
        self.outer = outer
        self.py_name = py_name
        self.extends = None           # ("name", "Foo") | ("path", "res://...") | None
        self.members = {}
        self.inners = {}
        self.exports = []
        self.body = []                # class-level statement nodes in order
        self.order = []               # names of members with initialisers, in declaration order

    @property
    def is_inner(self):
        return self.outer is not None


class Local:
    __slots__ = ("py", "type", "kind")

    def __init__(self, py, type_, kind):
        self.py, self.type, self.kind = py, type_, kind     # kind: "typed" | "infer" | "dyn"


class FuncCtx:
    def __init__(self, cls, static, ret_type, parent=None):
        self.cls = cls
        self.static = static
        self.ret = ret_type
        self.scopes = [{}]
        self.tmp = 0
        self.in_member_init = False
        self.parent = parent            # enclosing function context (lambdas)
        self.captured = {}              # outer locals a lambda uses: gd name -> Local
        self.cur_ind = None             # indentation of the statement being generated

    def push(self):
        self.scopes.append({})

    def pop(self):
        self.scopes.pop()

    def declare(self, name, type_, kind):
        py = mangle_local(name)
        self.scopes[-1][name] = Local(py, type_, kind)
        return py

    def lookup(self, name):
        for sc in reversed(self.scopes):
            if name in sc:
                return sc[name]
        if self.parent is not None:
            loc = self.parent.lookup(name)
            if loc is not None:
                self.captured[name] = loc
            return loc
        return None

    def new_tmp(self):
        root = self
        while root.parent is not None:
            root = root.parent
        root.tmp += 1
        return "_t%d" % root.tmp


class Project:
    """Knows every script of the project: class names, autoloads, members. Parses lazily."""

    def __init__(self, root):
        self.root = root
        self.class_paths = {}
        self.pyname_paths = {}
        self.autoloads = {}
        self.scripts = {}           # path -> ClassInfo (top level)
        self._scan()

    def _scan(self):
        pat = re.compile(r"^\s*class_name\s+(\w+)", re.M)
        for base in ("src", "tests", "tools"):
            for dp, dn, fn in os.walk(os.path.join(self.root, base)):
                for f in fn:
                    if f.endswith(".gd"):
                        p = os.path.join(dp, f)
                        res = "res://" + os.path.relpath(p, self.root).replace(os.sep, "/")
                        self.pyname_paths["S_" + re.sub(r"\W", "_", res[6:-3])] = res
                        with open(p, encoding="utf-8") as fh:
                            m = pat.search(fh.read())
                        if m:
                            self.class_paths[m.group(1)] = res
        try:
            sec = ""
            with open(os.path.join(self.root, "project.godot"), encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if line.startswith("["):
                        sec = line.strip("[]")
                    elif sec == "autoload" and "=" in line:
                        k, v = line.split("=", 1)
                        self.autoloads[k.strip()] = v.strip().strip('"').lstrip("*")
        except OSError:
            pass

    def real_path(self, res):
        return os.path.join(self.root, res[6:]) if res.startswith("res://") else res

    def script(self, res_path):
        ci = self.scripts.get(res_path)
        if ci is None:
            with open(self.real_path(res_path), encoding="utf-8") as fh:
                code = fh.read()
            try:
                tree = gdparser.parse(code, gather_metadata=True)
            except Exception as e:                      # lark errors carry the position
                raise TranspileError("%s: parse error: %s" % (res_path, e))
            ci = ClassInfo(res_path, None, None, "S_" + re.sub(r"\W", "_", res_path[6:-3]))
            ci.tree = tree
            self.scripts[res_path] = ci
            self._collect(ci, tree.children)
        return ci

    def by_class_name(self, name):
        p = self.class_paths.get(name)
        return self.script(p) if p else None

    # ---- member collection
    def _collect(self, ci, nodes):
        pending = []
        for n in nodes:
            if isinstance(n, Token):
                continue
            d = n.data
            if d == "annotation":
                pending.append(str(n.children[0]))
                continue
            if d == "classname_stmt":
                ci.cname = str(n.children[0])
            elif d == "classname_extends_stmt":
                ci.cname = str(n.children[0])
                self._set_extends(ci, n.children[1:])
            elif d == "extends_stmt":
                self._set_extends(ci, n.children)
            elif d == "signal_stmt":
                ci.members[str(n.children[0])] = Member("signal", str(n.children[0]), None, ci)
            elif d == "enum_stmt":
                self._enum(ci, n.children[0])
            elif d == "const_stmt":
                self._const(ci, n.children[0])
            elif d == "static_class_var_stmt":
                self._var(ci, n.children[0].children[0], True, pending)
            elif d == "class_var_stmt":
                self._var(ci, n.children[0], False, pending)
            elif d == "func_def":
                self._func(ci, n, False)
            elif d == "static_func_def":
                self._func(ci, n.children[0], True)
            elif d == "class_def":
                self._inner(ci, n)
            pending = [] if d != "annotation" else pending
            ci.body.append(n)

    def _set_extends(self, ci, parts):
        first = parts[0]
        if isinstance(first, Tree) and first.data == "string":
            ci.extends = ("path", string_value(first.children[0]))
        else:
            ci.extends = ("name", ".".join(str(p) for p in parts if isinstance(p, Token) and p.type == "NAME"))

    def _enum(self, ci, e):
        if e.data == "enum_named":
            name = str(e.children[0])
            body = e.children[1]
            ci.members[name] = Member("enum", name, "Dictionary", ci)
        else:
            body = e.children[0]
        for el in body.children:
            if isinstance(el, Tree) and el.data == "enum_element":
                ci.members[str(el.children[0])] = Member("enum_value", str(el.children[0]), "int", ci)
        ci.order.append(("enum", e))

    def _const(self, ci, c):
        name = str(c.children[0])
        typ = None
        val = c.children[-1]
        if c.data == "const_typed_assigned":
            typ = str(c.children[1])
        elif isinstance(val, Tree) and val.data == "expr":
            typ = None
        ci.members[name] = Member("const", name, typ, ci, c.data == "const_inf", val)
        ci.order.append(("const", c))

    def _var(self, ci, v, static, annotations):
        name = str(v.children[0])
        typ = None
        infer = False
        if v.data in ("class_var_typed", "class_var_typed_assgnd"):
            typ = str(v.children[1])
        elif v.data == "class_var_inf":
            infer = True
        ci.members[name] = Member("static_var" if static else "var", name, typ, ci, infer,
                                  v.children[-1] if v.data in ("class_var_assigned", "class_var_inf", "class_var_typed_assgnd") else None)
        if any(a.startswith("export") for a in annotations):
            ci.exports.append(name)
        ci.order.append(("static_var" if static else "var", v))

    def _func(self, ci, f, static):
        header = f.children[0]
        name = str(header.children[0])
        ret = None
        for c in header.children[1:]:
            if isinstance(c, Token) and c.type == "TYPE_HINT":
                ret = str(c)
        ci.members[name] = Member("static_func" if static else "func", name, ret, ci, False, f)

    def _inner(self, ci, n):
        name = str(n.children[0])
        inner = ClassInfo(ci.path, name, ci, "%s__%s" % (ci.py_name, name))
        inner.tree = n
        ci.inners[name] = inner
        ci.members[name] = Member("inner", name, None, ci)
        self._collect(inner, n.children[1:])

    # ---- lookups
    def parent_of(self, ci):
        """(ClassInfo | None, builtin_name | None)."""
        if ci.extends is None:
            return None, "RefCounted"
        kind, val = ci.extends
        if kind == "path":
            return self.script(val), None
        # extends an inner class of an outer script / a project class / a builtin
        o = ci.outer
        while o is not None:
            if val in o.inners:
                return o.inners[val], None
            o = o.outer
        other = self.by_class_name(val.split(".")[0])
        if other is not None:
            if "." in val:
                cur = other
                for part in val.split(".")[1:]:
                    cur = cur.inners[part]
                return cur, None
            return other, None
        return None, val

    def builtin_root(self, ci):
        """Name of the engine class at the root of a script's inheritance chain."""
        cur = ci
        for _ in range(50):
            nxt, builtin = self.parent_of(cur)
            if nxt is None:
                return builtin
            cur = nxt
        return None

    def resolve_member(self, ci, name):
        seen = 0
        cur = ci
        while cur is not None and seen < 50:
            m = cur.members.get(name)
            if m is not None:
                return m
            cur, _b = self.parent_of(cur)
            seen += 1
        return None

    def resolve_type(self, tname, ci):
        """Type name -> ClassInfo or None (builtins, enums and unknown names give None)."""
        if not tname or "[" in tname:
            return None
        parts = tname.split(".")
        cur = None
        o = ci
        while o is not None and cur is None:
            if parts[0] in o.inners:
                cur = o.inners[parts[0]]
            elif o.lname == parts[0] and o.is_inner:
                cur = o
            o = o.outer
        if cur is None:
            # inner classes inherited from parents
            p, _b = self.parent_of(ci)
            depth = 0
            while p is not None and cur is None and depth < 20:
                if parts[0] in p.inners:
                    cur = p.inners[parts[0]]
                p, _b = self.parent_of(p)
                depth += 1
        if cur is None:
            cur = self.by_class_name(parts[0])
        if cur is None:
            return None
        for part in parts[1:]:
            nxt = cur.inners.get(part)
            if nxt is None:
                return None
            cur = nxt
        return cur

    def top(self, ci):
        while ci.outer is not None:
            ci = ci.outer
        return ci


# ------------------------------------------------------------------------------------ generator
class Gen:
    def __init__(self, project):
        self.p = project
        self.lines = []          # (indent, text, gd_line)
        self.unresolved = set()

    # ---- output helpers
    def emit(self, ind, text, node=None, gd_line=None):
        self.lines.append((ind, text, gd_line if gd_line is not None else (line_of(node) if node is not None else 0)))

    def error(self, msg, node):
        raise TranspileError("line %d: %s" % (line_of(node), msg))

    # ---- class generation
    def gen_top(self, ci):
        """All classes of a script (inner classes first), returns (source, linemap)."""
        order = []
        self._inner_order(ci, order)
        for c in order:
            self.gen_class(c)
        return self.finish()

    def _inner_order(self, ci, out):
        done = set()
        pending = list(ci.inners.values())
        guard = 0
        while pending and guard < 100:
            guard += 1
            nxt = []
            for c in pending:
                p, _b = self.p.parent_of(c)
                if p is not None and p.outer is ci and p.py_name not in done and p is not c:
                    nxt.append(c)
                    continue
                self._inner_order(c, out)
                out.append(c)
                done.add(c.py_name)
            pending = nxt
        for c in pending:
            self._inner_order(c, out)
            out.append(c)
        if not ci.is_inner:
            out.append(ci)

    def finish(self):
        src = []
        lmap = []
        for ind, text, gl in self.lines:
            src.append("    " * ind + text)
            lmap.append(gl)
        return "\n".join(src) + "\n", lmap

    def base_expr(self, ci):
        p, builtin = self.p.parent_of(ci)
        if p is not None:
            return p.py_name if p.is_inner or p.cname is None else p.cname
        return builtin

    def global_name(self, ci):
        """The Python global a script class is reachable through."""
        return ci.py_name if (ci.is_inner or ci.cname is None) else ci.cname

    def gen_class(self, ci):
        name = self.global_name(ci)
        base = self.base_expr(ci)
        ind = 0
        self.emit(ind, "class %s(%s):" % (name, base))
        ind += 1
        self.emit(ind, "_gd_path = %r" % ci.path)
        self.emit(ind, "_gd_name = %r" % (ci.cname or ci.lname or ""))
        floats = sorted(m.name for m in ci.members.values() if m.kind in ("var",) and (m.type == "float" or (m.infer and self._infer_float(ci, m))))
        self.emit(ind, "_gd_floats = frozenset(%r)" % (floats,))
        self.emit(ind, "_gd_infer = frozenset(%r)" % (sorted(m.name for m in ci.members.values() if m.kind == "var" and m.infer),))
        self.emit(ind, "_gd_exports = %r" % (tuple(ci.exports),))
        allvars = [m.name for m in ci.members.values() if m.kind == "var"]
        self.emit(ind, "_gd_vars = %r" % (tuple(allvars),))
        sigs = [m.name for m in ci.members.values() if m.kind == "signal"]
        self.emit(ind, "_gd_signals = %r" % (tuple(sigs),))
        # member initialiser
        ctx = FuncCtx(ci, False, None)
        ctx.in_member_init = True
        self.emit(ind, "def _gd_members(self):")
        n0 = len(self.lines)
        for s in sigs:
            self.emit(ind + 1, "self.%s = Signal(self, %r)" % (mangle_attr(s), s))
        for kind, node in ci.order:
            if kind == "var":
                self._member_var(ci, node, ctx, ind + 1)
        if len(self.lines) == n0:
            self.emit(ind + 1, "pass")
        # methods
        for kind, node in [(("static" if isinstance(n, Tree) and n.data == "static_func_def" else "inst"), n) for n in ci.body
                           if isinstance(n, Tree) and n.data in ("func_def", "static_func_def")]:
            fdef = node.children[0] if node.data == "static_func_def" else node
            self.gen_func(ci, fdef, kind == "static", ind)
        # static initialiser: constants, enums, static vars
        self.emit(ind, "@classmethod")
        self.emit(ind, "def _gd_static_init(cls):")
        n0 = len(self.lines)
        sctx = FuncCtx(ci, True, None)
        for kind, node in ci.order:
            if kind == "const":
                self._member_const(ci, node, sctx, ind + 1)
            elif kind == "enum":
                self._member_enum(ci, node, sctx, ind + 1)
            elif kind == "static_var":
                self._member_static(ci, node, sctx, ind + 1)
        if len(self.lines) == n0:
            self.emit(ind + 1, "pass")
        self.emit(0, "")

    def _infer_float(self, ci, m):
        try:
            ctx = FuncCtx(ci, False, None)
            return self.stype(m.value_node, ctx) == "float"
        except TranspileError:
            return False

    def _member_var(self, ci, v, ctx, ind):
        name = str(v.children[0])
        attr = mangle_attr(name)
        d = v.data
        if d == "class_var_empty":
            self.emit(ind, "self.%s = None" % attr, v)
        elif d == "class_var_typed":
            self.emit(ind, "self.%s = %s" % (attr, DEFAULTS.get(str(v.children[1]).split("[")[0], "None") if "[" not in str(v.children[1]) else DEFAULTS.get(str(v.children[1]).split("[")[0], "None")), v)
        else:
            typ = str(v.children[1]) if d == "class_var_typed_assgnd" else None
            val = self.ex(v.children[-1], ctx)
            if typ == "float":
                val = "_f(%s)" % val
            self.emit(ind, "self.%s = %s" % (attr, val), v)

    def _member_const(self, ci, c, ctx, ind):
        name = str(c.children[0])
        val = self.ex(c.children[-1], ctx)
        if c.data == "const_typed_assigned" and str(c.children[1]) == "float":
            val = "_f(%s)" % val
        self.emit(ind, "cls.%s = %s" % (mangle_attr(name), val), c)

    def _member_enum(self, ci, e, ctx, ind):
        if e.data == "enum_named":
            ename = str(e.children[0])
            body = e.children[1]
        else:
            ename = None
            body = e.children[0]
        pairs = []
        nextv = "0"
        cur = -1
        for el in body.children:
            if not (isinstance(el, Tree) and el.data == "enum_element"):
                continue
            n = str(el.children[0])
            if len(el.children) > 1:
                v = self.ex(el.children[1], ctx)
                self.emit(ind, "_ev = %s" % v, el)
            else:
                self.emit(ind, "_ev = (_ev + 1) if '_ev' in dir() else 0", el) if False else None
                self.emit(ind, "_ev = %s" % ("0" if not pairs else "_ev + 1"), el)
            self.emit(ind, "cls.%s = _ev" % mangle_attr(n), el)
            pairs.append(n)
        if ename is not None:
            items = ", ".join("%r: cls.%s" % (n, mangle_attr(n)) for n in pairs)
            self.emit(ind, "cls.%s = _Enum({%s})" % (mangle_attr(ename), items), e)

    def _member_static(self, ci, v, ctx, ind):
        name = str(v.children[0])
        d = v.data
        if d in ("class_var_empty",):
            val = "None"
        elif d == "class_var_typed":
            val = DEFAULTS.get(str(v.children[1]).split("[")[0], "None")
        else:
            val = self.ex(v.children[-1], ctx)
            if d == "class_var_typed_assgnd" and str(v.children[1]) == "float":
                val = "_f(%s)" % val
        self.emit(ind, "cls.%s = %s" % (mangle_attr(name), val), v)

    # ---- functions
    def gen_func(self, ci, f, static, ind):
        header = f.children[0]
        name = str(header.children[0])
        args = header.children[1]
        ret = None
        for c in header.children[2:]:
            if isinstance(c, Token) and c.type == "TYPE_HINT":
                ret = str(c)
        ctx = FuncCtx(ci, static, ret)
        params = []
        pre = []
        if not static:
            params.append("self")
        else:
            self.emit(ind, "@staticmethod", f)
        for a in args.children:
            if isinstance(a, Tree) and a.data == "trailing_comma":
                continue
            if not isinstance(a, Tree):
                continue
            kind = a.data
            pname = str(a.children[0])
            ptype = None
            default = None
            if kind == "func_arg_typed":
                ptype = str(a.children[1])
                default = a.children[2] if len(a.children) > 2 else None
            elif kind == "func_arg_inf":
                default = a.children[1]
            elif kind == "func_arg_regular":
                default = a.children[1] if len(a.children) > 1 else None
            else:
                self.error("variadic parameters are not supported", a)
            py = ctx.declare(pname, ptype, "typed" if ptype else "dyn")
            if kind == "func_arg_inf":
                # inferred from the default value
                ctx.scopes[-1][pname].kind = "infer"
                ctx.scopes[-1][pname].type = self.stype(default, ctx)
            if default is None:
                params.append(py)
            else:
                d = default.children[0] if isinstance(default, Tree) and default.data == "expr" else default
                simple = self._simple_literal(d)
                if simple is not None:
                    params.append("%s=%s" % (py, simple))
                else:
                    params.append("%s=_U" % py)
                    pre.append((py, self.ex(default, ctx)))
            if ptype == "float" or (kind == "func_arg_inf" and ctx.scopes[-1][pname].type == "float"):
                pre.append((py, None))
        self.emit(ind, "def %s(%s):" % (mangle_attr(name), ", ".join(params)), f, line_of(header))
        n0 = len(self.lines)
        for py, expr in pre:
            if expr is None:
                self.emit(ind + 1, "%s = _f(%s)" % (py, py), f)
            else:
                self.emit(ind + 1, "if %s is _U:" % py, f)
                self.emit(ind + 2, "%s = %s" % (py, expr), f)
                # a float parameter with a non-literal default also needs the conversion below
        body = f.children[1:]
        self.block(body, ctx, ind + 1)
        if len(self.lines) == n0:
            self.emit(ind + 1, "pass")

    def _simple_literal(self, d):
        if isinstance(d, Token):
            if d.type in ("NUMBER",):
                return literal(number_value(d))
            if d.type in ("HEX", "BIN"):
                return literal(number_value(d))
            if d.type == "NAME" and str(d) in ("true", "false", "null"):
                return {"true": "True", "false": "False", "null": "None"}[str(d)]
            return None
        if isinstance(d, Tree) and d.data == "string":
            return repr(string_value(d.children[0]))
        if isinstance(d, Tree) and d.data == "string_name":
            return repr(string_value(d.children[0].children[0]))
        return None

    # ---- statements
    def block(self, stmts, ctx, ind, new_scope=False):
        if new_scope:
            ctx.push()
        n0 = len(self.lines)
        for s in stmts:
            self.stmt(s, ctx, ind)
        if len(self.lines) == n0:
            self.emit(ind, "pass")
        if new_scope:
            ctx.pop()

    def stmt(self, n, ctx, ind):
        if isinstance(n, Token):
            return
        d = n.data
        m = getattr(self, "s_" + d, None)
        if m is None:
            self.error("unsupported statement '%s'" % d, n)
        ctx.cur_ind = ind
        m(n, ctx, ind)

    def s_annotation(self, n, ctx, ind):
        pass

    def s_pass_stmt(self, n, ctx, ind):
        self.emit(ind, "pass", n)

    def s_break_stmt(self, n, ctx, ind):
        self.emit(ind, "break", n)

    def s_continue_stmt(self, n, ctx, ind):
        self.emit(ind, "continue", n)

    def s_breakpoint_stmt(self, n, ctx, ind):
        pass

    def s_docstr_stmt(self, n, ctx, ind):
        pass

    def s_return_stmt(self, n, ctx, ind):
        if not n.children:
            self.emit(ind, "return", n)
            return
        val = self.ex(n.children[0], ctx)
        if ctx.ret == "float":
            val = "_f(%s)" % val
        self.emit(ind, "return %s" % val, n)

    def s_const_stmt(self, n, ctx, ind):
        c = n.children[0]
        name = str(c.children[0])
        val = self.ex(c.children[-1], ctx)
        typ = str(c.children[1]) if c.data == "const_typed_assigned" else None
        if typ == "float":
            val = "_f(%s)" % val
        py = ctx.declare(name, typ, "typed" if typ else "dyn")
        self.emit(ind, "%s = %s" % (py, val), n)

    def s_func_var_stmt(self, n, ctx, ind):
        v = n.children[0]
        d = v.data
        name = str(v.children[0])
        if d == "func_var_empty":
            py = ctx.declare(name, None, "dyn")
            self.emit(ind, "%s = None" % py, n)
        elif d == "func_var_typed":
            typ = str(v.children[1])
            py = ctx.declare(name, typ, "typed")
            self.emit(ind, "%s = %s" % (py, DEFAULTS.get(typ.split("[")[0], "None")), n)
        elif d == "func_var_typed_assgnd":
            typ = str(v.children[1])
            val = self.ex(v.children[2], ctx)
            if typ == "float":
                val = "_f(%s)" % val
            py = ctx.declare(name, typ, "typed")
            self.emit(ind, "%s = %s" % (py, val), n)
        elif d == "func_var_inf":
            st = self.stype(v.children[1], ctx)
            val = self.ex(v.children[1], ctx)
            py = ctx.declare(name, st, "infer")
            self.emit(ind, "%s = %s" % (py, val), n)
        elif d == "func_var_assigned":
            val = self.ex(v.children[1], ctx)
            py = ctx.declare(name, None, "dyn")
            self.emit(ind, "%s = %s" % (py, val), n)
        else:
            self.error("unsupported var form %s" % d, n)

    def s_expr_stmt(self, n, ctx, ind):
        e = n.children[0]
        if isinstance(e, Tree) and e.data == "expr":
            e = e.children[0]
        if isinstance(e, Tree) and e.data == "assnmnt_expr":
            self.assign(e, ctx, ind)
            return
        if isinstance(e, Tree) and e.data == "string":
            return
        self.emit(ind, self.ex(e, ctx), n)

    def s_if_stmt(self, n, ctx, ind):
        first = True
        for br in n.children:
            if br.data in ("if_branch", "elif_branch"):
                cond = self.ex(br.children[0], ctx)
                self.emit(ind, "%s %s:" % ("if" if first else "elif", cond), br)
                first = False
                self.block(br.children[1:], ctx, ind + 1, True)
            elif br.data == "else_branch":
                self.emit(ind, "else:", br)
                self.block(br.children, ctx, ind + 1, True)

    def s_while_stmt(self, n, ctx, ind):
        cond = self.ex(n.children[0], ctx)
        self.emit(ind, "while %s:" % cond, n)
        self.block(n.children[1:], ctx, ind + 1, True)

    def s_for_stmt(self, n, ctx, ind):
        name = str(n.children[0])
        it = self.ex(n.children[1], ctx)
        ctx.push()
        py = ctx.declare(name, None, "dyn")
        self.emit(ind, "for %s in _iter(%s):" % (py, it), n)
        self.block(n.children[2:], ctx, ind + 1)
        ctx.pop()

    def s_for_stmt_typed(self, n, ctx, ind):
        name = str(n.children[0])
        typ = str(n.children[1])
        it = self.ex(n.children[2], ctx)
        ctx.push()
        py = ctx.declare(name, typ, "typed")
        self.emit(ind, "for %s in _iter(%s):" % (py, it), n)
        if typ == "float":
            self.emit(ind + 1, "%s = _f(%s)" % (py, py), n)
        self.block(n.children[3:], ctx, ind + 1)
        ctx.pop()

    def s_match_stmt(self, n, ctx, ind):
        subj = ctx.new_tmp()
        self.emit(ind, "%s = %s" % (subj, self.ex(n.children[0], ctx)), n)
        first = True
        for br in n.children[1:]:
            if not isinstance(br, Tree):
                continue
            pat = br.children[0]
            guard = None
            body = br.children[1:]
            if br.data == "guarded_match_branch":
                guard = br.children[1]
                body = br.children[2:]
            ctx.push()
            cond = self.pattern(pat, subj, ctx)
            if guard is not None:
                cond = "(%s) and (%s)" % (cond, self.ex(guard, ctx))
            self.emit(ind, "%s %s:" % ("if" if first else "elif", cond), br)
            first = False
            self.block(body, ctx, ind + 1)
            ctx.pop()

    def pattern(self, p, subj, ctx):
        d = p.data if isinstance(p, Tree) else None
        if d == "pattern":
            return self.pattern(p.children[0], subj, ctx)
        if d == "list_pattern":
            return "(" + " or ".join(self.pattern(c, subj, ctx) for c in p.children) + ")"
        if d == "wildcard_pattern":
            return "True"
        if d == "var_capture_pattern":
            py = ctx.declare(str(p.children[0]), None, "dyn")
            return "(_bind(lambda: None) or True)" if False else "True"
        if d == "attr_pattern":
            # Enum.VALUE / Class.CONST written as a pattern: same as the expression
            g = Tree("getattr", list(p.children), p.meta)
            return "(%s == %s)" % (subj, self.x_getattr(g, ctx))
        if d in ("array_pattern", "dict_pattern"):
            self.error("array/dict match patterns are not supported", p)
        return "(%s == %s)" % (subj, self.ex(p, ctx))

    # ---- assignment
    def assign(self, e, ctx, ind):
        target, op, value = e.children[0], str(e.children[1]), e.children[2]
        if isinstance(target, Tree) and target.data == "expr":
            target = target.children[0]
        binop = {"+=": "+", "-=": "-", "*=": "*", "/=": "/", "%=": "%", "&=": "&", "|=": "|", "^=": "^", ">>=": ">>", "<<=": "<<", "**=": "**"}.get(op)
        # target forms
        if isinstance(target, Token) and target.type == "NAME":
            self.assign_name(target, str(target), binop, value, ctx, ind, e)
            return
        d = norm(target.data)
        if d == "getattr":
            self.assign_attr(target, binop, value, ctx, ind, e)
            return
        if d == "subscr_expr":
            base = self.ex(target.children[0], ctx)
            idx = self.ex(target.children[1], ctx)
            if binop is None:
                self.emit(ind, "%s[%s] = %s" % (base, idx, self.ex(value, ctx)), e)
            else:
                bt, it = ctx.new_tmp(), ctx.new_tmp()
                self.emit(ind, "%s = %s" % (bt, base), e)
                self.emit(ind, "%s = %s" % (it, idx), e)
                self.emit(ind, "%s[%s] = %s" % (bt, it, self.binop(binop, "%s[%s]" % (bt, it), self.ex(value, ctx))), e)
            return
        self.error("unsupported assignment target '%s'" % target.data, e)

    def binop(self, op, a, b):
        if op == "/":
            return "_div(%s, %s)" % (a, b)
        if op == "%":
            return "_mod(%s, %s)" % (a, b)
        if op == "<<":
            return "_shl(%s, %s)" % (a, b)
        if op == "**":
            return "_pow(%s, %s)" % (a, b)
        return "(%s %s %s)" % (a, op, b)

    def assign_name(self, tok, name, binop, value, ctx, ind, node):
        loc = ctx.lookup(name)
        if loc is not None:
            target = loc.py
            cur = loc.py
            if binop is None:
                rhs = self.ex(value, ctx)
                if loc.type == "float" and loc.kind == "typed":
                    rhs = "_f(%s)" % rhs
                elif loc.kind == "infer":
                    rhs = "_like(%s, %s)" % (cur, rhs)
                self.emit(ind, "%s = %s" % (target, rhs), node)
            else:
                self.emit(ind, "%s = %s" % (target, self.binop(binop, cur, self.ex(value, ctx))), node)
            return
        m = self.p.resolve_member(ctx.cls, name)
        if m is None:
            if not ctx.static and self.inherited_builtin(name, ctx):
                m = Member("var", name, None, ctx.cls)
            else:
                self.unresolved.add(name)
                self.error("assignment to unknown name '%s'" % name, node)
        if m.kind == "var":
            if ctx.static:
                self.error("instance member '%s' assigned in a static function" % name, node)
            target = "self.%s" % mangle_attr(name)
        elif m.kind == "static_var":
            target = "%s.%s" % (self.global_name(m.owner), mangle_attr(name))
        else:
            self.error("cannot assign to %s '%s'" % (m.kind, name), node)
        if binop is None:
            rhs = self.ex(value, ctx)
            if m.type == "float":
                rhs = "_f(%s)" % rhs
            elif m.infer:
                rhs = "_like(%s, %s)" % (target, rhs)
            self.emit(ind, "%s = %s" % (target, rhs), node)
        else:
            self.emit(ind, "%s = %s" % (target, self.binop(binop, target, self.ex(value, ctx))), node)

    def split_getattr(self, n):
        """getattr children [recv, DOT, NAME, DOT, NAME...] -> (recv_node_or_names, attrs)."""
        recv = n.children[0]
        attrs = [str(c) for c in n.children[1:] if isinstance(c, Token) and c.type != "DOT"]
        return recv, attrs

    def assign_attr(self, target, binop, value, ctx, ind, node):
        recv, attrs = self.split_getattr(target)
        attr = attrs[-1]
        # receiver expression = recv + all attrs but the last
        rcode = self.attr_chain(recv, attrs[:-1], ctx)
        rtype = self.attr_chain_type(recv, attrs[:-1], ctx)
        py = mangle_attr(attr)
        is_self = (isinstance(recv, Token) and str(recv) == "self" and not attrs[:-1])
        member = None
        ci = None
        if is_self:
            ci = ctx.cls
        elif rtype is not None:
            ci = self.p.resolve_type(rtype, ctx.cls)
        if ci is not None:
            member = self.p.resolve_member(ci, attr)
        if binop is None:
            rhs = self.ex(value, ctx)
            if member is not None and member.kind in ("var", "static_var"):
                if member.type == "float":
                    rhs = "_f(%s)" % rhs
                elif member.infer:
                    rhs = "_like(%s.%s, %s)" % (rcode, py, rhs)
                self.emit(ind, "%s.%s = %s" % (rcode, py, rhs), node)
            elif ci is not None:
                self.emit(ind, "%s.%s = %s" % (rcode, py, rhs), node)
            else:
                self.emit(ind, "_setattr(%s, %r, %s)" % (rcode, py, rhs), node)
        else:
            if ci is not None or is_self:
                cur = "%s.%s" % (rcode, py)
                self.emit(ind, "%s = %s" % (cur, self.binop(binop, cur, self.ex(value, ctx))), node)
            else:
                t = ctx.new_tmp()
                self.emit(ind, "%s = %s" % (t, rcode), node)
                cur = "_ga(%s, %r)" % (t, py)
                self.emit(ind, "_setattr(%s, %r, %s)" % (t, py, self.binop(binop, cur, self.ex(value, ctx))), node)

    def attr_chain(self, recv, attrs, ctx):
        code = self.ex(recv, ctx)
        rtype = self.stype(recv, ctx)
        for a in attrs:
            code, rtype = self._attr_step(code, rtype, a, ctx, recv)
        return code

    def attr_chain_type(self, recv, attrs, ctx):
        code_unused = None
        rtype = self.stype(recv, ctx)
        for a in attrs:
            _c, rtype = self._attr_step("x", rtype, a, ctx, recv)
        return rtype

    def _attr_step(self, code, rtype, attr, ctx, node):
        """One `.attr` read on `code` whose static type is `rtype` -> (code, type)."""
        py = mangle_attr(attr)
        ci = self.p.resolve_type(rtype, ctx.cls) if rtype else None
        if ci is not None:
            m = self.p.resolve_member(ci, attr)
            if m is not None and m.kind in ("func", "static_func"):
                return "_mref(%s, %r)" % (code, py), "Callable"
            return "%s.%s" % (code, py), (m.type if m is not None else None)
        return "_ga(%s, %r)" % (code, py), None

    # ---- expressions
    def ex(self, n, ctx):
        if isinstance(n, Token):
            return self.ex_token(n, ctx)
        d = norm(n.data)
        m = getattr(self, "x_" + d, None)
        if m is None:
            self.error("unsupported expression '%s'" % n.data, n)
        return m(n, ctx)

    def ex_token(self, t, ctx):
        if t.type in ("NUMBER", "HEX", "BIN"):
            return literal(number_value(t))
        if t.type == "NAME":
            return self.name_value(str(t), ctx, t)
        self.error("unsupported token %s" % t.type, t)

    def x_expr(self, n, ctx):
        return self.ex(n.children[0], ctx)

    def x_par_expr(self, n, ctx):
        return "(%s)" % self.ex(n.children[0], ctx)

    def x_string(self, n, ctx):
        return repr(string_value(n.children[0]))

    def x_rstring(self, n, ctx):
        return repr(string_value(n.children[0]))

    def x_string_name(self, n, ctx):
        return repr(string_value(n.children[0].children[0]))

    def x_node_path(self, n, ctx):
        return repr(string_value(n.children[0].children[0]))

    def x_array(self, n, ctx):
        items = [self.ex(c, ctx) for c in n.children if not (isinstance(c, Tree) and c.data == "trailing_comma")]
        return "Array([%s])" % ", ".join(items)

    def x_dict(self, n, ctx):
        items = []
        for c in n.children:
            if not isinstance(c, Tree) or c.data == "trailing_comma":
                continue
            if c.data == "c_dict_element":
                items.append("%s: %s" % (self.ex(c.children[0], ctx), self.ex(c.children[1], ctx)))
            else:
                items.append("%r: %s" % (str(c.children[0]), self.ex(c.children[1], ctx)))
        return "Dictionary({%s})" % ", ".join(items)

    def x_lambda(self, n, ctx):
        """A lambda becomes a nested def emitted just before the statement that uses it.
        Captured locals are bound by value (default arguments), as GDScript does."""
        if ctx.cur_ind is None:
            self.error("a lambda outside of a function body is not supported", n)
        ind = ctx.cur_ind
        hdr = n.children[0]
        args = next(c for c in hdr.children if isinstance(c, Tree) and c.data == "func_args")
        ret = next((str(c) for c in hdr.children if isinstance(c, Token) and c.type == "TYPE_HINT"), None)
        lctx = FuncCtx(ctx.cls, ctx.static, ret, parent=ctx)
        name = "_lam%s" % ctx.new_tmp()[2:]
        params = []
        pre = []
        for a in args.children:
            if not isinstance(a, Tree) or a.data == "trailing_comma":
                continue
            pname = str(a.children[0])
            ptype = str(a.children[1]) if a.data == "func_arg_typed" and len(a.children) > 1 and isinstance(a.children[1], Token) and a.children[1].type == "TYPE_HINT" else None
            py = lctx.declare(pname, ptype, "typed" if ptype else "dyn")
            params.append(py)
            if ptype == "float":
                pre.append(py)
        first = len(self.lines)
        self.emit(ind, "def %s(PARAMS):" % name, n)          # placeholder, patched below
        header_index = len(self.lines) - 1
        for py in pre:
            self.emit(ind + 1, "%s = _f(%s)" % (py, py), n)
        self.block(n.children[1:], lctx, ind + 1)
        bound = ["%s=%s" % (loc.py, loc.py) for loc in lctx.captured.values()]
        i0, t0, g0 = self.lines[header_index]
        self.lines[header_index] = (i0, "def %s(%s):" % (name, ", ".join(params + bound)), g0)
        for nm, loc in lctx.captured.items():
            ctx.captured.setdefault(nm, loc) if ctx.parent is not None else None
        return "Callable(fn=%s)" % name

    def x_get_node(self, n, ctx):
        self.error("node paths are not supported by gdemu", n)

    @staticmethod
    def _bool_operands(n):
        return [c for c in n.children if not (isinstance(c, Token) and c.type != "NAME" and str(c) in ("or", "and", "||", "&&"))]

    def x_or_test(self, n, ctx):
        return "bool(%s)" % " or ".join("(%s)" % self.ex(c, ctx) for c in self._bool_operands(n))

    def x_and_test(self, n, ctx):
        return "bool(%s)" % " and ".join("(%s)" % self.ex(c, ctx) for c in self._bool_operands(n))

    def x_actual_not_test(self, n, ctx):
        return "(not %s)" % self.ex(n.children[1], ctx)

    def x_actual_neg_expr(self, n, ctx):
        return "(-%s)" % self.ex(n.children[1], ctx)

    def x_actual_bitw_not(self, n, ctx):
        return "(~%s)" % self.ex(n.children[1], ctx)

    def x_test_expr(self, n, ctx):
        toks = [c for c in n.children if not (isinstance(c, Token) and c.type in ("IF", "ELSE"))]
        return "(%s if %s else %s)" % (self.ex(toks[0], ctx), self.ex(toks[1], ctx), self.ex(toks[2], ctx))

    def x_comparison(self, n, ctx):
        a, op, b = n.children
        return "(%s %s %s)" % (self.ex(a, ctx), str(op), self.ex(b, ctx))

    def x_content_test(self, n, ctx):
        a = self.ex(n.children[0], ctx)
        rest = n.children[1:]
        out = a
        i = 0
        cur = a
        while i < len(rest):
            op = rest[i]
            neg = isinstance(op, Tree) and op.data == "not_in_op"
            b = self.ex(rest[i + 1], ctx)
            cur = "(%s %s %s)" % (cur, "not in" if neg else "in", b)
            i += 2
        return cur

    def x_type_test(self, n, ctx):
        cur = self.ex(n.children[0], ctx)
        i = 1
        while i < len(n.children):
            op = str(n.children[i])
            typ = str(n.children[i + 1])
            test = "_is(%s, %s)" % (cur, self.type_ref(typ, ctx, n))
            cur = "(not %s)" % test if op.replace(" ", "") == "isnot" else test
            i += 2
        return cur

    def x_actual_type_cast(self, n, ctx):
        cur = self.ex(n.children[0], ctx)
        i = 1
        while i < len(n.children):
            typ = str(n.children[i + 1]) if isinstance(n.children[i], Token) and n.children[i].type == "AS" else str(n.children[i])
            cur = "_as(%s, %s)" % (cur, self.type_ref(typ, ctx, n))
            i += 2 if isinstance(n.children[i], Token) and n.children[i].type == "AS" else 1
        return cur

    def type_ref(self, typ, ctx, node):
        """A type name used with `is` / `as`: scalar names stay strings, classes become Python names."""
        base = typ.split("[")[0]
        if base in SCALAR_TYPES:
            return repr(base)
        ci = self.p.resolve_type(base, ctx.cls)
        if ci is not None:
            return self.global_name(ci)
        if hasattr(rt, base):
            return base
        self.unresolved.add(base)
        return base

    def _chain(self, n, ctx, ops, mapper):
        kids = n.children
        cur = self.ex(kids[0], ctx)
        i = 1
        while i < len(kids):
            op = str(kids[i])
            cur = mapper(op, cur, self.ex(kids[i + 1], ctx))
            i += 2
        return cur

    def x_bitw_or(self, n, ctx):
        return self._chain(n, ctx, "|", lambda op, a, b: "(%s | %s)" % (a, b))

    def x_bitw_xor(self, n, ctx):
        return self._chain(n, ctx, "^", lambda op, a, b: "(%s ^ %s)" % (a, b))

    def x_bitw_and(self, n, ctx):
        return self._chain(n, ctx, "&", lambda op, a, b: "(%s & %s)" % (a, b))

    def x_shift_expr(self, n, ctx):
        return self._chain(n, ctx, None, lambda op, a, b: self.binop(op, a, b) if op == "<<" else "(%s >> %s)" % (a, b))

    def x_arith_expr(self, n, ctx):
        return self._chain(n, ctx, None, lambda op, a, b: "(%s %s %s)" % (a, op, b))

    def x_mdr_expr(self, n, ctx):
        return self._chain(n, ctx, None, lambda op, a, b: self.binop(op, a, b) if op in ("/", "%") else "(%s * %s)" % (a, b))

    def x_pow_expr(self, n, ctx):
        return self._chain(n, ctx, None, lambda op, a, b: "_pow(%s, %s)" % (a, b))

    def x_await_expr(self, n, ctx):
        cur = self.ex(n.children[-1], ctx)
        for _ in range(len(n.children) - 1):
            cur = "_await(%s)" % cur
        return cur

    def x_assnmnt_expr(self, n, ctx):
        self.error("assignment used as an expression", n)

    def x_subscr_expr(self, n, ctx):
        return "%s[%s]" % (self.ex(n.children[0], ctx), self.ex(n.children[1], ctx))

    # ---- names
    def name_value(self, name, ctx, node):
        if name == "true":
            return "True"
        if name == "false":
            return "False"
        if name == "null":
            return "None"
        if name == "self":
            if ctx.static:
                self.error("'self' used in a static function", node)
            return "self"
        loc = ctx.lookup(name)
        if loc is not None:
            return loc.py
        m = self.p.resolve_member(ctx.cls, name)
        if m is not None:
            if m.kind in ("var", "signal"):
                if ctx.static:
                    self.error("instance member '%s' used in a static function" % name, node)
                return "self.%s" % mangle_attr(name)
            if m.kind in ("const", "enum", "enum_value", "static_var"):
                return "%s.%s" % (self.global_name(m.owner), mangle_attr(name))
            if m.kind == "func":
                return "Callable(fn=self.%s)" % mangle_attr(name)
            if m.kind == "static_func":
                return "Callable(fn=%s.%s)" % (self.global_name(m.owner), mangle_attr(name))
            if m.kind == "inner":
                return self.global_name(m.owner.inners[name])
        ci = self.p.resolve_type(name, ctx.cls)
        if ci is not None:
            return self.global_name(ci)
        if name in self.p.autoloads:
            return name
        if not ctx.static and not hasattr(rt, name) and self.inherited_builtin(name, ctx):
            return "self.%s" % mangle_attr(name)
        if name in rt.NAMESPACE_OVERRIDES:
            return rt.NAMESPACE_OVERRIDES[name].__name__ if callable(rt.NAMESPACE_OVERRIDES[name]) else name
        if name in EXTRA_FUNCS:
            return EXTRA_FUNCS[name]
        if hasattr(rt, name):
            return name
        self.unresolved.add(name)
        return name

    def inherited_builtin(self, name, ctx=None):
        """A member the engine base class provides. Known ones are matched exactly; for scripts derived
        from other engine classes (Control, Node2D, ...) any lower-case name that is not a GDScript
        utility function is assumed to be an inherited member (the runtime stubs accept it)."""
        if hasattr(rt.Node, name) or hasattr(rt.Object, name):
            return True
        if ctx is None or name in UTILITY_FUNCTIONS or not name[:1].islower():
            return False
        root = self.p.builtin_root(ctx.cls)
        return root not in (None, "RefCounted", "Object", "Resource")

    def name_type(self, name, ctx):
        if name in ("true", "false"):
            return "bool"
        if name == "self":
            return ctx.cls.lname if ctx.cls.is_inner else (ctx.cls.cname or None)
        loc = ctx.lookup(name)
        if loc is not None:
            return loc.type
        m = self.p.resolve_member(ctx.cls, name)
        if m is not None:
            if m.kind in ("var", "static_var", "const"):
                if m.type:
                    return m.type
                if m.infer or m.kind == "const":
                    if m.value_node is not None:
                        try:
                            return self.stype(m.value_node, FuncCtx(m.owner, True, None))
                        except TranspileError:
                            return None
            if m.kind == "enum_value":
                return "int"
        return None

    # ---- static types (best effort; None = unknown, always safe)
    def stype(self, n, ctx):
        if isinstance(n, Token):
            if n.type == "NUMBER":
                return "float" if isinstance(number_value(n), float) else "int"
            if n.type in ("HEX", "BIN"):
                return "int"
            if n.type == "NAME":
                return self.name_type(str(n), ctx)
            return None
        d = norm(n.data)
        if d in ("expr", "par_expr"):
            return self.stype(n.children[0], ctx)
        if d in ("string", "string_name", "rstring"):
            return "String"
        if d == "array":
            return "Array"
        if d == "dict":
            return "Dictionary"
        if d in ("comparison", "and_test", "or_test", "actual_not_test", "content_test"):
            return "bool"
        if d == "type_test":
            return "bool"
        if d == "actual_type_cast":
            return str(n.children[-1])
        if d == "actual_neg_expr":
            return self.stype(n.children[1], ctx)
        if d == "test_expr":
            toks = [c for c in n.children if not (isinstance(c, Token) and c.type in ("IF", "ELSE"))]
            a, b = self.stype(toks[0], ctx), self.stype(toks[2], ctx)
            return a if a == b else None
        if d in ("arith_expr", "mdr_expr"):
            ts = [self.stype(c, ctx) for i, c in enumerate(n.children) if i % 2 == 0]
            if any(t == "String" for t in ts):
                return "String"
            if all(t == "int" for t in ts):
                return "int"
            if any(t == "float" for t in ts) and all(t in ("int", "float") for t in ts):
                return "float"
            return None
        if d == "getattr":
            recv, attrs = self.split_getattr(n)
            t = self.stype(recv, ctx) if not (isinstance(recv, Token) and self._is_class_name(str(recv), ctx)) else None
            if isinstance(recv, Token) and t is None:
                # Class.CONST / Enum.VALUE
                ci = self._class_of_name(str(recv), ctx)
                if ci is not None and len(attrs) == 1:
                    m = self.p.resolve_member(ci, attrs[0])
                    if m is not None:
                        return m.type or ("int" if m.kind == "enum_value" else None)
                return None
            for a in attrs:
                ci = self.p.resolve_type(t, ctx.cls) if t else None
                if ci is None:
                    return None
                m = self.p.resolve_member(ci, a)
                t = m.type if m is not None else None
            return t
        if d == "getattr_call":
            g = n.children[0]
            recv, attrs = self.split_getattr(g)
            meth = attrs[-1]
            if isinstance(recv, Token) and len(attrs) == 1:
                ci = self._class_of_name(str(recv), ctx)
                if ci is not None:
                    if meth == "new":
                        return ci.lname if ci.is_inner else ci.cname
                    m = self.p.resolve_member(ci, meth)
                    return m.type if m is not None and m.kind in ("func", "static_func") else None
                if str(recv) in ("Vector2", "Color", "Rect2") and meth == "new":
                    return str(recv)
            t = self.attr_chain_type(recv, attrs[:-1], ctx)
            ci = self.p.resolve_type(t, ctx.cls) if t else None
            if ci is not None:
                m = self.p.resolve_member(ci, meth)
                if m is not None and m.kind in ("func", "static_func"):
                    return m.type
            return None
        if d == "standalone_call":
            fname = str(n.children[0])
            m = self.p.resolve_member(ctx.cls, fname)
            if m is not None and m.kind in ("func", "static_func"):
                return m.type
            if fname in ("float", "absf", "minf", "maxf", "clampf", "sqrt", "lerpf", "floor", "ceil", "round", "fmod", "fposmod", "sin", "cos", "atan2", "randf"):
                return "float"
            if fname in ("int", "absi", "mini", "maxi", "clampi", "floori", "ceili", "roundi", "typeof", "randi", "len"):
                return "int"
            if fname in ("str", "String"):
                return "String"
            if fname in ("Vector2", "Vector3", "Color", "Rect2", "Array", "Dictionary", "PackedStringArray", "PackedByteArray"):
                return fname
            return None
        return None

    def _is_class_name(self, name, ctx):
        return ctx.lookup(name) is None and self._class_of_name(name, ctx) is not None

    def _class_of_name(self, name, ctx):
        if ctx.lookup(name) is not None:
            return None
        m = self.p.resolve_member(ctx.cls, name)
        if m is not None and m.kind == "inner":
            return m.owner.inners[name]
        if m is not None:
            return None
        return self.p.resolve_type(name, ctx.cls)

    # ---- calls
    def call_args(self, n, ctx, start=1):
        return [self.ex(c, ctx) for c in n.children[start:] if not (isinstance(c, Tree) and c.data == "trailing_comma")]

    def x_standalone_call(self, n, ctx):
        name = str(n.children[0])
        args = self.call_args(n, ctx)
        loc = ctx.lookup(name)
        if loc is not None:
            self.error("calling the local '%s' directly (use .call())" % name, n)
        m = self.p.resolve_member(ctx.cls, name)
        if m is not None:
            if m.kind == "func":
                if ctx.static:
                    self.error("instance method '%s' called from a static function" % name, n)
                return "self.%s(%s)" % (mangle_attr(name), ", ".join(args))
            if m.kind == "static_func":
                return "%s.%s(%s)" % (self.global_name(m.owner), mangle_attr(name), ", ".join(args))
        if not ctx.static and not hasattr(rt, name) and name not in rt.NAMESPACE_OVERRIDES and self.inherited_builtin(name, ctx):
            return "self.%s(%s)" % (mangle_attr(name), ", ".join(args))
        if name == "preload" or name == "load":
            return "%s(%s)" % (EXTRA_FUNCS[name], ", ".join(args))
        if name in rt.NAMESPACE_OVERRIDES:
            return "%s(%s)" % (rt.NAMESPACE_OVERRIDES[name].__name__, ", ".join(args))
        if name == "is_instance_valid":
            return "(%s is not None)" % args[0]
        if hasattr(rt, name):
            return "%s(%s)" % (name, ", ".join(args))
        ci = self.p.resolve_type(name, ctx.cls)
        if ci is not None:
            self.error("'%s(...)' is not a constructor call (use %s.new())" % (name, name), n)
        self.unresolved.add(name)
        return "%s(%s)" % (name, ", ".join(args))

    def x_getattr_call(self, n, ctx):
        g = n.children[0]
        recv, attrs = self.split_getattr(g)
        meth = attrs[-1]
        py = mangle_attr(meth)
        args = self.call_args(n, ctx)
        arglist = ", ".join(args)
        # Class.method(...) / Class.new(...)
        if isinstance(recv, Token) and recv.type == "NAME" and len(attrs) == 1:
            rname = str(recv)
            if rname == "self":
                return "self.%s(%s)" % (py, arglist)
            ci = self._class_of_name(rname, ctx)
            if ci is not None:
                return "%s.%s(%s)" % (self.global_name(ci), py, arglist)
            if ctx.lookup(rname) is None and self.p.resolve_member(ctx.cls, rname) is None:
                if rname in self.p.autoloads or hasattr(rt, rname):
                    return "%s.%s(%s)" % (self.name_value(rname, ctx, recv), py, arglist)
        rcode = self.attr_chain(recv, attrs[:-1], ctx)
        rtype = self.attr_chain_type(recv, attrs[:-1], ctx)
        if isinstance(recv, Token) and str(recv) == "self" and not attrs[:-1]:
            return "self.%s(%s)" % (py, arglist)
        ci = self.p.resolve_type(rtype, ctx.cls) if rtype else None
        if ci is not None:
            return "%s.%s(%s)" % (rcode, py, arglist)
        if rtype and rtype != "String" and rtype != "Variant" and (hasattr(rt, rtype.split("[")[0])):
            return "%s.%s(%s)" % (rcode, py, arglist)
        if arglist:
            return "_c(%s, %r, %s)" % (rcode, py, arglist)
        return "_c(%s, %r)" % (rcode, py)

    def x_getattr(self, n, ctx):
        recv, attrs = self.split_getattr(n)
        if isinstance(recv, Token) and recv.type == "NAME":
            rname = str(recv)
            if rname != "self":
                ci = self._class_of_name(rname, ctx)
                if ci is not None:
                    code = self.global_name(ci)
                    return self._class_attr_chain(code, ci, attrs, ctx)
                if ctx.lookup(rname) is None and self.p.resolve_member(ctx.cls, rname) is None and (
                        rname in self.p.autoloads or hasattr(rt, rname)):
                    code = self.name_value(rname, ctx, recv)
                    if rname in self.p.autoloads:
                        # singleton member: a property, or a method used as a value (Callable)
                        for a in attrs:
                            code = "_ga(%s, %r)" % (code, mangle_attr(a))
                        return code
                    return "%s%s" % (code, "".join(".%s" % mangle_attr(a) for a in attrs))
                m = self.p.resolve_member(ctx.cls, rname)
                if m is not None and m.kind in ("enum",):
                    return "%s.%s%s" % (self.global_name(m.owner), mangle_attr(rname), "".join(".%s" % mangle_attr(a) for a in attrs))
        return self.attr_chain(recv, attrs, ctx)

    def _class_attr_chain(self, code, ci, attrs, ctx):
        cur = ci
        for a in attrs:
            m = self.p.resolve_member(cur, a) if cur is not None else None
            code = "%s.%s" % (code, mangle_attr(a))
            if m is not None and m.kind == "inner":
                cur = m.owner.inners[a]
                code = self.global_name(cur)
            else:
                cur = None
        return code


def transpile_script(project, path):
    """Returns (python_source, linemap, unresolved_names) for the classes of one script."""
    ci = project.script(path)
    g = Gen(project)
    src, lmap = g.gen_top(ci)
    return src, lmap, g.unresolved
