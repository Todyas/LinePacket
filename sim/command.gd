class_name Command
extends RefCounted
## Единственный способ изменить мир. Игрок, бот, сеть и реплей кладут команды в очередь.

enum Type { NOOP, START_FLOW, STOP_FLOW, SET_FLOW_RATE }

var type: int = Type.NOOP
var player: int = 0
var tick: int = 0          # тик, на котором команда применяется
var args: Array = []       # только целые числа

static func make(t: int, p: int, at_tick: int, a: Array = []) -> Command:
	var c := Command.new()
	c.type = t
	c.player = p
	c.tick = at_tick
	c.args = a.duplicate()
	return c

static func start_flow(p: int, at_tick: int, src: int, dst: int, ptype: int, rate: int) -> Command:
	return make(Type.START_FLOW, p, at_tick, [src, dst, ptype, rate])

static func stop_flow(p: int, at_tick: int, flow_id: int) -> Command:
	return make(Type.STOP_FLOW, p, at_tick, [flow_id])

static func set_flow_rate(p: int, at_tick: int, flow_id: int, rate: int) -> Command:
	return make(Type.SET_FLOW_RATE, p, at_tick, [flow_id, rate])

func to_array() -> Array:
	return [tick, type, player, args]

static func from_array(a: Array) -> Command:
	var c := Command.new()
	c.tick = int(a[0])
	c.type = int(a[1])
	c.player = int(a[2])
	var raw: Array = a[3]
	c.args = []
	for v in raw:
		c.args.append(int(v))
	return c
