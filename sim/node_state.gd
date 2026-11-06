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
# Скрытое (S6): по игрокам-атакующим.
var virus: PackedInt32Array = PackedInt32Array()          # 1 — стоит тайный вирус этого игрока
var virus_meter: PackedInt32Array = PackedInt32Array()    # шкала скрытого заражения
var backdoor: PackedInt32Array = PackedInt32Array()       # 1 — у игрока есть бэкдор
var skim_acc: PackedInt32Array = PackedInt32Array()       # накопитель отвода DATA вирусом
var det_timer: PackedInt32Array = PackedInt32Array()      # тики наблюдения по [вид * MAX_PLAYERS + кто]
var found: PackedInt32Array = PackedInt32Array()          # 1 — найдено (видит нашедший), те же индексы
var door: PackedInt32Array = PackedInt32Array()          # тиков открытой двери по игрокам: у вора доступ
var soft_off: int = 0                      # тиков осталось, пока ПО выведено из строя активацией вируса
var sniff_acc: int = 0
var ids_cool: PackedInt32Array = PackedInt32Array()  # тик последней записи IDS по атакующим
var auto_sent: int = 0                     # сколько автоматических пакетов (DATA, KEEPALIVE) отправил узел
# Роль (S9).
var role: int = Defs.Role.WORK
var role_target: int = -1                  # цель боевой роли
var role_acc: int = 0                      # накопитель пакетов роли; у дозора — тики до снимка
var reconf: int = 0                        # тиков перенастройки осталось: машина ничего не шлёт

func _init() -> void:
	cpu_hist.resize(Defs.LOAD_WINDOW)
	capture.resize(Defs.MAX_PLAYERS)
	infect.resize(Defs.MAX_PLAYERS)
	brute.resize(Defs.MAX_PLAYERS)
	virus.resize(Defs.MAX_PLAYERS)
	virus_meter.resize(Defs.MAX_PLAYERS)
	backdoor.resize(Defs.MAX_PLAYERS)
	skim_acc.resize(Defs.MAX_PLAYERS)
	det_timer.resize(Defs.HIDDEN_KIND_COUNT * Defs.MAX_PLAYERS)
	found.resize(Defs.HIDDEN_KIND_COUNT * Defs.MAX_PLAYERS)
	door.resize(Defs.MAX_PLAYERS)
	ids_cool.resize(Defs.MAX_PLAYERS)
	ids_cool.fill(-1000000)

func reset_role() -> void:
	role = Defs.Role.WORK
	role_target = -1
	role_acc = 0
	reconf = 0

func is_combat() -> bool:
	return Defs.COMBAT_ROLES.has(role)

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

## ПО работает, только пока узел не лежит, не заражён и не открыта дверь.
func soft_active(t: int) -> bool:
	return not down and soft_off <= 0 and not is_infected() and soft.has(t)

## Заражена ли машина на 100% кем-то из чужих: ПО защитника молчит, у заразившего есть доступ, пока агент не вычистит.
func is_infected() -> bool:
	for p in infect.size():
		if p != owner and infect[p] >= Defs.INFECT_MAX:
			return true
	return false

## Игрок заразил эту машину на 100%.
func infected_by(p: int) -> bool:
	return p != owner and infect[p] >= Defs.INFECT_MAX

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
	door.fill(0)
	clear_hidden()

## Тайные вирусы, бэкдоры и всё, что нашли; сниффер — обычное ПО, его убирает clear_soft.
func clear_hidden() -> void:
	virus.fill(0)
	virus_meter.fill(0)
	backdoor.fill(0)
	skim_acc.fill(0)
	det_timer.fill(0)
	found.fill(0)

static func hidden_slot(kind: int, who: int) -> int:
	return kind * Defs.MAX_PLAYERS + who

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
	h.add_array(virus)
	h.add_array(virus_meter)
	h.add_array(backdoor)
	h.add_array(skim_acc)
	h.add_array(det_timer)
	h.add_array(found)
	h.add_array(door)
	h.add(soft_off)
	h.add(sniff_acc)
	h.add(prev_owner)
	h.add(auto_sent)
	h.add(role)
	h.add(role_target)
	h.add(role_acc)
	h.add(reconf)
