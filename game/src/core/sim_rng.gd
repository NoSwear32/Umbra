class_name SimRng
extends RefCounted
## Deterministic xorshift128 pseudo random generator.
##
## Godot's built-in RandomNumberGenerator is not used inside the simulation because
## its algorithm may change between engine versions, which would silently break
## stored replays. This generator only uses shifts and xors on 32-bit values, so
## its output is identical on every platform and engine version.

const M32: int = 0xFFFFFFFF

var _x: int = 0
var _y: int = 0
var _z: int = 0
var _w: int = 0


func _init(seed_value: int = 1) -> void:
	seed_state(seed_value)


static func _step32(v: int) -> int:
	v = v ^ ((v << 13) & M32)
	v = v ^ (v >> 17)
	v = v ^ ((v << 5) & M32)
	return v


func seed_state(s: int) -> void:
	var v: int = (s & M32) ^ 0x9E3779B9
	if v == 0:
		v = 0x1234567
	v = _step32(v)
	_x = v
	v = _step32(v)
	_y = v
	v = _step32(v)
	_z = v
	v = _step32(v)
	_w = v
	if (_x | _y | _z | _w) == 0:
		_w = 1
	for _i in range(16):
		next_u32()


## Next raw 32-bit value (0 .. 4294967295).
func next_u32() -> int:
	var t: int = _x ^ ((_x << 11) & M32)
	_x = _y
	_y = _z
	_z = _w
	_w = (_w ^ (_w >> 19)) ^ (t ^ (t >> 8))
	return _w


## Float in [0, 1) with 24 bits of resolution.
func next_float() -> float:
	return float(next_u32() >> 8) * (1.0 / 16777216.0)


func range_f(a: float, b: float) -> float:
	return a + (b - a) * next_float()


## Integer in [a, b] (inclusive).
func range_i(a: int, b: int) -> int:
	var n: int = b - a + 1
	return a + int((next_u32() >> 8) % n)
