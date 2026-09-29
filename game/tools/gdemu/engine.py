"""
Permissive stand-ins for the engine classes the UI / view / engine-heavy autoload scripts use.

They are NOT models of the engine: nodes keep a child list, a parent and properties, signals can be
connected and emitted, and everything else (layout, drawing, audio, themes ...) is accepted and ignored.
Values the engine would compute (sizes, colours, returns of unknown calls) are `Opaque` chameleons that
survive arithmetic and comparisons. The point is to execute the *project's own* code paths (building every
screen from real data, running the game loop, pressing every button) and surface Python-level failures in
them: missing keys, null dereferences, wrong project-function arguments, broken state machines.
"""
import zlib

from . import runtime as rt
from .runtime import (Array, Callable, Color, Dictionary, GDError, Node, Object, PackedStringArray, RefCounted, Signal,
                      Vector2, Vector2i, Vector3, Rect2, Rect2i, Resource)


class Opaque:
    """A value the emulator does not model. Accepts attribute chains, calls, arithmetic and comparisons."""
    _gd_opaque = True

    def __init__(self, name="opaque"):
        object.__setattr__(self, "_name", name)
        object.__setattr__(self, "_attrs", {})
        object.__setattr__(self, "_conns", [])

    # attributes: cached so `a.b is a.b` (signals stay connectable)
    def __getattr__(self, n):
        if n.startswith("_"):
            raise AttributeError(n)
        d = self._attrs
        v = d.get(n)
        if v is None:
            v = d[n] = Opaque("%s.%s" % (self._name, n))
        return v

    def __setattr__(self, n, v):
        if n in self.__dict__:                 # real fields of the singleton subclasses (gravity_value, clip ...)
            object.__setattr__(self, n, v)
        else:
            self._attrs[n] = v

    def __call__(self, *a, **k):
        return Opaque(self._name + "()")

    # signal-like
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

    # numbers and containers
    def __bool__(self):
        return False

    def __int__(self):
        return 0

    __index__ = __int__

    def __float__(self):
        return 0.0

    def __len__(self):
        return 0

    def __iter__(self):
        return iter(())

    def __contains__(self, x):
        return False

    def __getitem__(self, k):
        return Opaque(self._name + "[]")

    def __setitem__(self, k, v):
        pass

    def __str__(self):
        return ""

    def __repr__(self):
        return "<opaque %s>" % self._name

    def _op(self, *a):
        return Opaque(self._name + "~")

    __add__ = __radd__ = __sub__ = __rsub__ = __mul__ = __rmul__ = __truediv__ = __rtruediv__ = _op
    __neg__ = __pos__ = __abs__ = __mod__ = __rmod__ = __floordiv__ = __rfloordiv__ = _op

    def __lt__(self, o):
        return False

    __le__ = __gt__ = __ge__ = __lt__

    __hash__ = object.__hash__


def _const(owner, name):
    return zlib.crc32(("%s.%s" % (owner, name)).encode()) & 0x7FFFFFFF


class _EngineMeta(type):
    """Class-level engine constants (Control.PRESET_FULL_RECT, Tween.TRANS_SINE ...) resolve to stable ints."""

    def __getattr__(cls, name):
        if name.startswith("_") or not name[:1].isupper():
            raise AttributeError(name)
        return _const(cls.__name__, name)


class EngineObject(RefCounted, metaclass=_EngineMeta):
    """Any engine object that is not a node (Tween, StyleBoxFlat, Theme, AudioStreamPlayer's streams ...)."""
    _gd_opaque = True

    def __getattr__(self, n):
        if n.startswith("_"):
            raise AttributeError(n)
        v = Opaque("%s.%s" % (type(self).__name__, n))
        self.__dict__[n] = v          # cached
        return v


class EngineResource(Resource, metaclass=_EngineMeta):
    _gd_opaque = True

    def __getattr__(self, n):
        if n.startswith("_"):
            raise AttributeError(n)
        v = Opaque("%s.%s" % (type(self).__name__, n))
        self.__dict__[n] = v
        return v


