class_name Bot
extends RefCounted
## Бот: источник команд. Видит мир только через BotView (знания своего игрока), играет как человек.
## Приоритеты: расширение, укрепление, разведка, атака цепочкой, ответ на атаки по логам IDS, скрытые вирусы.

var v: BotView
var me: int
var enemy: int
var rng: Rng
var prof: Dictionary
var _last_event_tick: int = -1
var _threat: Dictionary = {}          # узел -> тик последней атаки по логу IDS
var _last_scan: int = -100000
var _dist_to_enemy_core: PackedInt32Array = PackedInt32Array()
var _enemy_core: int = -1
var _started_attack: bool = false

func _init(view: BotView, seed_value: int, profile: Dictionary = Defs.BOT_PROFILE) -> void:
	v = view
	me = view.me
	enemy = (me + 1) % view.player_count()
	rng = Rng.new(seed_value * 7919 + me * 104729 + 13)
	prof = profile
	for c in view.core_nodes():
		if c != view.my_core():
			_enemy_core = c
	_dist_to_enemy_core.resize(view.node_count())
	for n in view.node_count():
		_dist_to_enemy_core[n] = view.hops(n, _enemy_core) if _enemy_core >= 0 else 0

## Вызывается каждый тик; думает раз в think_ticks, со сдвигом по номеру игрока.
func act() -> void:
	if v.match_over():
		return
	if v.tick() % int(prof["think_ticks"]) != (me * 3) % int(prof["think_ticks"]):
		return
	var mine: Array[int] = v.my_nodes()
	if mine.is_empty():
		return
	_read_events()
	_drop_stale_flows()
	_activate_viruses(mine)
	_tune_floods()
	_retake_and_clean(mine)
	_fortify(mine)
	_expand(mine)
	_recon(mine)
	_attack(mine)
	_last_event_tick = v.tick() - 1

# --- События ---

func _read_events() -> void:
	for e in v.events():
		if int(e[0]) <= _last_event_tick:
			continue
		if int(e[1]) == Knowledge.EventKind.IDS_ATTACK:
			_threat[int(e[2])] = int(e[0])

func _under_threat(n: int) -> bool:
	return _threat.has(n) and v.tick() - int(_threat[n]) < int(prof["threat_memory_s"]) * Defs.TICK_HZ

# --- Потоки ---

func _drop_stale_flows() -> void:
	for f in v.my_flows():
		var t: int = int(f["ptype"])
		var dst: int = int(f["dst"])
		var o: int = v.owner_of(dst)
		var dead: bool = false
		if t == Defs.PacketType.PAYLOAD or t == Defs.PacketType.PAYLOAD_HIDDEN or t == Defs.PacketType.FLOOD:
			dead = o != enemy
			if t == Defs.PacketType.PAYLOAD_HIDDEN and v.snap(dst) != null and v.snap(dst).my_virus:
				dead = true
		elif t == Defs.PacketType.INIT:
			dead = o != Defs.NEUTRAL
		if dead:
			v.submit(Command.stop_flow(me, v.tick(), int(f["id"])))

## Пока цель лежит и её заражают, флуд приглушаем: ему хватает держать загрузку выше порога подъёма,
## а свободный CPU цели нужен пакетам вируса (общий CPU делят все пакеты).
func _tune_floods() -> void:
	for f in _flows_of(Defs.PacketType.FLOOD):
		var dst: int = int(f["dst"])
		var sn: NodeSnap = v.snap(dst)
		if sn == null:
			continue
		var infecting: bool = _has_flow_to(Defs.PacketType.PAYLOAD, dst) or _has_flow_to(Defs.PacketType.PAYLOAD_HIDDEN, dst)
		var want: int = int(prof["flood_hold_rate"]) if (sn.down and infecting) else Defs.FLOW_MAX_RATE
		if int(f["rate"]) != want:
			v.submit(Command.set_flow_rate(me, v.tick(), int(f["id"]), want))

