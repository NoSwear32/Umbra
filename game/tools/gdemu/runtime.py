"""
Runtime for gdemu: the parts of GDScript / the engine API that the engine-independent scripts use.

Only what the project needs is implemented; anything else raises GDError with a clear message
(so a gap is visible instead of silently wrong). Numbers follow GDScript: `/` on two ints is an
integer division, `%` follows the dividend's sign, floats are IEEE doubles, typed float variables
convert ints to floats.
"""
import base64
import functools
import json as _pyjson
import math
import os
import random as _random
import shutil
import struct
import sys
import time as _time
import zlib

INT_MAX = 0x7FFFFFFFFFFFFFFF
INT_MIN = -0x8000000000000000


class GDError(Exception):
    """A runtime error the engine would report (invalid call, null access, ...)."""


_U = object()          # "argument not passed" sentinel


# ------------------------------------------------------------------------------------------ numbers
def _f(x):
    """Implicit int -> float conversion of typed float variables, parameters and returns."""
    return float(x) if type(x) is int else x


def _like(old, new):
    """Assignment to a variable whose type was inferred (:=): ints become floats if it holds a float."""
    if type(old) is float and type(new) is int:
        return float(new)
    return new


def _div(a, b):
    if type(a) is int and type(b) is int:
        if b == 0:
            raise GDError("Division by zero error in operator '/'.")
        q = abs(a) // abs(b)
        return q if (a >= 0) == (b >= 0) else -q
    try:
        return a / b
    except ZeroDivisionError:
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            if a == 0 or a != a:
                return math.nan
            return math.inf if (a > 0) == (math.copysign(1.0, b) > 0) else -math.inf
        raise


def _mod(a, b):
    if type(a) is str:
        return _format(a, b)
    if type(a) is int and type(b) is int:
        if b == 0:
            raise GDError("Modulo by zero error in operator '%'.")
        r = abs(a) % abs(b)
        return r if a >= 0 else -r
    raise GDError("Invalid operands '%s' and '%s' in operator '%%'." % (type(a).__name__, type(b).__name__))


def _wrap64(v):
    v &= 0xFFFFFFFFFFFFFFFF
    return v - (1 << 64) if v >= (1 << 63) else v


def _shl(a, b):
    if type(a) is int and type(b) is int:
        return _wrap64(a << b) if 0 <= b < 64 else 0
    raise GDError("Invalid operands for '<<'.")


def _pow(a, b):
    if type(a) is int and type(b) is int and b >= 0:
        return _wrap64(a ** b)
    return float(a) ** float(b)


def _fnum(x):
    if x != x:
        return "nan"
    if x in (math.inf, -math.inf):
        return "inf" if x > 0 else "-inf"
    s = "%.14g" % x
    if "e" not in s and "." not in s:
        s += ".0"
    return s


def _str(x):
    t = type(x)
    if t is str:
        return x
    if x is None:
        return "<null>"
    if t is bool:
        return "true" if x else "false"
    if t is int:
        return str(x)
    if t is float:
        return _fnum(x)
    if isinstance(x, list) and not isinstance(x, PackedArray):
        return "[" + ", ".join(_str(e) for e in x) + "]"
    if isinstance(x, PackedArray):
        return "[" + ", ".join(_str(e) for e in x) + "]"
    if isinstance(x, dict):
        return "{ " + ", ".join("%s: %s" % (_repr(k), _repr(v)) for k, v in x.items()) + " }"
    return str(x)


def _repr(x):
    return '"%s"' % x if type(x) is str else _str(x)


def _format(fmt, b):
    args = tuple(b) if isinstance(b, list) else (b,)
    conv = []
    for a in args:
        if type(a) is bool:
            conv.append("true" if a else "false")
        elif a is None:
            conv.append("<null>")
        elif isinstance(a, (list, dict)) or isinstance(a, Object) or isinstance(a, (Vector2, Vector3)):
            conv.append(_str(a))
        else:
            conv.append(a)
    try:
        return fmt % tuple(conv)
    except (TypeError, ValueError) as e:
        raise GDError("String formatting error: %s (format %r)" % (e, fmt))


import keyword as _keyword


def _mangle(name):
    """Member names that are Python keywords get a trailing underscore (see transpile.mangle_attr)."""
    return name + "_" if _keyword.iskeyword(name) else name


# ------------------------------------------------------------------------------------- type names
def typeof(x):
    t = type(x)
    if x is None:
        return 0
    if t is bool:
        return 1
    if t is int:
        return 2
    if t is float:
        return 3
    if t is str:
        return 4
    if t is Vector2:
        return 5
    if t is Vector2i:
        return 6
    if t is Rect2:
        return 7
    if t is Rect2i:
        return 8
    if t is Vector3:
        return 9
    if t is Vector4:
        return 12
    if t is Color:
        return 20
    if isinstance(x, Object):
        return 24
    if t is Callable:
        return 25
    if isinstance(x, Dictionary):
        return 27
    if isinstance(x, Array):
        return 28
    if isinstance(x, PackedByteArray):
        return 29
    if isinstance(x, PackedInt32Array):
        return 30
    if isinstance(x, PackedFloat32Array):
        return 32
    if isinstance(x, PackedStringArray):
        return 34
    raise GDError("typeof: unsupported value %r" % (x,))


TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING = 0, 1, 2, 3, 4
TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3 = 5, 6, 7, 8, 9
TYPE_VECTOR4, TYPE_COLOR, TYPE_OBJECT, TYPE_CALLABLE = 12, 20, 24, 25
TYPE_DICTIONARY, TYPE_ARRAY = 27, 28
TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_STRING_ARRAY = 29, 30, 32, 34

_TYPE_BY_NAME = {
    "int": lambda x: type(x) is int,
    "float": lambda x: type(x) is float,
    "bool": lambda x: type(x) is bool,
    "String": lambda x: type(x) is str,
    "StringName": lambda x: type(x) is str,
    "Variant": lambda x: True,
}


class GDScript:
    """Type name only: every transpiled script class counts as a GDScript resource."""


def _is_script(x):
    return isinstance(x, type) and issubclass(x, Object)


def _is(x, t):
    if t is GDScript:
        return _is_script(x)
    if isinstance(t, str):
        f = _TYPE_BY_NAME.get(t)
        if f is None:
            raise GDError("'is' test against unsupported type '%s'" % t)
        return f(x)
    if t is None:
        return False
    if isinstance(t, type):
        if t in (Array, Dictionary, Vector2, Vector3, Vector4, Rect2, Color, PackedByteArray, PackedInt32Array, PackedFloat32Array, PackedStringArray):
            return type(x) is t or isinstance(x, t)
        return isinstance(x, t)
    raise GDError("'is' test against unsupported type %r" % (t,))


def _as(x, t):
    if t is GDScript:
        return x if _is_script(x) else None
    if isinstance(t, str):
        if t == "int":
            return int(x) if isinstance(x, (int, float)) else None
        if t == "float":
            return float(x) if isinstance(x, (int, float)) else None
        if t in ("String", "StringName"):
            return _str(x)
        if t == "bool":
            return bool(x)
        return x
    if isinstance(x, t):
        return x
    return None