class EngineNode(Node, metaclass=_EngineMeta):
    """A node from the engine (Control, Label, Node2D, CanvasLayer ...): tree behaviour from runtime.Node,
    every other member accepted."""
    _gd_opaque = True
    visible = True
    modulate = Color(1.0, 1.0, 1.0, 1.0)
    self_modulate = Color(1.0, 1.0, 1.0, 1.0)
    scale = Vector2(1.0, 1.0)
    rotation = 0.0
    z_index = 0
    text = ""
    layer = 1

    def _gd_prelude(self):
        Node._gd_prelude(self)
        self.position = Vector2()
        self.size = Vector2(1600.0, 720.0)
        self.global_position = Vector2()
        self.custom_minimum_size = Vector2()

    def __getattr__(self, n):
        if n.startswith("_"):
            raise AttributeError(n)
        v = Opaque("%s.%s" % (type(self).__name__, n))
        self.__dict__[n] = v
        return v

    def is_visible_in_tree(self):
        n = self
        while n is not None:
            if getattr(n, "visible", True) is False:
                return False
            n = n._parent
        return self._gd_in_tree

    def get_viewport_rect(self):
        return Rect2(0.0, 0.0, 1600.0, 720.0)

    def get_global_rect(self):
        return Rect2(self.global_position.x, self.global_position.y, self.size.x, self.size.y)

    def get_rect(self):
        return Rect2(self.position.x, self.position.y, self.size.x, self.size.y)

    def get_minimum_size(self):
        return Vector2()

    def get_theme_default_font(self):
        return Opaque("font")

    def create_tween(self):
        return Tween()

    def queue_redraw(self):
        self.__dict__["_gd_dirty"] = True

    def hide(self):
        self.visible = False

    def show(self):
        self.visible = True

    def set_anchors_and_offsets_preset(self, *a, **k):
        pass

    def get_local_mouse_position(self):
        return Vector2()

    def has_focus(self):
        return False

    def to_local(self, p):
        return p


# Node class hierarchy (child -> parent) so `x is Control` / `x as Control` behave like the engine.
NODE_PARENTS = {
    "CanvasItem": "Node", "Node2D": "CanvasItem", "Control": "CanvasItem", "Container": "Control",
    "BoxContainer": "Container", "VBoxContainer": "BoxContainer", "HBoxContainer": "BoxContainer",
    "GridContainer": "Container", "MarginContainer": "Container", "PanelContainer": "Container",
    "ScrollContainer": "Container", "CenterContainer": "Container", "TabContainer": "Container",
    "SplitContainer": "Container", "AspectRatioContainer": "Container", "FlowContainer": "Container",
    "HFlowContainer": "FlowContainer", "VFlowContainer": "FlowContainer", "SubViewportContainer": "Container",
    "Label": "Control", "RichTextLabel": "Control", "ColorRect": "Control", "TextureRect": "Control",
    "Panel": "Control", "NinePatchRect": "Control", "LineEdit": "Control", "TextEdit": "Control",
    "ReferenceRect": "Control", "ItemList": "Control", "Tree": "Control", "TabBar": "Control",
    "Separator": "Control", "HSeparator": "Separator", "VSeparator": "Separator",
    "BaseButton": "Control", "Button": "BaseButton", "CheckBox": "Button", "CheckButton": "Button",
    "OptionButton": "Button", "MenuButton": "Button", "LinkButton": "BaseButton", "TextureButton": "BaseButton",
    "Range": "Control", "Slider": "Range", "HSlider": "Slider", "VSlider": "Slider", "ScrollBar": "Range",
    "HScrollBar": "ScrollBar", "VScrollBar": "ScrollBar", "ProgressBar": "Range", "SpinBox": "Range",
    "TextureProgressBar": "Range",
    "Sprite2D": "Node2D", "AnimatedSprite2D": "Node2D", "Camera2D": "Node2D", "Line2D": "Node2D",
    "Polygon2D": "Node2D", "CPUParticles2D": "Node2D", "GPUParticles2D": "Node2D", "Marker2D": "Node2D",
    "TouchScreenButton": "Node2D", "CanvasGroup": "Node2D", "ParallaxLayer": "Node2D", "BackBufferCopy": "Node2D",
    "RemoteTransform2D": "Node2D", "AudioStreamPlayer2D": "Node2D",
    "CanvasLayer": "Node", "ParallaxBackground": "CanvasLayer", "Timer": "Node", "AudioStreamPlayer": "Node",
    "AnimationPlayer": "Node", "HTTPRequest": "Node", "Viewport": "Node", "Window": "Viewport", "SubViewport": "Viewport",
    "Popup": "Window", "PopupPanel": "Popup", "AcceptDialog": "Window", "ConfirmationDialog": "AcceptDialog",
    "FileDialog": "ConfirmationDialog",
}
NODE_CLASSES = set(NODE_PARENTS)

