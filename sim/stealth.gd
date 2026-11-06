class_name Stealth
extends RefCounted
## Скрытность: тайные вирусы, бэкдоры, снифферы и их обнаружение.

## IDS работает на этом узле или на соседнем узле того же игрока.
static func ids_covers(w: World, player: int, node: NodeState) -> bool:
	if node.owner == player and node.soft_active(Defs.SoftType.IDS):
		return true
	for lid in node.links:
		var o: NodeState = w.nodes[w.links[lid].other(node.id)]
		if o.owner == player and o.soft_active(Defs.SoftType.IDS):
			return true
	return false

## Скрытый PAYLOAD дошёл до чужой машины: шкала растёт тайно; на 100% вор получает вирус без смены владельца.
static func on_payload_hidden(w: World, node: NodeState, attacker: int) -> void:
	if node.owner < 0 or node.owner == attacker or node.type == Defs.NodeType.SWITCH:
		return
	if node.virus[attacker] == 1:
		return
	var gain: int = Defs.INFECT_HIDDEN_GAIN
	if node.soft_active(Defs.SoftType.ANTIVIRUS):
		gain = gain * Defs.ANTIVIRUS_GAIN_PERCENT / 100
	node.virus_meter[attacker] = mini(Defs.INFECT_MAX, node.virus_meter[attacker] + gain)
	if node.virus_meter[attacker] >= Defs.INFECT_MAX:
		node.virus_meter[attacker] = 0
		node.virus[attacker] = 1

## Активация вируса «Открыть дверь»: на DOOR_TICKS у вора доступ, ПО машины выключено. Вирус расходуется.
static func apply_activate(w: World, player: int, args: Array) -> bool:
	if args.size() != 2 or player < 0 or player >= w.players.size():
		return false
	var nid: int = args[0]
	var mode: int = args[1]
	if nid < 0 or nid >= w.nodes.size():
		return false
	var n: NodeState = w.nodes[nid]
	if n.owner < 0 or n.owner == player or n.virus[player] != 1:
		return false
	if mode != Defs.ActivateMode.OPEN_DOOR:
		return false
	n.soft_off = Defs.DOOR_TICKS
	n.door[player] = Defs.DOOR_TICKS
	n.virus[player] = 0
	n.det_timer[NodeState.hidden_slot(Defs.HiddenKind.VIRUS, player)] = 0
	n.found[NodeState.hidden_slot(Defs.HiddenKind.VIRUS, player)] = 0
	return true

## Вирус на машине отводит вору часть её DATA: true — байт ушёл вору и в буфер не попадёт.
static func skim_data(w: World, n: NodeState) -> bool:
	for a in Defs.MAX_PLAYERS:
		if a == n.owner or n.virus[a] != 1:
			continue
		n.skim_acc[a] += Defs.VIRUS_SKIM_PERCENT
		if n.skim_acc[a] >= 100:
			n.skim_acc[a] -= 100
			var pl: PlayerState = w.players[a]
			pl.bank += Defs.DATA_VALUE
			pl.earned_total += Defs.DATA_VALUE
			pl.income_hist[w.tick % Defs.LOAD_WINDOW] += Defs.DATA_VALUE
			return true
	return false

## Сниффер на транзитном узле крадёт часть чужих DATA: true — пакет забран.
static func sniff_transit(w: World, n: NodeState, idx: int) -> bool:
	if n.owner < 0 or not n.soft_active(Defs.SoftType.SNIFFER):
		return false
	var pool: PacketPool = w.pool
	if pool.ptype[idx] != Defs.PacketType.DATA or pool.owner[idx] == n.owner:
		return false
	n.sniff_acc += Defs.SNIFFER_STEAL_PERCENT
	if n.sniff_acc < 100:
		return false
	n.sniff_acc -= 100
	var pl: PlayerState = w.players[n.owner]
	pl.bank += Defs.DATA_VALUE
	pl.earned_total += Defs.DATA_VALUE
	pl.income_hist[w.tick % Defs.LOAD_WINDOW] += Defs.DATA_VALUE
	w.delivered_sniffed += 1
	return true

## Раз в тик: IDS и антивирус копят «время наблюдения» по скрытому и находят его.
static func detect(w: World) -> void:
	for n in w.nodes:
		if n.soft_off > 0:
			n.soft_off -= 1
		for p in Defs.MAX_PLAYERS:
			if n.door[p] > 0:
				n.door[p] -= 1
		if n.owner < 0:
			continue
		var by_ids: bool = ids_covers(w, n.owner, n)
		var by_av: bool = n.soft_active(Defs.SoftType.ANTIVIRUS)
		if by_ids or by_av:
			for a in Defs.MAX_PLAYERS:
				if a == n.owner:
					continue
				if n.virus[a] == 1:
					_advance(w, n, Defs.HiddenKind.VIRUS, a, n.owner, by_av and not by_ids)
				if n.backdoor[a] == 1:
					_advance(w, n, Defs.HiddenKind.BACKDOOR, a, n.owner, by_av and not by_ids)
		if n.has_soft(Defs.SoftType.SNIFFER):
			for p in w.players.size():
				if p != n.owner and ids_covers(w, p, n):
					_advance(w, n, Defs.HiddenKind.SNIFFER, p, p, false)

static func _advance(w: World, n: NodeState, kind: int, who: int, finder: int, by_av: bool) -> void:
	var slot: int = NodeState.hidden_slot(kind, who)
	if n.found[slot] == 1:
		return
	n.det_timer[slot] += 1
	if n.det_timer[slot] >= int(Defs.HIDDEN_DETECT_S[kind]) * Defs.TICK_HZ:
		n.found[slot] = 1
		Knowledge.log_event(w, finder, Knowledge.EventKind.HIDDEN_FOUND, n.id, -1, kind * 2 + (1 if by_av else 0))

## «Вычистить»: убирает обычную шкалу и всё найденное из скрытого. Ненайденное остаётся.
static func clean(n: NodeState) -> void:
	n.infect.fill(0)    # вместе с шкалой уходит и 100% заражение (доступ и выключенное ПО)
	for a in Defs.MAX_PLAYERS:
		var sv: int = NodeState.hidden_slot(Defs.HiddenKind.VIRUS, a)
		if n.found[sv] == 1:
			n.virus[a] = 0
			n.virus_meter[a] = 0
			n.found[sv] = 0
			n.det_timer[sv] = 0
		var sb: int = NodeState.hidden_slot(Defs.HiddenKind.BACKDOOR, a)
		if n.found[sb] == 1:
			n.backdoor[a] = 0
			n.found[sb] = 0
			n.det_timer[sb] = 0

## Есть ли на машине найденное владельцем, что можно вычистить.
static func has_found_threat(n: NodeState) -> bool:
	for a in Defs.MAX_PLAYERS:
		if n.found[NodeState.hidden_slot(Defs.HiddenKind.VIRUS, a)] == 1 and n.virus[a] == 1:
			return true
		if n.found[NodeState.hidden_slot(Defs.HiddenKind.BACKDOOR, a)] == 1 and n.backdoor[a] == 1:
			return true
	return false
