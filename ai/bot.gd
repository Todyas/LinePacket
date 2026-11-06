class_name Bot
extends RefCounted
## Бот: источник команд. Видит мир только через BotView (знания своего игрока), играет как человек.
## Играет ролями машин и задачами агентов: расширение, дозор, укрепление, операции давления и заражения, ответ на логи IDS.

var v: BotView
var me: int
var enemy: int
var rng: Rng
var prof: Dictionary
var _last_event_tick: int = -1
var _threat: Dictionary = {}          # узел -> тик последней атаки по логу IDS
var _alarm: Dictionary = {}           # узел -> тик, когда его начал захватывать чужой агент
var _dist_to_enemy_core: PackedInt32Array = PackedInt32Array()
var _dist_to_my_core: PackedInt32Array = PackedInt32Array()
var _enemy_core: int = -1
var _topology: int = -1
var _op_since: Dictionary = {}        # цель -> тик, когда бот впервые занялся ей
var _skip_until: Dictionary = {}      # цель -> тик, до которого не трогаем (спор или затянувшаяся операция)

func _init(view: BotView, seed_value: int, profile: Dictionary = Defs.BOT_PROFILE) -> void:
	v = view
	me = view.me
	enemy = (me + 1) % view.player_count()
	rng = Rng.new(seed_value * 7919 + me * 104729 + 13)
	prof = profile
	for c in view.core_nodes():
		if c != view.my_core():
			_enemy_core = c
	_refresh_distances()

## Расстояния до ядер в хопах; пересчитываются, когда стройка меняет карту.
func _refresh_distances() -> void:
	_topology = v.topology_stamp()
	_dist_to_enemy_core.resize(v.node_count())
	_dist_to_my_core.resize(v.node_count())
	for n in v.node_count():
		_dist_to_my_core[n] = v.hops(n, v.my_core())
		_dist_to_enemy_core[n] = v.hops(n, _enemy_core) if _enemy_core >= 0 else 0

## Вызывается каждый тик; думает раз в think_ticks, со сдвигом по номеру игрока.
func act() -> void:
	if v.match_over():
		return
	if v.tick() % int(prof["think_ticks"]) != (me * 3) % int(prof["think_ticks"]):
		return
	var mine: Array[int] = v.my_nodes()
	if mine.is_empty():
		return
	if v.topology_stamp() != _topology:
		_refresh_distances()
	_read_events()
	_release_stale_ops()
	_defend_with_agents(mine)
	_activate_viruses(mine)
	_capture_ops()
	_take_routers(mine)
	_router_rules()
	_retake_and_clean(mine)
	_fortify(mine)
	_build(mine)
	_expand(mine)
	_watch(mine)
	_attack(mine)
	_last_event_tick = v.tick() - 1

# --- События ---

func _read_events() -> void:
	for e in v.events():
		if int(e[0]) <= _last_event_tick:
			continue
		if int(e[1]) == Knowledge.EventKind.IDS_ATTACK:
			_threat[int(e[2])] = int(e[0])
		elif int(e[1]) == Knowledge.EventKind.AGENT_CAPTURING:
			_alarm[int(e[2])] = int(e[0])

func _under_threat(n: int) -> bool:
	return _threat.has(n) and v.tick() - int(_threat[n]) < int(prof["threat_memory_s"]) * Defs.TICK_HZ

# --- Роли ---

## Боевые роли своих машин: [{node, role, target}].
func _combat_roles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in v.my_nodes():
		var info: Dictionary = v.own(n)
		if info.is_empty():
			continue
		if Defs.COMBAT_ROLES.has(int(info["role"])):
			out.append({"node": n, "role": int(info["role"]), "target": int(info["role_target"])})
	return out

func _roles_on(target: int, role: int) -> int:
	var k: int = 0
	for r in _combat_roles():
		if int(r["target"]) == target and int(r["role"]) == role:
			k += 1
	return k

func _targets_of(role: int) -> Dictionary:
	var out: Dictionary = {}
	for r in _combat_roles():
		if int(r["role"]) == role:
			out[int(r["target"])] = true
	return out

func _set_role(node: int, role: int, target: int) -> void:
	v.submit(Command.set_role(me, v.tick(), node, role, target))

