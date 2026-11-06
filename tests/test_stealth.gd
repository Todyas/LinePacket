extends TestCase

func _hidden_world(rate: int = 20) -> World:
	var w: World = TestMaps.siege()
	w.players[1].bank = 10000
	w.submit(Command.start_flow(1, 0, 3, 2, Defs.PacketType.PAYLOAD_HIDDEN, rate))
	return w

func _infect_until_virus(w: World, guard: int = 800) -> void:
	var t: int = 0
	while w.nodes[2].virus[1] != 1 and t < guard:
		w.step()
		t += 1

func test_hidden_payload_is_pricier_and_slower_than_plain() -> void:
	var plain: World = TestMaps.siege()
	plain.players[1].bank = 10000
	plain.submit(Command.start_flow(1, 0, 3, 2, Defs.PacketType.PAYLOAD, 20))
	var t_plain: int = 0
	while plain.nodes[2].owner == 0 and t_plain < 800:
		plain.step()
		t_plain += 1
	var hid: World = _hidden_world()
	var t_hid: int = 0
	while hid.nodes[2].virus[1] != 1 and t_hid < 800:
		hid.step()
		t_hid += 1
	check(hid.nodes[2].virus[1] == 1, "скрытый вирус должен встать")
	check(t_hid > t_plain, "скрытый медленнее: %d против %d" % [t_hid, t_plain])
	check(Defs.PAYLOAD_HIDDEN_COST_BYTES > Defs.PAYLOAD_COST_BYTES)
	check(10000 - hid.players[1].bank >= 2 * (Defs.INFECT_MAX / Defs.INFECT_HIDDEN_GAIN), "байты списаны")

func test_hidden_virus_keeps_owner_and_is_invisible_to_owner_api() -> void:
	var w: World = _hidden_world()
	w.nodes[2].install_soft(Defs.SoftType.FIREWALL)   # у владельца есть обычная защита, но не IDS и не антивирус
	_infect_until_virus(w, 1500)
	check_eq(w.nodes[2].virus[1], 1)
	check_eq(w.nodes[2].owner, 0, "владелец не меняется")
	w.run(60 * 20)
	var snap: NodeSnap = Knowledge.snap(w, 0, 2)
	check(snap != null)
	check(not snap.found_virus and not snap.found_backdoor and not snap.my_virus, "владелец ничего не видит в снимке")
	check_eq(Knowledge.owner_of(w, 0, 2), 0)
	var text: String = NodeCard.text_for(w, 2, 0)
	check(not text.contains("вирус") and not text.contains("Заражение"), "карточка чиста: " + text)
	for e in Knowledge.events_of(w, 0):
		check(e[1] != Knowledge.EventKind.HIDDEN_FOUND, "никаких находок без IDS")
	check(Knowledge.snap(w, 1, 2).my_virus, "у вора свой вирус виден")

func test_ids_finds_hidden_virus_in_time_and_agent_cleans_it() -> void:
	var w: World = _hidden_world()
	w.nodes[2].install_soft(Defs.SoftType.IDS)
	_infect_until_virus(w, 1500)
	var t0: int = w.tick
	w.run(Defs.HIDDEN_DETECT_S[Defs.HiddenKind.VIRUS] * Defs.TICK_HZ - 20)
	check(not Knowledge.snap(w, 0, 2).found_virus, "ещё не нашли")
	w.run(60)
	var s: NodeSnap = Knowledge.snap(w, 0, 2)
	check(s.found_virus, "через время IDS находит вирус (тик %d)" % (w.tick - t0))
	var seen: bool = false
	for e in Knowledge.events_of(w, 0):
		if e[1] == Knowledge.EventKind.HIDDEN_FOUND and e[2] == 2 and int(e[4]) / 2 == Defs.HiddenKind.VIRUS:
			seen = true
	check(seen, "в ленту пришла запись о находке")
	check(NodeCard.text_for(w, 2, 0).contains("вирус"), "найденное видно в карточке")
	# Вычистить агентом.
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.CLEAN_VIRUS, 2))
	w.run(400)
	check_eq(w.nodes[2].virus[1], 0, "найденный вирус удалён задачей «вычистить»")

