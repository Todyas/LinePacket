extends TestCase
## Захват агентом (S11): владельца машины меняет только задача CAPTURE.

func _ready_attack() -> World:
	var w: World = TestMaps.siege()
	w.players[1].bank = 500
	w.players[0].bank = 500
	return w

func test_capture_validation() -> void:
	var w: World = _ready_attack()
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 3))   # свой узел
	w.step()
	check_eq(w.rejected_count, 1, "свой узел не захватывается")
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.CAPTURE, 2))
	w.step()
	check_eq(Agents.agent_of(w, 1, 0).queue.size(), 1, "чужую машину можно поставить в очередь")
	var neutral: World = TestMaps.scout()
	neutral.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CAPTURE, 1))
	neutral.step()
	check_eq(neutral.rejected_count, 1, "нейтрал захватывается ролью, а не агентом")

func test_capture_without_access_agent_is_turned_away() -> void:
	var w: World = _ready_attack()
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(200)
	check_eq(w.nodes[2].owner, 0, "без доступа владельца не сменить")
	check_eq(Agents.agent_of(w, 1, 0).mode, AgentState.Mode.LOST, "агента не пустили и отправили домой")

func test_infected_machine_is_captured_by_agent() -> void:
	var w: World = _ready_attack()
	TestMaps.infect_fully(w, 2, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(500)
	var m: NodeState = w.nodes[2]
	check_eq(m.owner, 1, "захват агентом меняет владельца")
	check_eq(m.prev_owner, 0)
	check(m.access_mask & 1 != 0, "прошлый владелец сохраняет доступ по старым ключам")
	check_eq(w.players[1].captures, 1)

func test_capture_time_and_cost_by_node_type() -> void:
	var w: World = _ready_attack()
	check_eq(Agents.task_params(Defs.TaskKind.CAPTURE, 0, w.nodes[2]), [10 * Defs.TICK_HZ, 20])
	check_eq(Agents.task_params(Defs.TaskKind.CAPTURE, 0, w.nodes[1]), [10 * Defs.TICK_HZ, 20], "шлюз как машина")
	check_eq(Agents.task_params(Defs.TaskKind.CAPTURE, 0, w.nodes[0]), [40 * Defs.TICK_HZ, 100], "ядро дольше и дороже")

func test_capture_pauses_when_access_lost_and_resumes() -> void:
	var w: World = _ready_attack()
	TestMaps.infect_fully(w, 2, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	var guard: int = 0
	while Agents.agent_of(w, 1, 0).mode != AgentState.Mode.WORK and guard < 400:
		w.step()
		guard += 1
	var a: AgentState = Agents.agent_of(w, 1, 0)
	check_eq(a.mode, AgentState.Mode.WORK)
	w.run(40)
	var left: int = a.work_left
	check(left < a.work_total, "задача идёт")
	w.nodes[2].infect.fill(0)                   # вирус вычищен: доступа нет
	w.run(60)
	check_eq(a.work_left, left, "доступ пропал: задача на паузе")
	check_eq(a.node, 2, "агент остаётся на машине")
	check_eq(w.nodes[2].owner, 0)
	TestMaps.infect_fully(w, 2, 1)
	w.run(left + 40)
	check_eq(w.nodes[2].owner, 1, "доступ вернулся: задача доведена")

func test_defender_agent_blocks_capture_and_evict_removes_attacker() -> void:
	var w: World = _ready_attack()
	TestMaps.infect_fully(w, 2, 1)
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 2))      # защитник встаёт на машину
	w.run(80)
	check_eq(Agents.agent_of(w, 0, 0).node, 2)
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(400)
	check_eq(w.nodes[2].owner, 0, "пока на машине агент хозяина, захват не идёт")
	# Атакующий вошёл (заражение даёт вход) и стоит. Хозяин выгоняет его.
	var att: AgentState = Agents.agent_of(w, 1, 0)
	check_eq(att.node, 2, "атакующий стоит на машине и ждёт")
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.EVICT, 2))
	w.run(Defs.TICK_HZ * 6)
	check_eq(att.mode, AgentState.Mode.LOST, "чужой агент выгнан и едет на ядро")
	check_eq(w.nodes[2].owner, 0)

