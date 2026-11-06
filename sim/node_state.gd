class_name NodeState
extends RefCounted

var id: int = 0
var type: int = Defs.NodeType.MACHINE
var owner: int = Defs.NEUTRAL
var x: int = 0
var y: int = 0
var links: Array[int] = []   # id линков, по возрастанию

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(type)
	h.add(owner)
	h.add(x)
	h.add(y)
