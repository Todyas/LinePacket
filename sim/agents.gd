class_name Agents
extends RefCounted
## Агенты: очередь задач, поездки AGENT-пакетом, работа за время и байты.

static func agent_of(w: World, player: int, idx: int) -> AgentState:
	return w.agents[player * Defs.AGENTS_PER_PLAYER + idx]

## [тиков, цена в байтах] для задачи.
static func task_params(kind: int, arg: int) -> Array:
	if kind == Defs.TaskKind.INSTALL_SOFT:
		var d: Dictionary = Defs.SOFT_DEFS[arg]
		return [int(d["time_s"]) * Defs.TICK_HZ, int(d["cost"])]
	var t: Dictionary = Defs.TASK_DEFS[kind]
	return [int(t["time_s"]) * Defs.TICK_HZ, int(t["cost"])]

## Проверка при постановке в очередь. Пока заходить можно только на свои узлы.
static func validate_task(w: World, player: int, kind: int, node: int, arg: int) -> bool:
	if node < 0 or node >= w.nodes.size():
		return false
	if not Defs.TASK_NAMES.has(kind):
		return false
	var n: NodeState = w.nodes[node]
	if n.owner != player or n.type == Defs.NodeType.SWITCH:
		return false
	if kind == Defs.TaskKind.INSTALL_SOFT and not Defs.PLAYER_SOFT.has(arg):
		return false
	return true

static func step(w: World) -> void:
	for a in w.agents:
		match a.mode:
			AgentState.Mode.LOST:
				a.lost_timer -= 1
				if a.lost_timer <= 0:
					a.node = w.players[a.owner].core_node
					a.mode = AgentState.Mode.IDLE
			AgentState.Mode.WORK:
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
		if tn.owner != a.owner:
			a.queue.pop_front()   # узел потерян — задача пропадает
			continue
		if a.node != target:
			var src: NodeState = w.nodes[a.node]
			if not Network.has_room(w, a.node, target, int(Defs.PACKET_SIZE[Defs.PacketType.AGENT])):
				return
			if not src.spend_cpu(Defs.CPU_COST_EMIT):
				return
			var from_node: int = a.node
			a.node = -1
			a.mode = AgentState.Mode.TRAVEL
			Network.inject(w, from_node, target, Defs.PacketType.AGENT, a.owner, a.id)
			return
		if kind == Defs.TaskKind.MOVE:
			a.queue.pop_front()
			continue
		if kind == Defs.TaskKind.INSTALL_SOFT and (tn.free_slots() <= 0 or tn.has_soft(arg)):
			a.queue.pop_front()   # нет места или уже стоит
			continue
		var params: Array = task_params(kind, arg)
		var pl: PlayerState = w.players[a.owner]
		if pl.bank < int(params[1]):
			return                 # без байтов задача не начинается
		pl.bank -= int(params[1])
		a.mode = AgentState.Mode.WORK
		a.work_total = int(params[0])
		a.work_left = int(params[0])
		return

static func _complete(w: World, a: AgentState) -> void:
	var head: Array = a.queue[0]
	var n: NodeState = w.nodes[head[1]]
	if n.owner != a.owner:
		return
	match int(head[0]):
		Defs.TaskKind.CHANGE_PASSWORD:
			n.access_mode = Defs.AccessMode.PASSWORD_STRONG
			n.access_mask = 1 << a.owner
		Defs.TaskKind.SET_KEYS:
			n.access_mode = Defs.AccessMode.KEYS
			n.key_version += 1
			n.access_mask = 1 << a.owner
		Defs.TaskKind.INSTALL_SOFT:
			n.install_soft(int(head[2]))

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

## AGENT-пакет добрался до узла.
static func on_arrived(w: World, node: NodeState, owner: int, agent_idx: int) -> void:
	var a: AgentState = agent_of(w, owner, agent_idx)
	if a.mode != AgentState.Mode.TRAVEL:
		return
	if node.owner == owner:
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
