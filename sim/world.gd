class_name World
extends RefCounted
## Состояние матча. Меняется только через submit() команд и step().

var map_name: String = ""
var seed_value: int = 0
var tick: int = 0
var rng: Rng
var nodes: Array[NodeState] = []
var links: Array[LinkState] = []
var players: Array[PlayerState] = []
var agents: Array[AgentState] = []          # по Defs.AGENTS_PER_PLAYER на игрока, подряд
var builds: Array = []                       # идущие стройки, см. Builds
var pool: PacketPool = PacketPool.new()
var routes: Array[PackedInt32Array] = []   # routes[dst][node] = id линка следующего шага или -1
var route_dist: Array[PackedInt64Array] = []   # route_dist[dst][node] = цена пути node→dst
var routes_dirty: bool = true
## Маршруты игроков: строятся по его знаниям (загрузку видно только у наблюдаемых линков). proutes[игрок][цель][узел].
var proutes: Array = []
var know: Array[Knowledge] = []             # карты знаний игроков

## Потери по причинам и доставки по типам пакетов (накопительно).
const DROP_QUEUE: int = 0     # очередь выходного порта переполнена
const DROP_CPU: int = 1       # у узла не хватило CPU
const DROP_NOROUTE: int = 2   # нет маршрута
const DROP_GATEWAY: int = 3   # потолок шлюза или чужой шлюз
const DROP_FIREWALL: int = 4  # файрвол сверх лимита
const DROP_CLOSED: int = 5    # закрытый чужой маршрутизатор не пустил транзит
var drops: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0])
var delivered: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
## Недавние потери для отрисовки: [тик, id линка, направление]. В хеш не входит.
var recent_drops: Array = []

var _pending: Dictionary = {}               # tick -> Array[Command]
var applied_log: Array[Command] = []        # применённые команды по порядку (для реплея)
var winner: int = -1                        # игрок, захвативший ядро; -1 — матч идёт
var finished_tick: int = -1
var delivered_sniffed: int = 0              # DATA, украденных снифферами (для проверок)
var rejected_count: int = 0                 # отвергнутые команды (невалидные)

func _init(seed_val: int = 1) -> void:
	seed_value = seed_val
	rng = Rng.new(seed_val)

## Поставить команду в очередь. Прошедший тик заменяется текущим.
func submit(cmd: Command) -> void:
	var c: Command = Command.from_array(cmd.to_array())
	if c.tick < tick:
		c.tick = tick
	if not _pending.has(c.tick):
		_pending[c.tick] = []
	(_pending[c.tick] as Array).append(c)

func step() -> void:
	if winner >= 0:
		return   # матч окончен, мир заморожен
	if _pending.has(tick):
		var list: Array = _pending[tick]
		for c in list:
			_apply(c as Command)
		_pending.erase(tick)
	Network.step(self)
	tick += 1

func run(ticks: int) -> void:
	for i in ticks:
		step()

func _apply(c: Command) -> void:
	var ok: bool = true
	match c.type:
		Command.Type.NOOP:
			pass
		Command.Type.SET_ROLE:
			ok = Roles.apply_set_role(self, c.player, c.args)
		Command.Type.QUEUE_TASK:
			ok = _apply_queue_task(c)
		Command.Type.CLEAR_QUEUE:
			ok = _apply_clear_queue(c)
		Command.Type.ACTIVATE:
			ok = Stealth.apply_activate(self, c.player, c.args)
		Command.Type.SET_ROUTER_RULE:
			ok = _apply_router_rule(c)
		Command.Type.BUILD:
			ok = Builds.apply(self, c.player, c.args)
		_:
			ok = false
	if ok:
		applied_log.append(c)
	else:
		rejected_count += 1

## Новый узел (стройка): id следующий по порядку, знания игроков растут вместе с картой.
func add_node(type: int, x: int, y: int, owner: int) -> NodeState:
	var n := NodeState.new()
	n.id = nodes.size()
	n.type = type
	n.x = x
	n.y = y
	n.owner = owner
	n.setup_cpu()
	n.produce_acc = (n.id * 7) % Defs.TICK_HZ
	n.ka_acc = (n.id * 11) % Defs.TICK_HZ
	if owner >= 0:
		n.control = Defs.CAPTURE_START_CONTROL
		n.reset_access()
	nodes.append(n)
	Knowledge.grow(self)
	routes_dirty = true
	return n

