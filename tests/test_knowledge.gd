extends TestCase

func test_start_knowledge_is_silhouettes_plus_observed_neighbourhood() -> void:
	var w: World = TestMaps.scout()
	check_eq(Knowledge.level(w, 0, 0), Knowledge.Level.OBSERVED)
	check_eq(Knowledge.level(w, 0, 1), Knowledge.Level.OBSERVED, "сосед своего узла наблюдается")
	check_eq(Knowledge.level(w, 0, 4), Knowledge.Level.OBSERVED)
	check_eq(Knowledge.level(w, 0, 2), Knowledge.Level.SILHOUETTE, "дальше только силуэт")
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.SILHOUETTE)

func test_enemy_machine_state_hidden_without_observation_or_scan() -> void:
	var w: World = TestMaps.scout()
	check_eq(Knowledge.owner_of(w, 0, 3), Knowledge.UNKNOWN_OWNER)
	check(Knowledge.snap(w, 0, 3) == null, "про дальний узел нет снимка")
	check_eq(Knowledge.age(w, 0, 3), -1)
	check_eq(Knowledge.owner_of(w, 0, 1), Defs.NEUTRAL, "наблюдаемый сосед виден")
	check_eq(Knowledge.owner_of(w, 1, 3), 1)

func test_scan_gives_snapshot_with_tick_of_arrival() -> void:
	var w: World = TestMaps.scout()
	w.nodes[3].install_soft(Defs.SoftType.FIREWALL)
	w.submit(Command.start_flow(0, 0, 0, 3, Defs.PacketType.SCAN, Defs.SCAN_FLOW_RATE))
	check(Knowledge.hops(w, 0, 3) == 3)
	w.run(120)
	var s: NodeSnap = Knowledge.snap(w, 0, 3)
	check(s != null, "скан должен дать снимок")
	check_eq(s.owner, 1)
	check(s.has_soft(Defs.SoftType.FIREWALL), "в снимке видно ПО")
	check(s.tick > 0 and s.tick < 120, "снимок помечен тиком прибытия: %d" % s.tick)
	check_eq(w.flows.size(), 0, "поток скана заканчивается после первого прибытия")
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.SNAPSHOT)
	check_eq(Knowledge.level(w, 0, 2), Knowledge.Level.SNAPSHOT, "соседи цели тоже снимаются")

func test_scan_range_limited_to_three_hops() -> void:
	var w: World = TestMaps.build({
		"name": "line", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 200, 0), TestMaps.node(2, "machine", 400, 0),
			TestMaps.node(3, "machine", 600, 0), TestMaps.node(4, "core", 800, 0, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3), TestMaps.link(3, 4)],
	})
	w.submit(Command.start_flow(0, 0, 0, 4, Defs.PacketType.SCAN, 4))
	w.step()
	check_eq(w.flows.size(), 0, "4 хопа — слишком далеко")
	check_eq(w.rejected_count, 1)
	w.submit(Command.start_flow(0, w.tick, 0, 3, Defs.PacketType.SCAN, 4))
	w.step()
	check_eq(w.flows.size(), 1, "3 хопа — можно")

func test_snapshot_stays_old_until_new_scan() -> void:
	var w: World = TestMaps.scout()
	w.submit(Command.start_flow(0, 0, 0, 3, Defs.PacketType.SCAN, 4))
	w.run(120)
	var first_tick: int = Knowledge.snap(w, 0, 3).tick
	check(not Knowledge.snap(w, 0, 3).has_soft(Defs.SoftType.ANTIVIRUS))
	w.nodes[3].install_soft(Defs.SoftType.ANTIVIRUS)
	w.run(200)
	var s: NodeSnap = Knowledge.snap(w, 0, 3)
	check_eq(s.tick, first_tick, "снимок не меняется без нового скана")
	check(not s.has_soft(Defs.SoftType.ANTIVIRUS), "изменение на узле не просочилось в снимок")
	check_eq(Knowledge.age(w, 0, 3), w.tick - first_tick)
	w.submit(Command.start_flow(0, w.tick, 0, 3, Defs.PacketType.SCAN, 4))
	w.run(120)
	check(Knowledge.snap(w, 0, 3).has_soft(Defs.SoftType.ANTIVIRUS), "новый скан обновляет снимок")
	check(Knowledge.snap(w, 0, 3).tick > first_tick)

