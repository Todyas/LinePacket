class_name Builds
extends RefCounted
## Строительство (S13): линки, новые машины, апгрейд CPU и слота ПО. Идёт удалённо, без агента:
## байты списываются при старте, стройка занимает время, отмены нет. Запись стройки w.builds:
## [игрок, вид BuildKind, узел a, узел b, тиков осталось, тиков всего, x, y] (x, y — место новой машины).

const F_PLAYER: int = 0
const F_KIND: int = 1
const F_A: int = 2
const F_B: int = 3
const F_LEFT: int = 4
const F_TOTAL: int = 5
const F_X: int = 6
const F_Y: int = 7

static func is_link(kind: int) -> bool:
	return kind == Defs.BuildKind.CABLE or kind == Defs.BuildKind.OPTIC

static func link_kind_of(build_kind: int) -> int:
	return Defs.LinkKind.OPTIC if build_kind == Defs.BuildKind.OPTIC else Defs.LinkKind.CABLE

static func ticks_for(kind: int) -> int:
	return int(Defs.BUILD_DEFS[kind]["time_s"]) * Defs.TICK_HZ

static func length_between(w: World, a: int, b: int) -> int:
	var dx: int = w.nodes[a].x - w.nodes[b].x
	var dy: int = w.nodes[a].y - w.nodes[b].y
	return IntMath.isqrt(dx * dx + dy * dy)

## Цена стройки в байтах; для линка зависит от длины.
static func cost_for(w: World, kind: int, a: int, b: int) -> int:
	var d: Dictionary = Defs.BUILD_DEFS[kind]
	var c: int = int(d["cost"])
	if is_link(kind) and a >= 0 and b >= 0 and a < w.nodes.size() and b < w.nodes.size():
		c += length_between(w, a, b) / int(d["per_length"])
	return c

## Занятые стройками порты узла.
static func reserved_ports(w: World, nid: int) -> int:
	var r: int = 0
	for b in w.builds:
		var kind: int = b[F_KIND]
		if is_link(kind) and (b[F_A] == nid or b[F_B] == nid):
			r += 1
		elif kind == Defs.BuildKind.MACHINE and b[F_A] == nid:
			r += 1
	return r

static func free_ports(w: World, nid: int) -> int:
	var n: NodeState = w.nodes[nid]
	return int(Defs.NODE_DEFS[n.type]["ports"]) - n.links.size() - reserved_ports(w, nid)

static func pending_of(w: World, player: int) -> int:
	var c: int = 0
	for b in w.builds:
		if b[F_PLAYER] == player:
			c += 1
	return c

static func _pending_on(w: World, kind: int, nid: int) -> bool:
	for b in w.builds:
		if b[F_KIND] == kind and b[F_A] == nid:
			return true
	return false

static func _linked_or_pending(w: World, a: int, b: int) -> bool:
	for lid in w.nodes[a].links:
		if w.links[lid].other(a) == b:
			return true
	for bd in w.builds:
		if is_link(bd[F_KIND]) and ((bd[F_A] == a and bd[F_B] == b) or (bd[F_A] == b and bd[F_B] == a)):
			return true
	return false

## Место для новой машины рядом с родителем: первое свободное из восьми направлений. null — места нет.
static func node_spot(w: World, parent: int) -> Variant:
	var p: NodeState = w.nodes[parent]
	var dirs: Array = [[10, 0], [0, 10], [-10, 0], [0, -10], [7, 7], [-7, 7], [-7, -7], [7, -7]]
	for ring in 2:
		var dist: int = Defs.BUILD_NODE_DISTANCE * (2 + ring) / 2
		for i in 8:
			var d: Array = dirs[(i + parent) % 8]
			var x: int = p.x + d[0] * dist / 10
			var y: int = p.y + d[1] * dist / 10
			if _spot_free(w, x, y):
				return [x, y]
	return null

static func _spot_free(w: World, x: int, y: int) -> bool:
	var sep2: int = Defs.BUILD_MIN_SEPARATION * Defs.BUILD_MIN_SEPARATION
	for n in w.nodes:
		var dx: int = n.x - x
		var dy: int = n.y - y
		if dx * dx + dy * dy < sep2:
			return false
	for b in w.builds:
		if b[F_KIND] == Defs.BuildKind.MACHINE:
			var dx: int = int(b[F_X]) - x
			var dy: int = int(b[F_Y]) - y
			if dx * dx + dy * dy < sep2:
				return false
	return true

## Годится ли узел как конец своего линка: свой или ничейный маршрутизатор.
static func _link_end_ok(n: NodeState, player: int) -> bool:
	return n.owner == player or (n.type == Defs.NodeType.ROUTER and n.owner == Defs.NEUTRAL)

