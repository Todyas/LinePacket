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

## Метка топологии: меняется, когда в мире появляются новые узлы или линки (кэши дистанций бота устаревают).
func topology_stamp() -> int:
	return _w.nodes.size() * 100003 + _w.links.size()

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
		"role": s.role, "role_target": s.role_target, "reconf": s.reconf, "router_open": s.router_open,
		"cpu_level": s.cpu_level, "extra_slots": s.extra_slots,
	}

# --- Своё состояние ---

## Свободные порты своего узла (за вычетом стройки).
func free_ports(n: int) -> int:
	return Builds.free_ports(_w, n)

func pending_builds() -> int:
	return Builds.pending_of(_w, me)

## Пустая строка — стройку можно начать; иначе причина отказа.
func build_refusal(kind: int, a: int, b: int = -1) -> String:
	return Builds.refusal(_w, me, kind, a, b)

func build_cost(kind: int, a: int, b: int = -1) -> int:
	return Builds.cost_for(_w, kind, a, b)

func bank() -> int:
	return _w.players[me].bank

func income() -> int:
	return _w.players[me].income_per_s()

func my_agents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in Defs.AGENTS_PER_PLAYER:
		var a: AgentState = Agents.agent_of(_w, me, i)
		if not a.hired:
			continue
		out.append({"idx": i, "node": a.node, "mode": a.mode, "queue": a.queue.duplicate(true), "progress": a.progress_permille()})
	return out

## Нанято агентов, идёт ли наём и цена следующего (-1 — больше нанимать некого).
func hired_count() -> int:
	return Agents.hired_count(_w, me)

func hiring() -> bool:
	return _w.players[me].hire_left > 0

func hire_cost() -> int:
	return Agents.hire_cost(_w, me)

## Единственный способ влиять на мир.
func submit(cmd: Command) -> void:
	_w.submit(cmd)
