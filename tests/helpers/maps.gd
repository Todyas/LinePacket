class_name TestMaps
extends RefCounted
## Небольшие карты для тестов (тестовый код, не часть игры).

static func node(id: int, type: String, x: int, y: int, owner: int = -1) -> Dictionary:
	return {"id": id, "type": type, "x": x, "y": y, "owner": owner}

static func link(a: int, b: int, kind: String = "cable") -> Dictionary:
	return {"a": a, "b": b, "kind": kind}

static func build(d: Dictionary, seed_value: int = 1) -> World:
	var res: Dictionary = MapLoader.load_dict(d, seed_value)
	assert(res["world"] != null, str(res["error"]))
	return res["world"]

## Два ядра, один линк длиной len_px.
static func pair(len_px: int, kind: String = "cable", seed_value: int = 1) -> World:
	return build({
		"name": "pair", "players": 2,
		"nodes": [node(0, "core", 0, 0, 0), node(1, "core", len_px, 0, 1)],
		"links": [link(0, 1, kind)],
	}, seed_value)

## Ромб: путь через A (узел 1) короче, чем через B (узел 2).
static func diamond(seed_value: int = 1) -> World:
	return build({
		"name": "diamond", "players": 2,
		"nodes": [
			node(0, "core", 0, 300, 0),
			node(1, "machine", 300, 0),
			node(2, "machine", 300, 900),
			node(3, "core", 600, 300, 1),
		],
		"links": [link(0, 1), link(1, 3), link(0, 2), link(2, 3)],
	}, seed_value)

## Мишень T (узел 2), к которой оптикой подключены оба ядра.
static func star(seed_value: int = 1) -> World:
	return build({
		"name": "star", "players": 2,
		"nodes": [
			node(0, "core", 0, 0, 0),
			node(1, "core", 0, 400, 1),
			node(2, "machine", 400, 200),
		],
		"links": [link(0, 2, "optic"), link(1, 2, "optic")],
	}, seed_value)

## Сетка side×side из оптики; все машины принадлежат игроку 0 (чтобы пускать потоки откуда угодно).
static func grid(side: int, spacing: int, seed_value: int = 1) -> World:
	var nodes: Array = []
	for y in side:
		for x in side:
			var id: int = y * side + x
			var t: String = "machine"
			var owner: int = 0
			if id == 0:
				t = "core"
			elif id == side * side - 1:
				t = "core"
				owner = 1
			nodes.append(node(id, t, x * spacing, y * spacing, owner))
	var links: Array = []
	for y in side:
		for x in side:
			var id2: int = y * side + x
			if x + 1 < side:
				links.append(link(id2, id2 + 1, "optic"))
			if y + 1 < side:
				links.append(link(id2, id2 + side, "optic"))
	return build({"name": "grid", "players": 2, "nodes": nodes, "links": links}, seed_value)

## Экономика: ядро P0, свой шлюз и n своих машин через свич (чтобы упереться в потолок шлюза).
static func eco_fan(machines: int, gateway_owner: int = 0, seed_value: int = 1) -> World:
	var nodes: Array = [
		node(0, "core", 0, 0, 0),
		node(1, "gateway", 200, 0, gateway_owner),
		node(2, "switch", 100, 150),
		node(3, "core", 3000, 0, 1),
	]
	var links: Array = [link(0, 1, "optic"), link(2, 1, "optic"), link(0, 2, "optic"), link(1, 3, "optic")]
	var second_switch: int = 4 + machines
	for i in machines:
		var id: int = 4 + i
		nodes.append(node(id, "machine", 60 + i * 20, 300, 0))
		links.append(link(id, 2 if i < 5 or machines <= 5 else second_switch, "optic"))
	if machines > 5:
		nodes.append(node(second_switch, "switch", 300, 150))
		links.append(link(second_switch, 1, "optic"))
		links.append(link(second_switch, 0, "optic"))
	return build({"name": "eco", "players": 2, "nodes": nodes, "links": links}, seed_value)

## Цепочка: ядро P0 — машина (P0) — машина (нейтрал); дальний конец — ядро P1.
static func chain(seed_value: int = 1) -> World:
	return build({
		"name": "chain", "players": 2,
		"nodes": [
			node(0, "core", 0, 0, 0),
			node(1, "machine", 200, 0, 0),
			node(2, "machine", 400, 0, -1),
			node(3, "gateway", 0, 200, 0),
			node(4, "core", 2000, 0, 1),
		],
		"links": [link(0, 1), link(1, 2), link(0, 3), link(2, 4, "optic")],
	}, seed_value)

