class_name Routing
extends RefCounted
## Маршруты: для каждой цели — таблица «из узла → id линка следующего шага».
## Кратчайший путь по цене: задержка*вес + загрузка*штраф. Ничья — меньший id линка.

const INF: int = 1 << 40

static func link_cost(l: LinkState, d: int) -> int:
	return l.latency * Defs.ROUTE_LATENCY_WEIGHT + l.load_pct(d) * Defs.ROUTE_LOAD_PENALTY

static func compute(w: World) -> void:
	var n: int = w.nodes.size()
	w.routes.clear()
	for dst in n:
		w.routes.append(_from_dst(w, dst, n))
	w.routes_dirty = false

static func _from_dst(w: World, dst: int, n: int) -> PackedInt32Array:
	var dist := PackedInt64Array()
	dist.resize(n)
	dist.fill(INF)
	var next := PackedInt32Array()
	next.resize(n)
	next.fill(-1)
	var settled := PackedByteArray()
	settled.resize(n)
	dist[dst] = 0
	for _round in n:
		var v: int = -1
		var best: int = INF
		for i in n:
			if settled[i] == 0 and dist[i] < best:
				best = dist[i]
				v = i
		if v < 0:
			break
		settled[v] = 1
		for lid in w.nodes[v].links:
			var l: LinkState = w.links[lid]
			var u: int = l.other(v)
			if settled[u] == 1:
				continue
			# Пакет идёт из u в v: цена направления, исходящего из u.
			var cand: int = dist[v] + link_cost(l, l.dir_from(u))
			if cand < dist[u] or (cand == dist[u] and lid < next[u]):
				dist[u] = cand
				next[u] = lid
	return next

## Путь из src в dst по текущим таблицам: список id узлов (включая оба конца). Пусто — нет маршрута.
static func path(w: World, src: int, dst: int) -> Array[int]:
	var out: Array[int] = [src]
	if src == dst:
		return out
	if w.routes.size() <= dst:
		return []
	var cur: int = src
	var guard: int = w.nodes.size()
	while cur != dst and guard > 0:
		var lid: int = w.routes[dst][cur]
		if lid < 0:
			return []
		cur = w.links[lid].other(cur)
		out.append(cur)
		guard -= 1
	return out if cur == dst else []
