extends TestCase
## Маршрутизаторы (S12): берутся агентом, правило закрывает транзит, маршруты игроков обходят известные закрытые.

## 0 ядро P0 — 1 маршрутизатор — 2 машина — 3 ядро P1.
func _line() -> World:
	return TestMaps.build({
		"name": "rline", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "router", 300, 0),
			TestMaps.node(2, "machine", 600, 0), TestMaps.node(3, "core", 900, 0, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3)],
	})

## Ромб: 0 ядро P0, 1 маршрутизатор (короткий путь), 2 машина (обход), 3 ядро P1.
func _diamond() -> World:
	return TestMaps.build({
		"name": "rdiamond", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 300, 0), TestMaps.node(1, "router", 300, 0),
			TestMaps.node(2, "machine", 300, 900), TestMaps.node(3, "core", 600, 300, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 3), TestMaps.link(0, 2), TestMaps.link(2, 3)],
	})

func _own_router(w: World, node: int, player: int) -> void:
	Economy.capture_node(w, w.nodes[node], player)

func test_router_is_a_node_type_in_maps() -> void:
	var w: World = _line()
	check_eq(w.nodes[1].type, Defs.NodeType.ROUTER)
	check_eq(w.nodes[1].owner, Defs.NEUTRAL)
	check_eq(Names.node_label(w.nodes[1]), "R1")
	check(Defs.NODE_DEFS[Defs.NodeType.ROUTER]["can_own"])

func test_router_has_no_roles_and_makes_no_data() -> void:
	var w: World = _line()
	_own_router(w, 1, 0)
	check(not Roles.can_have_role(w.nodes[1]))
	check(not Roles.apply_set_role(w, 0, [1, Defs.Role.WATCH, -1]), "у маршрутизатора ролей нет")
	w.run(400)
	check_eq(w.nodes[1].buffer, 0)
	check_eq(w.nodes[1].owner, 0, "KEEPALIVE держит контроль маршрутизатора")

func test_take_router_validation() -> void:
	var w: World = _line()
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.TAKE_ROUTER, 2))     # машина
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CAPTURE, 1))         # маршрутизатор — не CAPTURE
	w.step()
	check_eq(w.rejected_count, 2)
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.TAKE_ROUTER, 1))
	w.step()
	check_eq(Agents.agent_of(w, 0, 0).queue.size(), 1)
	_own_router(w, 1, 0)
	w.submit(Command.queue_task(0, w.tick, 1, Defs.TaskKind.TAKE_ROUTER, 1))
	w.step()
	check_eq(w.rejected_count, 3, "свой маршрутизатор брать не надо")

func test_agent_takes_neutral_router() -> void:
	var w: World = _line()
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.TAKE_ROUTER, 1))
	w.run(Defs.TICK_HZ * 25)
	check_eq(w.nodes[1].owner, 0, "агент взял ничей маршрутизатор")
	check_eq(w.players[0].bank >= 0, true)
	check_eq(Agents.task_params(Defs.TaskKind.TAKE_ROUTER, 0), [15 * Defs.TICK_HZ, 30])

func test_take_router_needs_bytes() -> void:
	var w: World = _line()
	w.players[0].bank = 0
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.TAKE_ROUTER, 1))
	w.run(Defs.TICK_HZ * 30)
	check_eq(w.nodes[1].owner, Defs.NEUTRAL, "без 30 байт задача не начинается")

func test_agent_takes_foreign_router_with_entry() -> void:
	var w: World = _line()
	_own_router(w, 1, 1)
	TestMaps.clear_defenders(w, 1)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.TAKE_ROUTER, 1))
	w.run(Defs.TICK_HZ * 25)
	check_eq(w.nodes[1].owner, 1, "без входа чужой маршрутизатор не взять")
	TestMaps.infect_fully(w, 1, 0)
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.TAKE_ROUTER, 1))
	w.run(Defs.TICK_HZ * 40)
	check_eq(w.nodes[1].owner, 0, "заражённый маршрутизатор взят агентом")

func test_router_rule_command() -> void:
	var w: World = _line()
	_own_router(w, 1, 0)
	w.submit(Command.set_router_rule(1, 0, 1, false))     # чужой
	w.submit(Command.set_router_rule(0, 0, 2, false))     # не маршрутизатор
	w.submit(Command.set_router_rule(0, 0, 1, false))
	w.step()
	check_eq(w.rejected_count, 2)
	check(not w.nodes[1].router_open)
	w.submit(Command.set_router_rule(0, w.tick, 1, true))
	w.step()
	check(w.nodes[1].router_open)

func _flood_from_p1(w: World, count: int, dst: int) -> void:
	for i in count:
		Network.inject(w, 3, dst, Defs.PacketType.FLOOD, 1, 0)

func test_closed_router_drops_foreign_transit_but_passes_own() -> void:
	var w: World = _line()
	_own_router(w, 1, 0)
	w.step()
	w.submit(Command.set_router_rule(0, w.tick, 1, false))
	w.step()
	_flood_from_p1(w, 5, 0)       # чужой транзит 3 → 0 через маршрутизатор 1
	for i in 5:
		Network.inject(w, 0, 2, Defs.PacketType.FLOOD, 0, 0)    # свой транзит 0 → 2 через тот же маршрутизатор
		w.run(6)                                                # вразбивку: бюджет CPU маршрутизатора не должен мешать
	w.run(120)
	check_eq(w.drops[World.DROP_CLOSED], 5, "чужие пакеты разбились о закрытый маршрутизатор")
	check_eq(w.delivered[Defs.PacketType.FLOOD], 5, "свои дошли")

