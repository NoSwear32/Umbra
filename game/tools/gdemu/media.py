"""
Emulated media resources for gdemu: enough of Image / Texture2D / Font / AudioStreamWAV to run the
tests that inspect shipped assets and untrusted character packs.

They read the real files (Pillow for PNG, fontTools for the cmap, the RIFF header for WAV), so the
checks are about the actual assets, but the engine's own import step is not emulated.
"""
import io
import os
import struct

from . import runtime as rt

try:
    from PIL import Image as _PIL
except ImportError:                                  # pragma: no cover - optional dependency
    _PIL = None
try:
    from fontTools.ttLib import TTFont as _TTFont
except ImportError:                                  # pragma: no cover - optional dependency
    _TTFont = None

ERR_FILE_CORRUPT = 16


class Texture2D(rt.Resource):
    def __init__(self, w=0, h=0):
        self._w, self._h = int(w), int(h)

    def get_width(self):
        return self._w

    def get_height(self):
        return self._h

    def get_size(self):
        return rt.Vector2(self._w, self._h)


class Image(rt.Resource):
    FORMAT_L8, FORMAT_LA8, FORMAT_R8, FORMAT_RG8, FORMAT_RGB8, FORMAT_RGBA8 = 0, 1, 2, 3, 4, 5

    def __init__(self):
        self._im = None

    @staticmethod
    def create_empty(w, h, mipmaps, fmt):
        if _PIL is None:
            raise rt.GDError("gdemu: Image needs Pillow")
        img = Image()
        img._im = _PIL.new("RGBA", (int(w), int(h)), (0, 0, 0, 0))
        return img

    @staticmethod
    def create(w, h, mipmaps, fmt):
        return Image.create_empty(w, h, mipmaps, fmt)

    def set_pixel(self, x, y, color):
        self._im.putpixel((int(x), int(y)), (int(round(color.r * 255)), int(round(color.g * 255)),
                                              int(round(color.b * 255)), int(round(color.a * 255))))

    def get_pixel(self, x, y):
        r, g, b, a = self._im.getpixel((int(x), int(y)))
        return rt.Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0)

    def fill(self, color):
        self._im.paste((int(round(color.r * 255)), int(round(color.g * 255)), int(round(color.b * 255)), int(round(color.a * 255))),
                       (0, 0, self._im.width, self._im.height))

    def save_png_to_buffer(self):
        out = io.BytesIO()
        self._im.save(out, format="PNG")
        return rt.PackedByteArray(out.getvalue())

    def load_png_from_buffer(self, buf):
        if _PIL is None:
            raise rt.GDError("gdemu: Image needs Pillow")
        try:
            im = _PIL.open(io.BytesIO(bytes(buf)))
            im.load()
        except Exception:                            # truncated / damaged data
            self._im = None
            return ERR_FILE_CORRUPT
        self._im = im.convert("RGBA")
        return rt.OK

    def get_width(self):
        return self._im.width if self._im is not None else 0

    def get_height(self):
        return self._im.height if self._im is not None else 0

    def is_empty(self):
        return self._im is None


class ImageTexture(Texture2D):
    @staticmethod
    def create_from_image(img):
        return ImageTexture(img.get_width(), img.get_height())


class Font(rt.Resource):
    def __init__(self, cmap=None):
        self._cmap = cmap or {}

    def has_char(self, code):
        return int(code) in self._cmap


class AudioStream(rt.Resource):
    pass


class AudioStreamWAV(AudioStream):
    LOOP_DISABLED, LOOP_FORWARD, LOOP_PINGPONG, LOOP_BACKWARD = 0, 1, 2, 3

    def __init__(self, length=0.0, loop_mode=0):
        self._length = float(length)
        self.loop_mode = loop_mode

    def get_length(self):
        return self._length


def load_wav(real):
    with open(real, "rb") as fh:
        data = fh.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return None
    pos = 12
    rate = channels = bits = 0
    frames = 0.0
    loops = 0
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            _fmt, channels, rate, _br, _ba, bits = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            frames = size / max(1, channels * bits // 8)
        elif cid == b"smpl" and len(body) >= 36:
            loops = struct.unpack("<I", body[28:32])[0]
        pos += 8 + size + (size & 1)
    return AudioStreamWAV(frames / max(1, rate), AudioStreamWAV.LOOP_FORWARD if loops > 0 else AudioStreamWAV.LOOP_DISABLED)


def load_media(real):
    ext = os.path.splitext(real)[1].lower()
    if ext == ".png":
        if _PIL is None:
            return None
        with _PIL.open(real) as im:
            return Texture2D(im.width, im.height)
    if ext == ".wav":
        return load_wav(real)
    if ext in (".ttf", ".otf"):
        if _TTFont is None:
            return None
        font = _TTFont(real)
        return Font(font.getBestCmap())
    return None


def install(module):
    """Publish the media classes as engine globals of the runtime."""
    for cls in (Texture2D, Image, ImageTexture, Font, AudioStream, AudioStreamWAV):
        setattr(module, cls.__name__, cls)
    module.ERR_FILE_CORRUPT = ERR_FILE_CORRUPT
