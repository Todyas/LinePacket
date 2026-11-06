class_name Knowledge
extends RefCounted
## Карта знаний игрока. Это единственный честный способ прочитать мир «глазами игрока»:
## view и бот ходят сюда, а не в NodeState напрямую.
## Уровни: силуэт (стартовая топология), снимок (дозор или давнее наблюдение), наблюдение (свои узлы и соседние).

enum Level { SILHOUETTE, SNAPSHOT, OBSERVED }
enum EventKind { IDS_ATTACK, NODE_CAPTURED, NODE_LOST, NODE_DOWN, HIDDEN_FOUND, AGENT_SEEN, AGENT_CAPTURING }

const UNKNOWN_OWNER: int = -2
const EVENT_LIMIT: int = 60

var snaps: Array = []                 # NodeSnap или null на каждый узел
var observed: PackedByteArray = PackedByteArray()
var link_seen: PackedByteArray = PackedByteArray()
var events: Array = []                # [тик, вид, узел, линк, тип пакета]

func _init(node_count: int, link_count: int) -> void:
	snaps.resize(node_count)
	observed.resize(node_count)
	link_seen.resize(link_count)

func hash_into(h: Hasher) -> void:
	for s in snaps:
		if s == null:
			h.add(-1)
		else:
			(s as NodeSnap).hash_into(h)
	h.add_array(Array(observed))
	h.add(events.size())
	for e in events:
		h.add_array(e)

# --- Служебное (вызывается симуляцией) ---

static func ensure(w: World) -> void:
	while w.know.size() < w.players.size():
		w.know.append(Knowledge.new(w.nodes.size(), w.links.size()))

## Карта выросла (стройка): массивы знаний растягиваются, новое — силуэт.
static func grow(w: World) -> void:
	for k in w.know:
		if k.snaps.size() < w.nodes.size():
			k.snaps.resize(w.nodes.size())
			k.observed.resize(w.nodes.size())
		if k.link_seen.size() < w.links.size():
			k.link_seen.resize(w.links.size())

## Раз в тик: что игрок наблюдает прямо сейчас, и свежие снимки наблюдаемого.
static func update(w: World) -> void:
	ensure(w)
	for p in w.players.size():
		var k: Knowledge = w.know[p]
		k.observed.fill(0)
		for n in w.nodes:
			# Узел игрока и заражённый его тайным вирусом: видно их и соседей.
			if n.owner != p and n.virus[p] != 1 and not n.infected_by(p):
				continue
			k.observed[n.id] = 1
			for lid in n.links:
				k.observed[w.links[lid].other(n.id)] = 1
		# Агент наблюдает узел, где стоит, и его соседей.
		for a in w.agents:
			if a.owner != p or not a.hired or a.node < 0:
				continue
			k.observed[a.node] = 1
			for lid in w.nodes[a.node].links:
				k.observed[w.links[lid].other(a.node)] = 1
		for l in w.links:
			k.link_seen[l.id] = 1 if (k.observed[l.a] == 1 or k.observed[l.b] == 1) else 0
		for n in w.nodes:
			if k.observed[n.id] == 1:
				k.snaps[n.id] = NodeSnap.capture(n, p, w.tick)

## Агент-разведчик проехал через узел: игрок получает его снимок.
static func scout(w: World, player: int, node_id: int) -> void:
	if player < 0 or player >= w.players.size():
		return
	ensure(w)
	w.know[player].snaps[node_id] = NodeSnap.capture(w.nodes[node_id], player, w.tick)

## Дозор: снимок узла-источника и всех узлов в радиусе radius линков на момент вызова.
static func watch(w: World, player: int, node_id: int, radius: int) -> void:
	ensure(w)
	var k: Knowledge = w.know[player]
	var dist := PackedInt32Array()
	dist.resize(w.nodes.size())
	dist.fill(-1)
	dist[node_id] = 0
	var queue: Array[int] = [node_id]
	var head: int = 0
	while head < queue.size():
		var v: int = queue[head]
		head += 1
		k.snaps[v] = NodeSnap.capture(w.nodes[v], player, w.tick)
		if dist[v] >= radius:
			continue
		for lid in w.nodes[v].links:
			var u: int = w.links[lid].other(v)
			if dist[u] < 0:
				dist[u] = dist[v] + 1
				queue.append(u)