func _flows_of(ptype: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in v.my_flows():
		if int(f["ptype"]) == ptype:
			out.append(f)
	return out

func _flows_to(ptype: int, dst: int) -> int:
	var k: int = 0
	for f in _flows_of(ptype):
		if int(f["dst"]) == dst:
			k += 1
	return k

func _has_flow_to(ptype: int, dst: int) -> bool:
	for f in _flows_of(ptype):
		if int(f["dst"]) == dst:
			return true
	return false

## Свой узел-источник, ближайший к цели.
func _nearest_mine(mine: Array[int], target: int) -> int:
	var best: int = -1
	var best_h: int = 1 << 20
	for n in mine:
		if v.own(n).get("down", false):
			continue
		var h: int = v.hops(n, target)
		if h >= 0 and h < best_h:
			best_h = h
			best = n
	return best

# --- Скрытые вирусы ---

func _activate_viruses(mine: Array[int]) -> void:
	for n in v.node_count():
		var s: NodeSnap = v.snap(n)
		if s != null and s.my_virus and v.owner_of(n) == enemy:
			v.submit(Command.activate(me, v.tick(), n, Defs.ActivateMode.TAKEOVER))

# --- Агенты ---

## Поставить задачу первому свободному агенту, если хватает байтов. true — поставлена.
func _give_task(kind: int, node: int, arg: int = 0) -> bool:
	var params: Array = Agents.task_params(kind, arg)
	if v.bank() < int(params[1]) + int(prof["reserve"]):
		return false
	var best: int = -1
	for a in v.my_agents():
		if (a["queue"] as Array).size() > 0 or int(a["mode"]) == AgentState.Mode.LOST:
			continue
		best = int(a["idx"])
		break
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
		if info["has_found_threat"] or int(info["infect"]) > 20000:
			if _give_task(Defs.TaskKind.CLEAN_VIRUS, n):
				return
		if int(info["prev_owner"]) >= 0:
			if _give_task(Defs.TaskKind.ENTRENCH, n):
				return
	# Машина, потерянная по заражению: старые ключи пускают обратно.
	for n in v.node_count():
		var s: NodeSnap = v.snap(n)
		if s != null and s.owner == enemy and s.my_access and v.level(n) != Knowledge.Level.SILHOUETTE and v.node_type(n) != Defs.NodeType.SWITCH:
			if not _pending_for(n) and _give_task(Defs.TaskKind.ENTRENCH, n):
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
	var active: int = _flows_of(Defs.PacketType.INIT).size()
	if active >= int(prof["max_init_flows"]):
		return
	var gateways: int = 0
	for n in mine:
		if v.node_type(n) == Defs.NodeType.GATEWAY:
			gateways += 1
	if mine.size() >= int(prof["base_nodes"]) + int(prof["nodes_per_gateway"]) * gateways:
		return     # не перерастягиваем сеть: дальние машины дорого держать
	var best: int = -1
	var best_score: int = -1000000
	var best_src: int = -1
	for n in v.node_count():
		if v.owner_of(n) != Defs.NEUTRAL or not Defs.INIT_NEEDED.has(v.node_type(n)) or _has_flow_to(Defs.PacketType.INIT, n):
			continue
		var src: int = _nearest_mine(mine, n)
		if src < 0 or v.hops(src, n) > int(prof["expand_hops"]):
			continue
		var score: int = 0
		if v.node_type(n) == Defs.NodeType.GATEWAY:
			score += 100 if gateways * 4 <= mine.size() else 30
		score -= v.hops(src, n) * 25
		score -= _dist_to_enemy_core[n] * int(prof["toward_enemy"])
		score += rng.range_int(0, 6)
		if score > best_score:
			best_score = score
			best = n
			best_src = src
	if best >= 0:
		v.submit(Command.start_flow(me, v.tick(), best_src, best, Defs.PacketType.INIT, Defs.FLOW_DEFAULT_RATE * 3))

# --- Разведка ---

func _recon(mine: Array[int]) -> void:
	if v.tick() - _last_scan < int(prof["scan_interval_s"]) * Defs.TICK_HZ:
		return
	if not _flows_of(Defs.PacketType.SCAN).is_empty():
		return
	var best: int = -1
	var best_score: int = -1000000
	var best_src: int = -1
	for n in v.node_count():
		if v.owner_of(n) == me:
			continue
		var a: int = v.age(n)
		if a >= 0 and a < int(prof["rescan_s"]) * Defs.TICK_HZ:
			continue
		var src: int = _nearest_mine(mine, n)
		if src < 0:
			continue
		var h: int = v.hops(src, n)
		if h < 1 or h > Defs.SCAN_MAX_HOPS:
			continue
		var score: int = -_dist_to_enemy_core[n] * 10 - h
		if a < 0:
			score += 15
		score += rng.range_int(0, 4)
		if score > best_score:
			best_score = score
			best = n
			best_src = src
	if best >= 0:
		_last_scan = v.tick()
		v.submit(Command.start_flow(me, v.tick(), best_src, best, Defs.PacketType.SCAN, Defs.SCAN_FLOW_RATE))

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

## Цепочка: защищённую цель сначала топим флудом (лежащая машина теряет ПО), потом заражаем; слабую заражаем сразу.
func _attack(mine: Array[int]) -> void:
	if v.tick() < int(prof["attack_start_s"]) * Defs.TICK_HZ or mine.size() < int(prof["attack_min_nodes"]):
		return
	# Под атакой одновременно не больше max_attack_targets целей; добить уже подготовленную цель можно всегда.
	var targets: Dictionary = {}
	for t in [Defs.PacketType.PAYLOAD, Defs.PacketType.PAYLOAD_HIDDEN, Defs.PacketType.FLOOD]:
		for f in _flows_of(t):
			targets[int(f["dst"])] = true
	var at_cap: bool = targets.size() >= int(prof["max_attack_targets"])
	var best: int = -1
	var best_score: int = 1 << 20
	var best_src: int = -1
	for n in v.node_count():
		if v.owner_of(n) != enemy or v.node_type(n) == Defs.NodeType.SWITCH:
			continue
		var busy: bool = targets.has(n)
		if busy and not _needs_payload(n):
			continue
		if at_cap and not busy:
			continue
		var src: int = _nearest_mine(mine, n)
		if src < 0:
			continue
		var h: int = v.hops(src, n)
		var s: NodeSnap = v.snap(n)
		if h > int(prof["attack_hops"]):
			continue
		var score: int = _dist_to_enemy_core[n] * int(prof["core_pull"]) + _defense(s) * 4 + h * 3 + rng.range_int(0, 4)
		if v.node_type(n) == Defs.NodeType.CORE:
			score -= 100
		if score < best_score:
			best_score = score
			best = n
			best_src = src
	if best < 0:
		return
	var tgt: NodeSnap = v.snap(best)
	var rich: bool = v.bank() >= int(prof["payload_rich_bank"])
	if _defended(tgt) and not tgt.down:
		# Защищённую цель: при деньгах — вирус напором (файрвол пропускает 8 пакетов в секунду, антивирус тает шкалу),
		# иногда скрытый, и флуд рядом, чтобы машина легла; при нехватке денег — только флуд.
		if rich and v.node_type(best) != Defs.NodeType.CORE and rng.range_int(0, 100) < int(prof["hidden_percent"]):
			v.submit(Command.start_flow(me, v.tick(), best_src, best, Defs.PacketType.PAYLOAD_HIDDEN, Defs.FLOW_MAX_RATE))
			return
		if rich and not _has_flow_to(Defs.PacketType.PAYLOAD, best):
			v.submit(Command.start_flow(me, v.tick(), best_src, best, Defs.PacketType.PAYLOAD, Defs.FLOW_MAX_RATE))
			return
		if _flows_to(Defs.PacketType.FLOOD, best) < int(prof["floods_per_target"]):
			v.submit(Command.start_flow(me, v.tick(), best_src, best, Defs.PacketType.FLOOD, Defs.FLOW_MAX_RATE))
		return
	if v.bank() >= 20 and not _has_flow_to(Defs.PacketType.PAYLOAD, best):
		var rate: int = int(prof["payload_hold_rate"]) if tgt.down else Defs.FLOW_MAX_RATE
		v.submit(Command.start_flow(me, v.tick(), best_src, best, Defs.PacketType.PAYLOAD, rate))

## Цель уже заливается флудом и теперь лежит или не защищена, а заражать её ещё не начали.
func _needs_payload(n: int) -> bool:
	var s: NodeSnap = v.snap(n)
	if s == null or _has_flow_to(Defs.PacketType.PAYLOAD, n) or _has_flow_to(Defs.PacketType.PAYLOAD_HIDDEN, n):
		return false
	return s.down or not _defended(s)
