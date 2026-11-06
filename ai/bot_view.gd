class_name BotView
extends RefCounted
## Единственное окно бота в мир: открытая топология, карта знаний своего игрока и собственное состояние
## (банк, агенты, роли своих узлов). Состояние чужих узлов отсюда не достать иначе, чем снимком.

var _w: World
var me: int

func _init(w: World, player: int) -> void:
	_w = w
	me = player

# --- Открытое всем ---

func tick() -> int:
	return _w.tick

func player_count() -> int:
	return _w.players.size()

func node_count() -> int:
	return _w.nodes.size()

func node_type(n: int) -> int:
	return _w.nodes[n].type

func neighbors(n: int) -> Array[int]:
	var out: Array[int] = []
	for lid in _w.nodes[n].links:
		out.append(_w.links[lid].other(n))
	return out

func hops(a: int, b: int) -> int:
	return Knowledge.hops(_w, a, b)

func match_over() -> bool:
	return _w.winner >= 0

## Ядра карты (позиции открыты всем): чужое ядро ищется как ядро, не равное своему.
func core_nodes() -> Array[int]:
	var out: Array[int] = []
	for n in _w.nodes:
		if n.type == Defs.NodeType.CORE:
			out.append(n.id)
	return out

func my_core() -> int:
	return _w.players[me].core_node

# --- Знания игрока ---

func level(n: int) -> int:
	return Knowledge.level(_w, me, n)

## Владелец по знаниям: Knowledge.UNKNOWN_OWNER, если неизвестен.
func owner_of(n: int) -> int:
	return Knowledge.owner_of(_w, me, n)

func snap(n: int) -> NodeSnap:
	return Knowledge.snap(_w, me, n)

## Возраст данных в тиках: -1 — данных нет.
func age(n: int) -> int:
	return Knowledge.age(_w, me, n)

func events() -> Array:
	return Knowledge.events_of(_w, me)

## Свои узлы: те, что игрок видит прямо сейчас и знает как свои.
func my_nodes() -> Array[int]:
	var out: Array[int] = []
	for n in _w.nodes:
		if Knowledge.level(_w, me, n.id) == Knowledge.Level.OBSERVED and Knowledge.owner_of(_w, me, n.id) == me:
			out.append(n.id)
	return out

## Подробности о своём узле (для чужих — пустой словарь).
func own(n: int) -> Dictionary:
	if Knowledge.level(_w, me, n) != Knowledge.Level.OBSERVED or Knowledge.owner_of(_w, me, n) != me:
		return {}
	var s: NodeState = _w.nodes[n]
	return {
		"control": s.control, "cpu_pct": s.cpu_load_pct(), "soft": Array(s.soft), "free_slots": s.free_slots(),
		"access_mode": s.access_mode, "buffer": s.buffer, "down": s.down, "infect": s.max_infect(),
		"prev_owner": s.prev_owner, "has_found_threat": Stealth.has_found_threat(s),
		"role": s.role, "role_target": s.role_target, "reconf": s.reconf,
	}

# --- Своё состояние ---

func bank() -> int:
	return _w.players[me].bank

func income() -> int:
	return _w.players[me].income_per_s()

func my_agents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in Defs.AGENTS_PER_PLAYER:
		var a: AgentState = Agents.agent_of(_w, me, i)
		out.append({"idx": i, "node": a.node, "mode": a.mode, "queue": a.queue.duplicate(true)})
	return out

## Единственный способ влиять на мир.
func submit(cmd: Command) -> void:
	_w.submit(cmd)
