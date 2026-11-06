extends TestCase

func _labels(items: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for it in items:
		out.append(String(it["label"]))
	return " | ".join(out)

func test_ring_menu_offers_capture_only_with_entry() -> void:
	var w: World = TestMaps.siege()
	w.step()
	check(not _labels(RingMenu.items_for(w, 1, 3, 2)).contains("Захватить"), "без входа захватывать нечем")
	TestMaps.infect_fully(w, 2, 1)
	w.step()
	var t: String = _labels(RingMenu.items_for(w, 1, 3, 2))
	check(t.contains("Захватить (20 Б, 10 с)"), t)
	var core: String = _labels(RingMenu.items_for(w, 1, 3, 0))
	check(not core.contains("Захватить"), "ядро без входа не предлагается")

func test_ring_menu_core_capture_costs_more() -> void:
	var w: World = TestMaps.rush()
	TestMaps.infect_fully(w, 0, 1)
	w.step()
	var t: String = _labels(RingMenu.items_for(w, 1, 1, 0))
	check(t.contains("Захватить (100 Б, 40 с)"), t)

func test_own_machine_offers_evict() -> void:
	var w: World = TestMaps.siege()
	check(_labels(RingMenu.items_for(w, 0, 0, 2)).contains("Выгнать"))

func test_hints_for_capture_evict_and_door() -> void:
	check(Hints.task(Defs.TaskKind.CAPTURE).contains("Захватить"))
	check(Hints.task(Defs.TaskKind.EVICT).contains("Выгнать"))
	check(Hints.ring_item({"kind": "activate", "mode": Defs.ActivateMode.OPEN_DOOR}).contains("дверь"))

func test_card_shows_infection_and_capture_progress() -> void:
	var w: World = TestMaps.siege()
	w.players[1].bank = 300
	TestMaps.infect_fully(w, 2, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	var guard: int = 0
	while Agents.agent_of(w, 1, 0).mode != AgentState.Mode.WORK and guard < 400:
		w.step()
		guard += 1
	w.run(60)
	var t: String = NodeCard.text_for(w, 2, 0)
	check(t.contains("ЗАРАЖЕНА"), t)
	check(t.contains("ЗАХВАТ АГЕНТОМ"), t)

func test_event_feed_line_for_agent_capture() -> void:
	var w: World = TestMaps.siege()
	var plain: String = EventFeed.line_for(w, [100, Knowledge.EventKind.AGENT_CAPTURING, 2, -1, -1])
	check(plain.contains("захватывает агент"), plain)
	var ids: String = EventFeed.line_for(w, [100, Knowledge.EventKind.AGENT_CAPTURING, 2, -1, 1])
	check(ids.contains("игрока 2"), ids)

func test_graph_view_draws_capture_arc() -> void:
	var w: World = TestMaps.siege()
	w.players[1].bank = 300
	TestMaps.infect_fully(w, 2, 1)
	TestMaps.clear_defenders(w, 0)
	w.submit(Command.queue_task(1, 0, 0, Defs.TaskKind.CAPTURE, 2))
	w.run(250)
	var gv := GraphView.new()
	gv.world = w
	gv.draw_nodes = true
	gv.viewer = 0
	Engine.get_main_loop().root.add_child(gv)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(gv.is_inside_tree())
	gv.queue_free()