func test_evict_needs_foreign_agent() -> void:
	var w: World = _ready_attack()
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.EVICT, 2))
	w.run(100)
	check(Agents.agent_of(w, 0, 0).queue.is_empty(), "некого выгонять: задача снимается")
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.EVICT, 2))
	w.step()
	check_eq(w.rejected_count, 0, "выгонять можно и на чужой при входе: проверка при прибытии")
	w.run(Defs.TICK_HZ * 10)
	check(Agents.agent_of(w, 1, 0).queue.is_empty(), "нет входа или некого выгонять: задача снимается")

func test_attacker_with_entry_evicts_defender_and_captures() -> void:
	var w: World = _ready_attack()
	TestMaps.infect_fully(w, 2, 1)
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 2))      # защитник встаёт на машину
	w.run(80)
	var def_a: AgentState = Agents.agent_of(w, 0, 0)
	check_eq(def_a.node, 2)
	w.submit(Command.queue_task(1, w.tick, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(300)
	check_eq(w.nodes[2].owner, 0, "защитник на месте: захват стоит")
	w.submit(Command.queue_task(1, w.tick, 1, Defs.TaskKind.EVICT, 2))
	w.run(Defs.TICK_HZ * 7)
	check_eq(def_a.mode, AgentState.Mode.LOST, "атакующий выгнал защитника")
	w.run(Defs.TICK_HZ * 14)
	check_eq(w.nodes[2].owner, 1, "пока защитник едет назад, захват доведён")

func test_core_capture_by_agent_wins_the_match() -> void:
	var w: World = TestMaps.rush()
	w.players[1].bank = 500
	TestMaps.infect_fully(w, 0, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 0))
	var guard: int = 0
	while w.winner < 0 and guard < 3000:
		w.step()
		guard += 1
	check_eq(w.winner, 1, "ядро взято агентом — победа")
	check(guard > 40 * Defs.TICK_HZ - 5, "ядро берётся не быстрее 40 с")

func test_core_with_defender_at_home_cannot_be_captured() -> void:
	var w: World = TestMaps.rush()
	w.players[1].bank = 500
	TestMaps.infect_fully(w, 0, 1)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 0))
	w.run(60 * Defs.TICK_HZ)
	check_eq(w.winner, -1, "агенты хозяина дома — захват стоит")

func test_open_door_lets_agent_capture_without_infection() -> void:
	var w: World = _ready_attack()
	w.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	w.nodes[2].virus[1] = 1
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.activate(1, 0, 2, Defs.ActivateMode.OPEN_DOOR))
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(500)
	check_eq(w.nodes[2].owner, 1, "в окне двери агент захватил машину без флуда")

func test_owner_is_alerted_when_capture_starts() -> void:
	var w: World = _ready_attack()
	TestMaps.infect_fully(w, 2, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(200)
	var alerts: Array = []
	for e in Knowledge.events_of(w, 0):
		if e[1] == Knowledge.EventKind.AGENT_CAPTURING and e[2] == 2:
			alerts.append(e)
	check(not alerts.is_empty(), "владелец узнал, что машину берут")
	check_eq(alerts[0][4], -1, "без IDS источник неизвестен")
	var w2: World = _ready_attack()
	w2.nodes[1].install_soft(Defs.SoftType.IDS)      # IDS на соседнем шлюзе прикрывает машину 2
	TestMaps.infect_fully(w2, 2, 1)
	TestMaps.clear_defenders(w2, 0)
	w2.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	w2.run(200)
	var seen: bool = false
	for e in Knowledge.events_of(w2, 0):
		if e[1] == Knowledge.EventKind.AGENT_CAPTURING and e[4] == 1:
			seen = true
	check(seen, "с IDS видно, чей агент")

func test_clean_virus_removes_full_infection() -> void:
	var w: World = _ready_attack()
	TestMaps.infect_fully(w, 2, 1)
	check(w.nodes[2].is_infected())
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CLEAN_VIRUS, 2))
	w.run(Defs.TICK_HZ * 40)
	check(not w.nodes[2].is_infected(), "агент вычистил заражение")
	check(not Agents.can_enter(w.nodes[2], 1))

func test_capture_is_deterministic() -> void:
	var a: World = Scenarios.build_siege(21)
	var b: World = Scenarios.build_siege(21)
	a.run(2500)
	b.run(2500)
	check_eq(a.state_hash(), b.state_hash())