## Свободные машины (и ядро, если нужно) в работе не дальше max_hops от цели, ближние первыми.
func _free_near(target: int, max_hops: int, count: int, allow_core: bool) -> Array[int]:
	var cands: Array = []
	for n in v.my_nodes():
		var t: int = v.node_type(n)
		if t != Defs.NodeType.MACHINE and not (allow_core and t == Defs.NodeType.CORE):
			continue
		var info: Dictionary = v.own(n)
		if info.is_empty() or info["down"] or int(info["role"]) != Defs.Role.WORK or int(info["reconf"]) > 0:
			continue
		var h: int = v.hops(n, target)
		if h < 0 or h > max_hops:
			continue
		cands.append([h + (1 if t == Defs.NodeType.CORE else 0) * 2, n])
	cands.sort()
	var out: Array[int] = []
	for c in cands:
		if out.size() >= count:
			break
		out.append(int(c[1]))
	return out

## Сколько машин сейчас в бою и сколько можно держать (доля от всех машин).
func _combat_room() -> int:
	var machines: int = 0
	for n in v.my_nodes():
		if v.node_type(n) == Defs.NodeType.MACHINE:
			machines += 1
	var cap: int = maxi(int(prof["min_combat"]), machines * int(prof["max_combat_percent"]) / 100)
	var busy: int = 0
	for r in _combat_roles():
		if int(r["role"]) != Defs.Role.CAPTURE:
			busy += 1
	return cap - busy

## Затянувшиеся операции снимаем: машины возвращаются к работе, цель на время откладывается.
func _release_stale_ops() -> void:
	var seen: Dictionary = {}
	for r in _combat_roles():
		var tgt: int = int(r["target"])
		seen[tgt] = true
		if not _op_since.has(tgt):
			_op_since[tgt] = v.tick()
		var limit: int = int(prof["init_timeout_s"]) if int(r["role"]) == Defs.Role.CAPTURE else int(prof["op_timeout_s"])
		if v.tick() - int(_op_since[tgt]) > limit * Defs.TICK_HZ:
			_set_role(int(r["node"]), Defs.Role.WORK, -1)
			_skip_until[tgt] = v.tick() + int(prof["op_cooldown_s"]) * Defs.TICK_HZ
	for tgt in _op_since.keys():
		if not seen.has(tgt):
			_op_since.erase(tgt)

func _skipped(n: int) -> bool:
	return _skip_until.has(n) and v.tick() < int(_skip_until[n])

# --- Скрытые вирусы ---

## Свой тайный вирус открывает дверь, только если агент сразу поедет захватывать (окно двери — 20 с).
func _activate_viruses(_mine: Array[int]) -> void:
	for n in v.node_count():
		var s: NodeSnap = v.snap(n)
		if s == null or not s.my_virus or v.owner_of(n) != enemy or _pending_for(n):
			continue
		if _give_task(Defs.TaskKind.CAPTURE, n, 0, true):
			v.submit(Command.activate(me, v.tick(), n, Defs.ActivateMode.OPEN_DOOR))
			return

# --- Агенты ---

## Поставить задачу первому свободному агенту, если хватает байтов. true — поставлена.
## urgent: если свободных нет, оборвать самого незанятого важным делом агента (но не захват и не защиту).
func _give_task(kind: int, node: int, arg: int = 0, urgent: bool = false) -> bool:
	var cost: int = int(Agents.capture_params(v.node_type(node))[1]) if kind == Defs.TaskKind.CAPTURE else int(Agents.task_params(kind, arg)[1])
	if kind == Defs.TaskKind.CAPTURE and v.node_type(node) == Defs.NodeType.ROUTER:
		kind = Defs.TaskKind.TAKE_ROUTER
	if v.bank() < cost + int(prof["reserve"]):
		return false
	var best: int = -1
	for a in v.my_agents():
		if (a["queue"] as Array).size() > 0 or int(a["mode"]) == AgentState.Mode.LOST:
			continue
		best = int(a["idx"])
		break
	if best < 0 and urgent:
		var fewest: int = 1 << 20
		for a in v.my_agents():
			var q: Array = a["queue"]
			if q.is_empty() or int(a["mode"]) == AgentState.Mode.LOST:
				continue
			var head: int = int(q[0][0])
			if head == Defs.TaskKind.CAPTURE or head == Defs.TaskKind.EVICT:
				continue
			if q.size() < fewest:
				fewest = q.size()
				best = int(a["idx"])
		if best >= 0:
			v.submit(Command.clear_queue(me, v.tick(), best))
	if best < 0:
		return false
	for a in v.my_agents():
		for t in (a["queue"] as Array):
			if int(t[0]) == kind and int(t[1]) == node and int(t[2]) == arg:
				return false
	v.submit(Command.queue_task(me, v.tick(), best, kind, node, arg))
	return true

