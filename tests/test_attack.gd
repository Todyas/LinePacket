extends TestCase

func _flood(w: World) -> void:
	# Две машины с ретрансляторами складывают давление: 16 + 12 пакетов в секунду на машину 2.
	TestMaps.boost(w, 3)
	TestMaps.boost(w, 4)
	w.nodes[2].cpu_base = 24
	w.nodes[2].cpu_per_s = 24    # слабая машина: давление двух атакующих держит её лежащей
	TestMaps.engage(w, 1, 3, 2, Defs.PacketType.FLOOD)
	TestMaps.engage(w, 1, 4, 2, Defs.PacketType.FLOOD)

func test_overloaded_machine_lies_and_stops_sending() -> void:
	var w: World = TestMaps.siege()
	var m: NodeState = w.nodes[2]
	w.run(200)
	check(not m.down, "в покое машина не лежит")
	var sent_before: int = m.auto_sent
	check(sent_before > 0, "здоровая машина шлёт DATA")
	_flood(w)
	w.run(150)
	check(m.down, "перегруженная машина должна лечь (загрузка %d%%)" % m.cpu_load_pct())
	var frozen: int = m.auto_sent
	w.run(60)
	check_eq(m.auto_sent, frozen, "лежащая машина не шлёт DATA и KEEPALIVE")
	# Передышка: поток остановлен, машина поднимается.
	TestMaps.stand_down(w, 3)
	TestMaps.stand_down(w, 4)
	w.run(120)
	check(not m.down, "после флуда машина должна подняться")
	w.run(100)
	check(m.auto_sent > frozen, "поднявшаяся машина снова шлёт пакеты")

func test_lying_machine_software_does_not_work() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	check(w.nodes[2].soft_active(Defs.SoftType.FIREWALL))
	w.nodes[2].down = true
	check(not w.nodes[2].soft_active(Defs.SoftType.FIREWALL), "у лежащей машины ПО не работает")

func test_flood_loses_control_of_lying_machine() -> void:
	var w: World = TestMaps.siege()
	_flood(w)
	w.run(30 * 20)
	check_eq(w.nodes[2].owner, Defs.NEUTRAL, "лежащая под флудом машина теряет KEEPALIVE и отваливается")

## Заражение машины 2 от перечисленных атакующих узлов (3 — ядро, 8/с; 4 — машина, 6/с).
func _payload_world(with_av: bool, attackers: Array = [3, 4]) -> World:
	var w: World = TestMaps.siege()
	w.players[1].bank = 10000
	if with_av:
		w.nodes[2].install_soft(Defs.SoftType.ANTIVIRUS)
	for a in attackers:
		TestMaps.engage(w, 1, a, 2, Defs.PacketType.PAYLOAD)
	return w

func test_payload_infects_at_100_percent_but_keeps_owner() -> void:
	var w: World = _payload_world(false)
	w.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	var guard: int = 0
	while not w.nodes[2].infected_by(1) and guard < 1600:
		w.step()
		guard += 1
	var m: NodeState = w.nodes[2]
	check(m.infected_by(1), "шкала заражения дошла до 100%")
	check_eq(m.owner, 0, "заражение владельца не меняет")
	check_eq(w.players[1].captures, 0)
	check(not m.soft_active(Defs.SoftType.FIREWALL), "ПО защитника на заражённой машине молчит")
	check(Agents.can_enter(m, 1), "у заразившего есть доступ для агента")
	for nid in [3, 4]:
		TestMaps.stand_down(w, nid)
	w.run(600)
	check(m.infected_by(1), "заражение держится, пока его не вычистят")
	var needed: int = Defs.INFECT_MAX / Defs.INFECT_GAIN
	check(w.delivered[Defs.PacketType.PAYLOAD] >= needed - 5, "нужно около %d пакетов" % needed)

func test_antivirus_slows_infection() -> void:
	var plain: World = _payload_world(false, [4])
	var guarded: World = _payload_world(true, [4])
	plain.run(60)
	guarded.run(60)
	var a: int = plain.nodes[2].infect[1]
	var b: int = guarded.nodes[2].infect[1]
	check(a > 0 and b > 0, "шкалы должны расти")
	check(b < a * 55 / 100, "антивирус должен замедлять заражение: %d против %d" % [b, a])
	# Без нового PAYLOAD антивирус быстро сбивает шкалу.
	TestMaps.stand_down(guarded, 4)
	guarded.run(80)
	check_eq(guarded.nodes[2].infect[1], 0, "антивирус сбивает шкалу")
	TestMaps.stand_down(plain, 4)
	plain.run(40)
	check(plain.nodes[2].infect[1] > 0, "без антивируса шкала тает медленно")

