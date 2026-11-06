extends TestCase

func _agent(w: World, idx: int = 0, player: int = 0) -> AgentState:
	return Agents.agent_of(w, player, idx)

func test_three_agents_start_on_core() -> void:
	var w: World = TestMaps.chain()
	for p in 2:
		for k in Defs.AGENTS_PER_PLAYER:
			var a: AgentState = _agent(w, k, p)
			check_eq(a.node, w.players[p].core_node)
			check_eq(a.mode, AgentState.Mode.IDLE)
	check_eq(w.agents.size(), 6)

func test_task_spends_bytes_and_lasts_defs_time() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CHANGE_PASSWORD, 0))
	w.run(1)
	var a: AgentState = _agent(w)
	check_eq(a.mode, AgentState.Mode.WORK)
	var params: Array = Agents.task_params(Defs.TaskKind.CHANGE_PASSWORD, 0)
	check_eq(w.players[0].bank, 100 - int(params[1]), "байты списываются на старте")
	check_eq(int(params[0]), 4 * Defs.TICK_HZ)
	w.run(int(params[0]) - 1)
	check_eq(w.nodes[0].access_mode, Defs.AccessMode.PASSWORD_WEAK, "задача не должна закончиться раньше срока")
	w.run(1)
	check_eq(w.nodes[0].access_mode, Defs.AccessMode.PASSWORD_STRONG)
	check_eq(a.mode, AgentState.Mode.IDLE)

func test_task_does_not_start_without_bytes() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 0
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 0))
	w.run(50)
	var a: AgentState = _agent(w)
	check_eq(a.mode, AgentState.Mode.IDLE, "без байтов задача не начинается")
	check_eq(a.queue.size(), 1)
	check_eq(w.nodes[0].access_mode, Defs.AccessMode.PASSWORD_WEAK)
	w.players[0].bank = 15
	w.run(1)
	check_eq(a.mode, AgentState.Mode.WORK)
	check_eq(w.players[0].bank, 0)

func test_agent_travels_by_route_and_stands_in_traffic() -> void:
	var w: World = TestMaps.chain()
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 1))
	var lat: int = w.links[0].latency
	w.run(lat)
	check_eq(_agent(w).node, -1, "агент ещё в пути")
	check_eq(_agent(w).mode, AgentState.Mode.TRAVEL)
	w.run(1)
	check_eq(_agent(w).node, 1)
	check_eq(_agent(w).mode, AgentState.Mode.IDLE)
	# Тот же путь по забитому линку идёт заметно дольше.
	var w2: World = TestMaps.chain()
	for i in 25:
		Network.inject(w2, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	w2.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 1))
	var t: int = 0
	while _agent(w2).node != 1 and t < 600:
		w2.step()
		t += 1
	check(t > lat + 30, "агент должен застрять в пробке: дошёл за %d тиков" % t)
	check_eq(_agent(w2).node, 1, "но дойти обязан")

func test_agent_goes_then_installs_software() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 200
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.INSTALL_SOFT, 1, Defs.SoftType.FIREWALL))
	w.run(400)
	check(w.nodes[1].has_soft(Defs.SoftType.FIREWALL), "файрвол не установился")
	var cost: int = int(Defs.SOFT_DEFS[Defs.SoftType.FIREWALL]["cost"])
	check_eq(w.players[0].bank, 200 + w.players[0].earned_total - cost, "байты за ПО должны быть списаны ровно один раз")

func test_queue_runs_tasks_in_order() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 500
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 1))
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.INSTALL_SOFT, 1, Defs.SoftType.FIREWALL))
	w.run(30 * 20)
	check_eq(w.nodes[1].access_mode, Defs.AccessMode.KEYS)
	check(w.nodes[1].has_soft(Defs.SoftType.FIREWALL))
	check(_agent(w).queue.is_empty())