## Осада: у P0 ядро, шлюз и машина (узел 2); у P1 ядро (3) и машина (4), оба подключены к цели оптикой.
static func siege(seed_value: int = 1) -> World:
	return build({
		"name": "siege", "players": 2,
		"nodes": [
			node(0, "core", 0, 0, 0),
			node(1, "gateway", 200, 0, 0),
			node(2, "machine", 400, 0, 0),
			node(3, "core", 400, 600, 1),
			node(4, "machine", 600, 300, 1),
			node(5, "gateway", 800, 600, 1),
		],
		"links": [link(0, 1, "optic"), link(1, 2, "optic"), link(3, 2, "optic"), link(4, 2, "optic"), link(3, 4, "optic"), link(4, 5, "optic"), link(3, 5, "optic")],
	}, seed_value)

## Дуэль двух ядер напрямую: захват ядра завершает матч.
static func rush(seed_value: int = 1) -> World:
	return build({
		"name": "rush", "players": 2,
		"nodes": [
			node(0, "core", 0, 0, 0),
			node(1, "core", 300, 0, 1),
		],
		"links": [link(0, 1, "optic")],
	}, seed_value)

## Разведка: цепочка 0–1–2–3 и обход 0–4–5–3. Ядро P0 — узел 0, ядро P1 — узел 3, остальное нейтрально.
## Линк 2–3 не виден P0 (ни один его конец не наблюдается).
static func scout(seed_value: int = 1) -> World:
	return build({
		"name": "scout", "players": 2,
		"nodes": [
			node(0, "core", 0, 0, 0),
			node(1, "machine", 300, 0),
			node(2, "machine", 600, 0),
			node(3, "core", 900, 0, 1),
			node(4, "machine", 300, 300),
			node(5, "machine", 600, 300),
		],
		"links": [link(0, 1), link(1, 2), link(2, 3), link(0, 4), link(4, 5), link(5, 3)],
	}, seed_value)


## --- Роли в тестах (тестовые двойники, не часть игры) ---

static func role_for(ptype: int) -> int:
	match ptype:
		Defs.PacketType.INIT:
			return Defs.Role.CAPTURE
		Defs.PacketType.FLOOD:
			return Defs.Role.PRESSURE
		Defs.PacketType.PAYLOAD:
			return Defs.Role.INFECT
		Defs.PacketType.PAYLOAD_HIDDEN:
			return Defs.Role.INFECT_HIDDEN
	return Defs.Role.WORK

## Боевая роль сразу, без перенастройки: как будто игрок назначил её 5 секунд назад.
static func engage(w: World, player: int, src: int, dst: int, ptype: int) -> void:
	var ok: bool = Roles.apply_set_role(w, player, [src, role_for(ptype), dst])
	assert(ok, "роль не назначена: %d → %d" % [src, dst])
	w.nodes[src].reconf = 0

## Ретранслятор удваивает боевую мощность машины.
static func boost(w: World, node: int) -> void:
	w.nodes[node].install_soft(Defs.SoftType.RELAY)

## Снять боевую роль: машина возвращается к работе.
static func stand_down(w: World, node: int) -> void:
	w.nodes[node].reset_role()

## Источник пакетов для тестов сети: per_s пакетов в секунду от src к dst, ticks тиков (шаги мира включены).
## Заменяет прежние потоки; сами пакеты рождаются так же, как у роли: Network.inject от имени владельца src.
static func pump(w: World, srcs: Array, dst_of: Array, ptype: int, per_s: int, ticks: int) -> void:
	var acc: Array[int] = []
	for i in srcs.size():
		acc.append(0)
	for t in ticks:
		for i in srcs.size():
			acc[i] += per_s
			while acc[i] >= Defs.TICK_HZ:
				acc[i] -= Defs.TICK_HZ
				Network.inject(w, srcs[i], dst_of[i], ptype, w.nodes[srcs[i]].owner, 0)
		w.step()

## Все агенты игрока «в пути домой» надолго: на ядре и узлах их нет, никто не защищает.
static func clear_defenders(w: World, player: int) -> void:
	for a in w.agents:
		if a.owner == player:
			a.node = -1
			a.mode = AgentState.Mode.LOST
			a.lost_timer = 1000000

## Машина заражена атакующим на 100% (как после полной шкалы PAYLOAD).
static func infect_fully(w: World, node: int, attacker: int) -> void:
	w.nodes[node].infect[attacker] = Defs.INFECT_MAX