func test_without_detector_nothing_found_ever() -> void:
	var w: World = _hidden_world()
	_infect_until_virus(w, 1500)
	w.run(120 * 20)
	check_eq(w.nodes[2].found[NodeState.hidden_slot(Defs.HiddenKind.VIRUS, 1)], 0)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.CLEAN_VIRUS, 2))
	w.run(400)
	check_eq(w.nodes[2].virus[1], 1, "ненайденный вирус вычистить нельзя")

func test_antivirus_also_finds_hidden_virus() -> void:
	var w: World = _hidden_world()
	w.nodes[2].install_soft(Defs.SoftType.ANTIVIRUS)
	_infect_until_virus(w, 4000)
	check_eq(w.nodes[2].virus[1], 1, "антивирус замедляет, но не гарантирует")
	w.run(Defs.HIDDEN_DETECT_S[Defs.HiddenKind.VIRUS] * Defs.TICK_HZ + 40)
	check(Knowledge.snap(w, 0, 2).found_virus, "антивирус нашёл вирус")

func test_activation_takeover_changes_owner_in_one_tick() -> void:
	var w: World = _hidden_world()
	_infect_until_virus(w, 1500)
	w.run(5)
	w.submit(Command.activate(1, w.tick, 2, Defs.ActivateMode.TAKEOVER))
	var tick_before: int = w.tick
	check_eq(w.nodes[2].owner, 0)
	w.step()
	check_eq(w.nodes[2].owner, 1, "за один тик")
	check_eq(w.tick, tick_before + 1)
	check_eq(w.nodes[2].virus[1], 0, "вирус израсходован")
	# Повторно без вируса — отказ.
	var rej: int = w.rejected_count
	w.submit(Command.activate(1, w.tick, 2, Defs.ActivateMode.TAKEOVER))
	w.step()
	check_eq(w.rejected_count, rej + 1)

func test_activation_disable_soft_is_temporary() -> void:
	var w: World = _hidden_world()
	w.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	_infect_until_virus(w, 1500)
	w.step()
	w.submit(Command.activate(1, w.tick, 2, Defs.ActivateMode.DISABLE_SOFT))
	w.step()
	check(not w.nodes[2].soft_active(Defs.SoftType.FIREWALL), "ПО выключено")
	check_eq(w.nodes[2].owner, 0)
	w.run(Defs.ACTIVATE_DISABLE_SOFT_TICKS + 5)
	check(w.nodes[2].soft_active(Defs.SoftType.FIREWALL), "через время ПО снова работает")

func test_virus_skims_part_of_data_and_shows_neighbourhood() -> void:
	var base: World = TestMaps.siege()
	base.run(600)
	var w: World = TestMaps.siege()
	w.nodes[2].virus[1] = 1
	var bank0: int = w.players[1].bank
	w.run(600)
	check(w.players[1].bank > bank0, "вор получает часть DATA")
	check(w.players[0].earned_total < base.players[0].earned_total, "у владельца доход ниже")
	check_eq(Knowledge.level(w, 1, 1), Knowledge.Level.OBSERVED, "через заражённую машину видно соседей: шлюз P0")

func test_backdoor_survives_password_and_key_change() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].access_mask |= 2        # у P1 есть доступ (украденный ключ)
	w.players[1].bank = 200
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.BACKDOOR, 2))
	w.run(400)
	check_eq(w.nodes[2].backdoor[1], 1, "бэкдор поставлен")
	# Владелец меняет ключи: доступ по ключу пропал, бэкдор остался.
	w.players[0].bank = 200
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.SET_KEYS, 2))
	w.run(400)
	check_eq(w.nodes[2].access_mode, Defs.AccessMode.KEYS)
	check_eq(w.nodes[2].access_mask & 2, 0, "старые доступы сброшены")
	check_eq(w.nodes[2].backdoor[1], 1, "бэкдор пережил смену ключей")
	w.submit(Command.queue_task(1, w.tick, 1, Defs.TaskKind.MOVE, 2))
	w.run(200)
	check_eq(Agents.agent_of(w, 1, 1).node, 2, "агент входит через бэкдор")

