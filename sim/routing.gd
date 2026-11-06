class_name Routing
extends RefCounted
## Маршруты: для каждой цели — таблица «из узла → id линка следующего шага».
## Кратчайший путь по цене: задержка*вес + загрузка*штраф. Ничья — меньший id линка.

const INF: int = 1 << 40

## seen=false: загрузка линка неизвестна (игрок её не видит), цена — одна задержка.
static func link_cost(l: LinkState, d: int, seen: bool = true) -> int:
	var cost: int = l.latency * Defs.ROUTE_LATENCY_WEIGHT
	if seen:
		cost += l.load_pct(d) * Defs.ROUTE_LOAD_PENALTY
	return cost

## Таблицы по истине (экономика) и по знаниям каждого игрока (пакеты игрока).
static func compute(w: World) -> void:
	var n: int = w.nodes.size()
	w.routes.clear()
	w.route_dist.clear()
	for dst in n:
		var res: Array = _from_dst(w, dst, n, null)
		w.routes.append(res[0])
		w.route_dist.append(res[1])
	w.proutes.clear()
	for p in w.players.size():
		var table: Array[PackedInt32Array] = []
		var seen: Variant = w.know[p].link_seen if p < w.know.size() else null
		for dst in n:
			table.append(_from_dst(w, dst, n, seen)[0])
		w.proutes.append(table)
	w.routes_dirty = false

## Возвращает [next: PackedInt32Array, dist: PackedInt64Array]. dist[u] — цена пути из u в dst.
static func _from_dst(w: World, dst: int, n: int, seen: Variant) -> Array:
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
			var known: bool = seen == null or (seen as PackedByteArray)[lid] == 1
			var cand: int = dist[v] + link_cost(l, l.dir_from(u), known)
			if cand < dist[u] or (cand == dist[u] and lid < next[u]):
				dist[u] = cand
				next[u] = lid
	return [next, dist]

## Путь из src в dst по текущим таблицам: список id узлов (включая оба конца). Пусто — нет маршрута.
static func path(w: World, src: int, dst: int, owner: int = -1) -> Array[int]:
	var out: Array[int] = [src]
	if src == dst:
		return out
	var table: Array[PackedInt32Array] = w.route_table(owner)
	if table.size() <= dst:
		return []
	var cur: int = src
	var guard: int = w.nodes.size()
	while cur != dst and guard > 0:
		var lid: int = table[dst][cur]
		if lid < 0:
			return []
		cur = w.links[lid].other(cur)
		out.append(cur)
		guard -= 1
	return out if cur == dst else []
