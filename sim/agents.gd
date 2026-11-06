class_name Agents
extends RefCounted
## Агенты: очередь задач, поездки AGENT-пакетом, работа за время и байты.

static func agent_of(w: World, player: int, idx: int) -> AgentState:
	return w.agents[player * Defs.AGENTS_PER_PLAYER + idx]

## [тиков, цена в байтах] захвата узла такого типа.
static func capture_params(node_type: int) -> Array:
	var cd: Dictionary = Defs.CAPTURE_DEFS.get(node_type, Defs.CAPTURE_DEFS[Defs.NodeType.MACHINE])
	return [int(cd["time_s"]) * Defs.TICK_HZ, int(cd["cost"])]

## [тиков, цена в байтах] для задачи.
static func task_params(kind: int, arg: int, node: NodeState = null) -> Array:
	if kind == Defs.TaskKind.CLEAN_VIRUS and node != null:
		var worst: int = 0
		for v in node.infect:
			worst = maxi(worst, v)
		var base: Dictionary = Defs.TASK_DEFS[kind]
		var extra: int = Defs.CLEAN_EXTRA_S * Defs.TICK_HZ * worst / Defs.INFECT_MAX
		return [int(base["time_s"]) * Defs.TICK_HZ + extra, int(base["cost"])]
	if kind == Defs.TaskKind.CAPTURE:
		return capture_params(node.type if node != null else Defs.NodeType.MACHINE)
	if kind == Defs.TaskKind.INSTALL_SOFT:
		var d: Dictionary = Defs.SOFT_DEFS[arg]
		return [int(d["time_s"]) * Defs.TICK_HZ, int(d["cost"])]
	var t: Dictionary = Defs.TASK_DEFS[kind]
	return [int(t["time_s"]) * Defs.TICK_HZ, int(t["cost"])]

## Задачи, которые выполняются на чужих машинах.
const ENEMY_KINDS: Array = [
	Defs.TaskKind.STEAL_KEY, Defs.TaskKind.DRAIN_BUFFER, Defs.TaskKind.BACKDOOR,
]

## Проверка при постановке в очередь. Доступ к чужой машине проверяется, когда агент до неё доедет.
static func validate_task(w: World, player: int, kind: int, node: int, arg: int) -> bool:
	if node < 0 or node >= w.nodes.size():
		return false
	if not Defs.TASK_NAMES.has(kind):
		return false
	var n: NodeState = w.nodes[node]
	if kind == Defs.TaskKind.TAKE_ROUTER:
		return n.type == Defs.NodeType.ROUTER and n.owner != player    # ничей или чужой маршрутизатор
	if n.owner < 0:
		return false
	if kind == Defs.TaskKind.CAPTURE and n.type == Defs.NodeType.ROUTER:
		return false    # маршрутизатор берут задачей «Взять управление»
	if kind == Defs.TaskKind.INSTALL_SOFT and not Defs.PLAYER_SOFT.has(arg):
		return false
	if n.owner == player:
		return not ENEMY_KINDS.has(kind) and kind != Defs.TaskKind.CAPTURE
	# Чужая машина: можно ехать (MOVE), делать «внутренние» задачи врага, захватывать и выгонять защитника.
	return kind == Defs.TaskKind.MOVE or kind == Defs.TaskKind.CAPTURE or kind == Defs.TaskKind.EVICT or ENEMY_KINDS.has(kind)

