extends TestCase

func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev

func test_parse_seed() -> void:
	check_eq(GameConfig.parse_seed("42"), 42)
	check_eq(GameConfig.parse_seed("  7 "), 7)
	check_eq(GameConfig.parse_seed(""), 1)
	check_eq(GameConfig.parse_seed("abc", 5), 5)
	check_eq(GameConfig.parse_seed("-9"), 9)
	check_eq(GameConfig.parse_seed("0"), 1)
	check_eq(GameConfig.parse_seed("99999999999999"), GameConfig.SEED_MAX)

func test_hints_cover_every_packet_soft_and_task() -> void:
	for t in Defs.PacketType.values():
		check(Hints.packet_type(t) != "", "нет подсказки для пакета %d" % t)
	for s in Defs.PLAYER_SOFT:
		check(Hints.soft(s) != "", "нет подсказки для ПО %d" % s)
	for k in Defs.TaskKind.values():
		check(Hints.task(k, Defs.SoftType.FIREWALL) != "", "нет подсказки для задачи %d" % k)

func test_every_ring_item_has_a_hint() -> void:
	var w: World = TestMaps.siege()
	w.players[0].bank = 500
	for sel in w.nodes.size():
		for tgt in w.nodes.size():
			for item in RingMenu.items_for(w, 0, sel, tgt):
				check(Hints.ring_item(item) != "", "нет подсказки у пункта %s" % item["label"])

func test_node_hint_respects_fog() -> void:
	var w: World = TestMaps.siege()
	var far: int = -1
	for n in w.nodes:
		if Knowledge.level(w, 0, n.id) == Knowledge.Level.SILHOUETTE:
			far = n.id
	check(far >= 0, "нужен узел за туманом")
	var t: String = Hints.node(w, 0, far)
	check(not t.contains("Игрок"), t)
	check(t.contains("Неизвестно"), t)
	var own: String = Hints.node(w, 0, w.players[0].core_node)
	check(own.contains("Игрок 1"), own)
	check(own.contains("Ядро"), own)

func test_hover_regions() -> void:
	var w: World = TestMaps.siege()
	var n: NodeState = w.nodes[w.players[0].core_node]
	var at_node: String = HoverTip.text_at(w, 0, 0, Vector2(400, 400), Vector2(n.x, n.y), 1.0, Defs.PacketType.FLOOD, -1)
	check(at_node.contains("Ядро"), at_node)
	var empty: String = HoverTip.text_at(w, 0, 0, Vector2(400, 400), Vector2(-9000, -9000), 1.0, Defs.PacketType.FLOOD, -1)
	check_eq(empty, "")
	var hud_tip: String = HoverTip.text_at(w, 0, 0, Vector2(300, 10), Vector2.ZERO, 1.0, Defs.PacketType.SCAN, -1)
	check(hud_tip.contains("SCAN"), hud_tip)
	var agent_tip: String = HoverTip.text_at(w, 0, 0, Vector2(100, 800), Vector2.ZERO, 1.0, Defs.PacketType.FLOOD, -1)
	check(agent_tip.contains("Очередь пуста"), agent_tip)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CHANGE_PASSWORD, w.players[0].core_node))
	w.step()
	var busy: String = HoverTip.text_at(w, 0, 0, Vector2(100, 800), Vector2.ZERO, 1.0, Defs.PacketType.FLOOD, -1)
	check(busy.contains("пароль"), busy)

func test_flow_hint_names_type_and_rate() -> void:
	var f := FlowState.new()
	f.ptype = Defs.PacketType.FLOOD
	f.rate = 7
	var t: String = Hints.flow(f)
	check(t.contains("FLOOD") and t.contains("7"), t)

func test_menu_applies_config() -> void:
	var menu: Menu = load("res://view/menu.tscn").instantiate()
	Engine.get_main_loop().root.add_child(menu)
	await Engine.get_main_loop().process_frame
	menu.seed_edit.text = "777"
	menu.side_pick.selected = 1
	menu.apply_config()
	check_eq(GameConfig.seed_value, 777)
	check_eq(GameConfig.player_side, 1)
	menu.seed_edit.text = "мусор"
	menu.apply_config()
	check_eq(GameConfig.seed_value, 1)
	GameConfig.player_side = 0
	GameConfig.seed_value = 1
	menu.queue_free()

func test_space_and_escape_toggle_pause() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	check(not main.paused)
	main.input_ctl._on_key(_key(KEY_SPACE))
	check(main.paused, "пробел ставит паузу")
	check(main.pause_screen.visible)
	var t0: int = main.world.tick
	for i in 40:
		main._process(0.05)
	check_eq(main.world.tick, t0, "в паузе тики стоят")
	main.input_ctl._on_key(_key(KEY_ESCAPE))
	check(not main.paused, "Esc снимает паузу")
	for i in 10:
		main._process(0.05)
	check(main.world.tick > t0, "после паузы тики идут")
	# Esc сначала снимает выбор, и только потом открывает паузу.
	main.input_ctl.selected_node = 2
	main.input_ctl._on_key(_key(KEY_ESCAPE))
	check(not main.paused)
	check_eq(main.input_ctl.selected_node, -1)
	main.input_ctl._on_key(_key(KEY_ESCAPE))
	check(main.paused, "Esc без выбора открывает паузу")
	main.queue_free()

func test_paused_input_is_ignored() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	main.set_paused(true)
	var ev := InputEventKey.new()
	ev.keycode = KEY_S
	ev.pressed = true
	main.input_ctl._on_key(ev)
	check(main.input_ctl.flow_type != Defs.PacketType.SCAN, "в паузе режимы не меняются")
	main.queue_free()

func test_game_has_bot_for_opponent() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	check(main.bot != null, "бот создан")
	for i in 600:
		main._process(0.05)
	var bot_cmds: int = 0
	var human_cmds: int = 0
	for c in main.world.applied_log:
		if c.player == 1:
			bot_cmds += 1
		else:
			human_cmds += 1
	check(bot_cmds > 0, "бот играет за вторую сторону")
	check_eq(human_cmds, 0, "за человека бот не ходит")
	main.queue_free()

func test_debug_hotkeys_guarded_by_debug_build() -> void:
	# В release-сборке F2/F3/F4 не работают: охрана стоит в самих обработчиках.
	for f in ["res://view/input_ctl.gd", "res://view/main.gd", "res://view/debug_overlay.gd"]:
		var src: String = FileAccess.get_file_as_string(f)
		for line in src.split("\n"):
			if line.contains("KEY_F2") or line.contains("KEY_F3") or line.contains("KEY_F4"):
				if line.contains("keycode"):
					check(line.contains("OS.is_debug_build()"), "%s: %s" % [f, line.strip_edges()])

func test_end_screen_shows_time_captures_and_earned() -> void:
	var w: World = TestMaps.siege()
	w.winner = 1
	w.finished_tick = 20 * 125
	w.players[0].captures = 3
	w.players[0].earned_total = 77
	var t: String = EndScreen.text_for(w, 0)
	check(t.contains("ПОРАЖЕНИЕ"), t)
	check(t.contains("2:05"), t)
	check(t.contains("захватов 3"), t)
	check(t.contains("заработано 77"), t)