## Новый линк между существующими узлами: длина, задержка и ёмкость по виду линка.
func add_link(a: int, b: int, kind: int) -> LinkState:
	var l := LinkState.new()
	l.id = links.size()
	l.a = a
	l.b = b
	l.kind = kind
	var ldef: Dictionary = Defs.LINK_DEFS[kind]
	var na: NodeState = nodes[a]
	var nb: NodeState = nodes[b]
	var dx: int = na.x - nb.x
	var dy: int = na.y - nb.y
	l.length = IntMath.isqrt(dx * dx + dy * dy)
	l.latency = maxi(Defs.LINK_MIN_LATENCY, IntMath.ceil_div(l.length, int(ldef["speed"])))
	l.capacity = int(ldef["capacity"])
	l.queue_limit = int(ldef["queue"])
	l.credit[0] = l.credit_cap()
	l.credit[1] = l.credit_cap()
	links.append(l)
	na.links.append(l.id)
	nb.links.append(l.id)
	Knowledge.grow(self)
	routes_dirty = true
	return l

func _apply_router_rule(c: Command) -> bool:
	if c.args.size() != 2 or c.player < 0 or c.player >= players.size():
		return false
	var nid: int = c.args[0]
	if nid < 0 or nid >= nodes.size() or (c.args[1] != 0 and c.args[1] != 1):
		return false
	var n: NodeState = nodes[nid]
	if n.type != Defs.NodeType.ROUTER or n.owner != c.player:
		return false
	var open: bool = c.args[1] == 1
	if n.router_open != open:
		n.router_open = open
		routes_dirty = true    # игроки, знающие правило, перестроят маршруты
	return true

func _apply_queue_task(c: Command) -> bool:
	if c.args.size() != 4 or c.player < 0 or c.player >= players.size():
		return false
	var idx: int = c.args[0]
	if idx < 0 or idx >= Defs.AGENTS_PER_PLAYER:
		return false
	var a: AgentState = Agents.agent_of(self, c.player, idx)
	if a.queue.size() >= Defs.AGENT_QUEUE_MAX:
		return false
	if not Agents.validate_task(self, c.player, c.args[1], c.args[2], c.args[3]):
		return false
	a.queue.append([c.args[1], c.args[2], c.args[3]])
	return true

func _apply_clear_queue(c: Command) -> bool:
	if c.args.size() != 1 or c.player < 0 or c.player >= players.size():
		return false
	var idx: int = c.args[0]
	if idx < 0 or idx >= Defs.AGENTS_PER_PLAYER:
		return false
	var a: AgentState = Agents.agent_of(self, c.player, idx)
	a.queue.clear()
	if a.mode == AgentState.Mode.WORK:
		a.mode = AgentState.Mode.IDLE   # оплаченная работа пропадает
		a.work_left = 0
		a.work_total = 0
	return true

## Таблица маршрутов для пакетов владельца: по его знаниям; без игрока — по истине.
func route_table(owner: int) -> Array[PackedInt32Array]:
	if owner >= 0 and owner < proutes.size():
		return proutes[owner]
	return routes

func total_drops() -> int:
	return drops[DROP_QUEUE] + drops[DROP_CPU] + drops[DROP_NOROUTE] + drops[DROP_GATEWAY] + drops[DROP_FIREWALL] + drops[DROP_CLOSED]

## Хеш всего состояния. Порядок обхода фиксирован: по id.
func state_hash() -> int:
	var h := Hasher.new()
	h.add(tick)
	h.add(rng.state)
	h.add(winner)
	h.add(finished_tick)
	h.add(delivered_sniffed)
	h.add(nodes.size())
	for n in nodes:
		n.hash_into(h)
	h.add(links.size())
	for l in links:
		l.hash_into(h)
	h.add(builds.size())
	for b in builds:
		h.add_array(b)
	h.add(players.size())
	for p in players:
		p.hash_into(h)
	h.add(agents.size())
	for a in agents:
		a.hash_into(h)
	h.add(know.size())
	for k in know:
		k.hash_into(h)
	pool.hash_into(h)
	h.add_array(Array(drops))
	h.add_array(Array(delivered))
	return h.result()