## Применима ли задача к узлу прямо сейчас (проверяется, когда агент на месте).
static func applicable(w: World, a: AgentState, n: NodeState, kind: int, arg: int) -> bool:
	if kind == Defs.TaskKind.TAKE_ROUTER:
		return n.type == Defs.NodeType.ROUTER and n.owner != a.owner
	if n.owner < 0:
		return false
	var mine: bool = n.owner == a.owner
	match kind:
		Defs.TaskKind.MOVE:
			return true
		Defs.TaskKind.CHANGE_PASSWORD, Defs.TaskKind.SET_KEYS, Defs.TaskKind.CLEAN_VIRUS:
			return mine
		Defs.TaskKind.INSTALL_SOFT:
			return mine and n.free_slots() > 0 and not n.has_soft(arg)
		Defs.TaskKind.STEAL_KEY, Defs.TaskKind.DRAIN_BUFFER, Defs.TaskKind.BACKDOOR:
			return not mine
		Defs.TaskKind.ENTRENCH:
			return mine and n.prev_owner >= 0
		Defs.TaskKind.CAPTURE:
			return not mine
		Defs.TaskKind.EVICT:
			return (mine or can_enter(n, a.owner)) and not others_on(w, a, n).is_empty()
	return false

## Агенты других игроков, стоящие на узле (в пути агент не стоит).
static func foreign_agents_on(w: World, n: NodeState) -> Array[AgentState]:
	var out: Array[AgentState] = []
	for b in w.agents:
		if b.owner != n.owner and b.node == n.id:
			out.append(b)
	return out

## Агенты других игроков (не того, кто спрашивает), стоящие на узле.
static func others_on(w: World, a: AgentState, n: NodeState) -> Array[AgentState]:
	var out: Array[AgentState] = []
	for b in w.agents:
		if b.owner != a.owner and b.node == n.id:
			out.append(b)
	return out

## Стоит ли на узле агент его владельца: пока он там, захват не идёт.
static func defender_present(w: World, n: NodeState) -> bool:
	for b in w.agents:
		if b.owner == n.owner and b.node == n.id:
			return true
	return false

## Задачи, меняющие владельца узла: захват машины, шлюза и ядра и взятие маршрутизатора.
static func is_capture_kind(kind: int) -> bool:
	return kind == Defs.TaskKind.CAPTURE or kind == Defs.TaskKind.TAKE_ROUTER

## Может ли агент прямо сейчас захватывать узел: у ничьего маршрутизатора ничего не мешает,
## у чужого узла нужен вход и не должно быть агента хозяина.
static func capture_possible(w: World, a: AgentState, n: NodeState) -> bool:
	if n.owner < 0:
		return n.type == Defs.NodeType.ROUTER
	return n.owner >= 0 and n.owner != a.owner and can_enter(n, a.owner) and not defender_present(w, n)

## Есть ли у игрока вход на узел: свой, по доступу или узел «лежит».
static func can_enter(n: NodeState, player: int) -> bool:
	return n.owner == player or n.down or (n.access_mask & (1 << player)) != 0 or n.backdoor[player] == 1 \
		or n.door[player] > 0 or n.infected_by(player)

## Нанято агентов у игрока.
static func hired_count(w: World, player: int) -> int:
	var c: int = 0
	for i in Defs.AGENTS_PER_PLAYER:
		if agent_of(w, player, i).hired:
			c += 1
	return c

## Цена следующего найма; -1 — нанимать больше некого.
static func hire_cost(w: World, player: int) -> int:
	var k: int = hired_count(w, player) - Defs.AGENTS_START
	if k < 0 or k >= Defs.HIRE_COSTS.size():
		return -1
	return int(Defs.HIRE_COSTS[k])

## Команда HIRE_AGENT: байты списываются сразу, агент выходит на ядре через HIRE_SECONDS. Один наём за раз.
static func apply_hire(w: World, player: int, args: Array) -> bool:
	if not args.is_empty() or player < 0 or player >= w.players.size():
		return false
	var ps: PlayerState = w.players[player]
	var cost: int = hire_cost(w, player)
	if cost < 0 or ps.hire_left > 0 or ps.bank < cost:
		return false
	ps.bank -= cost
	ps.hire_left = Defs.HIRE_SECONDS * Defs.TICK_HZ
	return true

