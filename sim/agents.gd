class_name Agents
extends RefCounted
## Агенты: очередь задач, поездки AGENT-пакетом, работа за время и байты.

static func agent_of(w: World, player: int, idx: int) -> AgentState:
	return w.agents[player * Defs.AGENTS_PER_PLAYER + idx]

## [тиков, цена в байтах] для задачи.
static func task_params(kind: int, arg: int, node: NodeState = null) -> Array:
	if kind == Defs.TaskKind.CLEAN_VIRUS and node != null:
		var worst: int = 0
		for v in node.infect:
			worst = maxi(worst, v)
		var base: Dictionary = Defs.TASK_DEFS[kind]
		var extra: int = Defs.CLEAN_EXTRA_S * Defs.TICK_HZ * worst / Defs.INFECT_MAX
		return [int(base["time_s"]) * Defs.TICK_HZ + extra, int(base["cost"])]
	if kind == Defs.TaskKind.INSTALL_SOFT:
		var d: Dictionary = Defs.SOFT_DEFS[arg]
		return [int(d["time_s"]) * Defs.TICK_HZ, int(d["cost"])]
	var t: Dictionary = Defs.TASK_DEFS[kind]
	return [int(t["time_s"]) * Defs.TICK_HZ, int(t["cost"])]

## Задачи, которые выполняются на чужих машинах.
const ENEMY_KINDS: Array = [
	Defs.TaskKind.STEAL_KEY, Defs.TaskKind.DRAIN_BUFFER, Defs.TaskKind.ENTRENCH,
]

## Проверка при постановке в очередь. Доступ к чужой машине проверяется, когда агент до неё доедет.
static func validate_task(w: World, player: int, kind: int, node: int, arg: int) -> bool:
	if node < 0 or node >= w.nodes.size():
		return false
	if not Defs.TASK_NAMES.has(kind):
		return false
	var n: NodeState = w.nodes[node]
	if n.type == Defs.NodeType.SWITCH or n.owner < 0:
		return false
	if kind == Defs.TaskKind.INSTALL_SOFT and not Defs.PLAYER_SOFT.has(arg):
		return false
	if n.owner == player:
		return not ENEMY_KINDS.has(kind) or kind == Defs.TaskKind.ENTRENCH
	# Чужая машина: можно ехать (MOVE) и делать «внутренние» задачи врага.
	return kind == Defs.TaskKind.MOVE or ENEMY_KINDS.has(kind)

## Применима ли задача к узлу прямо сейчас (проверяется, когда агент на месте).
static func applicable(a: AgentState, n: NodeState, kind: int, arg: int) -> bool:
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
		Defs.TaskKind.STEAL_KEY, Defs.TaskKind.DRAIN_BUFFER:
			return not mine
		Defs.TaskKind.ENTRENCH:
			return n.prev_owner >= 0
	return false

## Есть ли у игрока вход на узел: свой, по доступу или узел «лежит».
static func can_enter(n: NodeState, player: int) -> bool:
	return n.owner == player or n.down or (n.access_mask & (1 << player)) != 0

static func step(w: World) -> void:
	for a in w.agents:
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
			if tn.owner < 0:
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
		if not applicable(a, tn, kind, arg):
			a.queue.pop_front()
			continue
		if kind == Defs.TaskKind.MOVE:
			a.queue.pop_front()
			continue
		var params: Array = task_params(kind, arg, tn)
		var pl: PlayerState = w.players[a.owner]
		if pl.bank < int(params[1]):
			return                 # без байтов задача не начинается
		pl.bank -= int(params[1])
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
	if not applicable(a, n, kind, int(head[2])) and kind != Defs.TaskKind.INSTALL_SOFT:
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
			n.infect.fill(0)
		Defs.TaskKind.STEAL_KEY:
			n.access_mask |= 1 << a.owner
		Defs.TaskKind.ENTRENCH:
			# Закрепление: чужие доступы и ПО вылетают. Если прошлый владелец успел раньше —
			# машина возвращается к нему.
			if n.owner != a.owner:
				Economy.takeover(w, n, a.owner)
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
	if node.owner >= 0 and can_enter(node, owner):
		a.node = node.id
		a.mode = AgentState.Mode.IDLE
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