RESOURCE_PARENTS = {
    "StyleBox": "Resource", "StyleBoxFlat": "StyleBox", "StyleBoxEmpty": "StyleBox", "StyleBoxTexture": "StyleBox",
    "StyleBoxLine": "StyleBox", "Theme": "Resource", "Gradient": "Resource", "GradientTexture2D": "Resource",
    "GradientTexture1D": "Resource", "Curve": "Resource", "Material": "Resource", "ShaderMaterial": "Material",
    "CanvasItemMaterial": "Material", "Shader": "Resource", "LabelSettings": "Resource", "FontVariation": "Font",
    "FontFile": "Font", "SystemFont": "Font", "AtlasTexture": "Texture2D", "PackedScene": "Resource",
    "ButtonGroup": "Resource", "AudioStreamPolyphonic": "AudioStream", "AudioStreamRandomizer": "AudioStream",
}


class Timer(EngineNode):
    """A working Timer: counts down while in the tree and emits `timeout` (see stepping in SceneTree)."""

    def _gd_prelude(self):
        EngineNode._gd_prelude(self)
        self.wait_time = 1.0
        self.one_shot = False
        self.autostart = False
        self.timeout = Signal(self, "timeout")
        self._t_left = None

    def start(self, time_sec=-1.0):
        if time_sec > 0:
            self.wait_time = time_sec
        self._t_left = self.wait_time

    def stop(self):
        self._t_left = None

    def is_stopped(self):
        return self._t_left is None

    def _process(self, delta):
        if self._t_left is None:
            return
        self._t_left -= delta
        if self._t_left <= 0:
            self._t_left = None if self.one_shot else self.wait_time
            self.timeout.emit()


class Tween(EngineObject):
    """Tweens complete on the next frame: properties jump to their final values, callbacks run in order."""

    def _gd_prelude(self):
        self._steps = []
        self.finished = Signal(self, "finished")
        self._done = False
        self._parallel = False
        TWEENS.append(self)

    def tween_property(self, obj, path, final, duration):
        self._steps.append(("prop", obj, str(path), final))
        return self

    def tween_callback(self, cb):
        self._steps.append(("call", cb))
        return self

    def tween_interval(self, t):
        return self

    def tween_method(self, cb, frm, to, duration):
        self._steps.append(("call_args", cb, to))
        return self

    def set_parallel(self, on=True):
        return self

    def parallel(self):
        return self

    def chain(self):
        return self

    def set_trans(self, *a):
        return self

    def set_ease(self, *a):
        return self

    def set_loops(self, *a):
        return self

    def set_ignore_time_scale(self, *a):
        return self

    def bind_node(self, *a):
        return self

    def as_relative(self):
        return self

    def from_current(self):
        return self

    def kill(self):
        self._done = True
        self._steps = []

    def is_valid(self):
        return not self._done

    def is_running(self):
        return not self._done

    def _finish(self):
        if self._done:
            return
        steps, self._steps = self._steps, []
        for st in steps:
            if st[0] == "prop":
                _, obj, path, final = st
                if getattr(obj, "_gd_freed", False):
                    continue
                if ":" in path:
                    head, sub = path.split(":", 1)
                    base = getattr(obj, head)
                    setattr(base, sub, final)
                else:
                    rt._setattr(obj, path, final)
            elif st[0] == "call":
                st[1]()
            elif st[0] == "call_args":
                st[1](st[2])
        self._done = True
        self.finished.emit()