static func _step_hiring(w: World) -> void:
	for ps in w.players:
		if ps.hire_left <= 0:
			continue
		ps.hire_left -= 1
		if ps.hire_left > 0:
			continue
		for i in Defs.AGENTS_PER_PLAYER:
			var a: AgentState = agent_of(w, ps.id, i)
			if not a.hired:
				a.hired = true
				a.node = ps.core_node
				a.mode = AgentState.Mode.IDLE
				break

static func step(w: World) -> void:
	_step_hiring(w)
	for a in w.agents:
		if not a.hired:
			continue
		match a.mode:
			AgentState.Mode.LOST:
				a.lost_timer -= 1
				if a.lost_timer <= 0:
					a.node = w.players[a.owner].core_node
					a.mode = AgentState.Mode.IDLE
			AgentState.Mode.WORK:
				if int(a.queue[0][0]) == Defs.TaskKind.DRAIN_BUFFER:
					if _drain(w, a):
						a.queue.pop_front()
						a.mode = AgentState.Mode.IDLE
						_advance(w, a)
					continue
				if is_capture_kind(int(a.queue[0][0])) and not capture_possible(w, a, w.nodes[a.queue[0][1]]):
					continue    # доступ пропал или на машине агент защитника: задача на паузе, агент стоит
				a.work_left -= 1
				if a.work_left <= 0:
					_complete(w, a)
					a.queue.pop_front()
					a.mode = AgentState.Mode.IDLE
					_advance(w, a)
			AgentState.Mode.IDLE:
				_advance(w, a)
			_:
				pass

static func _advance(w: World, a: AgentState) -> void:
	while not a.queue.is_empty():
		var head: Array = a.queue[0]
		var kind: int = head[0]
		var target: int = head[1]
		var arg: int = head[2]
		var tn: NodeState = w.nodes[target]
		if a.node != target:
			if tn.owner < 0 and kind != Defs.TaskKind.TAKE_ROUTER:
				a.queue.pop_front()   # узел стал нейтральным — задача пропадает
				continue
			var src: NodeState = w.nodes[a.node]
			if not Network.has_room(w, a.node, target, int(Defs.PACKET_SIZE[Defs.PacketType.AGENT]), a.owner):
				return
			if not src.spend_cpu(Defs.CPU_COST_EMIT):
				return
			var from_node: int = a.node
			a.node = -1
			a.mode = AgentState.Mode.TRAVEL
			Network.inject(w, from_node, target, Defs.PacketType.AGENT, a.owner, a.id)
			return
		if not applicable(w, a, tn, kind, arg):
			a.queue.pop_front()
			continue
		if kind == Defs.TaskKind.MOVE:
			a.queue.pop_front()
			continue
		if is_capture_kind(kind) and not capture_possible(w, a, tn):
			return                 # нет доступа или стоит агент защитника: ждём на месте
		var params: Array = task_params(kind, arg, tn)
		var pl: PlayerState = w.players[a.owner]
		if pl.bank < int(params[1]):
			return                 # без байтов задача не начинается
		pl.bank -= int(params[1])
		if is_capture_kind(kind) and tn.owner >= 0:
			# Владелец узнаёт, что машину берут; с IDS ещё и чей агент.
			var src: int = a.owner if Stealth.ids_covers(w, tn.owner, tn) else -1
			Knowledge.log_event(w, tn.owner, Knowledge.EventKind.AGENT_CAPTURING, tn.id, -1, src)
		a.mode = AgentState.Mode.WORK
		a.work_total = int(params[0])
		a.work_left = int(params[0])
		return

## «Выкачать байты»: раз в секунду забирает до DRAIN_PER_S из буфера. true — задача закончена.
static func _drain(w: World, a: AgentState) -> bool:
	var n: NodeState = w.nodes[a.queue[0][1]]
	if n.owner < 0 or n.owner == a.owner:
		return true
	if w.tick % Defs.TICK_HZ == 0:
		var take: int = mini(Defs.DRAIN_PER_S, n.buffer)
		n.buffer -= take
		w.players[a.owner].bank += take
		w.players[a.owner].earned_total += take
	return n.buffer <= 0