func test_payload_costs_bytes() -> void:
	var w: World = _payload_world(false)
	w.players[1].bank = 5
	w.run(16)    # раньше, чем придёт доход с шлюза
	check_eq(w.players[1].bank, 0, "PAYLOAD должен списывать байты")
	var in_flight: int = 0
	for i in w.pool.alive.size():
		if w.pool.alive[i] != 0 and w.pool.ptype[i] == Defs.PacketType.PAYLOAD:
			in_flight += 1
	check_eq(w.total_drops(), 0)
	check_eq(w.delivered[Defs.PacketType.PAYLOAD] + in_flight, 5 / Defs.PAYLOAD_COST_BYTES, "без байтов пакеты не рождаются")

func _ticks_to_takeover(w: World) -> int:
	var t: int = 0
	while not w.nodes[2].infected_by(1) and t < 1600:
		w.step()
		t += 1
	return t

func test_firewall_slows_payload() -> void:
	var plain: World = _payload_world(false)
	var walled: World = _payload_world(false)
	for w in [plain, walled]:
		TestMaps.boost(w, 3)
		TestMaps.boost(w, 4)
	walled.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	var t_plain: int = _ticks_to_takeover(plain)
	var t_walled: int = _ticks_to_takeover(walled)
	check(walled.drops[World.DROP_FIREWALL] > 0, "файрвол должен сбрасывать лишний PAYLOAD")
	check(t_walled > t_plain, "с файрволом захват дольше: %d против %d" % [t_walled, t_plain])

func test_takeover_expels_defender_agents_and_resets_role() -> void:
	var w: World = TestMaps.siege()
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 2))
	w.run(60)
	check_eq(Agents.agent_of(w, 0, 0).node, 2)
	TestMaps.engage(w, 0, 2, 3, Defs.PacketType.FLOOD)
	check_eq(w.nodes[2].role, Defs.Role.PRESSURE)
	Economy.takeover(w, w.nodes[2], 1)
	check_eq(Agents.agent_of(w, 0, 0).mode, AgentState.Mode.LOST, "агенты защитника вылетают")
	check_eq(w.nodes[2].role, Defs.Role.WORK, "машина, сменившая владельца, возвращается к работе")
	w.run(Defs.AGENT_RETURN_TICKS + 5)
	check_eq(Agents.agent_of(w, 0, 0).node, 0, "и возвращаются на ядро через 20 с")

func test_weak_password_cracked_by_init_keys_never() -> void:
	var weak: World = TestMaps.siege()
	TestMaps.engage(weak, 1, 3, 2, Defs.PacketType.INIT)
	weak.run(200)
	check(weak.nodes[2].access_mask & 2 != 0, "слабый пароль должен подобраться")
	var strong: World = TestMaps.siege()
	strong.nodes[2].access_mode = Defs.AccessMode.PASSWORD_STRONG
	TestMaps.engage(strong, 1, 3, 2, Defs.PacketType.INIT)
	strong.run(200)
	check(strong.nodes[2].access_mask & 2 == 0, "сильный пароль за то же время не сдаётся")
	check(strong.nodes[2].brute[1] > 0, "но шкала подбора растёт")
	var keys: World = TestMaps.siege()
	keys.nodes[2].access_mode = Defs.AccessMode.KEYS
	keys.submit(Command.set_role(1, 0, 3, Defs.Role.CAPTURE, 2))
	keys.run(10)
	check_eq(keys.rejected_count, 1, "на ключи подбор не назначить")
	check(keys.nodes[2].access_mask & 2 == 0, "ключи не подбираются")
	check_eq(keys.nodes[2].brute[1], 0)

func test_agent_entry_needs_access_or_lying() -> void:
	var w: World = TestMaps.siege()
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.MOVE, 2))
	w.run(80)
	check_eq(Agents.agent_of(w, 1, 0).mode, AgentState.Mode.LOST, "без доступа агента не пускают")
	# С доступом входит.
	var w2: World = TestMaps.siege()
	w2.nodes[2].access_mask |= 2
	w2.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.MOVE, 2))
	w2.run(80)
	check_eq(Agents.agent_of(w2, 1, 0).node, 2)
	# Лежащая машина доступ не проверяет.
	var w3: World = TestMaps.siege()
	w3.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.MOVE, 2))
	for i in 40:
		w3.nodes[2].down = true     # держим машину лежащей (гистерезис её бы поднял)
		w3.step()
	check_eq(Agents.agent_of(w3, 1, 0).node, 2, "в лежащую машину можно войти без доступа")

