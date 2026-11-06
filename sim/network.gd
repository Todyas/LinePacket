class_name Network
extends RefCounted
## Один тик сети: прибытия → эмиссия потоков → вход в каналы. Порядок обхода всегда по id.

static func step(w: World) -> void:
	if w.routes_dirty or w.tick % Defs.ROUTE_RECALC_TICKS == 0:
		Routing.compute(w)
		Economy.refresh_targets(w)
	for n in w.nodes:
		n.cpu_used_tick = 0
		n.cpu_credit = mini(n.cpu_credit + n.cpu_per_s, n.cpu_per_s * Defs.BURST_TICKS)
	Economy.begin_tick(w)
	_process_arrivals(w)
	_emit_flows(w)
	Economy.emit(w)
	Agents.step(w)
	_drain_ports(w)
	Economy.upkeep(w)
	var slot: int = w.tick % Defs.LOAD_WINDOW
	for n in w.nodes:
		n.cpu_hist[slot] = n.cpu_used_tick
		if n.owner >= 0 and n.type != Defs.NodeType.SWITCH:
			var load_pct: int = n.cpu_load_pct()
			if not n.down and load_pct >= Defs.LYING_ON_PCT:
				n.down = true
			elif n.down and load_pct < Defs.LYING_OFF_PCT:
				n.down = false
		elif n.down:
			n.down = false
	_trim_drops(w)

## Создать пакет на узле src и поставить его в очередь порта. false — пакет потерян сразу.
static func inject(w: World, src: int, dst: int, ptype: int, owner: int, flow_id: int) -> bool:
	var idx: int = w.pool.alloc(ptype, owner, src, dst, flow_id)
	return _enqueue_out(w, src, idx)

static func _enqueue_out(w: World, node_id: int, idx: int) -> bool:
	var pool: PacketPool = w.pool
	var dst: int = pool.dst[idx]
	var lid: int = -1
	if w.routes.size() > dst:
		lid = w.routes[dst][node_id]
	if lid < 0:
		_drop(w, idx, -1, 0, World.DROP_NOROUTE)
		return false
	var l: LinkState = w.links[lid]
	var d: int = l.dir_from(node_id)
	var sz: int = pool.size[idx]
	if l.port_units[d] + sz > l.queue_limit:
		_drop(w, idx, lid, d, World.DROP_QUEUE)
		return false
	l.port_q[d].push(idx)
	l.port_units[d] += sz
	return true

## Есть ли у узла маршрут к цели и место в очереди порта под пакет такого размера.
static func has_room(w: World, node_id: int, dst: int, size: int) -> bool:
	if w.routes.size() <= dst:
		return false
	var lid: int = w.routes[dst][node_id]
	if lid < 0:
		return false
	var l: LinkState = w.links[lid]
	return l.port_units[l.dir_from(node_id)] + size <= l.queue_limit

static func _drop(w: World, idx: int, lid: int, d: int, kind: int) -> void:
	w.drops[kind] += 1
	if w.pool.ptype[idx] == Defs.PacketType.AGENT:
		Agents.on_packet_lost(w, w.pool.owner[idx], w.pool.flow[idx])
	w.pool.release(idx)
	if lid >= 0:
		w.recent_drops.append([w.tick, lid, d])

static func _process_arrivals(w: World) -> void:
	var pool: PacketPool = w.pool
	for l in w.links:
		for d in 2:
			var q: IntQueue = l.chan[d]
			if q.is_empty():
				continue
			var to_node: int = l.b if d == 0 else l.a
			while not q.is_empty():
				var e: int = q.peek()
				if (e >> LinkState.IDX_BITS) + l.latency > w.tick:
					break
				q.pop()
				_arrive(w, to_node, e & LinkState.IDX_MASK, l.id, d)