func test_queue_limit_and_ownership_validation() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 0       # без байтов задачи висят в очереди
	for i in 4:
		w.submit(Command.queue_task(0, 0, 1, Defs.TaskKind.SET_KEYS, 0))
	w.step()
	check_eq(_agent(w, 0).queue.size(), 0)
	check_eq(_agent(w, 1).queue.size(), Defs.AGENT_QUEUE_MAX, "в очереди не больше 3 задач")
	check_eq(w.rejected_count, 1)
	var w2: World = TestMaps.chain()
	w2.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 2))     # нейтрал
	w2.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.STEAL_KEY, 1))  # красть ключ у себя нельзя
	w2.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.INSTALL_SOFT, 1, 99))   # такого ПО нет
	w2.submit(Command.queue_task(0, 0, 7, Defs.TaskKind.MOVE, 1))     # нет такого агента
	w2.step()
	check_eq(w2.rejected_count, 4)
	check_eq(_agent(w2).queue.size(), 0)

func test_clear_queue() -> void:
	var w: World = TestMaps.chain()
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 1))
	w.step()
	check_eq(_agent(w).queue.size(), 1)
	w.submit(Command.clear_queue(0, w.tick, 0))
	w.step()
	check(_agent(w).queue.is_empty())

func test_password_and_keys_rewrite_access() -> void:
	var w: World = TestMaps.chain()
	w.nodes[0].access_mask = 0b11      # у второго игрока тоже есть доступ
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CHANGE_PASSWORD, 0))
	w.run(120)
	check_eq(w.nodes[0].access_mask, 1, "смена пароля обнуляет чужие доступы")
	check_eq(w.nodes[0].access_mode, Defs.AccessMode.PASSWORD_STRONG)
	w.nodes[0].access_mask = 0b11
	w.submit(Command.queue_task(0, w.tick, 0, Defs.TaskKind.SET_KEYS, 0))
	w.run(250)
	check_eq(w.nodes[0].access_mode, Defs.AccessMode.KEYS)
	check_eq(w.nodes[0].key_version, 1)
	check_eq(w.nodes[0].access_mask, 1, "смена ключей отбирает старые доступы")

func test_lost_agent_returns_to_core_after_20s() -> void:
	var w: World = TestMaps.chain()
	Economy.capture_node(w, w.nodes[2], 0)
	w.links[1].queue_limit = 0                   # линк 1–2 не принимает пакеты
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 2))
	var a: AgentState = _agent(w)
	var guard: int = 0
	while a.mode != AgentState.Mode.LOST and guard < 200:
		w.step()
		guard += 1
	check_eq(a.mode, AgentState.Mode.LOST, "потерянный в пути агент возвращается")
	check(a.queue.is_empty())
	w.run(Defs.AGENT_RETURN_TICKS - 2)
	check_eq(a.mode, AgentState.Mode.LOST, "возвращается не раньше чем через 20 с")
	w.run(3)
	check_eq(a.mode, AgentState.Mode.IDLE)
	check_eq(a.node, w.players[0].core_node)

func test_agent_kicked_when_node_lost() -> void:
	var w: World = TestMaps.chain()
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.MOVE, 1))
	w.run(20)
	check_eq(_agent(w).node, 1)
	Economy.release_node(w, w.nodes[1])
	check_eq(_agent(w).mode, AgentState.Mode.LOST)
	w.run(Defs.AGENT_RETURN_TICKS + 2)
	check_eq(_agent(w).node, 0)

func test_node_lost_cancels_queued_tasks_for_it() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 0
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 1))
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 0))
	w.step()
	Economy.release_node(w, w.nodes[1])
	check_eq(_agent(w).queue.size(), 1)
	check_eq(int(_agent(w).queue[0][1]), 0)

func test_agents_deterministic() -> void:
	var a: World = Scenarios.build_agents(3)
	var b: World = Scenarios.build_agents(3)
	a.run(1500)
	b.run(1500)
	check_eq(a.state_hash(), b.state_hash())
	check(a.nodes[2].has_soft(Defs.SoftType.FIREWALL) or a.nodes[3].has_soft(Defs.SoftType.FIREWALL), "агенты должны успеть поставить ПО")
