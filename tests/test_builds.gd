extends TestCase
## Строительство (S13): линки, новые машины, апгрейды; отказы, время, цена, видимость, детерминизм.

## 0 ядро P0 — 1 машина P0 — 2 машина P0; 3 нейтральный маршрутизатор рядом с 1; 4 ядро P1 за маршрутизатором; 5 нейтральная машина.
func _map() -> World:
	var w: World = TestMaps.build({
		"name": "bmap", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 300, 0, 0),
			TestMaps.node(2, "machine", 600, 0, 0), TestMaps.node(3, "router", 300, 300),
			TestMaps.node(4, "core", 300, 900, 1), TestMaps.node(5, "machine", 0, 300),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(1, 3), TestMaps.link(3, 4), TestMaps.link(0, 5)],
	})
	w.players[0].bank = 1000
	w.players[1].bank = 1000
	return w

func _build(w: World, kind: int, a: int, b: int = -1, player: int = 0) -> void:
	w.submit(Command.build(player, w.tick, kind, a, b))
	w.step()

func test_cable_costs_time_and_connects() -> void:
	var w: World = _map()
	var cost: int = Builds.cost_for(w, Defs.BuildKind.CABLE, 0, 2)
	check_eq(cost, 40 + 600 / 10)
	var before: int = w.players[0].bank
	_build(w, Defs.BuildKind.CABLE, 0, 2)
	check_eq(w.rejected_count, 0)
	check(w.players[0].bank <= before - cost, "байты списаны при старте")
	check_eq(w.builds.size(), 1)
	check_eq(w.links.size(), 5)
	w.run(Defs.TICK_HZ * 19)
	check_eq(w.links.size(), 5, "до конца стройки линка нет")
	w.run(Defs.TICK_HZ * 2)
	check_eq(w.links.size(), 6)
	check(w.builds.is_empty())
	var l: LinkState = w.links[5]
	check_eq(l.kind, Defs.LinkKind.CABLE)
	check_eq(l.length, 600)
	check_eq(w.nodes[0].links.size(), 3)
	check_eq(Routing.path(w, 0, 2, 0).size(), 2, "маршрут идёт по новому линку")

func test_optic_is_wider_than_cable() -> void:
	var w: World = _map()
	_build(w, Defs.BuildKind.OPTIC, 0, 2)
	w.run(Defs.TICK_HZ * 31)
	check_eq(w.links.size(), 6)
	check_eq(w.links[5].kind, Defs.LinkKind.OPTIC)
	check(w.links[5].capacity > w.links[0].capacity)
	check_eq(Builds.cost_for(w, Defs.BuildKind.OPTIC, 0, 2), 100 + 60)

func test_link_refusals() -> void:
	var w: World = _map()
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 0, 1) != "", "уже связаны")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 0, 0) != "", "петля")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 0, 5) != "", "уже связаны (0-5)")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 2, 5) != "", "нейтральная машина — не конец линка")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 4, 5) != "", "оба конца не ваши")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 2, 3) == "", "свободный маршрутизатор — можно")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 2, 4) != "", "чужое ядро — нельзя")
	w.players[0].bank = 10
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 0, 2) != "", "без байт")
	w.players[0].bank = 1000
	_build(w, Defs.BuildKind.CABLE, 0, 2)
	check(Builds.refusal(w, 0, Defs.BuildKind.OPTIC, 2, 0) != "", "та же пара уже строится")
	w.submit(Command.build(0, w.tick, Defs.BuildKind.CABLE, 0, 2))
	w.step()
	check_eq(w.rejected_count, 1, "команда с отказом отвергается")

func test_link_length_limit() -> void:
	var w: World = TestMaps.build({
		"name": "far", "players": 2,
		"nodes": [TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 400, 0, 0),
			TestMaps.node(2, "machine", 1500, 0, 0), TestMaps.node(3, "core", 1500, 400, 1)],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3)],
	})
	w.players[0].bank = 1000
	Economy.capture_node(w, w.nodes[2], 0)
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 0, 2) != "", "дальше BUILD_MAX_LINK_LENGTH")

