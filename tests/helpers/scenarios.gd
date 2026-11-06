class_name Scenarios
extends RefCounted
## Сценарии для тестов детерминизма (тестовый код, не часть игры).

## Партия на карте Дуэли: сид + список команд на заданное число тиков.
static func build_basic(seed_value: int) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	var w: World = res["world"]
	w.submit(Command.set_role(0, 10, 0, Defs.Role.CAPTURE, 2))
	w.submit(Command.set_role(1, 25, 10, Defs.Role.CAPTURE, 12))
	w.submit(Command.set_role(0, 400, 0, Defs.Role.WATCH))
	w.submit(Command.set_role(0, 700, 0, Defs.Role.WORK))
	w.submit(Command.make(Command.Type.NOOP, 0, 500))
	return w

## Партия Дуэли с расширением: роли «Захват» у обоих ядер — проверяет хеш экономики.
static func build_economy(seed_value: int) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	var w: World = res["world"]
	w.submit(Command.set_role(0, 5, 0, Defs.Role.CAPTURE, 2))
	w.submit(Command.set_role(1, 8, 10, Defs.Role.CAPTURE, 12))
	w.submit(Command.set_role(0, 400, 0, Defs.Role.CAPTURE, 3))
	w.submit(Command.set_role(1, 500, 10, Defs.Role.CAPTURE, 14))
	return w

## Агенты в работе: INIT-расширение, смена ключей и установка ПО.
static func build_agents(seed_value: int) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	var w: World = res["world"]
	w.players[0].bank = 150
	w.submit(Command.set_role(0, 5, 0, Defs.Role.CAPTURE, 2))
	w.submit(Command.set_role(0, 400, 0, Defs.Role.CAPTURE, 3))
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.INSTALL_SOFT, 1, Defs.SoftType.FIREWALL))
	w.submit(Command.queue_task(0, 0, 1, Defs.TaskKind.SET_KEYS, 1))
	w.submit(Command.queue_task(0, 300, 2, Defs.TaskKind.INSTALL_SOFT, 2, Defs.SoftType.FIREWALL))
	w.submit(Command.queue_task(0, 400, 1, Defs.TaskKind.CHANGE_PASSWORD, 3))
	w.submit(Command.set_role(1, 100, 10, Defs.Role.CAPTURE, 12))
	w.submit(Command.queue_task(1, 120, 0, Defs.TaskKind.SET_KEYS, 10))
	return w

## Осада: захват, заражение, давление, агенты по обе стороны — для проверки детерминизма атаки.
static func build_siege(seed_value: int) -> World:
	var w: World = TestMaps.siege(seed_value)
	w.players[0].bank = 200
	w.players[1].bank = 300
	w.submit(Command.set_role(1, 5, 3, Defs.Role.CAPTURE, 2))
	w.submit(Command.set_role(1, 100, 4, Defs.Role.INFECT, 2))
	w.submit(Command.set_role(1, 200, 3, Defs.Role.PRESSURE, 2))
	w.submit(Command.queue_task(0, 10, 0, Defs.TaskKind.INSTALL_SOFT, 2, Defs.SoftType.ANTIVIRUS))
	w.submit(Command.queue_task(0, 300, 1, Defs.TaskKind.SET_KEYS, 2))
	w.submit(Command.queue_task(1, 400, 0, Defs.TaskKind.STEAL_KEY, 2))
	return w

## Скрытность: скрытый вирус, IDS у защитника, бэкдор, активация и сниффер на транзите.
static func build_stealth(seed_value: int) -> World:
	var w: World = TestMaps.siege(seed_value)
	w.players[0].bank = 300
	w.players[1].bank = 400
	w.nodes[1].install_soft(Defs.SoftType.SNIFFER)
	w.submit(Command.queue_task(0, 5, 0, Defs.TaskKind.INSTALL_SOFT, 2, Defs.SoftType.IDS))
	w.submit(Command.set_role(1, 10, 3, Defs.Role.INFECT_HIDDEN, 2))
	w.submit(Command.set_role(1, 20, 4, Defs.Role.WATCH))
	w.submit(Command.queue_task(1, 300, 0, Defs.TaskKind.STEAL_KEY, 2))
	w.submit(Command.queue_task(1, 320, 1, Defs.TaskKind.BACKDOOR, 2))
	w.submit(Command.activate(1, 1200, 2, Defs.ActivateMode.DISABLE_SOFT))
	return w