static func _arrive(w: World, node_id: int, idx: int, via_link: int, via_dir: int) -> void:
	var pool: PacketPool = w.pool
	var n: NodeState = w.nodes[node_id]
	if _firewall_blocks(w, n, idx):
		_drop(w, idx, via_link, via_dir, World.DROP_FIREWALL)
		return
	if pool.dst[idx] == node_id:
		var cost: int = int(Defs.CPU_COST_ARRIVE[pool.ptype[idx]])
		if not n.spend_cpu(cost):
			_drop(w, idx, via_link, via_dir, World.DROP_CPU)
			return
		w.delivered[pool.ptype[idx]] += 1
		PacketEffects.deliver(w, n, idx)
		pool.release(idx)
	else:
		if not n.spend_cpu(Defs.CPU_COST_TRANSIT):
			_drop(w, idx, via_link, via_dir, World.DROP_CPU)
			return
		_enqueue_out(w, node_id, idx)

## Файрвол узла: чужие FLOOD и PAYLOAD проходят не чаще лимита; проверка стоит CPU.
static func _firewall_blocks(w: World, n: NodeState, idx: int) -> bool:
	if n.owner < 0 or not n.soft_active(Defs.SoftType.FIREWALL):
		return false
	var pool: PacketPool = w.pool
	if pool.owner[idx] == n.owner:
		return false
	var t: int = pool.ptype[idx]
	if t != Defs.PacketType.FLOOD and t != Defs.PacketType.PAYLOAD and t != Defs.PacketType.PAYLOAD_HIDDEN:
		return false
	if not n.spend_cpu(Defs.FIREWALL_CPU_COST):
		return false   # проверить нечем: дальше пакет разбирается как обычно (и упрётся в CPU)
	if n.fw_credit < Defs.TICK_HZ:
		return true
	n.fw_credit -= Defs.TICK_HZ
	return false

static func _emit_flows(w: World) -> void:
	var i: int = 0
	while i < w.flows.size():
		var f: FlowState = w.flows[i]
		var src: NodeState = w.nodes[f.src]
		if src.owner != f.owner:
			# Источник потерян — поток прекращается.
			w.flows.remove_at(i)
			continue
		if src.down:
			i += 1
			continue    # машина лежит: потоки не идут
		var pct: int = Defs.RELAY_FLOW_PERCENT if src.soft_active(Defs.SoftType.RELAY) else 100
		f.acc += f.rate * pct / 100
		while f.acc >= Defs.TICK_HZ:
			f.acc -= Defs.TICK_HZ
			var pl: PlayerState = w.players[f.owner]
			if f.ptype == Defs.PacketType.PAYLOAD and pl.bank < Defs.PAYLOAD_COST_BYTES:
				continue    # PAYLOAD стоит байты: без них пакет не рождается
			if not src.spend_cpu(Defs.CPU_COST_EMIT):
				w.drops[World.DROP_CPU] += 1
				continue
			if f.ptype == Defs.PacketType.PAYLOAD:
				pl.bank -= Defs.PAYLOAD_COST_BYTES
			inject(w, f.src, f.dst, f.ptype, f.owner, f.id)
		i += 1

static func _drain_ports(w: World) -> void:
	var pool: PacketPool = w.pool
	var slot: int = w.tick % Defs.LOAD_WINDOW
	for l in w.links:
		for d in 2:
			var pq: IntQueue = l.port_q[d]
			var cr: int = l.credit[d] + l.capacity
			var sent: int = 0
			while not pq.is_empty():
				var idx: int = pq.peek()
				var sz: int = pool.size[idx]
				var need: int = sz * Defs.TICK_HZ
				if cr < need:
					break
				pq.pop()
				l.port_units[d] -= sz
				cr -= need
				sent += sz
				l.chan[d].push((w.tick << LinkState.IDX_BITS) | idx)
			l.credit[d] = mini(cr, l.credit_cap())
			l.sent_hist[d][slot] = sent

static func _trim_drops(w: World) -> void:
	var drops: Array = w.recent_drops
	var keep_from: int = w.tick - Defs.TICK_HZ * 2
	var cut: int = 0
	while cut < drops.size() and int((drops[cut] as Array)[0]) < keep_from:
		cut += 1
	if cut > 0:
		w.recent_drops = drops.slice(cut)