func test_ports_are_limited_and_reserved() -> void:
	var w: World = _map()
	# У машины 4 порта: у 1 уже три линка (0, 2, 3).
	check_eq(Builds.free_ports(w, 1), 1)
	_build(w, Defs.BuildKind.MACHINE, 1)
	check_eq(Builds.free_ports(w, 1), 0, "порт занят стройкой")
	check(Builds.refusal(w, 0, Defs.BuildKind.CABLE, 1, 5) != "", "портов нет")
	check(Builds.refusal(w, 0, Defs.BuildKind.MACHINE, 1) != "", "портов нет и для машины")

func test_parallel_limit() -> void:
	var w: World = _map()
	_build(w, Defs.BuildKind.CPU, 0)
	_build(w, Defs.BuildKind.CPU, 1)
	_build(w, Defs.BuildKind.SLOT, 0)
	check_eq(w.builds.size(), 3)
	check(Builds.refusal(w, 0, Defs.BuildKind.SLOT, 1) != "", "четвёртая стройка не идёт")
	check_eq(Builds.pending_of(w, 1), 0)

func test_new_machine_appears_linked_and_owned() -> void:
	var w: World = _map()
	var spot: Variant = Builds.node_spot(w, 2)
	check(spot != null)
	_build(w, Defs.BuildKind.MACHINE, 2)
	check_eq(w.nodes.size(), 6)
	w.run(Defs.TICK_HZ * 31)
	check_eq(w.nodes.size(), 7)
	var n: NodeState = w.nodes[6]
	check_eq(n.owner, 0)
	check_eq(n.type, Defs.NodeType.MACHINE)
	check_eq([n.x, n.y], spot)
	check_eq(n.links.size(), 1)
	check_eq(w.links[n.links[0]].other(6), 2)
	check_eq(w.know[0].snaps.size(), 7, "знания выросли вместе с картой")
	check_eq(w.know[1].observed.size(), 7)
	w.run(Defs.TICK_HZ * 40)
	check_eq(w.nodes[6].owner, 0, "KEEPALIVE держит новую машину")
	check(w.nodes[6].auto_sent > 0 or w.nodes[6].buffer > 0, "новая машина работает")
	check_eq(Knowledge.level(w, 0, 6), Knowledge.Level.OBSERVED)

func test_new_machine_spots_do_not_overlap() -> void:
	var w: World = _map()
	_build(w, Defs.BuildKind.MACHINE, 2)
	var first: Array = w.builds[0].slice(Builds.F_X, Builds.F_Y + 1)
	check_eq(Builds.refusal(w, 0, Defs.BuildKind.MACHINE, 2), "", "у узла 2 ещё есть порты")
	var second: Variant = Builds.node_spot(w, 2)
	check(second != null)
	var dx: int = int(second[0]) - int(first[0])
	var dy: int = int(second[1]) - int(first[1])
	check(dx * dx + dy * dy >= Defs.BUILD_MIN_SEPARATION * Defs.BUILD_MIN_SEPARATION, "места не накладываются")

func test_cpu_upgrade_halves_then_raises() -> void:
	var w: World = _map()
	var n: NodeState = w.nodes[1]
	var base: int = n.cpu_base
	var per_s: int = n.cpu_per_s
	var power: int = Roles.power(n)
	_build(w, Defs.BuildKind.CPU, 1)
	check_eq(n.upgrading, 1)
	check(n.cpu_per_s <= per_s / 2 + 1, "во время апгрейда вполсилы")
	check_eq(Roles.power(n), power / 2)
	w.run(Defs.TICK_HZ * 31)
	check_eq(n.upgrading, 0)
	check_eq(n.cpu_level, 1)
	check_eq(n.cpu_base, base + Defs.CPU_UPGRADE_BONUS)
	check_eq(n.cpu_per_s, per_s + Defs.CPU_UPGRADE_BONUS)
	check_eq(Roles.power(n), power + Defs.CPU_UPGRADE_POWER)
	_build(w, Defs.BuildKind.CPU, 1)
	w.run(Defs.TICK_HZ * 31)
	check_eq(n.cpu_level, 2)
	check(Builds.refusal(w, 0, Defs.BuildKind.CPU, 1) != "", "предел апгрейдов")
	check(Builds.refusal(w, 0, Defs.BuildKind.CPU, 3) != "", "маршрутизатору и чужому не нужно")

