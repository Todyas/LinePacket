class_name Rng
extends RefCounted
## Детерминированный генератор (xorshift32). Единственный источник случайности в sim.

var state: int = 1

func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF
	if state == 0:
		state = 0x9E3779B9
	for i in 4:
		next_u32()

func next_u32() -> int:
	var x: int = state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x & 0xFFFFFFFF
	return state

## Целое в [lo, hi).
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo)