static func _complete(w: World, a: AgentState) -> void:
	var head: Array = a.queue[0]
	var n: NodeState = w.nodes[head[1]]
	var kind: int = head[0]
	if not applicable(w, a, n, kind, int(head[2])) and kind != Defs.TaskKind.INSTALL_SOFT:
		return
	match kind:
		Defs.TaskKind.CHANGE_PASSWORD:
			n.access_mode = Defs.AccessMode.PASSWORD_STRONG
			n.access_mask = 1 << a.owner
			n.brute.fill(0)
		Defs.TaskKind.SET_KEYS:
			n.access_mode = Defs.AccessMode.KEYS
			n.key_version += 1
			n.access_mask = 1 << a.owner
			n.brute.fill(0)
		Defs.TaskKind.INSTALL_SOFT:
			if n.owner == a.owner:
				n.install_soft(int(head[2]))
		Defs.TaskKind.CLEAN_VIRUS:
			Stealth.clean(n)
		Defs.TaskKind.BACKDOOR:
			n.backdoor[a.owner] = 1
		Defs.TaskKind.STEAL_KEY:
			n.access_mask |= 1 << a.owner
		Defs.TaskKind.CAPTURE:
			if capture_possible(w, a, n):
				Economy.takeover(w, n, a.owner)
		Defs.TaskKind.TAKE_ROUTER:
			if capture_possible(w, a, n):
				if n.owner < 0:
					Economy.capture_node(w, n, a.owner)
				else:
					Economy.takeover(w, n, a.owner)
		Defs.TaskKind.EVICT:
			for b in others_on(w, a, n):
				send_home(w, b)
		Defs.TaskKind.ENTRENCH:
			# Закрепление: чужие доступы и ПО вылетают.
			n.access_mask = 1 << a.owner
			n.access_mode = Defs.AccessMode.PASSWORD_STRONG
			n.clear_soft()
			n.prev_owner = -1

static func send_home(w: World, a: AgentState) -> void:
	a.node = -1
	a.mode = AgentState.Mode.LOST
	a.lost_timer = Defs.AGENT_RETURN_TICKS
	a.queue.clear()
	a.work_left = 0
	a.work_total = 0

## AGENT-пакет потерян в пути (очередь, CPU, нет маршрута).
static func on_packet_lost(w: World, owner: int, agent_idx: int) -> void:
	var a: AgentState = agent_of(w, owner, agent_idx)
	if a.mode == AgentState.Mode.TRAVEL:
		send_home(w, a)

## AGENT-пакет добрался до узла. На чужую машину пускают по доступу или если она лежит.
static func on_arrived(w: World, node: NodeState, owner: int, agent_idx: int) -> void:
	var a: AgentState = agent_of(w, owner, agent_idx)
	if a.mode != AgentState.Mode.TRAVEL:
		return
	if (node.owner >= 0 and can_enter(node, owner)) or (node.owner < 0 and node.type == Defs.NodeType.ROUTER):
		a.node = node.id
		a.mode = AgentState.Mode.IDLE
		if node.owner >= 0 and node.owner != owner and Stealth.ids_covers(w, node.owner, node):
			Knowledge.log_event(w, node.owner, Knowledge.EventKind.AGENT_SEEN, node.id)
	else:
		send_home(w, a)

## Узел перестал быть своим: агенты на нём возвращаются на ядро, задачи на него отменяются.
static func on_node_lost(w: World, node_id: int, old_owner: int) -> void:
	for a in w.agents:
		if a.owner != old_owner:
			continue
		if a.node == node_id:
			send_home(w, a)
		else:
			var keep: Array = []
			for t in a.queue:
				if int(t[1]) != node_id:
					keep.append(t)
			a.queue = keep