func test_extra_slot() -> void:
	var w: World = _map()
	var n: NodeState = w.nodes[1]
	check_eq(n.free_slots(), 2)
	_build(w, Defs.BuildKind.SLOT, 1)
	check_eq(n.free_slots(), 2, "пока строится, слота нет")
	w.run(Defs.TICK_HZ * 31)
	check_eq(n.free_slots(), 3)
	check(n.install_soft(Defs.SoftType.FIREWALL))
	check(n.install_soft(Defs.SoftType.IDS))
	check(n.install_soft(Defs.SoftType.ANTIVIRUS), "третье ПО встало в доп. слот")
	check(Builds.refusal(w, 0, Defs.BuildKind.SLOT, 1) != "", "доп. слот только один")

func test_upgrade_is_lost_with_the_node() -> void:
	var w: World = _map()
	_build(w, Defs.BuildKind.CPU, 2)
	Economy.release_node(w, w.nodes[2])
	w.run(Defs.TICK_HZ * 31)
	check_eq(w.nodes[2].cpu_level, 0, "узел потерян — апгрейд пропал")
	check_eq(w.nodes[2].upgrading, 0)

func test_enemy_sees_build_only_when_observing() -> void:
	var w: World = _map()
	_build(w, Defs.BuildKind.CPU, 1)
	check_eq(Builds.visible_to(w, 0).size(), 1)
	check_eq(Builds.visible_to(w, 1).size(), 0, "противник узла 1 не видит")
	w.nodes[3].owner = 1       # маршрутизатор рядом с узлом 1 теперь у противника
	w.step()
	check_eq(Builds.visible_to(w, 1).size(), 1, "сосед наблюдает узел и видит стройку")

func test_build_changes_routes_for_packets() -> void:
	var w: World = _map()
	check_eq(Routing.path(w, 0, 2, 0).size(), 3)
	_build(w, Defs.BuildKind.CABLE, 0, 2)
	w.run(Defs.TICK_HZ * 21)
	Network.inject(w, 0, 2, Defs.PacketType.FLOOD, 0, 0)
	w.run(40)
	check_eq(w.delivered[Defs.PacketType.FLOOD], 1)
	check_eq(Routing.path(w, 0, 2, 0).size(), 2)

func test_builds_are_deterministic_and_replayable() -> void:
	var hashes: Array[int] = []
	for i in 2:
		var w: World = _map()
		w.submit(Command.build(0, 5, Defs.BuildKind.MACHINE, 2))
		w.submit(Command.build(0, 7, Defs.BuildKind.CABLE, 0, 2))
		w.submit(Command.build(1, 9, Defs.BuildKind.CPU, 4))
		w.run(Defs.TICK_HZ * 40)
		hashes.append(w.state_hash())
		check_eq(w.nodes.size(), 7)
		check_eq(w.links.size(), 7)
	check_eq(hashes[0], hashes[1])

func test_bot_builds_machine_cpu_and_cable() -> void:
	var w: World = MapLoader.load_file("res://maps/duel.json", 5)["world"]
	var bot := Bot.new(BotView.new(w, 0), 5)
	var start_nodes: int = w.nodes.size()
	var start_links: int = w.links.size()
	var built_cpu: int = 0
	for i in Defs.TICK_HZ * 300:
		if i % 100 == 0:
			w.players[0].bank = maxi(w.players[0].bank, 300)
		bot.act()
		w.step()
	for n in w.nodes:
		built_cpu += n.cpu_level
	check(w.nodes.size() > start_nodes or w.links.size() > start_links, "бот что-то построил: узлов %d→%d, линков %d→%d" % [start_nodes, w.nodes.size(), start_links, w.links.size()])
	check(built_cpu > 0 or w.nodes.size() > start_nodes, "бот вкладывается в железо")
	check(w.rejected_count <= 3, "команды бота почти не отвергаются: %d" % w.rejected_count)