func _pending_for(node: int) -> bool:
	for a in v.my_agents():
		for t in (a["queue"] as Array):
			if int(t[1]) == node:
				return true
	return false

## Найденное чистим, потерянное по старым ключам отыгрываем, захваченное закрепляем.
func _retake_and_clean(mine: Array[int]) -> void:
	for n in mine:
		var info: Dictionary = v.own(n)
		if info.is_empty() or _pending_for(n):
			continue
		if info["has_found_threat"] or int(info["infect"]) > 20000 or int(info["infect"]) >= Defs.INFECT_MAX:
			if _give_task(Defs.TaskKind.CLEAN_VIRUS, n):
				return
		if int(info["prev_owner"]) >= 0:
			if _give_task(Defs.TaskKind.ENTRENCH, n):
				return

## Операция «агент → захват»: у врага есть узел, куда у нас есть вход (пароль, ключ, бэкдор, заражение, лежит) — агент едет захватывать.
## Первым — ядро, затем ближайшие к ядру врага. Потерянное по старым ключам берётся этим же путём.
func _capture_ops() -> void:
	var best: int = -1
	var best_score: int = 1 << 20
	for n in v.node_count():
		var s: NodeSnap = v.snap(n)
		if s == null or s.owner != enemy or not s.my_entry or _pending_for(n):
			continue
		if _skipped(n) or v.level(n) == Knowledge.Level.SILHOUETTE:
			continue
		var score: int = _dist_to_enemy_core[n]
		if v.node_type(n) == Defs.NodeType.CORE:
			score -= 100
		if score < best_score:
			best_score = score
			best = n
	if best >= 0 and _give_task(Defs.TaskKind.CAPTURE, best, 0, true):
		_skip_until[best] = v.tick() + int(prof["capture_retry_s"]) * Defs.TICK_HZ

## Ничьи маршрутизаторы своей половины карты берёт агент: чем ближе к нашему ядру, тем раньше.
func _take_routers(mine: Array[int]) -> void:
	var owned: int = 0
	for n in mine:
		if v.node_type(n) == Defs.NodeType.ROUTER:
			owned += 1
	if owned >= int(prof["max_routers"]):
		return
	var best: int = -1
	var best_d: int = 1 << 20
	for n in v.node_count():
		if v.node_type(n) != Defs.NodeType.ROUTER or v.owner_of(n) != Defs.NEUTRAL or _pending_for(n) or _skipped(n):
			continue
		if _dist_to_my_core[n] + int(prof["expand_enemy_gap"]) > _dist_to_enemy_core[n]:
			continue    # чужую половину не трогаем
		if _dist_to_my_core[n] < best_d:
			best_d = _dist_to_my_core[n]
			best = n
	if best >= 0 and _give_task(Defs.TaskKind.TAKE_ROUTER, best):
		_skip_until[best] = v.tick() + int(prof["capture_retry_s"]) * Defs.TICK_HZ

## Правило своих маршрутизаторов: на передовой закрыты для чужого транзита, в тылу открыты.
func _router_rules() -> void:
	for n in v.my_nodes():
		if v.node_type(n) != Defs.NodeType.ROUTER:
			continue
		var info: Dictionary = v.own(n)
		if info.is_empty():
			continue
		var want_open: bool = _dist_to_my_core[n] + int(prof["router_close_gap"]) < _dist_to_enemy_core[n]
		if bool(info["router_open"]) != want_open:
			v.submit(Command.set_router_rule(me, v.tick(), n, want_open))

