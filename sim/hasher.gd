class_name Hasher
extends RefCounted
## Два канала FNV-1a по 32 бита, вместе дают 64-битный хеш состояния.

var h1: int = 0x811C9DC5
var h2: int = 0x01000193

func add(v: int) -> void:
	var lo: int = v & 0xFFFFFFFF
	var hi: int = (v >> 32) & 0xFFFFFFFF
	h1 = ((h1 ^ lo) * 0x01000193) & 0xFFFFFFFF
	h1 = ((h1 ^ hi) * 0x01000193) & 0xFFFFFFFF
	h2 = ((h2 ^ lo) * 0x5BD1E995) & 0xFFFFFFFF
	h2 = ((h2 ^ (hi + 0x9E37)) * 0x5BD1E995) & 0xFFFFFFFF
	h2 ^= h2 >> 15

func add_array(a: Array) -> void:
	add(a.size())
	for v in a:
		add(int(v))

func result() -> int:
	return (h2 << 32) | h1
