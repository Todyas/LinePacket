class_name MapLoader
extends RefCounted
## Загрузка карты из JSON. Возвращает {"world": World или null, "error": String}.

static func load_file(path: String, seed_value: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"world": null, "error": "Файл карты не найден: %s" % path}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {"world": null, "error": "Карта %s: некорректный JSON" % path}
	return load_dict(parsed as Dictionary, seed_value)

static func _as_int(v: Variant, what: String, errors: Array) -> int:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return v
	if t == TYPE_FLOAT and v == floorf(v):
		return int(v)
	errors.append("%s: ожидалось целое число" % what)
	return 0

static func load_dict(d: Dictionary, seed_value: int) -> Dictionary:
	var errors: Array = []
	if not d.has("nodes") or typeof(d["nodes"]) != TYPE_ARRAY:
		return _fail("в карте нет списка nodes")
	if not d.has("links") or typeof(d["links"]) != TYPE_ARRAY:
		return _fail("в карте нет списка links")
	var player_count: int = _as_int(d.get("players", 0), "players", errors)
	if player_count < 1 or player_count > Defs.MAX_PLAYERS:
		errors.append("players: допустимо от 1 до %d" % Defs.MAX_PLAYERS)

	var w := World.new(seed_value)
	w.map_name = str(d.get("name", ""))
	var raw_nodes: Array = d["nodes"]
	for i in raw_nodes.size():
		var rn: Variant = raw_nodes[i]
		if typeof(rn) != TYPE_DICTIONARY:
			errors.append("узел #%d: ожидался объект" % i)
			continue
		var nd: Dictionary = rn
		var n := NodeState.new()
		n.id = _as_int(nd.get("id", -1), "узел #%d: id" % i, errors)
		if n.id != i:
			errors.append("узел #%d: id должен быть равен позиции в списке (получено %d)" % [i, n.id])
		var tname: String = str(nd.get("type", ""))
		if not Defs.NODE_TYPE_NAMES.has(tname):
			errors.append("узел %d: неизвестный тип '%s'" % [i, tname])
		else:
			n.type = Defs.NODE_TYPE_NAMES[tname]
		n.x = _as_int(nd.get("x", 0), "узел %d: x" % i, errors)
		n.y = _as_int(nd.get("y", 0), "узел %d: y" % i, errors)
		n.owner = _as_int(nd.get("owner", Defs.NEUTRAL), "узел %d: owner" % i, errors)
		if n.owner != Defs.NEUTRAL and (n.owner < 0 or n.owner >= player_count):
			errors.append("узел %d: владелец %d вне диапазона игроков" % [i, n.owner])
		if Defs.NODE_DEFS.has(n.type):
			n.setup_cpu()
		w.nodes.append(n)

	var seen_pairs: Dictionary = {}
	var raw_links: Array = d["links"]
	for i in raw_links.size():
		var rl: Variant = raw_links[i]
		if typeof(rl) != TYPE_DICTIONARY:
			errors.append("линк #%d: ожидался объект" % i)
			continue
		var ld: Dictionary = rl
		var l := LinkState.new()
		l.id = i
		l.a = _as_int(ld.get("a", -1), "линк %d: a" % i, errors)
		l.b = _as_int(ld.get("b", -1), "линк %d: b" % i, errors)
		if l.a < 0 or l.a >= w.nodes.size() or l.b < 0 or l.b >= w.nodes.size():
			errors.append("линк %d: ссылается на несуществующий узел (%d-%d)" % [i, l.a, l.b])
			continue
		if l.a == l.b:
			errors.append("линк %d: петля на узле %d" % [i, l.a])
			continue
		var key: int = mini(l.a, l.b) * 100000 + maxi(l.a, l.b)
		if seen_pairs.has(key):
			errors.append("линк %d: дубликат пары %d-%d" % [i, l.a, l.b])
			continue
		seen_pairs[key] = true
		var kname: String = str(ld.get("kind", "cable"))
		if not Defs.LINK_KIND_NAMES.has(kname):
			errors.append("линк %d: неизвестный вид '%s'" % [i, kname])
			continue
		l.kind = Defs.LINK_KIND_NAMES[kname]
		var ldef: Dictionary = Defs.LINK_DEFS[l.kind]
		var na: NodeState = w.nodes[l.a]
		var nb: NodeState = w.nodes[l.b]
		var dx: int = na.x - nb.x
		var dy: int = na.y - nb.y
		l.length = IntMath.isqrt(dx * dx + dy * dy)
		l.latency = maxi(Defs.LINK_MIN_LATENCY, IntMath.ceil_div(l.length, int(ldef["speed"])))
		l.capacity = int(ldef["capacity"])
		l.queue_limit = int(ldef["queue"])
		l.credit[0] = l.credit_cap()
		l.credit[1] = l.credit_cap()
		w.links.append(l)
		na.links.append(l.id)
		nb.links.append(l.id)

	if not errors.is_empty():
		return _fail("; ".join(errors))

	# Порты не превышены.
	for n in w.nodes:
		var maxp: int = int(Defs.NODE_DEFS[n.type]["ports"])
		if n.links.size() > maxp:
			errors.append("узел %d: %d линков при лимите портов %d" % [n.id, n.links.size(), maxp])
	# По одному ядру на игрока.
	var core_of: Dictionary = {}
	for n in w.nodes:
		if n.type == Defs.NodeType.CORE:
			if n.owner == Defs.NEUTRAL:
				errors.append("ядро %d без владельца" % n.id)
			elif core_of.has(n.owner):
				errors.append("у игрока %d больше одного ядра" % n.owner)
			else:
				core_of[n.owner] = n.id
	for p in player_count:
		if not core_of.has(p):
			errors.append("у игрока %d нет ядра" % p)
	if not errors.is_empty():
		return _fail("; ".join(errors))

	for n in w.nodes:
		# Разводим фазы автоматических пакетов, чтобы узлы не слали пачками в один тик.
		n.produce_acc = (n.id * 7) % Defs.TICK_HZ
		n.ka_acc = (n.id * 11) % Defs.TICK_HZ
		if n.owner >= 0:
			n.control = Defs.CONTROL_MAX
			n.reset_access()
		if n.type == Defs.NodeType.GATEWAY:
			n.gw_credit = Defs.GATEWAY_CAP_PER_S * Defs.GATEWAY_BURST_TICKS
	for p in player_count:
		var ps := PlayerState.new()
		ps.id = p
		ps.core_node = core_of[p]
		w.players.append(ps)
		for k in Defs.AGENTS_PER_PLAYER:
			var ag := AgentState.new()
			ag.id = k
			ag.owner = p
			ag.node = ps.core_node
			w.agents.append(ag)

	# Связность графа.
	if not _connected(w):
		return _fail("граф карты несвязный")
	Routing.compute(w)
	Economy.refresh_targets(w)
	return {"world": w, "error": ""}

static func _connected(w: World) -> bool:
	if w.nodes.is_empty():
		return false
	var seen: Array[bool] = []
	seen.resize(w.nodes.size())
	seen.fill(false)
	var stack: Array[int] = [0]
	seen[0] = true
	var count: int = 1
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for lid in w.nodes[cur].links:
			var o: int = w.links[lid].other(cur)
			if not seen[o]:
				seen[o] = true
				count += 1
				stack.append(o)
	return count == w.nodes.size()

static func _fail(msg: String) -> Dictionary:
	return {"world": null, "error": "Ошибка карты: " + msg}
