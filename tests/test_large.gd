extends TestCase
## Большая Дуэль, разведка агентом и наём агентов (S14).

const LARGE: String = "res://maps/duel_large.json"

func _large(seed_value: int = 1) -> World:
	return MapLoader.load_file(LARGE, seed_value)["world"]

func test_large_map_loads_with_expected_shape() -> void:
	var w: World = _large()
	check(w != null)
	check(w.nodes.size() >= 40 and w.nodes.size() <= 50, "узлов: %d" % w.nodes.size())
	var gw: int = 0
	var cores: int = 0
	var routers: int = 0
	for n in w.nodes:
		match n.type:
			Defs.NodeType.GATEWAY:
				gw += 1
			Defs.NodeType.CORE:
				cores += 1
			Defs.NodeType.ROUTER:
				routers += 1
	check_eq(gw, 6)
	check_eq(cores, 2)
	check(routers >= 3)
	check_eq(w.players.size(), 2)

func test_large_map_is_mirror_symmetric() -> void:
	var w: World = _large()
	var half: int = (w.nodes.size() - 5) / 2
	for i in half:
		var a: NodeState = w.nodes[i]
		var b: NodeState = w.nodes[i + half]
		check_eq(a.type, b.type, "тип узла %d" % i)
		check_eq(a.y, b.y)
		check_eq(a.x + b.x, 3000)
		check_eq(a.links.size(), b.links.size(), "степень узла %d" % i)
	check_eq(w.nodes[0].owner, 0)
	check_eq(w.nodes[half].owner, 1)
	# Путь от ядер до центрального шлюза одной длины.
	var d0: int = Knowledge.hops(w, 0, w.nodes.size() - 5)
	var d1: int = Knowledge.hops(w, half, w.nodes.size() - 5)
	check_eq(d0, d1, "ядра равноудалены от центрального шлюза")

func test_large_map_leaves_free_ports_for_building() -> void:
	var w: World = _large()
	var machines_with_room: int = 0
	var machines: int = 0
	for n in w.nodes:
		if n.type == Defs.NodeType.MACHINE:
			machines += 1
			if Builds.free_ports(w, n.id) > 0:
				machines_with_room += 1
	check(machines_with_room * 10 >= machines * 8, "у большинства машин есть свободный порт: %d из %d" % [machines_with_room, machines])
	check(Builds.free_ports(w, 0) > 0, "у ядра есть порты")

func test_large_map_has_several_trunks_between_halves() -> void:
	var w: World = _large()
	var half: int = (w.nodes.size() - 5) / 2
	var cross: int = 0
	for l in w.links:
		var left_a: bool = l.a < half
		var left_b: bool = l.b < half
		var right_a: bool = l.a >= half and l.a < 2 * half
		var right_b: bool = l.b >= half and l.b < 2 * half
		var center_a: bool = l.a >= 2 * half
		var center_b: bool = l.b >= 2 * half
		if (left_a and center_b) or (left_b and center_a):
			cross += 1
		if (right_a and center_b) or (right_b and center_a):
			cross += 1
	check(cross >= 6, "магистралей к центру с обеих сторон: %d" % cross)

func test_agent_in_transit_scouts_nodes() -> void:
	var nodes: Array = [TestMaps.node(0, "core", 0, 0, 0)]
	for i in range(1, 5):
		nodes.append(TestMaps.node(i, "machine", i * 300, 0))
	nodes.append(TestMaps.node(5, "machine", 1500, 0, 0))
	nodes.append(TestMaps.node(6, "core", 1800, 0, 1))
	var links: Array = []
	for i in 6:
		links.append(TestMaps.link(i, i + 1))
	var w: World = TestMaps.build({"name": "scout", "players": 2, "nodes": nodes, "links": links})
	w.step()
	check_eq(Knowledge.level(w, 0, 2), Knowledge.Level.SILHOUETTE)
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.SILHOUETTE)
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.MOVE, 5))
	w.run(200)
	check_eq(Knowledge.level(w, 0, 2), Knowledge.Level.SNAPSHOT, "узел на пути агента получил снимок")
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.SNAPSHOT)
	check_eq(Knowledge.owner_of(w, 0, 2), Defs.NEUTRAL)
	check_eq(Knowledge.level(w, 1, 2), Knowledge.Level.SILHOUETTE, "противник ничего не узнал")
	check_eq(Agents.agent_of(w, 0, 0).node, 5)

