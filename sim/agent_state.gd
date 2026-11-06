class_name AgentState
extends RefCounted
## Агент: стоит на узле, едет AGENT-пакетом, работает над задачей или возвращается на ядро.

enum Mode { IDLE, TRAVEL, WORK, LOST }

var id: int = 0             # номер у игрока, 0..2
var owner: int = 0
var node: int = -1          # где стоит; -1 — в пути или потерян
var mode: int = Mode.IDLE
var queue: Array = []       # задачи: [вид, узел, аргумент]
var work_left: int = 0      # тиков до конца текущей задачи
var work_total: int = 0
var lost_timer: int = 0

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(owner)
	h.add(node)
	h.add(mode)
	h.add(work_left)
	h.add(work_total)
	h.add(lost_timer)
	h.add(queue.size())
	for t in queue:
		h.add(int(t[0]))
		h.add(int(t[1]))
		h.add(int(t[2]))

## Доля выполнения текущей задачи 0..1000 (для полосы прогресса).
func progress_permille() -> int:
	if mode != Mode.WORK or work_total <= 0:
		return 0
	return (work_total - work_left) * 1000 / work_total