## Чужой агент берёт нашу машину: ближайший свободный агент едет и выгоняет его.
func _defend_with_agents(mine: Array[int]) -> void:
	for n in mine:
		if not _alarm.has(n) or v.tick() - int(_alarm[n]) > int(prof["alarm_memory_s"]) * Defs.TICK_HZ:
			continue
		if _pending_for(n):
			continue
		if _give_task(Defs.TaskKind.EVICT, n, 0, true):
			return

# --- Укрепление ---

func _fortify(mine: Array[int]) -> void:
	var core: int = v.my_core()
	var wants: Array = []     # [узел, вид, аргумент]
	# Узлы под атакой по логу IDS: файрвол, антивирус, ключи.
	for n in mine:
		if _under_threat(n):
			wants.append([n, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.FIREWALL])
			wants.append([n, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.ANTIVIRUS])
			wants.append([n, Defs.TaskKind.SET_KEYS, 0])
	# Ядро: IDS, файрвол, антивирус.
	wants.append([core, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.IDS])
	wants.append([core, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.FIREWALL])
	wants.append([core, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.ANTIVIRUS])
	# Шлюзы кормят банк: файрвол и ключи; ближние к врагу машины — ключи и файрвол.
	for n in mine:
		var t: int = v.node_type(n)
		if t == Defs.NodeType.GATEWAY:
			wants.append([n, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.FIREWALL])
			wants.append([n, Defs.TaskKind.SET_KEYS, 0])
			wants.append([n, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.ANTIVIRUS])
		elif t == Defs.NodeType.MACHINE and _is_border(n):
			wants.append([n, Defs.TaskKind.SET_KEYS, 0])
			wants.append([n, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.FIREWALL])
			wants.append([n, Defs.TaskKind.INSTALL_SOFT, Defs.SoftType.ANTIVIRUS])
	for n in mine:
		if v.node_type(n) == Defs.NodeType.MACHINE:
			wants.append([n, Defs.TaskKind.SET_KEYS, 0])
	for w in wants:
		var n: int = int(w[0])
		var info: Dictionary = v.own(n)
		if info.is_empty() or _pending_for(n):
			continue
		var kind: int = int(w[1])
		var arg: int = int(w[2])
		if kind == Defs.TaskKind.INSTALL_SOFT:
			if (info["soft"] as Array).has(arg) or int(info["free_slots"]) <= 0:
				continue
		elif kind == Defs.TaskKind.SET_KEYS:
			if int(info["access_mode"]) == Defs.AccessMode.KEYS:
				continue
		if _give_task(kind, n, arg):
			return

## Граница: есть сосед, который не мой и враждебен или неизвестен.
func _is_border(n: int) -> bool:
	for o in v.neighbors(n):
		var ow: int = v.owner_of(o)
		if ow == enemy or ow == Knowledge.UNKNOWN_OWNER:
			return true
	return false

# --- Расширение ---

func _expand(mine: Array[int]) -> void:
	var capturing: Dictionary = _targets_of(Defs.Role.CAPTURE)
	if capturing.size() >= int(prof["max_init_flows"]):
		return
	var gateways: int = 0
	for n in mine:
		if v.node_type(n) == Defs.NodeType.GATEWAY:
			gateways += 1
	if mine.size() >= int(prof["base_nodes"]) + int(prof["nodes_per_gateway"]) * gateways:
		return     # не перерастягиваем сеть: дальние машины дорого держать
	var best: int = -1
	var best_score: int = -1000000
	var best_src: Array[int] = []
	for n in v.node_count():
		if v.owner_of(n) != Defs.NEUTRAL or not Defs.INIT_NEEDED.has(v.node_type(n)) or capturing.has(n) or _skipped(n):
			continue
		# Нейтралов на чужой половине карты не трогаем: бот тянется к врагу, но не лезет ему под нос.
		if _dist_to_my_core[n] + int(prof["expand_enemy_gap"]) > _dist_to_enemy_core[n]:
			continue
		var src: Array[int] = _free_near(n, int(prof["expand_hops"]), int(prof["capture_machines"]), true)
		if src.is_empty():
			continue
		var h: int = v.hops(src[0], n)
		var score: int = 0
		if v.node_type(n) == Defs.NodeType.GATEWAY:
			score += 100 if gateways * 4 <= mine.size() else 30
		score -= h * 25
		score -= _dist_to_enemy_core[n] * int(prof["toward_enemy"])
		score += rng.range_int(0, 6)
		if score > best_score:
			best_score = score
			best = n
			best_src = src
	if best >= 0:
		for m in best_src:
			_set_role(m, Defs.Role.CAPTURE, best)