## Причина отказа по-русски или пустая строка, если стройку можно начинать. Чистая функция: годится для UI и бота.
static func refusal(w: World, player: int, kind: int, a: int, b: int = -1) -> String:
	if player < 0 or player >= w.players.size() or not Defs.BUILD_DEFS.has(kind):
		return "неверная команда"
	if a < 0 or a >= w.nodes.size():
		return "нет такого узла"
	var na: NodeState = w.nodes[a]
	if pending_of(w, player) >= Defs.BUILD_MAX_PARALLEL:
		return "уже идёт %d стройки" % Defs.BUILD_MAX_PARALLEL
	if is_link(kind):
		if b < 0 or b >= w.nodes.size() or a == b:
			return "нужны два разных узла"
		var nb: NodeState = w.nodes[b]
		if na.owner != player and nb.owner != player:
			return "хотя бы один конец линка должен быть вашим"
		if not _link_end_ok(na, player) or not _link_end_ok(nb, player):
			return "линк только между своими узлами или к свободному маршрутизатору"
		if _linked_or_pending(w, a, b):
			return "эти узлы уже связаны"
		if free_ports(w, a) <= 0 or free_ports(w, b) <= 0:
			return "нет свободного порта"
		if length_between(w, a, b) > Defs.BUILD_MAX_LINK_LENGTH:
			return "линк длиннее %d" % Defs.BUILD_MAX_LINK_LENGTH
	else:
		if na.owner != player:
			return "узел не ваш"
		match kind:
			Defs.BuildKind.MACHINE:
				if free_ports(w, a) <= 0:
					return "нет свободного порта"
				if node_spot(w, a) == null:
					return "рядом нет места"
			Defs.BuildKind.CPU:
				if na.type == Defs.NodeType.ROUTER:
					return "маршрутизатору CPU не нужен"
				if na.cpu_level >= Defs.CPU_UPGRADE_MAX or _pending_on(w, kind, a):
					return "CPU уже улучшен до предела"
			Defs.BuildKind.SLOT:
				if na.extra_slots >= Defs.EXTRA_SLOT_MAX or _pending_on(w, kind, a):
					return "доп. слот уже есть"
	if w.players[player].bank < cost_for(w, kind, a, b):
		return "не хватает байт (%d)" % cost_for(w, kind, a, b)
	return ""

## Команда BUILD: [вид, a, b].
static func apply(w: World, player: int, args: Array) -> bool:
	if args.size() != 3:
		return false
	var kind: int = args[0]
	var a: int = args[1]
	var b: int = args[2]
	if refusal(w, player, kind, a, b) != "":
		return false
	w.players[player].bank -= cost_for(w, kind, a, b)
	var x: int = 0
	var y: int = 0
	if kind == Defs.BuildKind.MACHINE:
		var spot: Array = node_spot(w, a)
		x = spot[0]
		y = spot[1]
	var total: int = ticks_for(kind)
	w.builds.append([player, kind, a, b if is_link(kind) else -1, total, total, x, y])
	if kind == Defs.BuildKind.CPU:
		w.nodes[a].upgrading += 1
		w.nodes[a].refresh_cpu()
	return true

## Раз в тик: идут стройки, готовые вводятся в мир.
static func step(w: World) -> void:
	if w.builds.is_empty():
		return
	var keep: Array = []
	for b in w.builds:
		b[F_LEFT] = int(b[F_LEFT]) - 1
		if int(b[F_LEFT]) > 0:
			keep.append(b)
	var done: Array = []
	for b in w.builds:
		if int(b[F_LEFT]) <= 0:
			done.append(b)
	w.builds = keep
	for b in done:
		_complete(w, b)

static func _complete(w: World, b: Array) -> void:
	var kind: int = b[F_KIND]
	var player: int = b[F_PLAYER]
	var a: int = b[F_A]
	match kind:
		Defs.BuildKind.CABLE, Defs.BuildKind.OPTIC:
			w.add_link(a, b[F_B], link_kind_of(kind))
		Defs.BuildKind.MACHINE:
			var n: NodeState = w.add_node(Defs.NodeType.MACHINE, b[F_X], b[F_Y], player)
			w.add_link(a, n.id, Defs.LinkKind.CABLE)
		Defs.BuildKind.CPU:
			var n: NodeState = w.nodes[a]
			n.upgrading = maxi(0, n.upgrading - 1)
			if n.owner == player:
				n.cpu_level += 1
				n.cpu_base += Defs.CPU_UPGRADE_BONUS
			n.refresh_cpu()
		Defs.BuildKind.SLOT:
			var n: NodeState = w.nodes[a]
			if n.owner == player:
				n.extra_slots += 1
	if is_link(kind) or kind == Defs.BuildKind.MACHINE:
		w.routes_dirty = true

## Стройки, которые игрок видит: свои и те, чей узел он наблюдает.
static func visible_to(w: World, player: int) -> Array:
	var out: Array = []
	for b in w.builds:
		if b[F_PLAYER] == player:
			out.append(b)
			continue
		var seen: bool = Knowledge.level(w, player, b[F_A]) == Knowledge.Level.OBSERVED
		if is_link(b[F_KIND]) and Knowledge.level(w, player, b[F_B]) == Knowledge.Level.OBSERVED:
			seen = true
		if seen:
			out.append(b)
	return out
