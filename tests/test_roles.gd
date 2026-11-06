extends TestCase

func test_set_role_validation() -> void:
	var w: World = TestMaps.chain()
	check(Roles.apply_set_role(w, 0, [0, Defs.Role.WATCH, -1]), "ядро может быть в дозоре")
	check(not Roles.apply_set_role(w, 1, [0, Defs.Role.WATCH, -1]), "чужую машину не назначить")
	check(not Roles.apply_set_role(w, 0, [0, 99, -1]), "неизвестная роль")
	check(not Roles.apply_set_role(w, 0, [0, Defs.Role.PRESSURE, 0]), "цель — сам исполнитель")
	check(not Roles.apply_set_role(w, 0, [0, Defs.Role.PRESSURE, 1]), "давление на нейтрал не нужно")

func test_combat_role_refused_beyond_three_hops() -> void:
	var w: World = _line5()
	check(not Roles.apply_set_role(w, 0, [0, Defs.Role.PRESSURE, 4]), "4 хопа — слишком далеко")
	Economy.capture_node(w, w.nodes[1], 0)
	check(Roles.apply_set_role(w, 0, [1, Defs.Role.PRESSURE, 4]), "3 хопа — можно")

func _line5() -> World:
	return TestMaps.build({
		"name": "line", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 200, 0), TestMaps.node(2, "machine", 400, 0),
			TestMaps.node(3, "machine", 600, 0), TestMaps.node(4, "core", 800, 0, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3), TestMaps.link(3, 4)],
	})

func test_reconfiguration_blocks_packets_and_data() -> void:
	var w: World = TestMaps.pair(200)
	w.submit(Command.set_role(0, 0, 0, Defs.Role.PRESSURE, 1))
	w.run(Defs.ROLE_RECONF_TICKS - 1)
	check_eq(w.pool.alive_count + w.delivered[Defs.PacketType.FLOOD], 0, "перенастройка: пакетов нет")
	check(w.nodes[0].reconf > 0)
	w.run(40)
	check(w.pool.alive_count + w.delivered[Defs.PacketType.FLOOD] > 0)

func test_combat_role_gives_no_data_but_watch_gives_half() -> void:
	var work: World = TestMaps.eco_fan(1, 0)
	var combat: World = TestMaps.eco_fan(1, 0)
	var watch: World = TestMaps.eco_fan(1, 0)
	# машина 4 — своя; её роль задаём напрямую, перенастройка уже прошла
	for w in [work, combat, watch]:
		Economy.capture_node(w, w.nodes[4], 0)
	watch.nodes[4].role = Defs.Role.WATCH
	combat.nodes[4].role = Defs.Role.PRESSURE
	combat.nodes[4].role_target = 3
	work.run(400)
	combat.run(400)
	watch.run(400)
	var w_prod: int = work.nodes[4].auto_sent
	var c_prod: int = combat.nodes[4].auto_sent
	var d_prod: int = watch.nodes[4].auto_sent
	check(w_prod > 0, "работа даёт DATA")
	check_eq(c_prod, 0, "боевая роль DATA не шлёт")
	check(d_prod > 0 and d_prod < w_prod, "дозор даёт часть дохода: %d из %d" % [d_prod, w_prod])

func test_several_machines_add_up_on_one_target() -> void:
	var one: World = TestMaps.siege()
	var two: World = TestMaps.siege()
	TestMaps.engage(one, 1, 3, 2, Defs.PacketType.FLOOD)
	TestMaps.engage(two, 1, 3, 2, Defs.PacketType.FLOOD)
	TestMaps.engage(two, 1, 4, 2, Defs.PacketType.FLOOD)
	one.run(200)
	two.run(200)
	var a: int = one.delivered[Defs.PacketType.FLOOD] + one.pool.alive_count + one.total_drops()
	var b: int = two.delivered[Defs.PacketType.FLOOD] + two.pool.alive_count + two.total_drops()
	# total_drops включает и чужой трафик (DATA, KEEPALIVE), поэтому сравниваем с допуском.
	check(a >= 78 and a <= 90, "ядро: 8 пакетов/с × 10 с, получено %d" % a)
	check(b - a >= 55 and b - a <= 65, "добавленная машина даёт ещё 6 пакетов/с × 10 с, получено %d" % (b - a))

func test_relay_doubles_combat_power() -> void:
	var w: World = TestMaps.siege()
	check_eq(Roles.power(w.nodes[4]), Defs.ROLE_POWER[Defs.NodeType.MACHINE])
	TestMaps.boost(w, 4)
	check_eq(Roles.power(w.nodes[4]), int(Defs.ROLE_POWER[Defs.NodeType.MACHINE]) * Defs.RELAY_COMBAT_PERCENT / 100)

func test_role_reverts_when_target_becomes_useless() -> void:
	var w: World = TestMaps.siege()
	w.players[1].bank = 10000
	TestMaps.engage(w, 1, 3, 2, Defs.PacketType.PAYLOAD)
	TestMaps.engage(w, 1, 4, 2, Defs.PacketType.PAYLOAD)
	var guard: int = 0
	while not w.nodes[2].infected_by(1) and guard < 1600:
		w.step()
		guard += 1
	check(w.nodes[2].infected_by(1))
	w.run(2)
	check_eq(w.nodes[3].role, Defs.Role.WORK, "цель заражена — ядро возвращается к работе")
	check_eq(w.nodes[4].role, Defs.Role.WORK)

func test_watch_role_updates_snapshots_in_radius() -> void:
	var w: World = _line5()
	Economy.capture_node(w, w.nodes[1], 0)
	w.submit(Command.set_role(0, 0, 1, Defs.Role.WATCH))
	w.run(Defs.ROLE_RECONF_TICKS + Defs.WATCH_INTERVAL_TICKS + 5)
	check(Knowledge.snap(w, 0, 3) != null, "узел в двух хопах снят")
	check(Knowledge.snap(w, 0, 4) == null, "ядро в трёх хопах за радиусом")

func test_roles_counts() -> void:
	var w: World = TestMaps.siege()
	check_eq(Roles.counts(w, 1), [2, 0])
	TestMaps.engage(w, 1, 3, 2, Defs.PacketType.FLOOD)
	check_eq(Roles.counts(w, 1), [1, 1])

func test_roles_deterministic() -> void:
	var a: World = Scenarios.build_siege(11)
	var b: World = Scenarios.build_siege(11)
	a.run(1500)
	b.run(1500)
	check_eq(a.state_hash(), b.state_hash())
