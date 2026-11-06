class_name Picking
extends RefCounted
## Выбор объектов под курсором. Чистые функции — тестируются без сцены.

## Ближайший узел в радиусе radius (в координатах мира) или -1.
static func hit_node(w: World, pos: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for n in w.nodes:
		var d: float = Vector2(n.x, n.y).distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = n.id
	return best

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len2: float = ab.length_squared()
	if len2 == 0.0:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Поток игрока player, чей маршрут проходит ближе всего к pos (не дальше max_dist) или -1.
static func hit_flow(w: World, player: int, pos: Vector2, max_dist: float) -> int:
	var best: int = -1
	var best_d: float = max_dist
	for f in w.flows:
		if f.owner != player:
			continue
		var path: Array[int] = Routing.path(w, f.src, f.dst)
		for i in range(path.size() - 1):
			var a: NodeState = w.nodes[path[i]]
			var b: NodeState = w.nodes[path[i + 1]]
			var d: float = _seg_dist(pos, Vector2(a.x, a.y), Vector2(b.x, b.y))
			if d < best_d:
				best_d = d
				best = f.id
	return best