# ------------------------------------------------------------------------------------ collections
class Array(list):
    def __add__(self, other):
        return Array(list.__add__(self, list(other)))

    def size(self):
        return len(self)

    def is_empty(self):
        return len(self) == 0

    def has(self, x):
        return x in self

    def duplicate(self, deep=False):
        if deep:
            return Array(_deep(e) for e in self)
        return Array(self)

    def append_array(self, other):
        self.extend(other)

    def push_back(self, x):
        self.append(x)

    def push_front(self, x):
        self.insert(0, x)

    def pop_back(self):
        return self.pop()

    def pop_front(self):
        return self.pop(0)

    def pop_at(self, i):
        return self.pop(i)

    def find(self, x, start=0):
        try:
            return self.index(x, start)
        except ValueError:
            return -1

    def erase(self, x):
        try:
            list.remove(self, x)
        except ValueError:
            pass

    def remove_at(self, i):
        del self[i]

    def fill(self, v):
        for i in range(len(self)):
            self[i] = v

    def resize(self, n, fill=None):
        if n < len(self):
            del self[n:]
        else:
            self.extend([fill] * (n - len(self)))
        return 0

    def slice(self, begin, end=INT_MAX, step=1, deep=False):
        n = len(self)
        b = begin + n if begin < 0 else begin
        e = end + n if end < 0 else min(end, n)
        return Array(self[b:e:step])

    def front(self):
        return self[0]

    def back(self):
        return self[-1]

    def sort_custom(self, cb):
        self.sort(key=functools.cmp_to_key(lambda a, b: -1 if cb(a, b) else (1 if cb(b, a) else 0)))

    def map(self, cb):
        return Array(cb(e) for e in self)

    def filter(self, cb):
        return Array(e for e in self if cb(e))

    def any(self, cb):
        return any(cb(e) for e in self)

    def all(self, cb):
        return all(cb(e) for e in self)

    def max(self):
        return max(self) if self else None

    def min(self):
        return min(self) if self else None

    def assign(self, other):
        self[:] = list(other)

    def hash(self):
        return hash(tuple(self)) & 0xFFFFFFFF

    def reverse(self):
        list.reverse(self)


class Dictionary(dict):
    def has(self, k):
        return k in self

    def has_all(self, keys):
        return all(k in self for k in keys)

    def keys(self):
        return Array(dict.keys(self))

    def values(self):
        return Array(dict.values(self))

    def size(self):
        return len(self)

    def is_empty(self):
        return len(self) == 0

    def erase(self, k):
        return self.pop(k, _U) is not _U

    def duplicate(self, deep=False):
        if deep:
            return Dictionary((k, _deep(v)) for k, v in self.items())
        return Dictionary(self)

    def merge(self, other, overwrite=False):
        for k, v in other.items():
            if overwrite or k not in self:
                self[k] = v

    def get_or_add(self, k, default=None):
        if k not in self:
            self[k] = default
        return self[k]

    def find_key(self, v):
        for k, x in self.items():
            if x == v:
                return k
        return None

    def get(self, k, default=None):
        return dict.get(self, k, default)


def _deep(x):
    if isinstance(x, Dictionary):
        return x.duplicate(True)
    if isinstance(x, Array):
        return x.duplicate(True)
    return x


class PackedArray(list):
    _kind = None

    def __add__(self, other):
        return type(self)(list(self) + list(other))

    def __init__(self, src=None):
        list.__init__(self)
        if src is not None:
            self.extend(src)

    def size(self):
        return len(self)

    def is_empty(self):
        return len(self) == 0

    def push_back(self, x):
        self.append(x)

    def append(self, x):
        list.append(self, self._conv(x))

    def extend(self, it):
        list.extend(self, (self._conv(x) for x in it))

    def append_array(self, other):
        self.extend(other)

    def __setitem__(self, i, v):
        list.__setitem__(self, i, self._conv(v))

    @staticmethod
    def _conv(x):
        return x

    def has(self, x):
        return x in self

    def find(self, x, start=0):
        try:
            return self.index(x, start)
        except ValueError:
            return -1

    def duplicate(self):
        return type(self)(self)

    def slice(self, begin, end=INT_MAX):
        n = len(self)
        b = begin + n if begin < 0 else begin
        e = end + n if end < 0 else min(end, n)
        return type(self)(list.__getitem__(self, slice(b, e)))

    def resize(self, n):
        if n < len(self):
            del self[n:]
        else:
            self.extend([self._zero()] * (n - len(self)))
        return 0

    def _zero(self):
        return 0

    def fill(self, v):
        for i in range(len(self)):
            self[i] = v

    def remove_at(self, i):
        del self[i]

    def clear(self):
        list.clear(self)

    def __eq__(self, other):
        return isinstance(other, PackedArray) and list.__eq__(self, other)

    def __ne__(self, other):
        return not self.__eq__(other)

    __hash__ = None


class PackedInt32Array(PackedArray):
    @staticmethod
    def _conv(x):
        if type(x) is not int:
            if type(x) is float:
                return int(x)
            raise GDError("PackedInt32Array element must be an int, got %r" % (x,))
        return ((x + 0x80000000) & 0xFFFFFFFF) - 0x80000000


class PackedInt64Array(PackedInt32Array):
    @staticmethod
    def _conv(x):
        return int(x)


class PackedFloat32Array(PackedArray):
    @staticmethod
    def _conv(x):
        return struct.unpack("f", struct.pack("f", float(x)))[0]

    def _zero(self):
        return 0.0


class PackedFloat64Array(PackedArray):
    @staticmethod
    def _conv(x):
        return float(x)

    def _zero(self):
        return 0.0


class PackedStringArray(PackedArray):
    @staticmethod
    def _conv(x):
        return x

    def _zero(self):
        return ""


class PackedVector2Array(PackedArray):
    @staticmethod
    def _conv(x):
        return x

    def _zero(self):
        return Vector2()

    def resize(self, n):
        if n < len(self):
            del self[n:]
        else:
            self.extend([Vector2() for _ in range(n - len(self))])
        return 0


class PackedVector3Array(PackedVector2Array):
    def _zero(self):
        return Vector3()


class PackedColorArray(PackedVector2Array):
    def _zero(self):
        return Color()


