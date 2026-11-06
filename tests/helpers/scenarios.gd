class_name Scenarios
extends RefCounted
## Сценарии для тестов детерминизма (тестовый код, не часть игры).

## Партия на карте Дуэли: сид + список команд на заданное число тиков.
static func build_basic(seed_value: int) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	var w: World = res["world"]
	w.submit(Command.start_flow(0, 10, 0, 22, Defs.PacketType.FLOOD, 6))
	w.submit(Command.start_flow(1, 25, 10, 20, Defs.PacketType.FLOOD, 4))
	w.submit(Command.start_flow(0, 40, 1, 17, Defs.PacketType.FLOOD, 12))
	w.submit(Command.stop_flow(0, 300, 1))
	w.submit(Command.make(Command.Type.NOOP, 0, 500))
	return w

## Партия Дуэли с расширением P0: INIT на соседей, затем потоки — проверяет хеш экономики.
static func build_economy(seed_value: int) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	var w: World = res["world"]
	w.submit(Command.start_flow(0, 5, 0, 2, Defs.PacketType.INIT, 10))
	w.submit(Command.start_flow(0, 5, 0, 3, Defs.PacketType.INIT, 10))
	w.submit(Command.start_flow(1, 8, 10, 12, Defs.PacketType.INIT, 14))
	w.submit(Command.start_flow(0, 400, 1, 4, Defs.PacketType.INIT, 20))
	w.submit(Command.start_flow(1, 500, 10, 14, Defs.PacketType.FLOOD, 9))
	return w

## Агенты в работе: INIT-расширение, смена ключей и установка ПО.
static func build_agents(seed_value: int) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	var w: World = res["world"]
	w.players[0].bank = 150
	w.submit(Command.start_flow(0, 5, 0, 2, Defs.PacketType.INIT, 20))
	w.submit(Command.start_flow(0, 5, 1, 3, Defs.PacketType.INIT, 20))
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.INSTALL_SOFT, 1, Defs.SoftType.FIREWALL))
	w.submit(Command.queue_task(0, 0, 1, Defs.TaskKind.SET_KEYS, 1))
	w.submit(Command.queue_task(0, 300, 2, Defs.TaskKind.INSTALL_SOFT, 2, Defs.SoftType.FIREWALL))
	w.submit(Command.queue_task(0, 400, 1, Defs.TaskKind.CHANGE_PASSWORD, 3))
	w.submit(Command.start_flow(1, 100, 10, 12, Defs.PacketType.INIT, 20))
	w.submit(Command.queue_task(1, 120, 0, Defs.TaskKind.SET_KEYS, 10))
	return w

## Осада: INIT, PAYLOAD, флуд, агенты по обе стороны — для проверки детерминизма атаки.
static func build_siege(seed_value: int) -> World:
	var w: World = TestMaps.siege(seed_value)
	w.players[0].bank = 200
	w.players[1].bank = 300
	w.submit(Command.start_flow(1, 5, 3, 2, Defs.PacketType.INIT, 20))
	w.submit(Command.start_flow(1, 100, 4, 2, Defs.PacketType.PAYLOAD, 14))
	w.submit(Command.start_flow(1, 200, 3, 2, Defs.PacketType.FLOOD, 12))
	w.submit(Command.queue_task(0, 10, 0, Defs.TaskKind.INSTALL_SOFT, 2, Defs.SoftType.ANTIVIRUS))
	w.submit(Command.queue_task(0, 300, 1, Defs.TaskKind.SET_KEYS, 2))
	w.submit(Command.queue_task(1, 400, 0, Defs.TaskKind.STEAL_KEY, 2))
	return w
