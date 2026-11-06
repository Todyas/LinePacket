class_name NodeState
extends RefCounted

var id: int = 0
var type: int = Defs.NodeType.MACHINE
var owner: int = Defs.NEUTRAL
var x: int = 0
var y: int = 0
var links: Array[int] = []   # id линков, по возрастанию

# CPU: кредит копится по cpu единиц за тик, одна операция стоит TICK_HZ.
var cpu_per_s: int = 0
var cpu_credit: int = 0
var cpu_used_tick: int = 0
var cpu_hist: PackedInt32Array = PackedInt32Array()   # затраты по тикам за последнюю секунду

# Контроль и захват.
var control: int = 0                       # 0..CONTROL_MAX, у нейтрала 0
var capture: PackedInt32Array = PackedInt32Array()   # шкала захвата нейтрала по игрокам
var capture_tick: int = -1000              # тик последнего INIT на этот узел
var supplier: int = -1                     # кто шлёт этому узлу KEEPALIVE
var ka_acc: int = 0
# Экономика.
var gw_target: int = -1                    # ближайший свой шлюз для DATA
var buffer: int = 0                        # байты, не довезённые до шлюза
var produce_acc: int = 0
var send_acc: int = 0
var gw_credit: int = 0                     # потолок шлюза

func _init() -> void:
	cpu_hist.resize(Defs.LOAD_WINDOW)
	capture.resize(Defs.MAX_PLAYERS)

func setup_cpu() -> void:
	cpu_per_s = int(Defs.NODE_DEFS[type]["cpu"])
	cpu_credit = cpu_per_s * Defs.BURST_TICKS

## Загрузка CPU за последнюю секунду, 0..100 (может превышать при упоре — ограничено 100).
func cpu_load_pct() -> int:
	var total: int = 0
	for v in cpu_hist:
		total += v
	return mini(100, total * 100 / cpu_per_s)

func spend_cpu(cost: int) -> bool:
	var need: int = cost * Defs.TICK_HZ
	if cpu_credit < need:
		return false
	cpu_credit -= need
	cpu_used_tick += cost
	return true

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(type)
	h.add(owner)
	h.add(x)
	h.add(y)
	h.add(cpu_credit)
	h.add_array(cpu_hist)
	h.add(control)
	h.add_array(capture)
	h.add(capture_tick)
	h.add(supplier)
	h.add(ka_acc)
	h.add(gw_target)
	h.add(buffer)
	h.add(produce_acc)
	h.add(send_acc)
	h.add(gw_credit)
