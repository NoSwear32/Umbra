#!/usr/bin/env python3
"""
gdcheck - a static semantic checker for GDScript 4 projects ("poor man's compiler").

It complements `gdparse`/`gdlint` (gdtoolkit), which only verify SYNTAX. gdcheck resolves
identifiers, members, signals and call arities against

  * the project's own scripts (class_name, autoloads, inner classes), and
  * Godot's `extension_api.json` (produce it with `godot --headless --dump-extension-api`),

so typos, wrong method names, wrong argument counts, `:=` on Variant expressions and
shadowed locals are caught without launching the engine. It is intentionally conservative:
anything it cannot infer is skipped, never guessed.

Usage
  python3 tools/gdcheck.py --api extension_api.json [--project game] [--verbose] [dirs...]

Requires: pip install gdtoolkit
Exit code: number of errors (warnings do not count).
"""
import argparse
import glob
import json
import os
import re
import sys

from lark import Tree, Token
from gdtoolkit.parser import parser as gdparser

# Object methods every script can call that extension_api.json does not list.
IMPLICIT_OBJECT_METHODS = frozenset(["free"])

# --------------------------------------------------------------------------- API
class Api:
    def __init__(self, path):
        d = json.load(open(path))
        self.version = d["header"]["version_full_name"]
        self.classes = {c["name"]: c for c in d["classes"]}
        self.builtins = {c["name"]: c for c in d["builtin_classes"]}
        self.utils = {u["name"]: u for u in d["utility_functions"]}
        self.singletons = {s["name"]: s["type"] for s in d["singletons"]}
        self.enum_names = set()      # e.g. Error, Key, "Node.ProcessMode"
        self.global_consts = set()   # OK, KEY_A, TYPE_INT ...
        for e in d.get("global_enums", []):
            self.enum_names.add(e["name"])
            for v in e["values"]:
                self.global_consts.add(v["name"])
        for cname, c in self.classes.items():
            for e in c.get("enums", []) or []:
                self.enum_names.add(cname + "." + e["name"])
        self._member_cache = {}

    def class_chain(self, cname):
        out = []
        c = self.classes.get(cname)
        while c:
            out.append(c)
            c = self.classes.get(c.get("inherits"))
        return out

    def members(self, cname):
        """name -> (kind, node) for a class including its bases."""
        if cname in self._member_cache:
            return self._member_cache[cname]
        res = {}
        for c in reversed(self.class_chain(cname)):
            for m in c.get("methods", []) or []:
                res[m["name"]] = ("method", m)
            for p in c.get("properties", []) or []:
                res[p["name"]] = ("property", p)
            for s in c.get("signals", []) or []:
                res[s["name"]] = ("signal", s)
            for k in c.get("constants", []) or []:
                res[k["name"]] = ("constant", k)
            for e in c.get("enums", []) or []:
                res[e["name"]] = ("enum", e)
                for v in e["values"]:
                    res[v["name"]] = ("constant", v)
        self._member_cache[cname] = res
        return res

    def builtin_members(self, tname):
        b = self.builtins.get(tname)
        res = {}
        if not b:
            return res
        for m in b.get("methods", []) or []:
            res[m["name"]] = ("method", m)
        for m in b.get("members", []) or []:
            res[m["name"]] = ("member", m)
        for k in b.get("constants", []) or []:
            res[k["name"]] = ("constant", k)
        for e in b.get("enums", []) or []:
            res[e["name"]] = ("enum", e)
            for v in e["values"]:
                res[v["name"]] = ("constant", v)
        return res


def api_type(t):
    """Convert an extension_api type string to a checker type."""
    if t is None:
        return None
    if t.startswith("enum::") or t.startswith("bitfield::"):
        return "int"
    if t.startswith("typedarray::"):
        return "Array[%s]" % api_type(t[len("typedarray::"):])
    return t


def arity_ok(args, n, vararg=False):
    if vararg:
        req = sum(1 for a in args if "default_value" not in a)
        return n >= req
    req = sum(1 for a in args if "default_value" not in a)
    return req <= n <= len(args)


# ------------------------------------------------------------------- script model
class FuncInfo:
    def __init__(self, name, params, ret, static, node):
        self.name = name
        self.params = params    # list of (name, type, has_default)
        self.ret = ret
        self.static = static
        self.node = node

    def arity(self):
        req = sum(1 for p in self.params if not p[2])
        return req, len(self.params)


class ScriptInfo:
    def __init__(self, path, tree):
        self.path = path
        self.tree = tree
        self.class_name = None
        self.base = None                # engine class / project class_name / res:// path
        self.members = {}               # name -> (kind, info)
        self.inner = {}                 # name -> ScriptInfo
        self.parent = None              # enclosing ScriptInfo for inner classes
        self.is_autoload = False
        self.funcs = {}                 # name -> FuncInfo (own funcs)
        self.signals = {}               # name -> arity
        self.enums = {}                 # enum name -> set(values)


TOKEN_LITERAL_TYPES = {"NUMBER": None, "STRING": "String", "TRUE": "bool", "FALSE": "bool", "NULL": None}


def tok_text(t):
    return str(t)


def first_name(node):
    """Return the identifier text of a Token or a 'name-like' subtree."""
    if isinstance(node, Token):
        return str(node)
    if isinstance(node, Tree) and node.children:
        return first_name(node.children[0])
    return None


def type_text(node):
    """Flatten a type annotation node to text ('Array[int]', 'Node.ProcessMode')."""
    if node is None:
        return None
    if isinstance(node, Token):
        return str(node)
    if isinstance(node, Tree):
        parts = [type_text(c) for c in node.children]
        return "".join(p for p in parts if p)
    return None