func test_steal_key_and_drain_buffer_on_enemy() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].access_mask |= 2
	w.nodes[2].buffer = 12
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.DRAIN_BUFFER, 2))
	var before: int = w.players[1].bank
	w.run(200)
	check_eq(w.nodes[2].buffer <= 2, true, "агент должен выкачать буфер: осталось %d" % w.nodes[2].buffer)
	check(w.players[1].bank > before)
	check(Agents.agent_of(w, 1, 0).queue.is_empty(), "когда качать нечего, задача заканчивается")
	# Кража ключа: доступ остаётся после смены состояния машины.
	var w2: World = TestMaps.siege()
	w2.nodes[2].access_mask |= 2
	w2.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.STEAL_KEY, 2))
	w2.run(14 * 20 + 40)
	check(w2.nodes[2].access_mask & 2 != 0)
	check(Agents.agent_of(w2, 1, 0).queue.is_empty(), "задача «украсть ключ» выполнена")

func test_old_keys_let_previous_owner_back_until_keys_changed() -> void:
	var w: World = TestMaps.siege()
	Economy.takeover(w, w.nodes[2], 1)          # P1 захватил машину
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.MOVE, 2))
	w.run(60)
	check_eq(Agents.agent_of(w, 0, 0).node, 2, "по старым ключам прошлый владелец входит")
	# Новый владелец меняет ключи — старый доступ закрывается.
	var w2: World = TestMaps.siege()
	Economy.takeover(w2, w2.nodes[2], 1)
	w2.players[1].bank = 100
	w2.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.SET_KEYS, 2))
	w2.run(300)
	check_eq(w2.nodes[2].access_mask, 2, "смена ключей отбирает старый доступ")
	w2.submit(Command.queue_task(0, w2.tick, 0, Defs.TaskKind.MOVE, 2))
	w2.run(80)
	check_eq(Agents.agent_of(w2, 0, 0).mode, AgentState.Mode.LOST, "теперь прошлого владельца не пускают")

func test_old_owner_retakes_with_old_keys_by_capture() -> void:
	var w: World = TestMaps.siege()
	Economy.takeover(w, w.nodes[2], 1)
	TestMaps.clear_defenders(w, 1)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(400)
	check_eq(w.nodes[2].owner, 0, "прошлый владелец вернул машину по старым ключам")

func test_entrench_by_new_owner_locks_out_old() -> void:
	var w: World = TestMaps.siege()
	Economy.takeover(w, w.nodes[2], 1)
	w.players[1].bank = 100
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.ENTRENCH, 2))
	w.run(300)
	check_eq(w.nodes[2].owner, 1)
	check_eq(w.nodes[2].access_mask, 2, "чужие доступы выброшены")
	check_eq(w.nodes[2].prev_owner, -1)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.ENTRENCH, 2))
	w.run(100)
	check_eq(w.nodes[2].owner, 1, "после закрепления прошлый владелец ничего не может")

func test_clean_virus_resets_infection() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].infect[1] = 60000
	w.players[0].bank = 50
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CLEAN_VIRUS, 2))
	var params: Array = Agents.task_params(Defs.TaskKind.CLEAN_VIRUS, 0, w.nodes[2])
	check_eq(int(params[0]), 6 * 20 + 14 * 20 * 60000 / 100000, "время чистки растёт со степенью заражения")
	w.run(60 + int(params[0]) + 40)
	check_eq(w.nodes[2].infect[1], 0)
	check_eq(w.players[0].bank >= 0, true)

func test_core_capture_by_agent_ends_match() -> void:
	var w: World = TestMaps.rush()
	w.players[1].bank = 1000
	TestMaps.infect_fully(w, 0, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 0))
	var guard: int = 0
	while w.winner < 0 and guard < 2000:
		w.step()
		guard += 1
	check_eq(w.winner, 1, "захват ядра завершает матч")
	check_eq(w.finished_tick >= 0, true)
	var t: int = w.tick
	w.run(50)
	check_eq(w.tick, t, "после конца матча мир заморожен")

func test_siege_scenario_deterministic() -> void:
	var a: World = Scenarios.build_siege(8)
	var b: World = Scenarios.build_siege(8)
	a.run(1500)
	b.run(1500)
	check_eq(a.state_hash(), b.state_hash())
	check(a.players[1].captures > 0 or a.players[0].captures > 0, "в сценарии должны быть захваты")