# --- Строительство ---

## Одна стройка за раз по приоритету: апгрейд боевой машины, линк в обход к своему шлюзу, новая машина ближе к врагу.
## Байты на задачи агентов (build_reserve) стройка не трогает.
func _build(mine: Array[int]) -> void:
	if v.pending_builds() >= int(prof["build_parallel"]):
		return
	var spare: int = v.bank() - int(prof["build_reserve"])
	if spare <= 0:
		return
	# 1. CPU боевым машинам.
	if v.tick() >= int(prof["build_cpu_start_s"]) * Defs.TICK_HZ:
		for n in mine:
			var info: Dictionary = v.own(n)
			if info.is_empty() or not Defs.COMBAT_ROLES.has(int(info["role"])):
				continue
			if int(info["cpu_level"]) >= int(prof["build_cpu_levels"]):
				continue
			if v.build_refusal(Defs.BuildKind.CPU, n) == "" and v.build_cost(Defs.BuildKind.CPU, n) <= spare:
				v.submit(Command.build(me, v.tick(), Defs.BuildKind.CPU, n))
				return
	# 2. Кабель от машины к своему шлюзу через один узел.
	for g in mine:
		if v.node_type(g) != Defs.NodeType.GATEWAY:
			continue
		for m in mine:
			if v.node_type(m) != Defs.NodeType.MACHINE or v.hops(m, g) != 2:
				continue
			if v.build_refusal(Defs.BuildKind.CABLE, m, g) == "" and v.build_cost(Defs.BuildKind.CABLE, m, g) <= spare:
				v.submit(Command.build(me, v.tick(), Defs.BuildKind.CABLE, m, g))
				return
	# 3. Новая машина рядом с тем своим узлом, что ближе к врагу и оставляет себе порт.
	if mine.size() >= int(prof["build_nodes_cap"]):
		return
	var best: int = -1
	var best_d: int = 1000000
	for n in mine:
		if v.node_type(n) == Defs.NodeType.ROUTER or v.free_ports(n) < 2:
			continue
		if _dist_to_enemy_core[n] < best_d and v.build_refusal(Defs.BuildKind.MACHINE, n) == "":
			best_d = _dist_to_enemy_core[n]
			best = n
	if best >= 0 and v.build_cost(Defs.BuildKind.MACHINE, best) <= spare:
		v.submit(Command.build(me, v.tick(), Defs.BuildKind.MACHINE, best))

# --- Дозор ---

## Одна граничная машина в дозоре: снимки соседей врага обновляются сами.
func _watch(mine: Array[int]) -> void:
	if mine.size() < int(prof["base_nodes"]):
		return
	var watchers: int = 0
	var best: int = -1
	var best_score: int = -(1 << 20)
	for n in mine:
		var info: Dictionary = v.own(n)
		if info.is_empty() or v.node_type(n) != Defs.NodeType.MACHINE:
			continue
		if int(info["role"]) == Defs.Role.WATCH:
			if _blind_near(n, true) == 0:
				_set_role(n, Defs.Role.WORK, -1)    # дозорному смотреть не на что: все вокруг уже наблюдаются
			else:
				watchers += 1
		elif int(info["role"]) == Defs.Role.WORK and int(info["reconf"]) == 0:
			# Дозор ставим туда, где в радиусе больше всего ещё неизвестных узлов; при равенстве — ближе к врагу.
			var score: int = _blind_near(n, false) * 8 - _dist_to_enemy_core[n]
			if score > best_score:
				best_score = score
				best = n
	if watchers < int(prof["watchers"]) and best >= 0:
		_set_role(best, Defs.Role.WATCH, -1)