func test_open_router_passes_everyone() -> void:
	var w: World = _line()
	_own_router(w, 1, 0)
	w.step()
	_flood_from_p1(w, 5, 0)
	w.run(120)
	check_eq(w.drops[World.DROP_CLOSED], 0)
	check_eq(w.delivered[Defs.PacketType.FLOOD], 5)

func test_closed_router_can_still_be_attacked() -> void:
	var w: World = _line()
	_own_router(w, 1, 0)
	w.step()
	w.submit(Command.set_router_rule(0, w.tick, 1, false))
	w.step()
	for i in 5:
		Network.inject(w, 2, 1, Defs.PacketType.FLOOD, 1, 0)   # адресат — сам маршрутизатор
	w.run(80)
	check_eq(w.drops[World.DROP_CLOSED], 0, "пакеты, адресованные самому маршрутизатору, проходят")
	check_eq(w.delivered[Defs.PacketType.FLOOD], 5)

func test_known_closed_router_is_bypassed_by_player_routes() -> void:
	var w: World = _diamond()
	_own_router(w, 1, 0)
	w.step()
	check_eq(Routing.path(w, 3, 0, 1), [3, 1, 0], "открытый маршрутизатор — короткий путь")
	w.submit(Command.set_router_rule(0, w.tick, 1, false))
	w.run(3)
	check_eq(Routing.path(w, 3, 0, 1), [3, 2, 0], "игрок видит закрытый маршрутизатор и идёт в обход")
	check_eq(Routing.path(w, 0, 3, 0), [0, 1, 3], "владелец через свой закрытый ходит")
	check_eq(Routing.path(w, 3, 0), [3, 1, 0], "таблица истины правила не знает")

func test_unknown_closed_router_swallows_packets() -> void:
	var w: World = TestMaps.build({
		"name": "rline5", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "router", 300, 0), TestMaps.node(2, "machine", 600, 0),
			TestMaps.node(3, "machine", 900, 0), TestMaps.node(4, "core", 1200, 0, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3), TestMaps.link(3, 4)],
	})
	_own_router(w, 1, 0)
	w.submit(Command.set_router_rule(0, 0, 1, false))
	w.run(3)
	check_eq(Knowledge.snap(w, 1, 1), null, "игрок 2 про маршрутизатор ничего не знает")
	check(Routing.path(w, 4, 0, 1).size() > 0, "по знаниям путь есть")
	for i in 4:
		Network.inject(w, 4, 0, Defs.PacketType.FLOOD, 1, 0)
	w.run(200)
	check_eq(w.drops[World.DROP_CLOSED], 4, "незнание: пакеты упёрлись в закрытый маршрутизатор")
	# Дозор даёт снимок: теперь игрок знает, что закрыт, и пути нет.
	Knowledge.watch(w, 1, 3, 3)
	w.run(Defs.ROUTE_RECALC_TICKS + 1)
	check_eq(Routing.path(w, 4, 0, 1).size(), 0, "после дозора путь через закрытый не строится")

## 0 ядро P0 — 1 маршрутизатор — 2 машина P0; 3 ядро P1 — 4 машина — 1. Из ядра P1 маршрутизатор 1 не виден (два хопа).
func _agent_map() -> World:
	var w: World = TestMaps.build({
		"name": "ragent", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "router", 300, 0),
			TestMaps.node(2, "machine", 600, 0), TestMaps.node(3, "core", 300, 600, 1),
			TestMaps.node(4, "machine", 300, 300),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(3, 4), TestMaps.link(4, 1)],
	})
	_own_router(w, 1, 0)
	Economy.capture_node(w, w.nodes[2], 0)
	w.nodes[2].access_mask |= 2         # у P1 есть ключ от машины 2
	return w

func test_closed_router_stops_foreign_agent() -> void:
	var w: World = _agent_map()
	w.submit(Command.set_router_rule(0, 0, 1, false))
	w.step()
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.MOVE, 2))
	w.run(240)
	check_eq(Agents.agent_of(w, 1, 0).mode, AgentState.Mode.LOST, "закрытый маршрутизатор остановил агента")
	check(w.drops[World.DROP_CLOSED] >= 1)
	var open_w: World = _agent_map()
	open_w.step()
	open_w.submit(Command.queue_task(1, open_w.tick, 0, Defs.TaskKind.MOVE, 2))
	open_w.run(240)
	check_eq(Agents.agent_of(open_w, 1, 0).node, 2, "через открытый агент доехал")

func test_known_closed_router_keeps_agent_home() -> void:
	var w: World = _agent_map()
	w.submit(Command.set_router_rule(0, 0, 1, false))
	w.step()
	Economy.capture_node(w, w.nodes[4], 1)          # теперь маршрутизатор — сосед своей машины: игрок видит его правило
	w.run(Defs.ROUTE_RECALC_TICKS + 2)
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.MOVE, 2))
	w.run(120)
	check_eq(Agents.agent_of(w, 1, 0).node, 3, "путь известен как закрытый: агент не выходит")
	check_eq(w.drops[World.DROP_CLOSED], 0)

func test_routers_are_deterministic() -> void:
	var a: World = _line()
	var b: World = _line()
	for w in [a, b]:
		w.players[0].bank = 100
		w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.TAKE_ROUTER, 1))
		w.submit(Command.set_router_rule(0, 700, 1, false))
	a.run(1500)
	b.run(1500)
	check_eq(a.state_hash(), b.state_hash())
	check(not a.nodes[1].router_open)
