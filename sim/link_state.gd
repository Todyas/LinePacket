class_name LinkState
extends RefCounted

var id: int = 0
var a: int = 0
var b: int = 0
var kind: int = Defs.LinkKind.CABLE
var length: int = 0
var latency: int = 2       # тиков
var capacity: int = 10     # размер/сек на направление

func other(n: int) -> int:
	return b if n == a else a

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(a)
	h.add(b)
	h.add(kind)
	h.add(latency)
	h.add(capacity)
