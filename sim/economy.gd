class_name Economy
extends RefCounted
## Владение, контроль, KEEPALIVE, DATA→байты, захват нейтралов INIT-ом.

## Пересчёт целей: кто кормит узел KEEPALIVE и в какой шлюз шлёт DATA. Вызывается вместе с маршрутами.
static func refresh_targets(w: World) -> void:
	for n in w.nodes:
		n.supplier = -1
		n.gw_target = -1
	if w.route_dist.size() != w.nodes.size():
		return
	for n in w.nodes:
		if n.owner < 0 or n.type == Defs.NodeType.SWITCH:
			continue
		var core: int = w.players[n.owner].core_node
		if n.type != Defs.NodeType.CORE:
			n.supplier = _pick_supplier(w, n, core)
		if n.type == Defs.NodeType.CORE or n.type == Defs.NodeType.MACHINE:
			n.gw_target = _pick_gateway(w, n)

static func _pick_supplier(w: World, m: NodeState, core: int) -> int:
	var dc_m: int = w.route_dist[m.id][core]    # цена core → m
	var best: int = -1
	var best_cost: int = Routing.INF
	for cand in w.nodes:
		if cand.owner != m.owner or cand.id == m.id:
			continue
		if cand.type == Defs.NodeType.CORE:
			pass
		elif cand.type == Defs.NodeType.SWITCH:
			continue
		else:
			if cand.control < Defs.SUPPLY_MIN_CONTROL:
				continue
			# Кормящий должен быть ближе к ядру, иначе два узла «кормили» бы друг друга.
			if w.route_dist[cand.id][core] >= dc_m:
				continue
		var cost: int = w.route_dist[m.id][cand.id]   # цена cand → m
		if cost < best_cost:
			best_cost = cost
			best = cand.id
	return best

static func _pick_gateway(w: World, m: NodeState) -> int:
	var best: int = -1
	var best_cost: int = Routing.INF
	for g in w.nodes:
		if g.type != Defs.NodeType.GATEWAY or g.owner != m.owner:
			continue
		var cost: int = w.route_dist[g.id][m.id]   # цена m → g
		if cost < best_cost:
			best_cost = cost
			best = g.id
	return best

## Эмиссия автоматических пакетов: KEEPALIVE и DATA.
static func emit(w: World) -> void:
	for n in w.nodes:
		if n.owner < 0:
			continue
		if n.type != Defs.NodeType.GATEWAY and n.type != Defs.NodeType.SWITCH:
			_produce_and_send_data(w, n)
		if n.supplier >= 0:
			n.ka_acc += Defs.KEEPALIVE_RATE
			while n.ka_acc >= Defs.TICK_HZ:
				n.ka_acc -= Defs.TICK_HZ
				var sup: NodeState = w.nodes[n.supplier]
				if sup.owner == n.owner and sup.spend_cpu(Defs.CPU_COST_EMIT):
					Network.inject(w, sup.id, n.id, Defs.PacketType.KEEPALIVE, n.owner, 0)

static func _produce_and_send_data(w: World, n: NodeState) -> void:
	var limit: int = int(Defs.BUFFER_LIMIT[n.type])
	n.produce_acc += Defs.DATA_RATE
	while n.produce_acc >= Defs.TICK_HZ:
		n.produce_acc -= Defs.TICK_HZ
		if n.buffer < limit:
			n.buffer += Defs.DATA_VALUE
	if n.buffer <= 0 or n.gw_target < 0:
		n.send_acc = 0
		return
	n.send_acc += Defs.DATA_RATE + Defs.BUFFER_UNLOAD_RATE
	while n.send_acc >= Defs.TICK_HZ and n.buffer > 0:
		n.send_acc -= Defs.TICK_HZ
		if not n.spend_cpu(Defs.CPU_COST_EMIT):
			break
		if Network.inject(w, n.id, n.gw_target, Defs.PacketType.DATA, n.owner, 0):
			n.buffer -= Defs.DATA_VALUE
		else:
			break   # очередь порта полна: байты остаются в буфере