func test_backdoor_found_and_cleaned() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].backdoor[1] = 1
	w.nodes[2].install_soft(Defs.SoftType.IDS)
	w.run(Defs.HIDDEN_DETECT_S[Defs.HiddenKind.BACKDOOR] * Defs.TICK_HZ + 40)
	check(Knowledge.snap(w, 0, 2).found_backdoor)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.CLEAN_VIRUS, 2))
	w.run(300)
	check_eq(w.nodes[2].backdoor[1], 0)

func _sniffer_world() -> World:
	return TestMaps.build({
		"name": "sniff", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0),
			TestMaps.node(1, "machine", 300, 0, 1),
			TestMaps.node(2, "gateway", 600, 0, 0),
			TestMaps.node(3, "core", 300, 400, 1),
		],
		"links": [TestMaps.link(0, 1, "optic"), TestMaps.link(1, 2, "optic"), TestMaps.link(3, 1, "optic")],
	})

func test_sniffer_steals_exactly_the_data_it_intercepts() -> void:
	var w: World = _sniffer_world()
	w.nodes[1].install_soft(Defs.SoftType.SNIFFER)
	var bank0: int = w.players[1].bank
	w.run(1200)
	check(w.delivered_sniffed > 0, "сниффер должен что-то перехватить")
	check_eq(w.players[1].bank - bank0, w.delivered_sniffed * Defs.DATA_VALUE, "банк вора вырос ровно на перехваченное")
	var w2: World = _sniffer_world()
	w2.run(1200)
	check_eq(w2.delivered_sniffed, 0)
	check(w2.players[0].earned_total > w.players[0].earned_total, "без сниффера у P0 дохода больше")

func test_sniffer_hidden_until_found_by_neighbour_ids() -> void:
	var w: World = _sniffer_world()
	w.nodes[1].install_soft(Defs.SoftType.SNIFFER)
	w.step()
	check(not Knowledge.soft_visible(w, 0, 1).has(Defs.SoftType.SNIFFER), "чужой сниффер не виден")
	check(not Knowledge.snap(w, 0, 1).has_soft(Defs.SoftType.SNIFFER))
	check(not NodeCard.text_for(w, 1, 0).contains("Сниффер"))
	w.nodes[0].install_soft(Defs.SoftType.IDS)    # IDS на соседнем узле P0
	w.run(Defs.HIDDEN_DETECT_S[Defs.HiddenKind.SNIFFER] * Defs.TICK_HZ + 40)
	check(Knowledge.soft_visible(w, 0, 1).has(Defs.SoftType.SNIFFER), "IDS соседа нашёл сниффер")
	check(NodeCard.text_for(w, 1, 0).contains("Сниффер"))

func test_foreign_agent_visible_only_to_ids() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].access_mask |= 2
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.MOVE, 2))
	w.run(120)
	var ag: AgentState = Agents.agent_of(w, 1, 0)
	check_eq(ag.node, 2)
	check(not Knowledge.agent_visible(w, 0, ag), "без IDS чужого агента не видно")
	check(not NodeCard.text_for(w, 2, 0).contains("Агенты здесь"), "в карточке чужого агента нет")
	w.nodes[2].install_soft(Defs.SoftType.IDS)
	check(Knowledge.agent_visible(w, 0, ag), "IDS видит агента")
	check(NodeCard.text_for(w, 2, 0).contains("Агенты здесь"))
	check(Knowledge.agent_visible(w, 1, ag), "свой агент виден всегда")

func test_stealth_scenario_hash_stable_across_runs() -> void:
	var a: World = _hidden_world()
	var b: World = _hidden_world()
	a.run(400)
	b.run(400)
	check_eq(a.state_hash(), b.state_hash())