class PackedByteArray(bytearray):
    def __init__(self, src=None):
        bytearray.__init__(self)
        if src is not None:
            self.extend(src)

    def size(self):
        return len(self)

    def is_empty(self):
        return len(self) == 0

    def push_back(self, x):
        self.append(x)

    def append_array(self, other):
        self.extend(other)

    def slice(self, begin, end=INT_MAX):
        n = len(self)
        b = begin + n if begin < 0 else begin
        e = end + n if end < 0 else min(end, n)
        return PackedByteArray(bytearray.__getitem__(self, slice(b, e)))

    def duplicate(self):
        return PackedByteArray(self)

    def resize(self, n):
        if n < len(self):
            del self[n:]
        else:
            self.extend(bytes(n - len(self)))
        return 0

    def compress(self, mode=1):
        if mode not in (1, 3):
            raise GDError("gdemu: only DEFLATE/GZIP compression is emulated")
        return PackedByteArray(zlib.compress(bytes(self)))

    def decompress(self, buffer_size, mode=1):
        try:
            data = zlib.decompress(bytes(self))
        except zlib.error:
            return PackedByteArray()
        return PackedByteArray(data)

    def get_string_from_utf8(self):
        return bytes(self).decode("utf-8", errors="replace")

    def has(self, x):
        return x in self

    def to_int32_array(self):
        return PackedInt32Array(struct.unpack("<%di" % (len(self) // 4), bytes(self)[: len(self) // 4 * 4]))

    def __eq__(self, other):
        return isinstance(other, bytearray) and bytes(self) == bytes(other)

    def __ne__(self, other):
        return not self.__eq__(other)

    __hash__ = None


# --------------------------------------------------------------------------------------- vectors
class Vector2:
    __slots__ = ("x", "y")

    def __init__(self, x=0.0, y=0.0):
        if isinstance(x, Vector2i):
            x, y = x.x, x.y
        self.x = float(x)
        self.y = float(y)

    def __add__(self, o):
        return Vector2(self.x + o.x, self.y + o.y)

    def __sub__(self, o):
        return Vector2(self.x - o.x, self.y - o.y)

    def __mul__(self, o):
        if isinstance(o, Vector2):
            return Vector2(self.x * o.x, self.y * o.y)
        return Vector2(self.x * o, self.y * o)

    __rmul__ = __mul__

    def __truediv__(self, o):
        if isinstance(o, Vector2):
            return Vector2(self.x / o.x, self.y / o.y)
        return Vector2(self.x / o, self.y / o)

    def __neg__(self):
        return Vector2(-self.x, -self.y)

    def __eq__(self, o):
        return isinstance(o, Vector2) and self.x == o.x and self.y == o.y

    def __hash__(self):
        return hash((self.x, self.y))

    def __repr__(self):
        return "(%s, %s)" % (_fnum(self.x), _fnum(self.y))

    def length(self):
        return math.hypot(self.x, self.y)

    def length_squared(self):
        return self.x * self.x + self.y * self.y

    def normalized(self):
        l = self.length()
        return Vector2(self.x / l, self.y / l) if l else Vector2()

    def dot(self, o):
        return self.x * o.x + self.y * o.y

    def distance_to(self, o):
        return (self - o).length()

    def lerp(self, o, t):
        return Vector2(self.x + (o.x - self.x) * t, self.y + (o.y - self.y) * t)

    def is_equal_approx(self, o):
        return is_equal_approx(self.x, o.x) and is_equal_approx(self.y, o.y)

    def abs(self):
        return Vector2(abs(self.x), abs(self.y))

    def duplicate(self):
        return Vector2(self.x, self.y)




class Vector2i:
    __slots__ = ("x", "y")

    def __init__(self, x=0, y=0):
        self.x = int(x)
        self.y = int(y)

    def __eq__(self, o):
        return isinstance(o, Vector2i) and self.x == o.x and self.y == o.y

    def __hash__(self):
        return hash((self.x, self.y))

    def __add__(self, o):
        return Vector2i(self.x + o.x, self.y + o.y)

    def __sub__(self, o):
        return Vector2i(self.x - o.x, self.y - o.y)

    def __repr__(self):
        return "(%d, %d)" % (self.x, self.y)


Vector2i.ZERO = Vector2i(0, 0)
Vector2.ZERO = Vector2(0.0, 0.0)
Vector2.ONE = Vector2(1.0, 1.0)
Vector2.LEFT = Vector2(-1.0, 0.0)
Vector2.RIGHT = Vector2(1.0, 0.0)
Vector2.UP = Vector2(0.0, -1.0)
Vector2.DOWN = Vector2(0.0, 1.0)


class Vector3:
    __slots__ = ("x", "y", "z")

    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)

    def __add__(self, o):
        return Vector3(self.x + o.x, self.y + o.y, self.z + o.z)

    def __sub__(self, o):
        return Vector3(self.x - o.x, self.y - o.y, self.z - o.z)

    def __mul__(self, o):
        if isinstance(o, Vector3):
            return Vector3(self.x * o.x, self.y * o.y, self.z * o.z)
        return Vector3(self.x * o, self.y * o, self.z * o)

    __rmul__ = __mul__

    def __truediv__(self, o):
        return Vector3(self.x / o, self.y / o, self.z / o)

    def __neg__(self):
        return Vector3(-self.x, -self.y, -self.z)

    def __eq__(self, o):
        return isinstance(o, Vector3) and self.x == o.x and self.y == o.y and self.z == o.z

    def __hash__(self):
        return hash((self.x, self.y, self.z))

    def __repr__(self):
        return "(%s, %s, %s)" % (_fnum(self.x), _fnum(self.y), _fnum(self.z))

    def length(self):
        return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)

    def length_squared(self):
        return self.x * self.x + self.y * self.y + self.z * self.z

    def normalized(self):
        l = self.length()
        return Vector3(self.x / l, self.y / l, self.z / l) if l else Vector3()

    def dot(self, o):
        return self.x * o.x + self.y * o.y + self.z * o.z


Vector3.ZERO = Vector3(0.0, 0.0, 0.0)


class Vector4:
    __slots__ = ("x", "y", "z", "w")

    def __init__(self, x=0.0, y=0.0, z=0.0, w=0.0):
        self.x = float(x)
        self.y = float(y)
        self.z = float(z)
        self.w = float(w)

    def __eq__(self, o):
        return isinstance(o, Vector4) and (self.x, self.y, self.z, self.w) == (o.x, o.y, o.z, o.w)

    def __hash__(self):
        return hash((self.x, self.y, self.z, self.w))

    def __repr__(self):
        return "(%s, %s, %s, %s)" % tuple(_fnum(v) for v in (self.x, self.y, self.z, self.w))


class Rect2:
    __slots__ = ("position", "size")

    def __init__(self, a=None, b=None, c=None, d=None):
        if a is None:
            self.position, self.size = Vector2(), Vector2()
        elif isinstance(a, Vector2):
            self.position, self.size = a, b
        else:
            self.position, self.size = Vector2(a, b), Vector2(c, d)

    @property
    def end(self):
        return self.position + self.size

    def has_point(self, p):
        return (p.x >= self.position.x and p.y >= self.position.y
                and p.x < self.position.x + self.size.x and p.y < self.position.y + self.size.y)

    def grow(self, amount):
        return Rect2(self.position.x - amount, self.position.y - amount, self.size.x + 2 * amount, self.size.y + 2 * amount)

    def intersection(self, b):
        x1, y1 = max(self.position.x, b.position.x), max(self.position.y, b.position.y)
        x2 = min(self.position.x + self.size.x, b.position.x + b.size.x)
        y2 = min(self.position.y + self.size.y, b.position.y + b.size.y)
        if x2 <= x1 or y2 <= y1:
            return Rect2()
        return Rect2(x1, y1, x2 - x1, y2 - y1)

    def intersects(self, b, include_borders=False):
        return not self.intersection(b).size == Vector2()

    def merge(self, b):
        x1, y1 = min(self.position.x, b.position.x), min(self.position.y, b.position.y)
        x2 = max(self.position.x + self.size.x, b.position.x + b.size.x)
        y2 = max(self.position.y + self.size.y, b.position.y + b.size.y)
        return Rect2(x1, y1, x2 - x1, y2 - y1)

    def expand(self, v):
        return self.merge(Rect2(v.x, v.y, 0.0, 0.0))

    def has_area(self):
        return self.size.x > 0 and self.size.y > 0

    def get_area(self):
        return self.size.x * self.size.y

    def get_center(self):
        return self.position + self.size * 0.5

    def __eq__(self, o):
        return isinstance(o, Rect2) and self.position == o.position and self.size == o.size

    def __hash__(self):
        return hash((self.position, self.size))

    def __repr__(self):
        return "[P: %r, S: %r]" % (self.position, self.size)


class Rect2i:
    __slots__ = ("position", "size")

    def __init__(self, a=None, b=None, c=None, d=None):
        if a is None:
            self.position, self.size = Vector2i(), Vector2i()
        elif isinstance(a, Vector2i):
            self.position, self.size = a, b
        else:
            self.position, self.size = Vector2i(a, b), Vector2i(c, d)

    def __eq__(self, o):
        return isinstance(o, Rect2i) and self.position == o.position and self.size == o.size


class Color:
    __slots__ = ("r", "g", "b", "a")

    def __init__(self, r=0.0, g=0.0, b=0.0, a=1.0):
        if isinstance(r, Color):
            r, g, b, a = r.r, r.g, r.b, (g if isinstance(g, (int, float)) else r.a)
        elif isinstance(r, str):
            c = Color.html(r)
            r, g, b, a = c.r, c.g, c.b, c.a
        self.r, self.g, self.b, self.a = float(r), float(g), float(b), float(a)

    @staticmethod
    def html(s):
        s = s.lstrip("#")
        if len(s) == 3:
            s = "".join(ch * 2 for ch in s)
        v = [int(s[i:i + 2], 16) / 255.0 for i in range(0, len(s), 2)]
        if len(v) == 3:
            v.append(1.0)
        return Color(*v)

    @staticmethod
    def html_is_valid(s):
        s = s.lstrip("#")
        return len(s) in (3, 4, 6, 8) and all(c in "0123456789abcdefABCDEF" for c in s)

    def is_equal_approx(self, o):
        return all(is_equal_approx(a, b) for a, b in ((self.r, o.r), (self.g, o.g), (self.b, o.b), (self.a, o.a)))

    def lerp(self, o, t):
        return Color(self.r + (o.r - self.r) * t, self.g + (o.g - self.g) * t, self.b + (o.b - self.b) * t, self.a + (o.a - self.a) * t)

    def darkened(self, amount):
        return Color(self.r * (1.0 - amount), self.g * (1.0 - amount), self.b * (1.0 - amount), self.a)

    def lightened(self, amount):
        return Color(self.r + (1.0 - self.r) * amount, self.g + (1.0 - self.g) * amount, self.b + (1.0 - self.b) * amount, self.a)

    def __repr__(self):
        return "(%s, %s, %s, %s)" % tuple(_fnum(v) for v in (self.r, self.g, self.b, self.a))

    def __eq__(self, o):
        return isinstance(o, Color) and (self.r, self.g, self.b, self.a) == (o.r, o.g, o.b, o.a)

    def __hash__(self):
        return hash((self.r, self.g, self.b, self.a))


Color.WHITE = Color(1.0, 1.0, 1.0, 1.0)


# ----------------------------------------------------------------------------------------- objects
class Object:
    _gd_path = None
    _gd_name = None
    _gd_exports = ()
    _gd_signals = ()
    _gd_vars = ()
    _gd_floats = frozenset()
    _gd_floats_all = frozenset()

    def __init_subclass__(cls, **kw):
        super().__init_subclass__(**kw)
        allf = set()
        for k in cls.__mro__:
            allf |= set(k.__dict__.get("_gd_floats", ()))
        cls._gd_floats_all = frozenset(allf)

    def __init__(self, *args):
        prelude = getattr(type(self), "_gd_prelude", None)
        if prelude is not None:
            prelude(self)
        for klass in reversed(type(self).__mro__):
            init = klass.__dict__.get("_gd_members")
            if init is not None:
                init(self)
        ini = getattr(self, "_init", None)
        if ini is not None:
            ini(*args)

    @classmethod
    def new(cls, *args):
        return cls(*args)

    def free(self):
        pass

    def queue_free(self):
        pass

    def get(self, name):
        return getattr(self, _mangle(str(name)), None)

    def set(self, name, value):
        _setattr(self, _mangle(str(name)), value)

    def get_script(self):
        return type(self)

    def get_class(self):
        return type(self).__name__

    def get_instance_id(self):
        return id(self)

    def has_method(self, name):
        return callable(getattr(self, _mangle(str(name)), None))

    def call_deferred(self, name, *args):
        _DEFERRED.append((self, _mangle(str(name)), args))

    def emit_signal(self, name, *args):
        getattr(self, _mangle(str(name))).emit(*args)

    def connect(self, name, cb, flags=0):
        return getattr(self, _mangle(str(name))).connect(cb, flags)

    def call(self, name, *args):
        return getattr(self, name)(*args)

    def __contains__(self, name):
        return hasattr(self, name)

    def get_property_list(self):
        out = Array()
        seen = set()
        for klass in reversed(type(self).__mro__):
            exported = set(klass.__dict__.get("_gd_exports", ()))
            for n in klass.__dict__.get("_gd_vars", ()):
                if n in seen:
                    continue
                seen.add(n)
                out.append(Dictionary({"name": n, "usage": 4102 if n in exported else 4096}))
        return out


class RefCounted(Object):
    pass


class Resource(RefCounted):
    def duplicate(self, deep=False):
        import copy
        c = copy.copy(self)
        return c


class Node(Object):
    """A scene-tree node: children, parent, lifecycle order (_enter_tree, children, _ready) and processing."""
    PROCESS_MODE_INHERIT, PROCESS_MODE_PAUSABLE, PROCESS_MODE_WHEN_PAUSED, PROCESS_MODE_ALWAYS, PROCESS_MODE_DISABLED = 0, 1, 2, 3, 4
    process_mode = 0
    _gd_in_tree = False

    def _gd_prelude(self):
        self._children = []
        self._parent = None
        self._gd_blocked = 0
        self._gd_freed = False
        self._gd_ready_done = False
        self._gd_groups = set()
        self.name = type(self).__name__

    def add_child(self, child, force_readable_name=False, internal=0):
        if child is None:
            raise GDError("Parameter \"p_child\" is null.")
        if self._gd_blocked:
            raise GDError("Parent node is busy setting up children, `add_child()` failed. "
                          "Consider using `add_child.call_deferred(child)` instead.")
        if child._parent is not None:
            raise GDError("Can't add child '%s' to '%s', already has a parent '%s'." % (child.name, self.name, child._parent.name))
        if child is self:
            raise GDError("Can't add child '%s' to itself." % child.name)
        child._parent = self
        self._children.append(child)
        if self._gd_in_tree:
            self._gd_blocked += 1              # the engine blocks the parent while the child enters the tree
            try:
                child._gd_enter_tree()
            finally:
                self._gd_blocked -= 1

    def add_sibling(self, sibling, force_readable_name=False):
        self._parent.add_child(sibling)

    def remove_child(self, child):
        if self._gd_blocked:
            raise GDError("Parent node is busy adding/removing children, `remove_child()` can't be called at this time. "
                          "Consider using `remove_child.call_deferred(child)` instead.")
        if child not in self._children:
            raise GDError("Cannot remove a child that is not a child of this node.")
        self._children.remove(child)
        child._parent = None
        if self._gd_in_tree:
            child._gd_exit_tree()

    def reparent(self, new_parent, keep_global_transform=True):
        if self._parent is not None:
            self._parent.remove_child(self)
        new_parent.add_child(self)

    def get_children(self, include_internal=False):
        return Array(self._children)

    def get_child_count(self, include_internal=False):
        return len(self._children)

    def get_child(self, i, include_internal=False):
        return self._children[i]

    def move_child(self, child, to_index):
        self._children.remove(child)
        n = len(self._children)
        self._children.insert(to_index if to_index >= 0 else n + 1 + to_index, child)

    def get_parent(self):
        return self._parent

    def has_node(self, path):
        return self.get_node_or_null(path) is not None

    def get_node_or_null(self, path):
        cur = self
        for part in str(path).split("/"):
            if part in ("", "."):
                continue
            if part == "..":
                cur = cur._parent
            else:
                cur = next((c for c in cur._children if c.name == part), None)
            if cur is None:
                return None
        return cur

    def get_node(self, path):
        n = self.get_node_or_null(path)
        if n is None:
            raise GDError("Node not found: \"%s\" (relative to \"%s\")." % (path, self.name))
        return n

    def find_child(self, pattern, recursive=True, owned=True):
        for c in self._children:
            if c.name == pattern:
                return c
            if recursive:
                r = c.find_child(pattern, True, owned)
                if r is not None:
                    return r
        return None

    def add_to_group(self, group, persistent=False):
        self._gd_groups.add(group)

    def is_in_group(self, group):
        return group in self._gd_groups

    def queue_free(self):
        if not self._gd_freed:
            self._gd_freed = True
            TREE._to_free.append(self)

    def is_queued_for_deletion(self):
        return self._gd_freed

    def is_inside_tree(self):
        return self._gd_in_tree

    def get_tree(self):
        if not self._gd_in_tree:
            raise GDError("Cannot get_tree(): the node '%s' is not inside the scene tree." % self.name)
        return TREE

    def get_viewport(self):
        """Null outside the tree, as in the engine."""
        return TREE.viewport if self._gd_in_tree else None

    def get_window(self):
        return TREE.viewport if self._gd_in_tree else None

    def set_process(self, on):
        self._gd_process_on = bool(on)

    def set_physics_process(self, on):
        self._gd_physics_on = bool(on)

    def set_process_input(self, on):
        pass

    def is_processing(self):
        return getattr(self, "_gd_process_on", True)

    def _gd_enter_tree(self):
        if self._gd_in_tree:
            return
        self._gd_in_tree = True
        f = getattr(self, "_enter_tree", None)
        if f is not None:
            f()
        for c in list(self._children):
            c._gd_enter_tree()
        if not self._gd_ready_done:
            self._gd_ready_done = True
            f = getattr(self, "_ready", None)
            if f is not None:
                f()

    def _gd_exit_tree(self):
        for c in list(self._children):
            c._gd_exit_tree()
        f = getattr(self, "_exit_tree", None)
        if f is not None:
            f()
        self._gd_in_tree = False

    def _gd_effective_mode(self):
        n = self
        while n is not None:
            if n.process_mode != 0:
                return n.process_mode
            n = n._parent
        return 1

    def _gd_should_process(self):
        mode = self._gd_effective_mode()
        if mode == 4:
            return False
        if TREE.paused:
            return mode in (2, 3)
        return mode != 2

    def _gd_walk(self):
        yield self
        for c in list(self._children):
            yield from c._gd_walk()


class InputEvent(RefCounted):
    pass


class InputEventScreenTouch(InputEvent):
    def __init__(self, *args):
        self.index = 0
        self.position = Vector2()
        self.pressed = False
        self.canceled = False
        self.double_tap = False


class InputEventScreenDrag(InputEvent):
    def __init__(self, *args):
        self.index = 0
        self.position = Vector2()
        self.relative = Vector2()


class InputEventMouseButton(InputEvent):
    def __init__(self, *args):
        self.button_index = 0
        self.position = Vector2()
        self.pressed = False
        self.double_click = False


class InputEventKey(InputEvent):
    def __init__(self, *args):
        self.physical_keycode = 0
        self.pressed = False
        self.echo = False


class Signal:
    def __init__(self, owner=None, name=""):
        self._conns = []
        self.owner = owner
        self.name = name

    def connect(self, cb, flags=0):
        self._conns.append(cb)
        return 0

    def disconnect(self, cb):
        self._conns = [c for c in self._conns if c != cb]

    def is_connected(self, cb):
        return cb in self._conns

    def emit(self, *args):
        for cb in list(self._conns):
            cb(*args)

    def get_connections(self):
        return Array(self._conns)


class Callable:
    def __init__(self, target=None, method=None, fn=None, bound=()):
        if fn is None and target is not None and method is not None:
            fn = getattr(target, method)
        self.fn = fn
        self.bound = tuple(bound)

    def __call__(self, *args):
        if self.fn is None:
            raise GDError("Attempt to call an invalid (null) Callable.")
        return self.fn(*args, *self.bound)

    def call(self, *args):
        return self(*args)

    def callv(self, args):
        return self(*args)

    def bind(self, *args):
        return Callable(fn=self.fn, bound=self.bound + tuple(args))

    def call_deferred(self, *args):
        _DEFERRED.append((self, "__call__", args))

    def unbind(self, n):
        return Callable(fn=self.fn, bound=self.bound)

    def is_valid(self):
        return self.fn is not None

    def is_null(self):
        return self.fn is None

    def __eq__(self, o):
        return isinstance(o, Callable) and self.fn == o.fn and self.bound == o.bound

    def __hash__(self):
        return hash((self.fn, self.bound))


_DEFERRED = []


def run_deferred():
    """Runs the calls queued by call_deferred() (what the engine does at the end of a frame)."""
    while _DEFERRED:
        obj, name, args = _DEFERRED.pop(0)
        getattr(obj, name)(*args)


class SceneTreeTimer(RefCounted):
    def __init__(self, seconds=0.0):
        self.time_left = seconds
        self.timeout = Signal(self, "timeout")


class SceneTree(Object):
    """Just enough of the main loop: process / physics_process callbacks, input delivery, timers, deferred calls."""

    def __init__(self):
        self.paused = False
        self.root = Node()
        self.root._gd_in_tree = True
        self.root.name = "root"
        self.viewport = None            # set by the engine stubs
        self.current_scene = None
        self.process_frame = Signal(self, "process_frame")
        self.physics_frame = Signal(self, "physics_frame")
        self.quit_code = None
        self._to_free = []
        self._timers = []
        self._physics_accum = 0.0
        self.frames = 0
        self.frame_hook = None          # the engine stubs finish tweens here

    def create_timer(self, seconds, *a):
        t = SceneTreeTimer(seconds)
        self._timers.append(t)
        return t

    def quit(self, code=0):
        self.quit_code = code

    def call_group(self, *a):
        pass

    def get_nodes_in_group(self, group):
        return Array(n for n in self.root._gd_walk() if group in n._gd_groups)

    def step(self, delta, physics_hz=60):
        """One frame: deferred calls, timers, _process, fixed-rate _physics_process, then queued frees."""
        self.frames += 1
        if Time.virtual:
            Time.advance(delta)
        run_deferred()
        for t in list(self._timers):
            t.time_left -= delta
            if t.time_left <= 0:
                self._timers.remove(t)
                t.timeout.emit()
        self.process_frame.emit()
        self._physics_accum += delta
        step = 1.0 / physics_hz
        while self._physics_accum >= step:
            self._physics_accum -= step
            for n in list(self.root._gd_walk()):
                f = getattr(n, "_physics_process", None)
                if f is not None and n._gd_in_tree and n._gd_should_process():
                    f(step)
        for n in list(self.root._gd_walk()):
            f = getattr(n, "_process", None)
            if f is not None and n._gd_in_tree and not n._gd_freed and n.is_processing() and n._gd_should_process():
                f(delta)
        run_deferred()
        if self.frame_hook is not None:
            self.frame_hook()
        self.flush_frees()

    def notify_all(self, what):
        """Sends a notification (lifecycle, focus, close request) to every node that handles it."""
        for n in list(self.root._gd_walk()):
            f = getattr(n, "_notification", None)
            if f is not None:
                f(what)

    def flush_frees(self):
        while self._to_free:
            n = self._to_free.pop(0)
            if n._parent is not None:
                n._parent.remove_child(n)
            elif n._gd_in_tree:
                n._gd_exit_tree()

    def input(self, event):
        """Delivers an input event: _input of every node (last added first), then _unhandled_input."""
        nodes = [n for n in self.root._gd_walk() if n._gd_in_tree and n._gd_should_process()]
        for name in ("_input", "_unhandled_input"):
            for n in reversed(nodes):
                f = getattr(n, name, None)
                if f is not None:
                    f(event)


def _await(x):
    """`await` in gdemu: everything completes immediately (timers fire at once, signals resolve to null)."""
    return None if isinstance(x, Signal) else x


class AutoStub(Object):
    """Stands in for an autoload singleton whose real implementation needs the engine (audio, sensors,
    UI...). Every call is recorded and returns null."""

    def __init__(self, name="stub"):
        object.__setattr__(self, "_stub_name", name)
        object.__setattr__(self, "calls", [])

    def __getattr__(self, attr):
        if attr.startswith("__") or attr.startswith("_gd"):
            raise AttributeError(attr)
        calls = self.calls

        def call(*args):
            calls.append((attr, args))
            return None
        return call


def _mref(obj, name):
    """`obj.method` used as a value: a Callable for methods, the value itself for fields."""
    if obj is None:
        raise GDError("Invalid access to property or key '%s' on a base object of type 'Nil'." % name)
    v = getattr(obj, name)
    if getattr(v, "_gd_opaque", False) and not isinstance(v, type):
        return Callable(fn=v) if not hasattr(v, "connect") else v
    if callable(v) and not isinstance(v, (Callable, Signal, type)):
        return Callable(fn=v)
    return v


def _ga(obj, name):
    """Property read on a receiver whose type is not known statically (objects and dictionaries)."""
    if obj is None:
        raise GDError("Invalid access to property or key '%s' on a base object of type 'Nil'." % name)
    if isinstance(obj, dict):
        if name in obj:
            return obj[name]
        v = getattr(obj, name, _U)
        if v is _U:
            raise GDError("Invalid access to property or key '%s' on a base object of type 'Dictionary'." % name)
        return Callable(fn=v) if callable(v) else v
    try:
        v = getattr(obj, name)
    except AttributeError:
        raise GDError("Invalid access to property or key '%s' on a base object of type '%s'." % (name, type(obj).__name__))
    if getattr(v, "_gd_opaque", False):
        return v
    if callable(v) and not isinstance(v, (Callable, Signal, type)):
        return Callable(fn=v)
    return v


def _setattr(obj, name, v):
    """Property write on a receiver whose type is not known statically."""
    if obj is None:
        raise GDError("Invalid assignment of property or key '%s' on a base object of type 'Nil'." % name)
    if isinstance(obj, dict):
        obj[name] = v
        return
    if type(v) is int and name in getattr(type(obj), "_gd_floats_all", ()):
        v = float(v)
    setattr(obj, name, v)


class _Enum(Dictionary):
    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError:
            raise AttributeError(name)


_STR_M = {}


def _strm(name):
    def deco(f):
        _STR_M[name] = f
        return f
    return deco


@_strm("is_empty")
def _s_is_empty(s):
    return len(s) == 0


@_strm("begins_with")
def _s_begins(s, p):
    return s.startswith(p)


@_strm("ends_with")
def _s_ends(s, p):
    return s.endswith(p)


@_strm("contains")
def _s_contains(s, p):
    return p in s


@_strm("containsn")
def _s_containsn(s, p):
    return p.lower() in s.lower()


@_strm("substr")
def _s_substr(s, start, length=-1):
    if start < 0:
        start = 0
    return s[start:] if length < 0 else s[start:start + length]


@_strm("length")
def _s_length(s):
    return len(s)


@_strm("to_lower")
def _s_lower(s):
    return s.lower()


@_strm("to_upper")
def _s_upper(s):
    return s.upper()


@_strm("strip_edges")
def _s_strip(s, left=True, right=True):
    if left and right:
        return s.strip(" \t\r\n")
    return s.lstrip(" \t\r\n") if left else s.rstrip(" \t\r\n")


@_strm("repeat")
def _s_repeat(s, n):
    return s * n


@_strm("trim_prefix")
def _s_trim_prefix(s, p):
    return s[len(p):] if s.startswith(p) else s


@_strm("trim_suffix")
def _s_trim_suffix(s, p):
    return s[:-len(p)] if p and s.endswith(p) else s


@_strm("unicode_at")
def _s_unicode_at(s, i):
    return ord(s[i])


@_strm("to_utf8_buffer")
def _s_utf8(s):
    return PackedByteArray(s.encode("utf-8"))


@_strm("to_int")
def _s_to_int(s):
    try:
        return int(s.strip())
    except ValueError:
        return 0


@_strm("to_float")
def _s_to_float(s):
    try:
        return float(s.strip())
    except ValueError:
        return 0.0


@_strm("is_valid_int")
def _s_valid_int(s):
    try:
        int(s)
        return True
    except ValueError:
        return False


@_strm("is_valid_float")
def _s_valid_float(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


@_strm("split")
def _s_split(s, delim="", allow_empty=True, maxsplit=0):
    parts = s.split(delim) if delim else list(s)
    if not allow_empty:
        parts = [p for p in parts if p]
    return PackedStringArray(parts)


@_strm("join")
def _s_join(s, parts):
    return s.join(parts)


@_strm("replace")
def _s_replace(s, a, b):
    return s.replace(a, b)


@_strm("find")
def _s_find(s, what, start=0):
    return s.find(what, start)


@_strm("hash")
def _s_hash(s):
    h = 5381
    for ch in s:
        h = ((h << 5) + h + ord(ch)) & 0xFFFFFFFF
    return h


@_strm("capitalize")
def _s_capitalize(s):
    return s.replace("_", " ").title()


@_strm("pad_zeros")
def _s_pad_zeros(s, n):
    return s.zfill(n)


@_strm("left")
def _s_left(s, n):
    return s[:n]


@_strm("right")
def _s_right(s, n):
    return s[-n:] if n else ""


@_strm("count")
def _s_count(s, what):
    return s.count(what)


def _c(obj, name, *args):
    """Generic method call `obj.name(args)`; strings get the GDScript String methods."""
    if type(obj) is str:
        f = _STR_M.get(name)
        if f is None:
            raise GDError("gdemu: String method '%s' is not implemented" % name)
        return f(obj, *args)
    if obj is None:
        raise GDError("Invalid call. Nonexistent function '%s' in base 'Nil'." % name)
    f = getattr(obj, name, None)
    if f is None:
        raise GDError("Invalid call. Nonexistent function '%s' in base '%s'." % (name, type(obj).__name__))
    return f(*args)


def _iter(x):
    if type(x) is int:
        return range(x)
    if x is None:
        raise GDError("Invalid iterator on a null value")
    return x


# -------------------------------------------------------------------------------------- functions
PI = math.pi
TAU = math.tau
INF = math.inf
NAN = math.nan


def abs_(x):
    return abs(x)


def absf(x):
    return abs(float(x))


def absi(x):
    return abs(int(x))


def sign(x):
    return (x > 0) - (x < 0) if type(x) is int else signf(x)


def signf(x):
    return 1.0 if x > 0 else (-1.0 if x < 0 else 0.0)


def signi(x):
    return (x > 0) - (x < 0)


def sqrt(x):
    return math.sqrt(x) if x >= 0 else math.nan


def pow_(a, b):
    return _pow(a, b)


def exp(x):
    try:
        return math.exp(x)
    except OverflowError:
        return math.inf


def log(x):
    return math.log(x) if x > 0 else (-math.inf if x == 0 else math.nan)


sin, cos, tan = math.sin, math.cos, math.tan


def asin(x):
    return math.asin(x) if -1.0 <= x <= 1.0 else math.nan


def acos(x):
    return math.acos(x) if -1.0 <= x <= 1.0 else math.nan


atan, atan2 = math.atan, math.atan2


def floor(x):
    return float(math.floor(x))


def ceil(x):
    return float(math.ceil(x))


def round_(x):
    return float(math.floor(x + 0.5)) if x >= 0 else -float(math.floor(-x + 0.5))


def floori(x):
    return int(math.floor(x))


def ceili(x):
    return int(math.ceil(x))


def roundi(x):
    return int(round_(x))


def fmod(a, b):
    return math.fmod(a, b) if b != 0 else math.nan


def fposmod(a, b):
    r = math.fmod(a, b)
    return r + b if r != 0 and (r < 0) != (b < 0) else r


def posmod(a, b):
    r = a % b
    return r


def min_(*a):
    return min(a[0]) if len(a) == 1 else min(a)


def max_(*a):
    return max(a[0]) if len(a) == 1 else max(a)


def mini(a, b):
    return min(int(a), int(b))


def maxi(a, b):
    return max(int(a), int(b))


def minf(a, b):
    return min(float(a), float(b))


def maxf(a, b):
    return max(float(a), float(b))


def clamp(x, lo, hi):
    return lo if x < lo else (hi if x > hi else x)


def clampi(x, lo, hi):
    return int(lo) if x < lo else (int(hi) if x > hi else int(x))


def clampf(x, lo, hi):
    x, lo, hi = float(x), float(lo), float(hi)
    return lo if x < lo else (hi if x > hi else x)


def lerp(a, b, t):
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    return a.lerp(b, t)


def lerpf(a, b, t):
    return float(a) + (float(b) - float(a)) * t


def inverse_lerp(a, b, v):
    return (v - a) / (b - a)


def smoothstep(a, b, x):
    if a == b:
        return 0.0
    t = clampf((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def move_toward(a, b, d):
    return b if abs(b - a) <= d else a + math.copysign(d, b - a)


def is_equal_approx(a, b):
    if a == b:
        return True
    tol = 1e-5 * abs(a)
    if tol < 1e-5:
        tol = 1e-5
    return abs(a - b) < tol


def is_zero_approx(a):
    return abs(a) < 1e-5


def is_nan(x):
    return x != x


def is_inf(x):
    return x in (math.inf, -math.inf)


def is_finite(x):
    return not (x != x or x in (math.inf, -math.inf))


def deg_to_rad(x):
    return x * math.pi / 180.0


def rad_to_deg(x):
    return x * 180.0 / math.pi


def snappedf(x, step):
    return round_(x / step) * step if step else x


snapped = snappedf


def snappedi(x, step):
    return int(round_(x / step) * step) if step else int(x)


def linear_to_db(x):
    return math.log(x) * 8.6858896380650365530225783783321 if x > 0 else -math.inf


def db_to_linear(x):
    return math.exp(x * 0.11512925464970228420089957273422)


def wrapf(v, lo, hi):
    span = hi - lo
    return lo if span == 0 else v - span * math.floor((v - lo) / span)


def wrapi(v, lo, hi):
    span = hi - lo
    return lo if span == 0 else lo + (v - lo) % span


def remap(v, istart, istop, ostart, ostop):
    return ostart + (ostop - ostart) * ((v - istart) / (istop - istart))


def pingpong(v, length):
    if length == 0:
        return 0.0
    t = math.fmod(v, length * 2.0)
    t = t + length * 2.0 if t < 0 else t
    return length - abs(t - length)


def angle_difference(a, b):
    d = math.fmod(b - a, math.tau)
    return math.fmod(2.0 * d, math.tau) - d


def lerp_angle(a, b, t):
    return a + angle_difference(a, b) * t


_rng = _random.Random(1234)


def randi():
    return _rng.getrandbits(32)


def randf():
    return _rng.random()


def randi_range(a, b):
    return _rng.randint(a, b)


def randf_range(a, b):
    return _rng.uniform(a, b)


def randomize():
    pass


def seed(s):
    _rng.seed(s)


def hash_(x):
    return _s_hash(x) if type(x) is str else hash(x) & 0xFFFFFFFF


def int_(x=0):
    if type(x) is str:
        try:
            return int(x)
        except ValueError:
            return 0
    if type(x) is float:
        if x != x or x in (math.inf, -math.inf):
            return 0
        return int(x)
    if x is None:
        return 0
    return int(x)


def float_(x=0.0):
    if type(x) is str:
        try:
            return float(x)
        except ValueError:
            return 0.0
    if x is None:
        return 0.0
    return float(x)


def bool_(x=False):
    return bool(x)


def String(x=""):
    return _str(x)


StringName = String


def str_(*args):
    return "".join(_str(a) for a in args)


def print_(*args):
    print("".join(_str(a) for a in args))


def printerr(*args):
    print("".join(_str(a) for a in args), file=sys.stderr)


def prints(*args):
    print(" ".join(_str(a) for a in args))


def push_error(*args):
    print("PUSH_ERROR:", "".join(_str(a) for a in args), file=sys.stderr)


def push_warning(*args):
    print("PUSH_WARNING:", "".join(_str(a) for a in args), file=sys.stderr)


def _assert(cond, msg=""):
    if not cond:
        raise GDError("Assertion failed: %s" % msg)


def char(c):
    return chr(c)


def ord_(s):
    return ord(s)


def len_(x):
    return len(x)


def range_(*a):
    return range(*[int(v) for v in a])


SCRIPT_LOADER = None       # set by the gdemu loader: res:// path of a .gd file -> script class
RESOURCE_LOADER = None     # set by the gdemu loader: other res:// resources (only .tres of scripts)


def load_(path):
    if path.endswith(".gd"):
        return SCRIPT_LOADER(path)
    if RESOURCE_LOADER is not None:
        return RESOURCE_LOADER(path)
    return None


preload_ = load_


def is_instance_valid(x):
    return x is not None


# ---------------------------------------------------------------------------------- constants
OK = 0
FAILED = 1
ERR_FILE_NOT_FOUND = 12
ERR_PARSE_ERROR = 43
NOTIFICATION_WM_FOCUS_IN, NOTIFICATION_WM_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST = 1004, 1005, 1006, 1007
NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_OUT = 2014, 2015, 2016, 2017
PROPERTY_USAGE_STORAGE = 2
PROPERTY_USAGE_EDITOR = 4
PROPERTY_USAGE_DEFAULT = 6
PROPERTY_USAGE_SCRIPT_VARIABLE = 4096
KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_A, KEY_D, KEY_W, KEY_SPACE, KEY_ESCAPE, KEY_P, KEY_F3 = 4194319, 4194321, 4194320, 65, 68, 87, 32, 4194305, 80, 4194334


# ------------------------------------------------------------------------------------ singletons
PROJECT_ROOT = os.getcwd()
USER_DIR = os.path.join(os.environ.get("GDEMU_TMP", "/tmp"), "gdemu_user")


def _path(p):
    if p.startswith("res://"):
        return os.path.join(PROJECT_ROOT, p[6:])
    if p.startswith("user://"):
        return os.path.join(USER_DIR, p[7:])
    return p


class Time:
    """Real time by default; with `virtual` set (smoke runs) the clock only moves when the emulated
    SceneTree steps, so touch hold times and timers behave as if frames took 1/60 s each."""
    virtual = False
    _virtual_usec = 1000000

    @staticmethod
    def get_unix_time_from_system():
        return _time.time()

    @staticmethod
    def get_ticks_msec():
        return Time.get_ticks_usec() // 1000

    @staticmethod
    def get_ticks_usec():
        if Time.virtual:
            return int(Time._virtual_usec)
        return int(_time.monotonic() * 1000000)

    @staticmethod
    def advance(seconds):
        Time._virtual_usec += seconds * 1000000

    @staticmethod
    def get_time_zone_from_system():
        return Dictionary({"bias": 0, "name": "UTC"})

    @staticmethod
    def get_datetime_dict_from_unix_time(t):
        import datetime
        d = datetime.datetime.fromtimestamp(int(t), datetime.timezone.utc)
        return Dictionary({"year": d.year, "month": d.month, "day": d.day, "weekday": (d.weekday() + 1) % 7,
                           "hour": d.hour, "minute": d.minute, "second": d.second, "dst": False})

    @staticmethod
    def get_datetime_dict_from_system(utc=False):
        return Time.get_datetime_dict_from_unix_time(_time.time())

    @staticmethod
    def get_date_string_from_system(utc=False):
        d = Time.get_datetime_dict_from_system()
        return "%04d-%02d-%02d" % (d["year"], d["month"], d["day"])


class OS:
    @staticmethod
    def has_feature(name):
        return False

    @staticmethod
    def is_debug_build():
        return True

    @staticmethod
    def get_name():
        return "Linux"

    @staticmethod
    def get_model_name():
        return "gdemu"

    @staticmethod
    def get_locale():
        return "en_US"

    @staticmethod
    def get_cmdline_args():
        return PackedStringArray()

    @staticmethod
    def request_permissions():
        return True

    @staticmethod
    def shell_open(uri):
        return OK

    @staticmethod
    def get_unique_id():
        return "gdemu"


class Engine:
    max_fps = 0

    @staticmethod
    def get_frames_per_second():
        return 60.0

    @staticmethod
    def has_singleton(name):
        return False

    @staticmethod
    def get_singleton(name):
        return None

    @staticmethod
    def get_license_text():
        return "Godot Engine (emulated licence text)"

    @staticmethod
    def get_copyright_info():
        return Array([Dictionary({"name": "Godot Engine", "parts": Array([Dictionary({"files": Array(["*"]), "copyright": Array(["Godot Engine contributors"]), "license": "MIT"})])})])

    @staticmethod
    def get_license_info():
        return Dictionary({"MIT": "MIT licence text"})

    @staticmethod
    def get_version_info():
        return Dictionary({"major": 4, "minor": 3, "patch": 0, "string": "4.3-emulated"})


class FileAccess(RefCounted):
    READ, WRITE, READ_WRITE, WRITE_READ = 1, 2, 3, 7
    COMPRESSION_FASTLZ, COMPRESSION_DEFLATE, COMPRESSION_ZSTD, COMPRESSION_GZIP = 0, 1, 2, 3
    _last_error = 0

    def __init__(self, fh=None):
        self._fh = fh

    @staticmethod
    def file_exists(p):
        return os.path.isfile(_path(p))

    @staticmethod
    def get_file_as_string(p):
        try:
            with open(_path(p), "r", encoding="utf-8") as f:
                return f.read()
        except OSError:
            return ""

    @staticmethod
    def get_open_error():
        return FileAccess._last_error

    @staticmethod
    def open(p, mode):
        real = _path(p)
        try:
            if mode == FileAccess.READ:
                fh = open(real, "r", encoding="utf-8", newline="")
            elif mode == FileAccess.WRITE:
                fh = open(real, "w", encoding="utf-8", newline="")
            else:
                raise GDError("gdemu: FileAccess mode %r not emulated" % mode)
        except OSError:
            FileAccess._last_error = ERR_FILE_NOT_FOUND
            return None
        FileAccess._last_error = 0
        return FileAccess(fh)

    def store_string(self, s):
        self._fh.write(s)
        return True

    def get_as_text(self):
        return self._fh.read()

    def flush(self):
        self._fh.flush()

    def close(self):
        self._fh.close()


class DirAccess(RefCounted):
    @staticmethod
    def make_dir_recursive_absolute(p):
        os.makedirs(_path(p), exist_ok=True)
        return 0

    @staticmethod
    def remove_absolute(p):
        real = _path(p)
        try:
            if os.path.isdir(real):
                os.rmdir(real)
            else:
                os.remove(real)
            return 0
        except OSError:
            return 1

    @staticmethod
    def copy_absolute(a, b, chmod=-1):
        try:
            shutil.copyfile(_path(a), _path(b))
            return 0
        except OSError:
            return 1

    @staticmethod
    def rename_absolute(a, b):
        try:
            os.replace(_path(a), _path(b))
            return 0
        except OSError:
            return 1

    @staticmethod
    def dir_exists_absolute(p):
        return os.path.isdir(_path(p))

    @staticmethod
    def get_files_at(p):
        real = _path(p)
        if not os.path.isdir(real):
            return PackedStringArray()
        return PackedStringArray(sorted(f for f in os.listdir(real) if os.path.isfile(os.path.join(real, f))))

    @staticmethod
    def get_directories_at(p):
        real = _path(p)
        if not os.path.isdir(real):
            return PackedStringArray()
        return PackedStringArray(sorted(f for f in os.listdir(real) if os.path.isdir(os.path.join(real, f))))


class Marshalls:
    @staticmethod
    def raw_to_base64(b):
        return base64.b64encode(bytes(b)).decode("ascii")

    @staticmethod
    def base64_to_raw(s):
        try:
            return PackedByteArray(base64.b64decode(s.encode("ascii"), validate=True))
        except Exception:
            return PackedByteArray()


class ResourceLoader:
    THREAD_LOAD_INVALID_RESOURCE, THREAD_LOAD_IN_PROGRESS, THREAD_LOAD_FAILED, THREAD_LOAD_LOADED = 0, 1, 2, 3
    _requested = set()

    @staticmethod
    def exists(p, type_hint=""):
        return os.path.exists(_path(p))

    @staticmethod
    def load_threaded_request(path, type_hint="", use_sub_threads=False, cache_mode=1):
        ResourceLoader._requested.add(path)
        return OK

    @staticmethod
    def load_threaded_get_status(path, progress=None):
        return ResourceLoader.THREAD_LOAD_LOADED if path in ResourceLoader._requested else ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

    @staticmethod
    def load_threaded_get(path):
        return load_(path)

    @staticmethod
    def load(path, type_hint="", cache_mode=1):
        return load_(path)


def _to_gd(x):
    if isinstance(x, dict):
        return Dictionary((k, _to_gd(v)) for k, v in x.items())
    if isinstance(x, list):
        return Array(_to_gd(v) for v in x)
    if type(x) is int:
        return float(x)      # JSON numbers are always floats in Godot
    return x


def _from_gd(x, full=False):
    if isinstance(x, dict):
        return {str(k): _from_gd(v, full) for k, v in x.items()}
    if isinstance(x, (list, PackedArray)):
        return [_from_gd(v, full) for v in x]
    if isinstance(x, bytearray):
        return list(x)
    if isinstance(x, (Vector2, Vector3)):
        return str(x)
    return x


class JSON(RefCounted):
    def __init__(self, *a):
        self.data = None

    def parse(self, text, keep_text=False):
        try:
            self.data = _to_gd(_pyjson.loads(text))
            return OK
        except (ValueError, RecursionError):
            self.data = None
            return ERR_PARSE_ERROR

    @staticmethod
    def parse_string(text):
        try:
            return _to_gd(_pyjson.loads(text))
        except ValueError:
            return None

    @staticmethod
    def stringify(data, indent="", sort_keys=True, full_precision=False):
        return _pyjson.dumps(_from_gd(data), indent=(len(indent) or None) if indent else None,
                             sort_keys=sort_keys, separators=(",", ":") if not indent else None, ensure_ascii=False)


class ProjectSettings:
    """Reads project.godot (only what the config tests need)."""
    _cache = None

    @staticmethod
    def _load():
        if ProjectSettings._cache is not None:
            return ProjectSettings._cache
        d = {}
        section = ""
        try:
            with open(os.path.join(PROJECT_ROOT, "project.godot"), encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith(";"):
                        continue
                    if line.startswith("["):
                        section = line.strip("[]")
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        d[(section + "/" + k.strip()) if section else k.strip()] = v.strip()
        except OSError:
            pass
        ProjectSettings._cache = d
        return d

    @staticmethod
    def _parse(v):
        v = v.strip()
        if v in ("true", "false"):
            return v == "true"
        if v.startswith('"') and v.endswith('"'):
            return v[1:-1]
        try:
            return int(v)
        except ValueError:
            pass
        try:
            return float(v)
        except ValueError:
            return v

    @staticmethod
    def has_setting(name):
        return name in ProjectSettings._load()

    @staticmethod
    def get_setting(name, default=None):
        d = ProjectSettings._load()
        return ProjectSettings._parse(d[name]) if name in d else default


TREE = SceneTree()
GLOBAL_CLASS_LIST = None    # set by the gdemu loader


def _global_class_list():
    out = Array()
    for name, path in sorted((GLOBAL_CLASS_LIST or {}).items()):
        out.append(Dictionary({"class": name, "path": path, "base": "", "language": "GDScript"}))
    return out


ProjectSettings.get_global_class_list = staticmethod(_global_class_list)


def _cfg_value(text):
    text = text.strip()
    if text in ("true", "false"):
        return text == "true"
    if text.startswith('"'):
        return _pyjson.loads(text)
    if text.startswith("PackedStringArray("):
        inner = text[len("PackedStringArray("):-1].strip()
        return PackedStringArray([_pyjson.loads(x.strip()) for x in inner.split(",") if x.strip()])
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        return text


class ConfigFile(RefCounted):
    """The subset of ConfigFile the tests use: load(), get_sections(), get_value(), has_section()."""

    def __init__(self):
        self._data = {}

    def load(self, path):
        try:
            with open(_path(path), encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            return ERR_FILE_NOT_FOUND
        self._data = {}
        section = ""
        for line in lines:
            line = line.strip()
            if not line or line.startswith(";"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                self._data.setdefault(section, {})
            elif "=" in line:
                k, v = line.split("=", 1)
                self._data.setdefault(section, {})[k.strip()] = _cfg_value(v)
        return OK

    def get_sections(self):
        return PackedStringArray(list(self._data.keys()))

    def has_section(self, section):
        return section in self._data

    def get_value(self, section, key, default=None):
        return self._data.get(section, {}).get(key, default)


NAMESPACE_OVERRIDES = {
    "abs": abs_, "pow": pow_, "round": round_, "min": min_, "max": max_, "hash": hash_,
    "int": int_, "float": float_, "bool": bool_, "str": str_, "print": print_, "range": range_,
    "len": len_, "ord": ord_, "assert": _assert, "load": load_, "preload": preload_,
}