## Начало тика: окно дохода и кредит потолка шлюза.
static func begin_tick(w: World) -> void:
	var slot: int = w.tick % Defs.LOAD_WINDOW
	for p in w.players:
		p.income_hist[slot] = 0
	for n in w.nodes:
		if n.type == Defs.NodeType.GATEWAY:
			n.gw_credit = mini(n.gw_credit + Defs.GATEWAY_CAP_PER_S, Defs.GATEWAY_CAP_PER_S * Defs.GATEWAY_BURST_TICKS)

## Конец тика: распад контроля и шкал захвата.
static func upkeep(w: World) -> void:
	# Распад контроля (кроме ядра).
	for n in w.nodes:
		if n.owner < 0:
			continue
		if n.type == Defs.NodeType.CORE:
			n.control = Defs.CONTROL_MAX
			continue
		n.control -= Defs.CONTROL_DECAY_PER_S / Defs.TICK_HZ
		if n.control <= 0:
			release_node(w, n)
	# Шкалы захвата раз в секунду.
	if w.tick % Defs.TICK_HZ == 0:
		for n in w.nodes:
			if n.owner >= 0 or w.tick - n.capture_tick < Defs.TICK_HZ:
				continue    # пока на узел идёт INIT, шкала не спадает
			for p in Defs.MAX_PLAYERS:
				n.capture[p] = maxi(0, n.capture[p] - Defs.CAPTURE_DECAY_PER_S)

static func release_node(w: World, n: NodeState) -> void:
	n.owner = Defs.NEUTRAL
	n.control = 0
	n.buffer = 0
	n.supplier = -1
	n.gw_target = -1
	n.ka_acc = 0
	w.routes_dirty = true   # цели DATA и KEEPALIVE у остальных пересчитаются

## DATA дошёл до узла node.
static func on_data(w: World, node: NodeState, owner: int) -> void:
	if node.type != Defs.NodeType.GATEWAY or node.owner != owner:
		w.drops[World.DROP_GATEWAY] += 1
		return
	if node.gw_credit < Defs.TICK_HZ:
		w.drops[World.DROP_GATEWAY] += 1
		return
	node.gw_credit -= Defs.TICK_HZ
	var pl: PlayerState = w.players[owner]
	pl.bank += Defs.DATA_VALUE
	pl.earned_total += Defs.DATA_VALUE
	pl.income_hist[w.tick % Defs.LOAD_WINDOW] += Defs.DATA_VALUE

static func on_keepalive(_w: World, node: NodeState, owner: int) -> void:
	if node.owner == owner and node.type != Defs.NodeType.CORE:
		node.control = mini(Defs.CONTROL_MAX, node.control + Defs.KEEPALIVE_BOOST)

## INIT дошёл до нейтрала: заполняет шкалу атакующего и сбивает шкалы остальных.
static func on_init(w: World, node: NodeState, owner: int) -> void:
	if node.owner != Defs.NEUTRAL or not Defs.INIT_NEEDED.has(node.type):
		return
	node.capture_tick = w.tick
	node.capture[owner] += 1
	for p in Defs.MAX_PLAYERS:
		if p != owner and node.capture[p] > 0:
			node.capture[p] -= 1
	if node.capture[owner] >= int(Defs.INIT_NEEDED[node.type]):
		capture_node(w, node, owner)

static func capture_node(w: World, node: NodeState, owner: int) -> void:
	node.owner = owner
	node.control = Defs.CAPTURE_START_CONTROL
	node.capture.fill(0)
	node.buffer = 0
	w.players[owner].captures += 1
	w.routes_dirty = true
	# Потоки INIT на этот узел больше не нужны.
	var i: int = 0
	while i < w.flows.size():
		var f: FlowState = w.flows[i]
		if f.ptype == Defs.PacketType.INIT and f.dst == node.id and f.owner == owner:
			w.flows.remove_at(i)
		else:
			i += 1
