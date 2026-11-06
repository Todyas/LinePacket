class_name PlayerState
extends RefCounted

var id: int = 0
var core_node: int = -1

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(core_node)