func test_standing_agent_observes_node_and_neighbours() -> void:
	var w: World = TestMaps.build({
		"name": "stand", "players": 2,
		"nodes": [TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 300, 0, 0),
			TestMaps.node(2, "machine", 600, 0), TestMaps.node(3, "machine", 900, 0), TestMaps.node(4, "core", 1200, 0, 1)],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3), TestMaps.link(3, 4)],
	})
	w.step()
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.SILHOUETTE)
	Economy.capture_node(w, w.nodes[3], 0)
	w.nodes[3].owner = Defs.NEUTRAL      # вернуть нейтралом: хотим проверить именно наблюдение агентом
	Economy.release_node(w, w.nodes[3])
	var a: AgentState = Agents.agent_of(w, 0, 0)
	a.node = 2
	w.step()
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.OBSERVED, "сосед узла с агентом наблюдается")
	check_eq(Knowledge.level(w, 0, 2), Knowledge.Level.OBSERVED)
	a.node = -1
	a.mode = AgentState.Mode.LOST
	a.lost_timer = 100000
	w.step()
	check_eq(Knowledge.level(w, 0, 3), Knowledge.Level.SNAPSHOT, "агент ушёл: остался снимок")

func test_hire_agent_costs_and_timing() -> void:
	var w: World = _large()
	w.players[0].bank = 2000
	check_eq(Agents.hired_count(w, 0), 3)
	check_eq(Agents.hire_cost(w, 0), 300)
	w.submit(Command.hire_agent(0, 0))
	w.step()
	check(w.players[0].bank <= 1700)
	check(w.players[0].hire_left > 0)
	check(not Agents.agent_of(w, 0, 3).hired, "пока наём идёт, агента нет")
	w.submit(Command.hire_agent(0, w.tick))
	w.step()
	check_eq(w.rejected_count, 1, "второй наём одновременно отвергается")
	w.run(Defs.HIRE_SECONDS * Defs.TICK_HZ + 2)
	var a: AgentState = Agents.agent_of(w, 0, 3)
	check(a.hired)
	check_eq(a.node, w.players[0].core_node)
	check_eq(Agents.hire_cost(w, 0), 600)
	w.submit(Command.hire_agent(0, w.tick))
	w.run(Defs.HIRE_SECONDS * Defs.TICK_HZ + 2)
	check_eq(Agents.hired_count(w, 0), 5)
	check_eq(Agents.hire_cost(w, 0), -1)
	var before: int = w.rejected_count
	w.submit(Command.hire_agent(0, w.tick))
	w.step()
	check_eq(w.rejected_count, before + 1, "шестого агента нет")

func test_hire_needs_bytes_and_new_agent_works() -> void:
	var w: World = _large()
	w.players[0].bank = 299
	w.submit(Command.hire_agent(0, 0))
	w.step()
	check_eq(w.rejected_count, 1)
	w.players[0].bank = 500
	w.submit(Command.queue_task(0, w.tick, 3, Defs.TaskKind.CHANGE_PASSWORD, 0))
	w.step()
	check_eq(w.rejected_count, 2, "ненанятому агенту задач не ставят")
	w.submit(Command.hire_agent(0, w.tick))
	w.run(Defs.HIRE_SECONDS * Defs.TICK_HZ + 2)
	w.submit(Command.queue_task(0, w.tick, 3, Defs.TaskKind.CHANGE_PASSWORD, 0))
	w.run(5)
	check_eq(Agents.agent_of(w, 0, 3).mode, AgentState.Mode.WORK)

func test_large_map_is_deterministic_with_bots_and_hires() -> void:
	var hashes: Array[int] = []
	for i in 2:
		var w: World = _large(4)
		var bots: Array[Bot] = []
		for p in 2:
			bots.append(Bot.new(BotView.new(w, p), 4))
		for t in Defs.TICK_HZ * 150:
			if t % 100 == 0:
				for p in w.players:
					p.bank += 40
			for b in bots:
				b.act()
			w.step()
		hashes.append(w.state_hash())
	check_eq(hashes[0], hashes[1])

func test_bot_hires_agents_when_rich() -> void:
	var w: World = _large(2)
	var bot := Bot.new(BotView.new(w, 0), 2)
	for t in Defs.TICK_HZ * 540:
		if t % 100 == 0:
			w.players[0].bank = maxi(w.players[0].bank, 800)
		bot.act()
		w.step()
	check(Agents.hired_count(w, 0) >= 4, "бот нанял агента: %d" % Agents.hired_count(w, 0))
	check(w.rejected_count <= 3, "команды бота почти не отвергаются: %d" % w.rejected_count)