TWEENS = []


def draw_pass():
    """Calls _draw() of visible CanvasItems that asked for a redraw (or never drew), like the renderer would."""
    for n in list(rt.TREE.root._gd_walk()):
        f = getattr(n, "_draw", None)
        if f is None or not n._gd_in_tree or getattr(n, "_gd_freed", False):
            continue
        d = n.__dict__
        if d.get("_gd_drawn") and not d.get("_gd_dirty"):
            continue
        if hasattr(n, "is_visible_in_tree") and not n.is_visible_in_tree():
            continue
        d["_gd_drawn"] = True
        d["_gd_dirty"] = False
        f()


def frame_hook():
    finish_tweens()
    draw_pass()


def finish_tweens():
    while TWEENS:
        t = TWEENS.pop(0)
        t._finish()


class Viewport(EngineNode):
    def _gd_prelude(self):
        EngineNode._gd_prelude(self)
        self.size_changed = Signal(self, "size_changed")

    def get_visible_rect(self):
        return Rect2(0.0, 0.0, 1600.0, 720.0)

    def get_mouse_position(self):
        return Vector2()

    def set_input_as_handled(self):
        pass


class _Singleton(Opaque):
    """Engine singleton: unknown members are opaque, a few return realistic values."""

    def __init__(self, name):
        Opaque.__init__(self, name)


class InputSingleton(_Singleton):
    def __init__(self):
        _Singleton.__init__(self, "Input")
        object.__setattr__(self, "gravity_value", Vector3(0.0, 9.81, 0.0))
        object.__setattr__(self, "vibrations", [])
        object.__setattr__(self, "pressed_keys", set())

    def get_gravity(self):
        return self.gravity_value

    def get_accelerometer(self):
        return self.gravity_value

    def get_gyroscope(self):
        return Vector3()

    def get_magnetometer(self):
        return Vector3()

    def vibrate_handheld(self, ms=500, amplitude=-1.0):
        self.vibrations.append(ms)

    def is_key_pressed(self, k):
        return k in self.pressed_keys

    def is_action_pressed(self, *a):
        return False

    def is_action_just_pressed(self, *a):
        return False

    def is_mouse_button_pressed(self, *a):
        return False

    def get_mouse_button_mask(self):
        return 0


class DisplayServerSingleton(_Singleton):
    def __init__(self):
        _Singleton.__init__(self, "DisplayServer")
        object.__setattr__(self, "window_size", Vector2i(2400, 1080))
        object.__setattr__(self, "safe_area", Rect2i(0, 0, 2400, 1080))
        object.__setattr__(self, "clip", "")

    def window_get_size(self, *a):
        return self.window_size

    def window_get_position(self, *a):
        return Vector2i(0, 0)

    def screen_get_size(self, *a):
        return self.window_size

    def get_display_safe_area(self):
        return self.safe_area

    def is_touchscreen_available(self):
        return True

    def screen_get_dpi(self, *a):
        return 420

    def clipboard_get(self):
        return self.clip

    def clipboard_set(self, text):
        object.__setattr__(self, "clip", text)

    def has_feature(self, *a):
        return False


class AudioServerSingleton(_Singleton):
    def __init__(self):
        _Singleton.__init__(self, "AudioServer")

    def get_bus_index(self, name):
        return 0

    def get_bus_count(self):
        return 3


_SINGLETONS = {}


def _singleton(name):
    if name not in _SINGLETONS:
        factory = {"Input": InputSingleton, "DisplayServer": DisplayServerSingleton, "AudioServer": AudioServerSingleton}.get(name)
        _SINGLETONS[name] = factory() if factory else _Singleton(name)
    return _SINGLETONS[name]


