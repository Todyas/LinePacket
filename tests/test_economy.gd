extends TestCase

func test_data_credited_only_via_own_gateway() -> void:
	var w: World = TestMaps.eco_fan(0, 0)
	w.run(400)
	check(w.players[0].bank > 0, "своя машина через свой шлюз должна приносить байты")
	check_eq(w.players[0].bank, w.delivered[Defs.PacketType.DATA] - w.drops[World.DROP_GATEWAY], "каждый доехавший DATA = байт")
	# Чужой (нейтральный) шлюз — дохода нет, байты копятся в буфере.
	var w2: World = TestMaps.eco_fan(0, -1)
	w2.run(400)
	check_eq(w2.players[0].bank, 0, "нейтральный шлюз не должен давать доход")
	check(w2.nodes[0].buffer > 0, "без шлюза байты копятся в буфере ядра")

func test_gateway_ceiling_cuts_income() -> void:
	var w: World = TestMaps.eco_fan(8, 0)       # 8 машин + ядро = 18 DATA/с при потолке 10
	w.run(600)
	var income: int = w.players[0].income_per_s()
	check(income >= Defs.GATEWAY_CAP_PER_S - 1 and income <= Defs.GATEWAY_CAP_PER_S + 1, "доход %d при потолке %d" % [income, Defs.GATEWAY_CAP_PER_S])
	check(w.drops[World.DROP_GATEWAY] > 0, "лишние DATA должны теряться на шлюзе")
	# Без перегруза доход равен суммарной выработке.
	var w2: World = TestMaps.eco_fan(2, 0)      # 2 машины + ядро = 6 DATA/с
	w2.run(600)
	var inc2: int = w2.players[0].income_per_s()
	check(inc2 >= 5 and inc2 <= 7, "доход %d, ожидалось около 6" % inc2)

func test_buffer_fills_without_route_and_unloads_when_route_appears() -> void:
	var w: World = TestMaps.eco_fan(1, -1)
	var m: NodeState = w.nodes[4]
	w.run(60 * 20)
	check_eq(m.buffer, int(Defs.BUFFER_LIMIT[Defs.NodeType.MACHINE]), "буфер должен упереться в лимит")
	check_eq(w.players[0].bank, 0)
	# Шлюз становится своим: маршрут появился.
	Economy.capture_node(w, w.nodes[1], 0)
	w.run(40 * 20)
	check(m.buffer < 5, "буфер должен выгрузиться, осталось %d" % m.buffer)
	check(w.players[0].bank >= int(Defs.BUFFER_LIMIT[Defs.NodeType.MACHINE]), "накопленные байты должны дойти до банка: %d" % w.players[0].bank)

func test_buffer_has_limit() -> void:
	var w: World = TestMaps.eco_fan(1, -1)
	w.run(2000)
	check(w.nodes[4].buffer <= int(Defs.BUFFER_LIMIT[Defs.NodeType.MACHINE]))
	check(w.nodes[0].buffer <= int(Defs.BUFFER_LIMIT[Defs.NodeType.CORE]))

func test_init_captures_neutral_for_defs_count() -> void:
	var w: World = TestMaps.chain()
	var target: NodeState = w.nodes[2]
	check_eq(target.owner, Defs.NEUTRAL)
	TestMaps.engage(w, 0, 1, 2, Defs.PacketType.INIT)
	var needed: int = int(Defs.INIT_NEEDED[Defs.NodeType.MACHINE])
	var guard: int = 0
	while target.owner == Defs.NEUTRAL and guard < 600:
		w.step()
		guard += 1
	check_eq(target.owner, 0, "узел не захвачен")
	check_eq(w.delivered[Defs.PacketType.INIT], needed, "нейтрал должен сдаться ровно за число INIT из defs")
	check(target.control <= Defs.CAPTURE_START_CONTROL and target.control >= Defs.CAPTURE_START_CONTROL - 1000, "контроль после захвата: %d" % target.control)
	check_eq(w.players[0].captures, 1)
	check_eq(w.nodes[1].role, Defs.Role.WORK, "роль «Захват» после взятия цели возвращается к работе")

