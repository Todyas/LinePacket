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
