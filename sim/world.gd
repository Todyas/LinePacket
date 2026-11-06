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
var next_flow_id: int = 1

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
	return h.result()