func test_denser_init_flow_wins() -> void:
	var w: World = TestMaps.star()           # узел 2 — нейтрал, к нему подключены оба ядра
	TestMaps.boost(w, 0)                      # ядро с ретранслятором шлёт INIT вдвое плотнее
	TestMaps.engage(w, 0, 0, 2, Defs.PacketType.INIT)
	TestMaps.engage(w, 1, 1, 2, Defs.PacketType.INIT)
	w.run(600)
	check_eq(w.nodes[2].owner, 0, "узел должен достаться более плотному потоку")
	check_eq(w.nodes[2].capture[1], 0)

func test_capture_meter_decays_without_init() -> void:
	var w: World = TestMaps.chain()
	var target: NodeState = w.nodes[2]
	target.capture[0] = 20
	w.run(20 * 7 + 1)
	check_eq(target.capture[0], 0, "шкала захвата должна тихо спадать")

func test_gateway_captured_with_its_own_count() -> void:
	var w: World = TestMaps.eco_fan(0, -1)
	TestMaps.engage(w, 0, 0, 1, Defs.PacketType.INIT)
	var guard: int = 0
	while w.nodes[1].owner == Defs.NEUTRAL and guard < 800:
		w.step()
		guard += 1
	check_eq(w.nodes[1].owner, 0)
	check_eq(w.delivered[Defs.PacketType.INIT], int(Defs.INIT_NEEDED[Defs.NodeType.GATEWAY]))

func test_keepalive_holds_control() -> void:
	var w: World = TestMaps.chain()
	w.run(2000)
	check_eq(w.nodes[1].owner, 0, "связанная машина должна остаться своей")
	check(w.nodes[1].control >= 50000, "контроль держится на KEEPALIVE: %d" % w.nodes[1].control)
	check_eq(w.nodes[0].control, Defs.CONTROL_MAX, "ядро не распадается")

func test_cut_machine_decays_to_neutral() -> void:
	var w: World = TestMaps.chain()
	w.run(100)
	# Режем линк 0–1: KEEPALIVE больше не доходит (очередь порта не принимает).
	w.links[0].queue_limit = 0
	w.run(180)
	check(w.nodes[1].owner == 0 and w.nodes[1].control < 100000 - 10000, "контроль должен падать: %d" % w.nodes[1].control)
	w.run(300)     # суммарно > 20 с без поддержки
	check_eq(w.nodes[1].owner, Defs.NEUTRAL, "без KEEPALIVE машина должна стать нейтральной")
	check_eq(w.nodes[1].control, 0)

func test_supplier_is_closer_to_core_not_mutual() -> void:
	var w: World = TestMaps.chain()
	Economy.capture_node(w, w.nodes[2], 0)
	Routing.compute(w)
	Economy.refresh_targets(w)
	check_eq(w.nodes[1].supplier, 0)
	check_eq(w.nodes[2].supplier, 1, "дальнюю машину кормит ближайший к ядру сосед")
	check_eq(w.nodes[0].supplier, -1, "ядро не нуждается в KEEPALIVE")

func test_far_machine_falls_when_middle_cut() -> void:
	var w: World = TestMaps.chain()
	Economy.capture_node(w, w.nodes[2], 0)
	w.run(100)
	w.links[1].queue_limit = 0       # режем 1–2
	w.run(500)
	check_eq(w.nodes[2].owner, Defs.NEUTRAL, "отрезанная машина должна отвалиться")
	check_eq(w.nodes[1].owner, 0, "ближняя машина остаётся")

func test_flood_on_own_link_drops_far_machine() -> void:
	# Флуд своей же сети: линк 1–2 забит чужим потоком, KEEPALIVE не пробивается.
	var w: World = TestMaps.chain()
	Economy.capture_node(w, w.nodes[2], 0)
	w.run(40)
	for i in 2 * 400 + 200:     # свой же флуд по линку 1→2: тестовый двойник забивает порт пакетами
		for k in 3:
			Network.inject(w, 1, 2, Defs.PacketType.FLOOD, 0, 0)
		w.step()
	check(w.drops[World.DROP_QUEUE] > 0)
	check_eq(w.nodes[2].owner, Defs.NEUTRAL, "забитый флудом линк должен отрезать дальнюю машину")

func test_economy_state_deterministic() -> void:
	var a: World = Scenarios.build_economy(11)
	var b: World = Scenarios.build_economy(11)
	a.run(1500)
	b.run(1500)
	check_eq(a.state_hash(), b.state_hash())
	check(a.players[0].captures > 0, "в сценарии должны быть захваты")
	check(a.players[0].bank > 0)