static func log_event(w: World, player: int, kind: int, node: int, link: int = -1, ptype: int = -1) -> void:
	if player < 0 or player >= w.players.size():
		return
	ensure(w)
	var k: Knowledge = w.know[player]
	k.events.append([w.tick, kind, node, link, ptype])
	if k.events.size() > EVENT_LIMIT:
		k.events.pop_front()

## Пакет враждебного типа прибыл на узел с работающим IDS: запись в лог со стороны линка.
static func on_hostile_packet(w: World, n: NodeState, idx: int, via_link: int) -> void:
	if n.owner < 0 or not n.soft_active(Defs.SoftType.IDS):
		return
	var attacker: int = w.pool.owner[idx]
	var t: int = w.pool.ptype[idx]
	if attacker < 0 or attacker == n.owner or not Defs.IDS_WATCHED.has(t):
		return
	if w.tick - n.ids_cool[attacker] < Defs.IDS_COOLDOWN_TICKS:
		return
	n.ids_cool[attacker] = w.tick
	log_event(w, n.owner, EventKind.IDS_ATTACK, n.id, via_link, t)

# --- API знаний: только его читают view и бот ---

static func _k(w: World, player: int) -> Knowledge:
	if player < 0 or player >= w.know.size():
		return null
	return w.know[player]

static func level(w: World, player: int, node_id: int) -> int:
	var k: Knowledge = _k(w, player)
	if k == null:
		return Level.SILHOUETTE
	if k.observed[node_id] == 1:
		return Level.OBSERVED
	if k.snaps[node_id] != null:
		return Level.SNAPSHOT
	return Level.SILHOUETTE

## Снимок (или текущее состояние для наблюдаемого). null — силуэт: о состоянии ничего не известно.
static func snap(w: World, player: int, node_id: int) -> NodeSnap:
	if level(w, player, node_id) == Level.SILHOUETTE:
		return null
	return _k(w, player).snaps[node_id]

static func owner_of(w: World, player: int, node_id: int) -> int:
	var s: NodeSnap = snap(w, player, node_id)
	return UNKNOWN_OWNER if s == null else s.owner

## Возраст данных в тиках: 0 для наблюдаемого, -1 — данных нет.
static func age(w: World, player: int, node_id: int) -> int:
	var s: NodeSnap = snap(w, player, node_id)
	if s == null:
		return -1
	if level(w, player, node_id) == Level.OBSERVED:
		return 0
	return w.tick - s.tick

## Видны ли пакеты и загрузка на линке: он рядом с наблюдаемым узлом.
static func link_visible(w: World, player: int, link_id: int) -> bool:
	var k: Knowledge = _k(w, player)
	return k != null and k.link_seen[link_id] == 1

## Виден ли чужой агент игроку: свой — всегда, чужой — только если IDS игрока смотрит на этот узел.
static func agent_visible(w: World, player: int, a: AgentState) -> bool:
	if a.owner == player:
		return true
	if a.node < 0:
		return false
	return Stealth.ids_covers(w, player, w.nodes[a.node])

## ПО узла, каким его видит игрок: чужой сниффер скрыт, пока IDS его не нашёл.
static func soft_visible(w: World, player: int, node_id: int) -> Array[int]:
	var out: Array[int] = []
	var n: NodeState = w.nodes[node_id]
	for t in n.soft:
		if t < 0:
			continue
		if t == Defs.SoftType.SNIFFER and n.owner != player and n.found[NodeState.hidden_slot(Defs.HiddenKind.SNIFFER, player)] != 1:
			continue
		out.append(t)
	return out

static func events_of(w: World, player: int) -> Array:
	var k: Knowledge = _k(w, player)
	return [] if k == null else k.events

## Число линков кратчайшего пути между узлами по топологии (она известна всем с начала матча); -1 — нет пути.
static func hops(w: World, a: int, b: int) -> int:
	if a == b:
		return 0
	var dist := PackedInt32Array()
	dist.resize(w.nodes.size())
	dist.fill(-1)
	dist[a] = 0
	var queue: Array[int] = [a]
	var head: int = 0
	while head < queue.size():
		var v: int = queue[head]
		head += 1
		for lid in w.nodes[v].links:
			var u: int = w.links[lid].other(v)
			if dist[u] < 0:
				dist[u] = dist[v] + 1
				if u == b:
					return dist[u]
				queue.append(u)
	return -1