SINGLETON_NAMES = {"Input", "DisplayServer", "AudioServer", "Performance", "JavaClassWrapper", "RenderingServer",
                   "ThemeDB", "ResourceSaver", "ClassDB", "TextServerManager", "Geometry2D", "NavigationServer2D"}

# a few global enum constants with their real values (the rest resolve to stable hashes)
GLOBAL_CONSTANTS = {
    "HORIZONTAL_ALIGNMENT_LEFT": 0, "HORIZONTAL_ALIGNMENT_CENTER": 1, "HORIZONTAL_ALIGNMENT_RIGHT": 2, "HORIZONTAL_ALIGNMENT_FILL": 3,
    "VERTICAL_ALIGNMENT_TOP": 0, "VERTICAL_ALIGNMENT_CENTER": 1, "VERTICAL_ALIGNMENT_BOTTOM": 2, "VERTICAL_ALIGNMENT_FILL": 3,
    "MOUSE_BUTTON_LEFT": 1, "MOUSE_BUTTON_RIGHT": 2, "MOUSE_BUTTON_MIDDLE": 3,
    "MOUSE_MODE_VISIBLE": 0, "MOUSE_MODE_HIDDEN": 1, "MOUSE_MODE_CAPTURED": 2,
    "SIDE_LEFT": 0, "SIDE_TOP": 1, "SIDE_RIGHT": 2, "SIDE_BOTTOM": 3,
    "CORNER_TOP_LEFT": 0, "CORNER_TOP_RIGHT": 1, "CORNER_BOTTOM_RIGHT": 2, "CORNER_BOTTOM_LEFT": 3,
}

_CLASSES = {}


def engine_class(name):
    cls = _CLASSES.get(name)
    if cls is None:
        if name == "Timer":
            cls = Timer
        elif name == "Tween":
            cls = Tween
        elif name == "Node":
            cls = Node
        elif name == "Viewport":
            cls = Viewport
        elif name in NODE_PARENTS:
            parent = NODE_PARENTS[name]
            cls = type(name, (Viewport if parent == "Viewport" else engine_class(parent) if parent != "Node" else EngineNode,), {})
        elif name in RESOURCE_PARENTS:
            parent = RESOURCE_PARENTS[name]
            base = getattr(rt, parent, None) if parent in ("Resource", "Font", "Texture2D", "AudioStream") else engine_class(parent)
            if parent == "Resource" or not isinstance(base, type):
                base = EngineResource
            cls = type(name, (base,) if base is not EngineResource and issubclass(base, EngineResource) else (EngineResource,), {})
        else:
            cls = type(name, (EngineObject,), {})
        _CLASSES[name] = cls
    return cls


def lookup(name):
    """Global-name fallback used by the loader: engine singletons, constants and classes. None if unknown."""
    if name in SINGLETON_NAMES:
        return _singleton(name)
    if name in GLOBAL_CONSTANTS:
        return GLOBAL_CONSTANTS[name]
    if name[:1].isupper():
        if name.isupper() or (name.upper() == name.replace("_", "").upper() and "_" in name):
            return _const("global", name)
        return engine_class(name)
    return None


def _permissive_getattr(self, n):
    if n.startswith("_"):
        raise AttributeError(n)
    v = Opaque("%s.%s" % (type(self).__name__, n))
    self.__dict__[n] = v
    return v


def install(module, permissive=False):
    """Publish the engine stubs into the runtime module (so the transpiler sees them as known globals).
    permissive=True (smoke runs) also lets plain Node / SceneTree accept members the emulator does not
    model; the test runs keep them strict so a mistyped member is an error there."""
    if permissive:
        module.Time.virtual = True
        module.Node.__getattr__ = _permissive_getattr
        module.SceneTree.__getattr__ = _permissive_getattr
    module.Opaque = Opaque
    module.Node.create_tween = lambda self, *a: Tween()
    module.SceneTree.create_tween = lambda self, *a: Tween()
    module.TREE.viewport = Viewport()
    module.TREE.viewport._gd_in_tree = True
    module.TREE.root.add_child(module.TREE.viewport)
    module.finish_tweens = finish_tweens
    module.TREE.frame_hook = frame_hook
