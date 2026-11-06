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
