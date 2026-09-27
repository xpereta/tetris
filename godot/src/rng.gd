# src/rng.gd — EXACT port of the mulberry32 PRNG from js/engine.js (lines 18-27).
# JS uses 32-bit integer ops; GDScript ints are 64-bit, so every step is masked
# with & 0xFFFFFFFF and Math.imul is emulated via split multiplication.
#
# Bit-pattern convention: all intermediates are kept as UNSIGNED 32-bit patterns
# in [0, 2^32). Every shift in mulberry32 is a logical `>>>`, which on these
# non-negative values is exactly GDScript's plain `>>`.

class_name RNG extends RefCounted

const MASK := 0xFFFFFFFF


func _imul(a: int, b: int) -> int:
	# Emulates JS Math.imul: low 32 bits of the product (as a bit pattern).
	a &= MASK
	b &= MASK
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) << 16) & MASK)) & MASK


var _state: int


func _init(seed: int) -> void:
	# JS: let a = seed >>> 0;
	_state = seed & MASK


func next_uint() -> int:
	# JS closure body (returns the unsigned 32-bit numerator before division):
	#   a |= 0;
	#   a = (a + 0x6d2b79f5) | 0;
	#   let t = Math.imul(a ^ (a >>> 15), 1 | a);
	#   t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
	#   return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	_state = (_state + 0x6D2B79F5) & MASK # int32 add wraps mod 2^32
	var t := _imul(_state ^ (_state >> 15), _state | 1) # `a >>> 15` is logical: plain >> on a pattern
	var u := _imul(t ^ (t >> 7), t | 61) # `t >>> 7` is logical: plain >> on a pattern
	t = ((t + u) & MASK) ^ t # int32 addition wraps mod 2^32; XOR on bit patterns
	return (t ^ (t >> 14)) & MASK


func next() -> float:
	# JS divides the unsigned numerator by 2^32. IEEE-754 double division of two
	# exact values is deterministic, so this matches JS bit-for-bit.
	return next_uint() / 4294967296.0
