class_name NodeState
extends RefCounted

var id: int = 0
var type: int = Defs.NodeType.MACHINE
var owner: int = Defs.NEUTRAL
var x: int = 0
var y: int = 0
var links: Array[int] = []   # id линков, по возрастанию

# CPU: кредит копится по cpu единиц за тик, одна операция стоит TICK_HZ.
var cpu_base: int = 0                      # мощность по типу узла
var cpu_per_s: int = 0                     # свободная мощность: база минус постоянная нагрузка ПО
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
# ПО и доступ.
var soft: PackedInt32Array = PackedInt32Array()
var fw_credit: int = 0
var access_mode: int = Defs.AccessMode.PASSWORD_WEAK
var access_mask: int = 0                   # у каких игроков (битовая маска) есть действующий доступ
var key_version: int = 0
# Атака.
var down: bool = false                     # перегружена и «лежит»
var infect: PackedInt32Array = PackedInt32Array()   # шкала заражения по атакующим
var brute: PackedInt32Array = PackedInt32Array()    # шкала подбора пароля по атакующим
var prev_owner: int = -1                   # кто владел до захвата заражением (пока не «закрепились»)
var ids_cool: PackedInt32Array = PackedInt32Array()  # тик последней записи IDS по атакующим
var auto_sent: int = 0                     # сколько автоматических пакетов (DATA, KEEPALIVE) отправил узел

func _init() -> void:
	cpu_hist.resize(Defs.LOAD_WINDOW)
	capture.resize(Defs.MAX_PLAYERS)
	infect.resize(Defs.MAX_PLAYERS)
	brute.resize(Defs.MAX_PLAYERS)
	ids_cool.resize(Defs.MAX_PLAYERS)
	ids_cool.fill(-1000000)

func setup_cpu() -> void:
	cpu_base = int(Defs.NODE_DEFS[type]["cpu"])
	soft.resize(Defs.MAX_SOFT_SLOTS)
	soft.fill(-1)
	refresh_cpu()
	cpu_credit = cpu_per_s * Defs.BURST_TICKS

## ПО ест CPU постоянно: свободная мощность = база − нагрузка ПО (но не меньше 4).
func refresh_cpu() -> void:
	cpu_per_s = maxi(4, cpu_base - soft_load())

func soft_load() -> int:
	var total: int = 0
	for t in soft:
		if t >= 0:
			total += int(Defs.SOFT_DEFS[t]["cpu_per_s"])
	return total

func has_soft(t: int) -> bool:
	return soft.has(t)

## ПО работает, только пока узел не лежит.
func soft_active(t: int) -> bool:
	return not down and soft.has(t)

func free_slots() -> int:
	var used: int = 0
	for t in soft:
		if t >= 0:
			used += 1
	return int(Defs.SOFT_SLOTS[type]) - used

func install_soft(t: int) -> bool:
	if free_slots() <= 0 or has_soft(t):
		return false
	for i in soft.size():
		if soft[i] < 0:
			soft[i] = t
			refresh_cpu()
			return true
	return false

func clear_soft() -> void:
	soft.fill(-1)
	refresh_cpu()

func clear_threats() -> void:
	infect.fill(0)
	brute.fill(0)

func reset_access() -> void:
	access_mode = Defs.AccessMode.PASSWORD_WEAK
	access_mask = 0 if owner < 0 else (1 << owner)

## Загрузка CPU за последнюю секунду, 0..100 (может превышать при упоре — ограничено 100).
func max_infect() -> int:
	var m: int = 0
	for v in infect:
		m = maxi(m, v)
	return m

func cpu_load_pct() -> int:
	var total: int = 0
	for v in cpu_hist:
		total += v
	return mini(100, (total + soft_load()) * 100 / cpu_base)

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
	h.add_array(soft)
	h.add(fw_credit)
	h.add(access_mode)
	h.add(access_mask)
	h.add(key_version)
	h.add(1 if down else 0)
	h.add_array(infect)
	h.add_array(brute)
	h.add_array(ids_cool)
	h.add(prev_owner)
	h.add(auto_sent)
