class_name Command
extends RefCounted
## Единственный способ изменить мир. Игрок, бот, сеть и реплей кладут команды в очередь.

enum Type { NOOP, SET_ROLE, QUEUE_TASK, CLEAR_QUEUE, ACTIVATE, SET_ROUTER_RULE, BUILD, HIRE_AGENT }

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

## Назначить машине роль из Defs.Role; target — узел-цель боевой роли (для остальных -1).
static func set_role(p: int, at_tick: int, node: int, role: int, target: int = -1) -> Command:
	return make(Type.SET_ROLE, p, at_tick, [node, role, target])

## Поставить задачу в очередь агента. Перед выполнением агент сам доедет до узла.
static func queue_task(p: int, at_tick: int, agent: int, kind: int, node: int, arg: int = 0) -> Command:
	return make(Type.QUEUE_TASK, p, at_tick, [agent, kind, node, arg])

static func clear_queue(p: int, at_tick: int, agent: int) -> Command:
	return make(Type.CLEAR_QUEUE, p, at_tick, [agent])

func to_array() -> Array:
	return [tick, type, player, args]

## Активировать свой тайный вирус на узле: режим из Defs.ActivateMode.
static func activate(p: int, at_tick: int, node: int, mode: int) -> Command:
	return make(Type.ACTIVATE, p, at_tick, [node, mode])

## Правило своего маршрутизатора: пускать (true) или не пускать чужой транзит.
static func set_router_rule(p: int, at_tick: int, node: int, open: bool) -> Command:
	return make(Type.SET_ROUTER_RULE, p, at_tick, [node, 1 if open else 0])

## Стройка: kind из Defs.BuildKind; a — узел (для линка один конец), b — второй конец линка или -1.
static func build(p: int, at_tick: int, kind: int, a: int, b: int = -1) -> Command:
	return make(Type.BUILD, p, at_tick, [kind, a, b])

## Нанять следующего агента на ядре.
static func hire_agent(p: int, at_tick: int) -> Command:
	return make(Type.HIRE_AGENT, p, at_tick, [])

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
