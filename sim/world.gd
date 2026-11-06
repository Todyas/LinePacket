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
var flows: Array[FlowState] = []
var agents: Array[AgentState] = []          # по Defs.AGENTS_PER_PLAYER на игрока, подряд
var next_flow_id: int = 1
var pool: PacketPool = PacketPool.new()
var routes: Array[PackedInt32Array] = []   # routes[dst][node] = id линка следующего шага или -1
var route_dist: Array[PackedInt64Array] = []   # route_dist[dst][node] = цена пути node→dst
var routes_dirty: bool = true

## Потери по причинам и доставки по типам пакетов (накопительно).
const DROP_QUEUE: int = 0     # очередь выходного порта переполнена
const DROP_CPU: int = 1       # у узла не хватило CPU
const DROP_NOROUTE: int = 2   # нет маршрута
const DROP_GATEWAY: int = 3   # потолок шлюза или чужой шлюз
const DROP_FIREWALL: int = 4  # файрвол сверх лимита
var drops: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
var delivered: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
## Недавние потери для отрисовки: [тик, id линка, направление]. В хеш не входит.
var recent_drops: Array = []

var _pending: Dictionary = {}               # tick -> Array[Command]
var applied_log: Array[Command] = []        # применённые команды по порядку (для реплея)
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
		Command.Type.START_FLOW:
			ok = _apply_start_flow(c)
		Command.Type.STOP_FLOW:
			ok = _apply_stop_flow(c)
		Command.Type.SET_FLOW_RATE:
			ok = _apply_set_flow_rate(c)
		Command.Type.QUEUE_TASK:
			ok = _apply_queue_task(c)
		Command.Type.CLEAR_QUEUE:
			ok = _apply_clear_queue(c)
		_:
			ok = false
	if ok:
		applied_log.append(c)
	else:
		rejected_count += 1

func _apply_start_flow(c: Command) -> bool:
	if c.args.size() != 4:
		return false
	var src: int = c.args[0]
	var dst: int = c.args[1]
	var ptype: int = c.args[2]
	var rate: int = c.args[3]
	if src < 0 or src >= nodes.size() or dst < 0 or dst >= nodes.size() or src == dst:
		return false
	if c.player < 0 or c.player >= players.size():
		return false
	if nodes[src].owner != c.player:
		return false  # поток можно пустить только со своего узла
	if not Defs.PLAYER_FLOW_TYPES.has(ptype):
		return false
	if rate < Defs.FLOW_MIN_RATE or rate > Defs.FLOW_MAX_RATE:
		return false
	var f := FlowState.new()
	f.id = next_flow_id
	next_flow_id += 1
	f.owner = c.player
	f.src = src
	f.dst = dst
	f.ptype = ptype
	f.rate = rate
	flows.append(f)
	return true

func _apply_stop_flow(c: Command) -> bool:
	if c.args.size() != 1:
		return false
	var fid: int = c.args[0]
	for i in flows.size():
		if flows[i].id == fid:
			if flows[i].owner != c.player:
				return false
			flows.remove_at(i)
			return true
	return false

func _apply_set_flow_rate(c: Command) -> bool:
	if c.args.size() != 2:
		return false
	var f: FlowState = get_flow(c.args[0])
	if f == null or f.owner != c.player:
		return false
	var rate: int = c.args[1]
	if rate < Defs.FLOW_MIN_RATE or rate > Defs.FLOW_MAX_RATE:
		return false
	f.rate = rate
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

func total_drops() -> int:
	return drops[DROP_QUEUE] + drops[DROP_CPU] + drops[DROP_NOROUTE] + drops[DROP_GATEWAY] + drops[DROP_FIREWALL]

func get_flow(fid: int) -> FlowState:
	for f in flows:
		if f.id == fid:
			return f
	return null

## Хеш всего состояния. Порядок обхода фиксирован: по id.
func state_hash() -> int:
	var h := Hasher.new()
	h.add(tick)
	h.add(rng.state)
	h.add(next_flow_id)
	h.add(nodes.size())
	for n in nodes:
		n.hash_into(h)
	h.add(links.size())
	for l in links:
		l.hash_into(h)
	h.add(players.size())
	for p in players:
		p.hash_into(h)
	h.add(flows.size())
	for f in flows:
		f.hash_into(h)
	h.add(agents.size())
	for a in agents:
		a.hash_into(h)
	pool.hash_into(h)
	h.add_array(Array(drops))
	h.add_array(Array(delivered))
	return h.result()
