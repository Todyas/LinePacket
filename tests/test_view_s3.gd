extends TestCase

func test_node_card_text_for_own_machine() -> void:
	var w: World = TestMaps.chain()
	w.nodes[1].install_soft(Defs.SoftType.FIREWALL)
	w.nodes[1].buffer = 12
	var t: String = NodeCard.text_for(w, 1)
	check(t.contains("M1"), t)
	check(t.contains("Машина"), t)
	check(t.contains("Игрок 1"), t)
	check(t.contains("слабый пароль"), t)
	check(t.contains("Файрвол"), t)
	check(t.contains("[пусто]"), t)
	check(t.contains("12 / 60"), t)

func test_node_card_for_neutral_shows_capture() -> void:
	var w: World = TestMaps.chain()
	w.nodes[2].capture[0] = 7
	var t: String = NodeCard.text_for(w, 2)
	check(t.contains("нейтрал"), t)
	check(t.contains("INIT"), t)
	check(t.contains("Игрок 1: 7"), t)

func test_node_card_lists_agents() -> void:
	var w: World = TestMaps.chain()
	var t: String = NodeCard.text_for(w, 0)
	check(t.contains("Агенты здесь"), t)
	check(t.contains("1(И1)"), t)

func test_agent_panel_lines() -> void:
	var w: World = TestMaps.chain()
	w.players[0].bank = 0
	check(AgentPanel.lines_for(w, 0, 0, true).contains("очередь пуста"))
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 0))
	w.step()
	var t: String = AgentPanel.lines_for(w, 0, 0, true)
	check(t.contains("Ключи @C0"), t)
	check(t.contains("ждёт байт"), t)
	w.players[0].bank = 50
	w.run(40)
	var t2: String = AgentPanel.lines_for(w, 0, 0, false)
	check(t2.contains("работает"), t2)
	check(t2.contains("%"), t2)

func test_ring_menu_items_own_node() -> void:
	var w: World = TestMaps.chain()
	var items: Array[Dictionary] = RingMenu.items_for(w, 0, 0, 1)
	var labels: Array[String] = []
	for it in items:
		labels.append(it["label"])
	var joined: String = " | ".join(labels)
	check(joined.contains("Агент сюда"), joined)
	check(joined.contains("Сменить пароль"), joined)
	check(joined.contains("Ключи"), joined)
	check(joined.contains("Файрвол"), joined)
	check(joined.contains("Хранилище"), joined)
	check(joined.contains("Ретранслятор"), joined)
	check(joined.contains("IDS"), joined)
	check(joined.contains("Сниффер"), joined)
	# Установленное ПО в меню не предлагается.
	w.nodes[1].install_soft(Defs.SoftType.FIREWALL)
	var items2: Array[Dictionary] = RingMenu.items_for(w, 0, 0, 1)
	var l2: Array[String] = []
	for it in items2:
		l2.append(it["label"])
	check(not " | ".join(l2).contains("Файрвол"))

func test_ring_menu_items_for_neutral_and_enemy() -> void:
	var w: World = TestMaps.chain()
	var on_neutral: Array[Dictionary] = RingMenu.items_for(w, 0, 1, 2)
	var kinds: Array[String] = []
	for it in on_neutral:
		kinds.append(it["label"])
	check(" | ".join(kinds).contains("Захватить"), " | ".join(kinds))
	check(" | ".join(kinds).contains("Флуд"))
	var no_src: Array[String] = []
	for it in RingMenu.items_for(w, 0, -1, 2):
		no_src.append(it["label"])
	check(not " | ".join(no_src).contains("Захватить"), "без источника потоков в items_for нет; источник подбирает source_for")
	check(RingMenu.items_for(w, 0, 1, -1).is_empty())

func test_apply_ring_item_sends_commands() -> void:
	var w: World = TestMaps.chain()
	var ic := InputCtl.new()
	ic.world = w
	ic.camera = CameraCtl.new()
	ic.selected_node = 1
	ic.selected_agent = 2
	ic.ring_target = 1
	ic.apply_item({"label": "x", "kind": "task", "task": Defs.TaskKind.SET_KEYS, "arg": 0})
	ic.ring_target = 2
	ic.ring_source = 1
	ic.apply_item({"label": "y", "kind": "flow", "flow_type": Defs.PacketType.INIT})
	w.step()
	check_eq(Agents.agent_of(w, 0, 2).queue.size(), 1)
	check_eq(w.flows.size(), 1)
	check_eq(w.flows[0].src, 1)
	check_eq(w.flows[0].dst, 2)
	ic.camera.free()
	ic.free()

func test_agent_keys_select_agent() -> void:
	var ic := InputCtl.new()
	ic.world = TestMaps.chain()
	ic.camera = CameraCtl.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_3
	ev.pressed = true
	ic._on_key(ev)
	check_eq(ic.selected_agent, 2)
	ic.camera.free()
	ic.free()

func test_main_scene_with_new_ui_runs() -> void:
	var scene: PackedScene = load("res://view/main.tscn")
	var main: Node = scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	main.input_ctl.selected_node = 0
	main.input_ctl.selected_agent = 1
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(main.card.panel.visible, "карточка должна показываться при выбранном узле")
	main.ring.open(Vector2(400, 300), RingMenu.items_for(main.world, 0, 0, 1))
	check(main.ring.is_open)
	main.ring.close()
	main.queue_free()
