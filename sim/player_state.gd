class_name PlayerState
extends RefCounted

var id: int = 0
var core_node: int = -1
var bank: int = 0
var income_hist: PackedInt32Array = PackedInt32Array()   # байт по тикам за последнюю секунду
var earned_total: int = 0
var captures: int = 0          # захвачено нейтралов за матч
var hire_left: int = 0         # тиков до выхода нанимаемого агента; 0 — наёма нет

func _init() -> void:
	income_hist.resize(Defs.LOAD_WINDOW)

## Доход в байтах за последнюю секунду.
func income_per_s() -> int:
	var total: int = 0
	for v in income_hist:
		total += v
	return total

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(core_node)
	h.add(bank)
	h.add_array(income_hist)
	h.add(earned_total)
	h.add(captures)
	h.add(hire_left)