class Checker:
    def __init__(self, api, project_root, verbose=False):
        self.api = api
        self.root = project_root
        self.verbose = verbose
        self.errors = []
        self.warnings = []
        self.scripts = {}          # path -> ScriptInfo
        self.classes = {}          # class_name -> ScriptInfo
        self.autoloads = {}        # name -> ScriptInfo
        self.autoload_paths = {}   # name -> res:// path
        self.cur_file = None

    # ---------------------------------------------------------------- reporting
    def err(self, node, msg):
        self.errors.append((self.cur_file, self._line(node), msg))

    def warn(self, node, msg):
        self.warnings.append((self.cur_file, self._line(node), msg))

    @staticmethod
    def _line(node):
        if isinstance(node, Token):
            return node.line
        if isinstance(node, Tree):
            m = getattr(node, "meta", None)
            if m is not None and not getattr(m, "empty", True):
                return m.line
            for c in node.children:
                l = Checker._line(c)
                if l:
                    return l
        return 0

    # ---------------------------------------------------------------- loading
    def load_project(self, files):
        for f in files:
            code = open(f, encoding="utf-8").read()
            try:
                tree = gdparser.parse(code, gather_metadata=True)
            except Exception as e:  # syntax error
                self.errors.append((f, 0, "PARSE ERROR: %s" % str(e).split("\n")[0]))
                continue
            si = ScriptInfo(f, tree)
            self._collect(si, tree.children)
            self.scripts[f] = si
            if si.class_name:
                if si.class_name in self.classes:
                    self.errors.append((f, 0, "duplicate class_name %s" % si.class_name))
                self.classes[si.class_name] = si
        # autoloads from project.godot
        pg = os.path.join(self.root, "project.godot")
        if os.path.exists(pg):
            in_auto = False
            for line in open(pg, encoding="utf-8"):
                line = line.strip()
                if line.startswith("["):
                    in_auto = line == "[autoload]"
                    continue
                if in_auto and "=" in line:
                    name, val = line.split("=", 1)
                    val = val.strip().strip('"').lstrip("*")
                    self.autoload_paths[name.strip()] = val
                    p = os.path.join(self.root, val.replace("res://", ""))
                    for sp, si in self.scripts.items():
                        if os.path.normpath(sp) == os.path.normpath(p):
                            self.autoloads[name.strip()] = si
                            si.is_autoload = True
        # autoload names must not clash with class_name
        for n in self.autoloads:
            if n in self.classes:
                self.errors.append((self.autoloads[n].path, 0, "autoload '%s' hides class_name of the same name" % n))

    def _collect(self, si, children):
        pending_annotations = []
        for ch in children:
            if not isinstance(ch, Tree):
                continue
            if ch.data == "static_class_var_stmt":
                ch = ch.children[0]
            k = ch.data
            if k == "classname_stmt":
                si.class_name = first_name(ch)
            elif k == "extends_stmt":
                si.base = type_text(ch).strip('"')
            elif k == "signal_stmt":
                name = first_name(ch)
                n = 0
                for c in ch.children:
                    if isinstance(c, Tree) and c.data == "signal_args":
                        n = len([a for a in c.children if isinstance(a, Tree)])
                si.members[name] = ("signal", n)
                si.signals[name] = n
            elif k == "const_stmt":
                inner = ch.children[0]
                name = first_name(inner)
                t = None
                if inner.data == "const_typed_assigned":
                    t = type_text(inner.children[1])
                si.members[name] = ("const", t)
            elif k == "class_var_stmt":
                inner = ch.children[0]
                name = first_name(inner)
                t = None
                if inner.data in ("class_var_typed_assgnd", "class_var_typed"):
                    t = type_text(inner.children[1])
                elif inner.data == "class_var_inf":
                    t = ":="   # inferred
                si.members[name] = ("var", t)
                if inner.data == "class_var_inf":
                    si.members[name] = ("var", ("infer", inner))
            elif k == "enum_stmt":
                inner = ch.children[0]
                if inner.data == "enum_named":
                    ename = first_name(inner)
                    vals = set()
                    for e in inner.children[1].children:
                        if isinstance(e, Tree):
                            vals.add(first_name(e))
                    si.enums[ename] = vals
                    si.members[ename] = ("enum", vals)
                    for v in vals:
                        si.members[v] = ("enumval", ename)
                else:  # anonymous enum
                    body = inner.children[0]
                    for e in body.children:
                        if isinstance(e, Tree):
                            n = first_name(e)
                            si.members[n] = ("enumval", None)
            elif k in ("func_def", "static_func_def"):
                fd = ch if k == "func_def" else ch.children[0]
                fi = self._func_info(fd, k == "static_func_def")
                if fi.name in si.funcs:
                    self.errors.append((si.path, self._line(fd), "function %s declared twice" % fi.name))
                si.funcs[fi.name] = fi
                si.members[fi.name] = ("func", fi)
            elif k == "class_def":
                iname = first_name(ch)
                isi = ScriptInfo(si.path, ch)
                isi.class_name = None
                isi.parent = si
                isi.base = "RefCounted"
                # 'extends' inside inner class
                self._collect(isi, ch.children[1:])
                si.inner[iname] = isi
                si.members[iname] = ("inner", isi)

    def _func_info(self, fd, static):
        header = fd.children[0]
        name = first_name(header)
        params = []
        ret = None
        for c in header.children[1:]:
            if isinstance(c, Tree) and c.data == "func_args":
                for a in c.children:
                    if not isinstance(a, Tree):
                        continue
                    an = first_name(a)
                    at = None
                    has_def = False
                    if a.data == "func_arg_typed":
                        at = type_text(a.children[1])
                        has_def = len(a.children) > 2
                    elif a.data == "func_arg_regular":
                        has_def = len(a.children) > 1
                    elif a.data == "func_arg_inf":
                        has_def = True
                        at = ":="
                    params.append((an, at, has_def))
            elif isinstance(c, (Token, Tree)) and not (isinstance(c, Tree) and c.data == "func_args"):
                ret = type_text(c)
        return FuncInfo(name, params, ret, static, fd)

    # ---------------------------------------------------------------- type helpers
    def is_type_known(self, t, si):
        """Is annotation text `t` a valid type in the context of script `si`?"""
        if t is None or t == ":=":
            return True
        if t == "void" or t == "Variant":
            return True
        m = re.match(r"^(Array|Dictionary)\[(.+)\]$", t)
        if m:
            return all(self.is_type_known(x.strip(), si) for x in m.group(2).split(","))
        head = t.split(".")[0]
        if t in self.api.enum_names:
            return True
        if head in self.api.classes or head in self.api.builtins:
            if "." in t:
                return t in self.api.enum_names or self._api_has_nested(head, t.split(".", 1)[1])
            return True
        if head in self.classes:
            return True
        if head in self.autoloads:
            return True
        s = si
        while s is not None:
            if head in s.inner or head in s.enums:
                return True
            s = s.parent
        if self.base_has_enum(si, head):
            return True
        return False

    def _api_has_nested(self, cname, rest):
        c = self.api.classes.get(cname)
        if not c:
            return True
        return any(e["name"] == rest for e in c.get("enums", []) or [])

    def base_has_enum(self, si, ename):
        b = self.resolve_base(si)
        while b is not None:
            if isinstance(b, ScriptInfo):
                if ename in b.enums:
                    return True
                b = self.resolve_base(b)
            else:
                return (b + "." + ename) in self.api.enum_names or ename in self.api.enum_names
        return False

    def resolve_base(self, si):
        """Return ScriptInfo (project base) or str (engine class) or None."""
        base = si.base
        if base is None:
            return "RefCounted"
        if base.startswith("res://"):
            p = os.path.join(self.root, base.replace("res://", ""))
            for sp, s in self.scripts.items():
                if os.path.normpath(sp) == os.path.normpath(p):
                    return s
            return None
        if base in self.classes:
            return self.classes[base]
        if base in self.api.classes:
            return base
        s = si.parent
        while s is not None:
            if base in s.inner:
                return s.inner[base]
            s = s.parent
        return base

    def engine_root(self, si):
        """Engine class at the root of the inheritance chain."""
        seen = 0
        cur = si
        while isinstance(cur, ScriptInfo) and seen < 20:
            cur = self.resolve_base(cur)
            seen += 1
        return cur if isinstance(cur, str) else "RefCounted"

    def find_member(self, si, name):
        """Look up a member in script `si` and its bases. Returns (kind, info) or None."""
        cur = si
        seen = 0
        while isinstance(cur, ScriptInfo) and seen < 30:
            if name in cur.members:
                return cur.members[name]
            cur = self.resolve_base(cur)
            seen += 1
        if isinstance(cur, str):
            m = self.api.members(cur).get(name)
            if m:
                return ("api_" + m[0], m[1])
        return None

    def class_of_type(self, t):
        """Map a type text to ('project', ScriptInfo) | ('engine', name) | ('builtin', name) | None"""
        if t is None:
            return None
        base = re.sub(r"\[.*\]$", "", t)
        if base in self.classes:
            return ("project", self.classes[base])
        if base in self.autoloads:
            return ("project", self.autoloads[base])
        if base in self.api.classes:
            return ("engine", base)
        if base in self.api.builtins:
            return ("builtin", base)
        return None

    # ---------------------------------------------------------------- checking
    def check_all(self):
        for path, si in self.scripts.items():
            self.cur_file = path
            self._check_script(si)

    def _check_script(self, si):
        # annotations of members and base class
        if si.base and si.base.startswith("res://") is False and self.resolve_base(si) is None:
            self.err(si.tree, "unknown base class '%s'" % si.base)
        for name, (kind, info) in si.members.items():
            if kind == "var" and isinstance(info, str) and info != ":=":
                if not self.is_type_known(info, si):
                    self.warn(si.tree, "member '%s': unknown type '%s'" % (name, info))
        # walk top-level nodes
        children = si.tree.children
        for ch in children:
            if not isinstance(ch, Tree):
                continue
            if ch.data == "static_class_var_stmt":
                ch = ch.children[0]
            k = ch.data
            if k in ("func_def", "static_func_def"):
                fd = ch if k == "func_def" else ch.children[0]
                self._check_func(si, fd, k == "static_func_def")
            elif k == "class_var_stmt":
                self._check_member_init(si, ch)
            elif k == "const_stmt":
                self._check_member_init(si, ch)
            elif k == "class_def":
                isi = si.inner.get(first_name(ch))
                if isi:
                    self._check_script_inner(isi, ch)

    def _check_script_inner(self, isi, node):
        for ch in node.children[1:]:
            if not isinstance(ch, Tree):
                continue
            if ch.data == "static_class_var_stmt":
                ch = ch.children[0]
            k = ch.data
            if k in ("func_def", "static_func_def"):
                fd = ch if k == "func_def" else ch.children[0]
                self._check_func(isi, fd, k == "static_func_def")
            elif k in ("class_var_stmt", "const_stmt"):
                self._check_member_init(isi, ch)

    def _check_member_init(self, si, stmt):
        ctx = Ctx(si, static=False)
        ctx.push()
        inner = stmt.children[0]
        for c in inner.children:
            if isinstance(c, Tree) and c.data == "expr":
                self.visit(c, ctx)
        # ':=' members need a known type
        if inner.data == "class_var_inf":
            t = self.visit(inner.children[1], ctx)
            if t in (None, "Variant"):
                self.warn(stmt, "member '%s' declared with := but its type cannot be inferred here" % first_name(inner))
            else:
                si.members[first_name(inner)] = ("var", t)

    def _check_func(self, si, fd, static):
        ctx = Ctx(si, static)
        ctx.push()
        header = fd.children[0]
        fname = first_name(header)
        ctx.func_name = fname
        for c in header.children[1:]:
            if isinstance(c, Tree) and c.data == "func_args":
                for a in c.children:
                    if not isinstance(a, Tree):
                        continue
                    an = first_name(a)
                    at = None
                    if a.data == "func_arg_typed":
                        at = type_text(a.children[1])
                        if not self.is_type_known(at, si):
                            self.err(a, "unknown type '%s' for parameter '%s'" % (at, an))
                    if a.data in ("func_arg_typed", "func_arg_regular", "func_arg_inf"):
                        for d in a.children:
                            if isinstance(d, Tree) and d.data == "expr":
                                self.visit(d, ctx)
                    self.declare(ctx, a, an, at)
            elif not isinstance(c, Tree) or c.data != "func_args":
                rt = type_text(c)
                if rt and not self.is_type_known(rt, si):
                    self.err(header, "unknown return type '%s'" % rt)
        ctx.ret = self._func_info(fd, static).ret
        for st in fd.children[1:]:
            self.stmt(st, ctx)
        ctx.pop()

    # ------------------------------------------------------------ scoping helpers
    def declare(self, ctx, node, name, typ):
        if name is None:
            return
        # shadowing an outer local / parameter is an error in GDScript 4
        for sc in ctx.scopes:
            if name in sc:
                self.err(node, "variable '%s' is already declared in this function (GDScript forbids shadowing outer locals)" % name)
                break
        else:
            if name in ("len", "str", "min", "max", "abs", "sign", "floor", "ceil", "round", "range", "print", "seed", "lerp", "clamp", "load", "type_convert", "hash", "char", "ord"):
                self.warn(node, "local '%s' shadows a built-in function" % name)
        ctx.scopes[-1][name] = typ

    # ------------------------------------------------------------ statements
    def stmt(self, st, ctx):
        if not isinstance(st, Tree):
            return
        k = st.data
        if k == "func_var_stmt":
            self._var_stmt(st.children[0], ctx)
        elif k == "expr_stmt":
            self.visit(st.children[0], ctx)
        elif k == "return_stmt":
            for c in st.children:
                if isinstance(c, Tree):
                    self.visit(c, ctx)
        elif k == "if_stmt":
            for br in st.children:
                if not isinstance(br, Tree):
                    continue
                if br.data in ("if_branch", "elif_branch"):
                    self.visit(br.children[0], ctx)
                    ctx.push()
                    for s2 in br.children[1:]:
                        self.stmt(s2, ctx)
                    ctx.pop()
                elif br.data == "else_branch":
                    ctx.push()
                    for s2 in br.children:
                        self.stmt(s2, ctx)
                    ctx.pop()
        elif k == "while_stmt":
            self.visit(st.children[0], ctx)
            ctx.push()
            for s2 in st.children[1:]:
                self.stmt(s2, ctx)
            ctx.pop()
        elif k == "for_stmt":
            vname = first_name(st.children[0])
            it_t = self.visit(st.children[1], ctx)
            ctx.push()
            vt = None
            m = re.match(r"^(?:Packed(?:Int32|Int64)Array|Array\[int\])$", it_t or "")
            if it_t in ("int",) or (isinstance(st.children[1], Tree) and self._is_range_call(st.children[1])):
                vt = "int"
            self.declare(ctx, st.children[0], vname, vt)
            for s2 in st.children[2:]:
                self.stmt(s2, ctx)
            ctx.pop()
        elif k == "match_stmt":
            self.visit(st.children[0], ctx)
            for br in st.children[1:]:
                if isinstance(br, Tree) and br.data == "match_branch":
                    ctx.push()
                    for c in br.children:
                        if isinstance(c, Tree) and c.data == "pattern":
                            self._pattern(c, ctx)
                        else:
                            self.stmt(c, ctx)
                    ctx.pop()
        elif k in ("pass_stmt", "break_stmt", "continue_stmt", "breakpoint_stmt"):
            pass
        else:
            # unknown statement kinds: just walk expressions
            for c in st.children:
                if isinstance(c, Tree):
                    self.stmt(c, ctx)

    def _pattern(self, pat, ctx):
        # patterns can bind variables: `var x` ; literals/constants are checked as expressions
        for c in pat.children:
            if isinstance(c, Tree):
                if c.data in ("pattern_var", "match_var"):
                    self.declare(ctx, c, first_name(c), None)
                else:
                    self._pattern(c, ctx)
            elif isinstance(c, Token) and c.type == "NAME":
                nm = str(c)
                if not self.resolve_ident(nm, ctx, quiet=True)[0]:
                    pass

    @staticmethod
    def _is_range_call(node):
        n = node
        while isinstance(n, Tree) and n.data == "expr" and len(n.children) == 1:
            n = n.children[0]
        return isinstance(n, Tree) and n.data == "standalone_call" and first_name(n) == "range"

    def _var_stmt(self, v, ctx):
        kind = v.data
        name = first_name(v)
        declared = None
        init_expr = None
        if kind == "func_var_typed_assgnd":
            declared = type_text(v.children[1])
            init_expr = v.children[2]
        elif kind == "func_var_typed":
            declared = type_text(v.children[1])
        elif kind == "func_var_inf":
            init_expr = v.children[1]
        elif kind == "func_var_assigned":
            init_expr = v.children[1]
        if declared and not self.is_type_known(declared, ctx.script):
            self.err(v, "unknown type '%s' for variable '%s'" % (declared, name))
        vt = declared
        if init_expr is not None:
            it = self.visit(init_expr, ctx)
            if kind == "func_var_inf":
                if it in (None,):
                    self.warn(v, "'%s :=' initialiser type could not be inferred by gdcheck (verify manually)" % name)
                elif it == "Variant":
                    self.err(v, "cannot infer type of '%s': initialiser is Variant" % name)
                vt = it
        self.declare(ctx, v, name, vt)

    # ------------------------------------------------------------ expressions
    def visit(self, node, ctx):
        """Visit an expression; returns the inferred type text or None."""
        if isinstance(node, Token):
            return self._token(node, ctx)
        if not isinstance(node, Tree):
            return None
        k = node.data
        ch = node.children
        if k == "expr" or k == "par_expr":
            r = None
            for c in ch:
                r = self.visit(c, ctx)
            return r if len(ch) == 1 else None
        if k == "getattr":
            return self._getattr(node, ctx)
        if k == "getattr_call":
            return self._method_call(node, ctx)
        if k == "standalone_call":
            return self._func_call(node, ctx)
        if k in ("array",):
            for c in ch:
                self.visit(c, ctx)
            return "Array"
        if k == "dict":
            for c in ch:
                self.visit(c, ctx)
            return "Dictionary"
        if k == "c_dict_element":
            for c in ch:
                self.visit(c, ctx)
            return None
        if k == "subscr_expr":
            bt = self.visit(ch[0], ctx)
            for c in ch[1:]:
                self.visit(c, ctx)
            if bt and bt.startswith("Array[") and bt.endswith("]"):
                return bt[6:-1]
            if bt in ("PackedInt32Array", "PackedInt64Array"):
                return "int"
            if bt in ("PackedFloat32Array", "PackedFloat64Array"):
                return "float"
            if bt == "PackedStringArray":
                return "String"
            if bt == "PackedByteArray":
                return "int"
            if bt in ("Vector2", "Vector3", "Vector4", "Vector2i", "Vector3i"):
                return "int" if bt.endswith("i") else "float"
            return "Variant" if bt in ("Array", "Dictionary", None) else None
        if k in ("arith_expr", "mdr_expr", "shift_expr", "bitw_and", "bitw_or", "bitw_xor"):
            return self._binary(node, ctx)
        if k in ("comparison", "and_test", "or_test", "content_test", "type_test", "asless_comparison", "asless_and_test", "asless_or_test", "asless_content_test", "asless_type_test", "not_test", "actual_not_test", "asless_actual_not_test"):
            for c in ch:
                if isinstance(c, Tree) or (isinstance(c, Token) and c.type == "NAME"):
                    if k in ("type_test", "asless_type_test") and c is ch[-1]:
                        tn = type_text(c)
                        if tn and not self.is_type_known(tn, ctx.script):
                            self.err(node, "unknown type '%s' in 'is' test" % tn)
                        continue
                    self.visit(c, ctx)
            return "bool"
        if k in ("neg_expr", "actual_neg_expr", "asless_actual_neg_expr", "asless_neg_expr", "bitw_not", "asless_bitw_not"):
            t = None
            for c in ch:
                if isinstance(c, (Tree,)) or (isinstance(c, Token) and c.type == "NAME"):
                    t = self.visit(c, ctx)
            return t
        if k in ("test_expr",):
            types = []
            for c in ch:
                if isinstance(c, Token) and str(c) in ("if", "else"):
                    continue
                types.append(self.visit(c, ctx))
            # a if cond else b
            if len(types) == 3 and types[0] is not None and types[0] == types[2]:
                return types[0]
            return None
        if k == "assnmnt_expr":
            tt = self.visit(ch[0], ctx)
            for c in ch[2:]:
                self.visit(c, ctx)
            self._check_assign_target(ch[0], ctx)
            return None
        if k == "await_expr":
            for c in ch:
                if isinstance(c, Tree):
                    self.visit(c, ctx)
            return None
        if k == "lambda":
            ctx.push()
            for c in ch:
                if isinstance(c, Tree) and c.data == "lambda_header":
                    for a in c.children:
                        if isinstance(a, Tree) and a.data == "func_args":
                            for arg in a.children:
                                if isinstance(arg, Tree):
                                    self.declare(ctx, arg, first_name(arg), None)
                elif isinstance(c, Tree):
                    self.stmt(c, ctx) if c.data.endswith("_stmt") else self.visit(c, ctx)
            ctx.pop()
            return "Callable"
        if k == "get_node":
            return None
        if k == "string":
            return "String"
        if k in ("string_name", "node_path"):
            return "StringName" if k == "string_name" else "NodePath"
        if k in ("yield_expr",):
            return None
        # unknown expression kind: walk children
        r = None
        for c in ch:
            if isinstance(c, (Tree, Token)):
                r = self.visit(c, ctx)
        return None

    def _check_assign_target(self, tgt, ctx):
        n = tgt
        while isinstance(n, Tree) and n.data == "expr" and len(n.children) == 1:
            n = n.children[0]
        if isinstance(n, Token) and n.type == "NAME":
            nm = str(n)
            kind = None
            for sc in reversed(ctx.scopes):
                if nm in sc:
                    kind = "local"
                    break
            if kind is None:
                m = self.find_member(ctx.script, nm)
                if m and m[0] in ("const", "func", "signal", "enum", "inner", "enumval", "api_method", "api_signal", "api_constant"):
                    self.err(tgt, "cannot assign to %s '%s'" % (m[0], nm))

    def _binary(self, node, ctx):
        ts = []
        ops = []
        for c in node.children:
            if isinstance(c, Token) and c.type != "NAME" and str(c) in ("+", "-", "*", "/", "%", "<<", ">>", "&", "|", "^", "**"):
                ops.append(str(c))
            else:
                ts.append(self.visit(c, ctx))
        if not ts:
            return None
        if any(t is None or t == "Variant" for t in ts):
            return None
        if all(t in ("int", "float") for t in ts):
            if "/" in ops and all(t == "int" for t in ts):
                return "int"
            return "float" if "float" in ts else "int"
        if all(t == ts[0] for t in ts) and ts[0] in ("Vector2", "Vector3", "Vector2i", "Color", "String", "Rect2", "Transform2D"):
            if "%" in ops and ts[0] == "String":
                return "String"
            return ts[0]
        if "%" in ops and ts[0] == "String":
            return "String"
        # vector * float etc.
        vec = [t for t in ts if t in ("Vector2", "Vector3", "Vector2i", "Color")]
        if vec and all(t in ("int", "float") or t in vec for t in ts):
            return vec[0]
        return None

    # --------------------------------------------------------- identifiers
    def _token(self, tok, ctx):
        tt = tok.type
        s = str(tok)
        if tt == "NAME":
            ok, typ = self.resolve_ident(s, ctx)
            if not ok:
                self.err(tok, "unknown identifier '%s'" % s)
                return None
            return typ
        if tt in ("NUMBER", "HEX_NUMBER", "BIN_NUMBER", "INT", "FLOAT", "DEC_NUMBER"):
            if s.startswith("0x") or s.startswith("0b"):
                return "int"
            if "." in s or "e" in s.lower():
                return "float"
            return "int"
        if tt in ("STRING",):
            return "String"
        if s in ("true", "false"):
            return "bool"
        if s == "null":
            return None
        if s == "self":
            return "self"
        return None

    def resolve_ident(self, name, ctx, quiet=False):
        """Returns (found, type)."""
        for sc in reversed(ctx.scopes):
            if name in sc:
                return True, sc[name]
        if name in ("true", "false"):
            return True, "bool"
        if name == "self":
            return True, "self"
        if name in ("null", "super"):
            return True, None
        if name in ("PI", "TAU", "INF", "NAN"):
            return True, "float"
        # class members (with inheritance)
        m = self.find_member(ctx.script, name)
        if m is not None:
            return True, self._member_type(m, ctx)
        # outer classes (inner class code may reference outer members/consts)
        s = ctx.script.parent
        while s is not None:
            m = self.find_member(s, name)
            if m is not None and m[0] in ("const", "enum", "enumval", "inner", "func", "api_constant"):
                return True, self._member_type(m, ctx)
            s = s.parent
        # global scope
        if name in self.autoloads or name in self.autoload_paths:
            return True, name
        if name in self.classes:
            return True, "class:" + name
        if name in self.api.classes or name in self.api.builtins:
            return True, "class:" + name
        if name in self.api.singletons:
            return True, self.api.singletons[name]
        if name in self.api.utils:
            return True, "func:" + name
        if name in self.api.global_consts or name in self.api.enum_names:
            return True, "int"
        if name in GDSCRIPT_BUILTINS:
            return True, "func:" + name
        return False, None

    def _member_type(self, m, ctx):
        kind, info = m
        if kind == "var":
            if isinstance(info, tuple) and info and info[0] == "infer":
                t = self.visit(info[1].children[1], Ctx(ctx.script, False))
                return t
            return info if isinstance(info, str) else None
        if kind == "const":
            return info if isinstance(info, str) else None
        if kind in ("enum",):
            return "enum:"
        if kind == "enumval":
            return "int"
        if kind == "api_property":
            return api_type(info.get("type"))
        if kind == "api_constant":
            return "int"
        if kind == "api_enum":
            return "enum:"
        if kind == "signal":
            return "Signal:%d" % info
        if kind == "api_signal":
            return "Signal:%d" % len(info.get("arguments", []) or [])
        if kind == "inner":
            return "class:inner"
        return None

    # --------------------------------------------------------- attribute access
    @staticmethod
    def _chain_names(node):
        """getattr chains are flat: [base, '.', n1, '.', n2 ...] -> (base, [n1, n2 ...])"""
        ch = node.children
        names = [c for c in ch[1:] if not (isinstance(c, Token) and str(c) == ".")]
        return ch[0], names

    def _getattr(self, node, ctx):
        base, names = self._chain_names(node)
        bt = self.visit(base, ctx)
        for nm in names:
            name = str(nm) if isinstance(nm, Token) else first_name(nm)
            bt = self._member_access(node, bt, name, ctx, base)
        return bt

    def _member_access(self, node, bt, name, ctx, base_node=None, is_call=False, nargs=None):
        """Type of `bt.name`, verifying that the member exists when the base type is known."""
        if bt is None or bt == "Variant":
            return None
        if bt == "self":
            m = self.find_member(ctx.script, name)
            if m is None:
                self.err(node, "self has no member '%s'" % name)
                return None
            return self._member_type(m, ctx)
        if bt.startswith("class:"):
            cname = bt[len("class:"):]
            # static access on a class: constants, enums, static funcs, .new
            if cname == "inner":
                return None
            if name == "new" and is_call:
                return cname
            if cname in self.classes:
                si = self.classes[cname]
                m = self.find_member(si, name)
                if m is None:
                    if name in ("new",):
                        return cname
                    self.err(node, "class %s has no member '%s'" % (cname, name))
                    return None
                if m[0] == "enum":
                    return "enum:%s.%s" % (cname, name)
                return self._member_type(m, ctx) if m[0] != "func" else "func:%s.%s" % (cname, name)
            if cname in self.api.classes:
                mm = self.api.members(cname).get(name)
                if mm is None:
                    self.err(node, "engine class %s has no member '%s' (in %s)" % (cname, name, self.api.version))
                    return None
                if mm[0] == "constant":
                    return "int"
                if mm[0] == "enum":
                    return "enum:%s.%s" % (cname, name)
                if mm[0] == "method":
                    return "func:%s.%s" % (cname, name)
                return api_type(mm[1].get("type"))
            if cname in self.api.builtins:
                mm = self.api.builtin_members(cname).get(name)
                if mm is None:
                    self.err(node, "builtin type %s has no member '%s'" % (cname, name))
                    return None
                if mm[0] == "constant":
                    return cname if mm[1].get("type") == cname else api_type(mm[1].get("type"))
                if mm[0] == "enum":
                    return "enum:%s.%s" % (cname, name)
                return "func:%s.%s" % (cname, name)
            return None
        if bt.startswith("enum:"):
            return "int"
        if bt.startswith("func:"):
            return None
        # instance access
        info = self.class_of_type(bt)
        if info is None:
            return None
        kind, target = info
        if kind == "project":
            m = self.find_member(target, name)
            if m is None:
                self.err(node, "%s has no member '%s'" % (bt, name))
                return None
            if m[0] == "func":
                return "func:%s.%s" % (bt, name)
            return self._member_type(m, ctx)
        if kind == "engine":
            mm = self.api.members(target).get(name)
            if mm is None:
                self.err(node, "engine class %s has no member '%s' (in %s)" % (target, name, self.api.version))
                return None
            if mm[0] == "method":
                return "func:%s.%s" % (target, name)
            if mm[0] == "property":
                return api_type(mm[1].get("type"))
            if mm[0] == "signal":
                return "Signal:%d" % len(mm[1].get("arguments", []) or [])
            if mm[0] == "constant":
                return "int"
            return None
        if kind == "builtin":
            mm = self.api.builtin_members(target).get(name)
            if mm is None:
                if target in ("Array", "Dictionary", "Object"):
                    return None
                self.err(node, "builtin type %s has no member '%s'" % (target, name))
                return None
            if mm[0] == "member":
                return api_type(mm[1].get("type"))
            if mm[0] == "method":
                return "func:%s.%s" % (target, name)
            return None
        return None

    # --------------------------------------------------------- calls
    def _call_args(self, node, start, ctx):
        types = []
        for c in node.children[start:]:
            types.append(self.visit(c, ctx))
        return types

    def _func_call(self, node, ctx):
        """standalone_call: name(args)"""
        name = str(node.children[0]) if isinstance(node.children[0], Token) else first_name(node.children[0])
        nargs = len(node.children) - 1
        # visit args
        self._call_args(node, 1, ctx)
        if name == "preload":
            self._check_preload(node)
            return "Resource"
        if name == "load":
            return "Resource"
        # local callable?
        for sc in reversed(ctx.scopes):
            if name in sc:
                return None
        m = self.find_member(ctx.script, name)
        if m is not None:
            kind, info = m
            if kind == "func":
                req, mx = info.arity()
                if not (req <= nargs <= mx):
                    self.err(node, "%s() takes %s argument(s), %d given" % (name, (str(req) if req == mx else "%d-%d" % (req, mx)), nargs))
                if ctx.static and not info.static:
                    self.err(node, "static function cannot call instance method '%s'" % name)
                return info.ret if info.ret not in (None, "void") else None
            if kind == "api_method":
                mm = info
                args = mm.get("arguments", []) or []
                if not arity_ok(args, nargs, mm.get("is_vararg", False)):
                    self.err(node, "%s() takes %d..%d argument(s), %d given" % (name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
                rv = mm.get("return_value")
                return api_type(rv["type"]) if rv else None
            # calling something else (callable var/signal...)
            return None
        # global: builtin type constructor?
        if name in self.api.builtins:
            b = self.api.builtins[name]
            ctors = b.get("constructors", []) or []
            ok = False
            for c in ctors:
                if len(c.get("arguments", []) or []) == nargs:
                    ok = True
            if ctors and not ok:
                self.err(node, "no constructor of %s takes %d argument(s)" % (name, nargs))
            return name
        if name in self.classes:
            return name
        if name in self.api.utils:
            u = self.api.utils[name]
            args = u.get("arguments", []) or []
            if not arity_ok(args, nargs, u.get("is_vararg", False)):
                self.err(node, "%s() takes %d..%d argument(s), %d given" % (name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
            return api_type(u.get("return_type"))
        if name in GDSCRIPT_BUILTINS:
            lo, hi, ret = GDSCRIPT_BUILTINS[name]
            if not (lo <= nargs and (hi is None or nargs <= hi)):
                self.err(node, "%s() takes %s argument(s), %d given" % (name, "%d-%s" % (lo, hi if hi is not None else "n"), nargs))
            return ret
        if name in ("super",):
            return None
        self.err(node, "unknown function '%s'" % name)
        return None

    def _check_preload(self, node):
        arg = node.children[1] if len(node.children) > 1 else None
        s = None
        n = arg
        while isinstance(n, Tree) and len(n.children) == 1:
            n = n.children[0]
        if isinstance(n, Token):
            s = str(n).strip('"').strip("'")
        elif isinstance(n, Tree) and n.data == "string":
            s = str(n.children[0]).strip('"')
        if s and s.startswith("res://"):
            p = os.path.join(self.root, s.replace("res://", ""))
            if not os.path.exists(p):
                self.err(node, "preload path does not exist: %s" % s)

    def _method_call(self, node, ctx):
        """getattr_call: getattr(base . n1 . ... . method) args..."""
        ga = node.children[0]
        base, names = self._chain_names(ga)
        nargs = len(node.children) - 1
        arg_types = self._call_args(node, 1, ctx)
        bt = self.visit(base, ctx)
        for nm in names[:-1]:
            nm_s = str(nm) if isinstance(nm, Token) else first_name(nm)
            bt = self._member_access(ga, bt, nm_s, ctx, base)
        last = names[-1]
        name = str(last) if isinstance(last, Token) else first_name(last)
        if bt is not None and bt.startswith("Signal"):
            return self._signal_call(node, bt, name, nargs, ctx)
        if bt is None or bt == "Variant":
            return None
        if bt.startswith("class:"):
            cname = bt[len("class:"):]
            if name == "new":
                if cname in self.classes:
                    si = self.classes[cname]
                    init = self._find_init(si)
                    if init is not None:
                        req, mx = init.arity()
                        if not (req <= nargs <= mx):
                            self.err(node, "%s.new() takes %d..%d argument(s), %d given" % (cname, req, mx, nargs))
                    elif nargs > 0:
                        self.err(node, "%s.new() takes no arguments, %d given" % (cname, nargs))
                return cname
            return self._static_call(node, cname, name, nargs, ctx)
        if bt == "self":
            m = self.find_member(ctx.script, name)
            if m is None:
                self.err(node, "self has no method '%s'" % name)
                return None
            return self._check_member_call(node, m, name, nargs, ctx)
        info = self.class_of_type(bt)
        if info is None:
            return None
        kind, target = info
        if kind == "project":
            m = self.find_member(target, name)
            if m is None:
                self.err(node, "%s has no method '%s'" % (bt, name))
                return None
            return self._check_member_call(node, m, name, nargs, ctx)
        if kind == "engine":
            mm = self.api.members(target).get(name)
            if mm is None:
                if name in IMPLICIT_OBJECT_METHODS:
                    return None
                self.err(node, "engine class %s has no method '%s' (in %s)" % (target, name, self.api.version))
                return None
            if mm[0] == "method":
                args = mm[1].get("arguments", []) or []
                if not arity_ok(args, nargs, mm[1].get("is_vararg", False)):
                    self.err(node, "%s.%s() takes %d..%d argument(s), %d given" % (target, name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
                rv = mm[1].get("return_value")
                return api_type(rv["type"]) if rv else None
            return None
        if kind == "builtin":
            mm = self.api.builtin_members(target).get(name)
            if mm is None:
                if target in ("Array", "Dictionary") and name in ("size",):
                    return "int"
                self.err(node, "builtin type %s has no method '%s'" % (target, name))
                return None
            if mm[0] == "method":
                args = mm[1].get("arguments", []) or []
                if not arity_ok(args, nargs, mm[1].get("is_vararg", False)):
                    self.err(node, "%s.%s() takes %d..%d argument(s), %d given" % (target, name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
                rt = mm[1].get("return_type")
                return api_type(rt) if rt else None
        return None

    def _find_init(self, si):
        cur = si
        seen = 0
        while isinstance(cur, ScriptInfo) and seen < 20:
            if "_init" in cur.funcs:
                return cur.funcs["_init"]
            cur = self.resolve_base(cur)
            seen += 1
        return None

    def _signal_call(self, node, sig_type, name, nargs, ctx):
        arity = -1
        if ":" in sig_type:
            try:
                arity = int(sig_type.split(":")[1])
            except ValueError:
                arity = -1
        if name == "emit" and arity >= 0 and arity != nargs:
            self.err(node, "signal takes %d argument(s), emit() given %d" % (arity, nargs))
        elif name not in ("emit", "connect", "disconnect", "is_connected", "get_name", "get_object", "get_connections", "is_null", "has_connections", "get_object_id", "is_valid"):
            self.err(node, "Signal has no method '%s'" % name)
        elif name == "connect" and not (1 <= nargs <= 2):
            self.err(node, "Signal.connect() takes 1..2 arguments, %d given" % nargs)
        return None

    def _static_call(self, node, cname, name, nargs, ctx):
        if cname in self.classes:
            si = self.classes[cname]
            m = self.find_member(si, name)
            if m is None:
                self.err(node, "class %s has no member '%s'" % (cname, name))
                return None
            if m[0] == "func":
                if not m[1].static:
                    self.err(node, "%s.%s() is not static" % (cname, name))
                req, mx = m[1].arity()
                if not (req <= nargs <= mx):
                    self.err(node, "%s.%s() takes %d..%d argument(s), %d given" % (cname, name, req, mx, nargs))
                return m[1].ret if m[1].ret not in (None, "void") else None
            return None
        if cname in self.api.classes:
            mm = self.api.members(cname).get(name)
            if mm is None:
                if name in IMPLICIT_OBJECT_METHODS:
                    return None
                self.err(node, "engine class %s has no method '%s' (in %s)" % (cname, name, self.api.version))
                return None
            if mm[0] == "method":
                args = mm[1].get("arguments", []) or []
                if not arity_ok(args, nargs, mm[1].get("is_vararg", False)):
                    self.err(node, "%s.%s() takes %d..%d argument(s), %d given" % (cname, name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
                rv = mm[1].get("return_value")
                return api_type(rv["type"]) if rv else None
            return None
        if cname in self.api.builtins:
            mm = self.api.builtin_members(cname).get(name)
            if mm is None:
                self.err(node, "builtin type %s has no member '%s'" % (cname, name))
                return None
            if mm[0] == "method":
                args = mm[1].get("arguments", []) or []
                if not arity_ok(args, nargs, mm[1].get("is_vararg", False)):
                    self.err(node, "%s.%s() takes %d..%d argument(s), %d given" % (cname, name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
                rt = mm[1].get("return_type")
                return api_type(rt) if rt else None
        return None

    def _check_member_call(self, node, m, name, nargs, ctx):
        kind, info = m
        if kind == "func":
            req, mx = info.arity()
            if not (req <= nargs <= mx):
                self.err(node, "%s() takes %s argument(s), %d given" % (name, (str(req) if req == mx else "%d-%d" % (req, mx)), nargs))
            return info.ret if info.ret not in (None, "void") else None
        if kind == "api_method":
            args = info.get("arguments", []) or []
            if not arity_ok(args, nargs, info.get("is_vararg", False)):
                self.err(node, "%s() takes %d..%d argument(s), %d given" % (name, sum(1 for a in args if 'default_value' not in a), len(args), nargs))
            rv = info.get("return_value")
            return api_type(rv["type"]) if rv else None
        return None


class Ctx:
    def __init__(self, script, static):
        self.script = script
        self.static = static
        self.scopes = []
        self.func_name = None
        self.ret = None

    def push(self):
        self.scopes.append({})

    def pop(self):
        self.scopes.pop()


# functions provided by the GDScript compiler itself (not in utility_functions)
GDSCRIPT_BUILTINS = {
    "preload": (1, 1, "Resource"),
    "assert": (1, 2, None),
    "range": (1, 3, "Array"),
    "len": (1, 1, "int"),
    "char": (1, 1, "String"),
    "ord": (1, 1, "int"),
    "convert": (2, 2, None),
    "type_exists": (1, 1, "bool"),
    "is_instance_of": (2, 2, "bool"),
    "get_stack": (0, 0, "Array"),
    "print_debug": (0, None, None),
    "print_stack": (0, 0, None),
    "inst_to_dict": (1, 1, "Dictionary"),
    "dict_to_inst": (1, 1, None),
    "is_instance_valid": (1, 1, "bool"),
    "load": (1, 1, "Resource"),
    "super": (0, None, None),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", required=True, help="extension_api.json (godot --headless --dump-extension-api)")
    ap.add_argument("--project", default=".", help="folder containing project.godot")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("dirs", nargs="*", help="folders (relative to --project) to scan; default: whole project")
    args = ap.parse_args()
    api = Api(args.api)
    root = os.path.abspath(args.project)
    dirs = args.dirs or ["."]
    files = []
    for d in dirs:
        files += glob.glob(os.path.join(root, d, "**", "*.gd"), recursive=True)
    files = sorted(set(files))
    chk = Checker(api, root, args.verbose)
    chk.load_project(files)
    chk.check_all()
    for f, l, m in sorted(chk.errors):
        print("ERROR   %s:%s: %s" % (os.path.relpath(f, root), l, m))
    for f, l, m in sorted(chk.warnings):
        print("warning %s:%s: %s" % (os.path.relpath(f, root), l, m))
    print("%d file(s), %d error(s), %d warning(s)  [API %s]" % (len(files), len(chk.errors), len(chk.warnings), api.version))
    sys.exit(min(len(chk.errors), 100))


if __name__ == "__main__":
    main()
