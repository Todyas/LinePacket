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
			if cand.control < Defs.SUPPLY_MIN_CONTROL or cand.down:
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
		if n.owner < 0 or n.down:
			continue    # лежащая машина не шлёт ни DATA, ни KEEPALIVE
		if n.type != Defs.NodeType.GATEWAY and n.type != Defs.NodeType.SWITCH:
			_produce_and_send_data(w, n)
		if n.supplier >= 0:
			n.ka_acc += Defs.KEEPALIVE_RATE
			while n.ka_acc >= Defs.TICK_HZ:
				n.ka_acc -= Defs.TICK_HZ
				var sup: NodeState = w.nodes[n.supplier]
				if sup.owner == n.owner and not sup.down and sup.spend_cpu(Defs.CPU_COST_EMIT):
					sup.auto_sent += 1
					Network.inject(w, sup.id, n.id, Defs.PacketType.KEEPALIVE, n.owner, 0)

static func _produce_and_send_data(w: World, n: NodeState) -> void:
	var limit: int = buffer_limit(n)
	var data_pct: int = Defs.RELAY_DATA_PERCENT if n.soft_active(Defs.SoftType.RELAY) else 100
	n.produce_acc += Defs.DATA_RATE * data_pct / 100
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
			n.auto_sent += 1
			n.buffer -= Defs.DATA_VALUE
		else:
			break   # очередь порта полна: байты остаются в буфере

static func buffer_limit(n: NodeState) -> int:
	var lim: int = int(Defs.BUFFER_LIMIT[n.type])
	if lim > 0 and n.has_soft(Defs.SoftType.STORAGE):
		lim += Defs.STORAGE_BUFFER_BONUS
	return lim

## Начало тика: окно дохода и кредит потолка шлюза.
static func begin_tick(w: World) -> void:
	var slot: int = w.tick % Defs.LOAD_WINDOW
	for p in w.players:
		p.income_hist[slot] = 0
	for n in w.nodes:
		if n.type == Defs.NodeType.GATEWAY:
			n.gw_credit = mini(n.gw_credit + Defs.GATEWAY_CAP_PER_S, Defs.GATEWAY_CAP_PER_S * Defs.GATEWAY_BURST_TICKS)
		if n.soft_active(Defs.SoftType.FIREWALL):
			n.fw_credit = mini(n.fw_credit + Defs.FIREWALL_LIMIT_PER_S, Defs.FIREWALL_LIMIT_PER_S * Defs.FIREWALL_BURST_TICKS)

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
	# Шкалы заражения и подбора пароля тают.
	for n in w.nodes:
		if n.owner < 0:
			continue
		var inf_dec: int = Defs.INFECT_DECAY_PER_S / Defs.TICK_HZ
		if n.soft_active(Defs.SoftType.ANTIVIRUS):
			inf_dec += Defs.ANTIVIRUS_DECAY_PER_S / Defs.TICK_HZ
		var br_dec: int = Defs.BRUTE_DECAY_PER_S / Defs.TICK_HZ
		for p in Defs.MAX_PLAYERS:
			if n.infect[p] > 0:
				n.infect[p] = maxi(0, n.infect[p] - inf_dec)
			if n.brute[p] > 0:
				n.brute[p] = maxi(0, n.brute[p] - br_dec)
	# Шкалы захвата раз в секунду.
	if w.tick % Defs.TICK_HZ == 0:
		for n in w.nodes:
			if n.owner >= 0 or w.tick - n.capture_tick < Defs.TICK_HZ:
				continue    # пока на узел идёт INIT, шкала не спадает
			for p in Defs.MAX_PLAYERS:
				n.capture[p] = maxi(0, n.capture[p] - Defs.CAPTURE_DECAY_PER_S)

static func release_node(w: World, n: NodeState) -> void:
	var old_owner: int = n.owner
	n.owner = Defs.NEUTRAL
	n.clear_soft()
	n.reset_access()
	n.clear_threats()
	n.prev_owner = -1
	n.down = false
	Agents.on_node_lost(w, n.id, old_owner)
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
	if node.owner >= 0 and node.owner != owner and node.type != Defs.NodeType.SWITCH:
		_brute_force(w, node, owner)
		return
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
	node.clear_soft()
	node.reset_access()
	node.clear_threats()
	node.prev_owner = -1
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

## INIT на чужую машину подбирает пароль: слабый сдаётся быстро, сильный медленно, ключи никак.
static func _brute_force(_w: World, node: NodeState, attacker: int) -> void:
	if node.down or (node.access_mask & (1 << attacker)) != 0:
		return    # лежащая машина доступ не проверяет, а доступ у атакующего уже есть
	var gain: int = int(Defs.BRUTE_GAIN[node.access_mode])
	if gain <= 0:
		return
	node.brute[attacker] = mini(Defs.BRUTE_MAX, node.brute[attacker] + gain)
	if node.brute[attacker] >= Defs.BRUTE_MAX:
		node.access_mask |= 1 << attacker
		node.brute[attacker] = 0

## PAYLOAD дошёл до чужой машины: заполняет шкалу заражения атакующего.
static func on_payload(w: World, node: NodeState, attacker: int) -> void:
	if node.owner < 0 or node.owner == attacker or node.type == Defs.NodeType.SWITCH:
		return
	var gain: int = Defs.INFECT_GAIN
	if node.soft_active(Defs.SoftType.ANTIVIRUS):
		gain = gain * Defs.ANTIVIRUS_GAIN_PERCENT / 100
	node.infect[attacker] = mini(Defs.INFECT_MAX, node.infect[attacker] + gain)
	if node.infect[attacker] >= Defs.INFECT_MAX:
		takeover(w, node, attacker)

## Машина меняет владельца (заражение 100% или «закрепиться» агентом прошлого владельца).
## Прошлый владелец сохраняет доступ по старым ключам, его агенты вылетают.
static func takeover(w: World, node: NodeState, attacker: int) -> void:
	var old: int = node.owner
	node.prev_owner = old
	node.owner = attacker
	node.control = Defs.TAKEOVER_CONTROL
	node.clear_threats()
	node.access_mask |= 1 << attacker
	node.capture.fill(0)
	node.ka_acc = 0
	w.players[attacker].captures += 1
	w.routes_dirty = true
	Agents.on_node_lost(w, node.id, old)
	if node.type == Defs.NodeType.CORE and w.winner < 0:
		w.winner = attacker
		w.finished_tick = w.tick
