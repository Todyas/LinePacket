class_name FlowState
extends RefCounted

var id: int = 0
var owner: int = 0
var src: int = 0
var dst: int = 0
var ptype: int = 0
var rate: int = 1   # пакетов в секунду

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(owner)
	h.add(src)
	h.add(dst)
	h.add(ptype)
	h.add(rate)