func test_lost_observation_keeps_last_state_as_aging_snapshot() -> void:
	var w: World = TestMaps.scout()
	w.step()
	var seen_tick: int = Knowledge.snap(w, 0, 1).tick
	w.nodes[0].owner = Defs.NEUTRAL      # P0 потерял ядро: соседей он больше не видит
	w.run(100)
	check_eq(Knowledge.level(w, 0, 1), Knowledge.Level.SNAPSHOT)
	check(Knowledge.age(w, 0, 1) >= 90, "возраст растёт: %d" % Knowledge.age(w, 0, 1))

func test_ids_logs_attack_with_neighbour_link() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].install_soft(Defs.SoftType.IDS)
	w.submit(Command.start_flow(1, 0, 3, 2, Defs.PacketType.FLOOD, 5))
	w.run(100)
	var ev: Array = Knowledge.events_of(w, 0)
	var found: Array = []
	for e in ev:
		if e[1] == Knowledge.EventKind.IDS_ATTACK:
			found.append(e)
	check(not found.is_empty(), "IDS должен записать атаку")
	var e0: Array = found[0]
	check_eq(e0[2], 2, "записано на узле с IDS")
	check_eq(e0[4], Defs.PacketType.FLOOD)
	var l: LinkState = w.links[int(e0[3])]
	check(l.a == 3 or l.b == 3, "записан линк со стороны источника: %d-%d" % [l.a, l.b])
	check(found.size() <= 3, "повторы сжимаются кулдауном: %d" % found.size())
	check_eq(Knowledge.events_of(w, 1).size(), 0, "атакующему в лог ничего не пишут")

func test_ids_notices_scans_and_needs_to_be_installed() -> void:
	var w: World = TestMaps.siege()
	w.submit(Command.start_flow(1, 0, 3, 2, Defs.PacketType.SCAN, 4))
	w.run(100)
	check_eq(Knowledge.events_of(w, 0).size(), 0, "без IDS скана не заметить")
	var w2: World = TestMaps.siege()
	w2.nodes[2].install_soft(Defs.SoftType.IDS)
	w2.submit(Command.start_flow(1, 0, 3, 2, Defs.PacketType.SCAN, 4))
	w2.run(100)
	var kinds: Array = []
	for e in Knowledge.events_of(w2, 0):
		kinds.append(e[4])
	check(kinds.has(Defs.PacketType.SCAN), "IDS видит чужой скан")

func test_route_is_built_from_player_knowledge_not_truth() -> void:
	var w: World = TestMaps.scout()
	w.step()
	check_eq(Routing.path(w, 0, 3, 0), [0, 1, 2, 3])
	# Забиваем направление 2→3: линк у чужого ядра, P0 его не наблюдает.
	for i in 60:
		Network.inject(w, 2, 3, Defs.PacketType.FLOOD, 1, 0)
	check(w.links[2].load_pct(w.links[2].dir_from(2)) >= 90, "линк забит")
	check(not Knowledge.link_visible(w, 0, 2), "P0 загрузки этого линка не видит")
	Routing.compute(w)
	check_eq(Routing.path(w, 0, 3), [0, 4, 5, 3], "по истине путь обходит пробку")
	check_eq(Routing.path(w, 0, 3, 0), [0, 1, 2, 3], "игрок про пробку не знает и идёт через неё")
	# Если бы линк был виден (рядом свой узел), маршрут обошёл бы пробку.
	w.nodes[1].owner = 0
	Knowledge.update(w)
	check(Knowledge.link_visible(w, 0, 2), "теперь рядом свой узел")
	Routing.compute(w)
	check_eq(Routing.path(w, 0, 3, 0), [0, 4, 5, 3], "увидев пробку, игрок её обходит")

func test_events_for_capture_and_loss() -> void:
	var w: World = TestMaps.siege()
	w.step()
	Economy.takeover(w, w.nodes[2], 1)
	var lost: bool = false
	for e in Knowledge.events_of(w, 0):
		if e[1] == Knowledge.EventKind.NODE_LOST and e[2] == 2:
			lost = true
	check(lost, "потеря машины попадает в ленту")
	var got: bool = false
	for e in Knowledge.events_of(w, 1):
		if e[1] == Knowledge.EventKind.NODE_CAPTURED and e[2] == 2:
			got = true
	check(got)

func test_knowledge_is_part_of_state_hash() -> void:
	var a: World = TestMaps.scout()
	var b: World = TestMaps.scout()
	a.run(5)
	b.run(5)
	check_eq(a.state_hash(), b.state_hash())
	b.submit(Command.start_flow(0, b.tick, 0, 3, Defs.PacketType.SCAN, 4))
	a.run(150)
	b.run(150)
	check(a.state_hash() != b.state_hash(), "скан меняет хеш состояния")