## Сколько узлов в радиусе дозора от n не наблюдаются прямо сейчас: только силуэт или (если with_snaps) ещё и снимок.
func _blind_near(n: int, with_snaps: bool) -> int:
	var seen: Dictionary = {n: true}
	var frontier: Array[int] = [n]
	var blind: int = 0
	for step in Defs.WATCH_RADIUS:
		var next: Array[int] = []
		for f in frontier:
			for u in v.neighbors(f):
				if seen.has(u):
					continue
				seen[u] = true
				next.append(u)
				var lvl: int = v.level(u)
				if lvl == Knowledge.Level.SILHOUETTE or (with_snaps and lvl == Knowledge.Level.SNAPSHOT):
					blind += 1
		frontier = next
	return blind

# --- Атака ---

func _defense(s: NodeSnap) -> int:
	var d: int = 0
	if s.has_soft(Defs.SoftType.FIREWALL):
		d += 3
	if s.has_soft(Defs.SoftType.ANTIVIRUS):
		d += 3
	if s.has_soft(Defs.SoftType.IDS):
		d += 1
	return d

func _defended(s: NodeSnap) -> bool:
	return s.has_soft(Defs.SoftType.FIREWALL) or s.has_soft(Defs.SoftType.ANTIVIRUS)

## Операция против одной цели: защищённую давим машинами и при деньгах заражаем; слабую или лежащую заражаем сразу.
func _attack(mine: Array[int]) -> void:
	if v.tick() < int(prof["attack_start_s"]) * Defs.TICK_HZ or mine.size() < int(prof["attack_min_nodes"]):
		return
	# Цели, над которыми уже работают; новая берётся, только если не больше max_attack_targets.
	var targets: Dictionary = {}
	for r in _combat_roles():
		if int(r["role"]) != Defs.Role.CAPTURE:
			targets[int(r["target"])] = true
	var best: int = -1
	var best_score: int = 1 << 20
	for n in v.node_count():
		if v.owner_of(n) != enemy or v.node_type(n) == Defs.NodeType.ROUTER or _skipped(n):
			continue
		var busy: bool = targets.has(n)
		if not busy and targets.size() >= int(prof["max_attack_targets"]):
			continue
		var near: Array[int] = _free_near(n, Defs.ROLE_MAX_HOPS, 1, false)
		if near.is_empty() and not busy:
			continue
		var s: NodeSnap = v.snap(n)
		if s == null or (s.my_entry and not busy):
			continue    # вход уже есть: дальше работает агент
		var h: int = v.hops(near[0], n) if not near.is_empty() else 1
		if h > int(prof["attack_hops"]):
			continue
		var score: int = _dist_to_enemy_core[n] * int(prof["core_pull"]) + _defense(s) * 4 + h * 3 + rng.range_int(0, 4)
		if busy:
			score -= 1000     # начатую операцию доводим
		if v.node_type(n) == Defs.NodeType.CORE:
			score -= 100
		if score < best_score:
			best_score = score
			best = n
	if best < 0:
		return
	var tgt: NodeSnap = v.snap(best)
	var rich: bool = v.bank() >= int(prof["payload_rich_bank"])
	# Желаемый состав: [давление, заражение, тайное заражение].
	var want_press: int = 0
	var want_inf: int = 0
	var want_hidden: int = 0
	if _defended(tgt) and not tgt.down:
		want_press = int(prof["pressure_machines"])
		if rich:
			if v.node_type(best) != Defs.NodeType.CORE and rng.range_int(0, 100) < int(prof["hidden_percent"]):
				want_hidden = 1
			else:
				want_inf = 1
	else:
		want_press = 1 if tgt.down else 0
		if v.bank() >= 20:
			want_inf = int(prof["infect_machines"])
	_fill_roles(best, Defs.Role.PRESSURE, want_press)
	_fill_roles(best, Defs.Role.INFECT, want_inf)
	_fill_roles(best, Defs.Role.INFECT_HIDDEN, want_hidden)

func _fill_roles(target: int, role: int, want: int) -> void:
	var have: int = _roles_on(target, role)
	if have >= want or _combat_room() <= 0:
		return
	if role == Defs.Role.INFECT_HIDDEN and v.snap(target) != null and v.snap(target).my_virus:
		return
	for m in _free_near(target, Defs.ROLE_MAX_HOPS, want - have, false):
		_set_role(m, role, target)
