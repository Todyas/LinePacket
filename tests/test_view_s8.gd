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
	var at_node: String = HoverTip.text_at(w, 0, 0, Vector2(400, 400), Vector2(n.x, n.y), 1.0, Defs.Role.PRESSURE, -1)
	check(at_node.contains("Ядро"), at_node)
	var empty: String = HoverTip.text_at(w, 0, 0, Vector2(400, 400), Vector2(-9000, -9000), 1.0, Defs.Role.PRESSURE, -1)
	check_eq(empty, "")
	var hud_tip: String = HoverTip.text_at(w, 0, 0, Vector2(300, 10), Vector2.ZERO, 1.0, Defs.Role.WATCH, -1)
	check(hud_tip.contains("Дозор"), hud_tip)
	var agent_tip: String = HoverTip.text_at(w, 0, 0, Vector2(100, 800), Vector2.ZERO, 1.0, Defs.Role.PRESSURE, -1)
	check(agent_tip.contains("Очередь пуста"), agent_tip)
	w.players[0].bank = 100
	w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.CHANGE_PASSWORD, w.players[0].core_node))
	w.step()
	var busy: String = HoverTip.text_at(w, 0, 0, Vector2(100, 800), Vector2.ZERO, 1.0, Defs.Role.PRESSURE, -1)
	check(busy.contains("пароль"), busy)

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
	main.set_speed_index(2)
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
	ev.keycode = KEY_T
	ev.pressed = true
	main.input_ctl._on_key(ev)
	check(main.input_ctl.role_mode != Defs.Role.WATCH, "в паузе режимы не меняются")
	main.queue_free()

func test_game_has_bot_for_opponent() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	main.set_speed_index(2)
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

func test_speed_keys_scale_tick_rate() -> void:
	var main: Node = load("res://view/main.tscn").instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	main.set_speed_index(2)
	var t0: int = main.world.tick
	for i in 20:
		main._process(0.05)
	var full: int = main.world.tick - t0
	main.input_ctl._on_key(_key(KEY_MINUS))
	check_eq(main.speed_percent, 50, "минус замедляет")
	t0 = main.world.tick
	for i in 20:
		main._process(0.05)
	var half: int = main.world.tick - t0
	check(half * 2 <= full + 1 and half * 2 >= full - 1, "вдвое медленнее: %d против %d" % [half, full])
	main.input_ctl._on_key(_key(KEY_EQUAL))
	main.input_ctl._on_key(_key(KEY_EQUAL))
	check_eq(main.speed_percent, 200)
	main.input_ctl._on_key(_key(KEY_EQUAL))
	check_eq(main.speed_percent, 200, "быстрее максимума не бывает")
	check(Hud.text_for(main.world, 0, Defs.PacketType.FLOOD, 50).contains("×0.5"))
	GameConfig.speed_index = Defs.GAME_SPEED_DEFAULT_INDEX
	main.queue_free()

func test_ring_menu_does_not_depend_on_selection() -> void:
	# ПКМ по узлу даёт одно и то же, выбран ли какой-то узел левой кнопкой или нет.
	var w: World = TestMaps.scout()
	w.players[0].bank = 100
	for tgt in w.nodes.size():
		var a: Array[String] = []
		var b: Array[String] = []
		for item in RingMenu.items_for(w, 0, RingMenu.source_for(w, 0, -1, tgt), tgt):
			a.append(item["label"])
		for item in RingMenu.items_for(w, 0, RingMenu.source_for(w, 0, 0, tgt), tgt):
			b.append(item["label"])
		check(not a.is_empty(), "меню для узла %d не пустое" % tgt)
		if tgt != 0:
			check_eq(a, b, "узел %d" % tgt)

func test_ring_menu_has_flow_items_without_selection() -> void:
	var w: World = TestMaps.scout()
	var src: int = RingMenu.source_for(w, 0, -1, 1)
	check_eq(src, 0, "ближайший свой к цели")
	var labels: Array[String] = []
	for item in RingMenu.items_for(w, 0, src, 1):
		labels.append(item["label"])
	check(labels.any(func(l: String) -> bool: return l.begins_with("Захват")), str(labels))

func test_ring_menu_explains_empty_cases() -> void:
	var w: World = TestMaps.scout()
	var far: Array[Dictionary] = RingMenu.items_for(w, 0, 0, 3)
	check(not far.is_empty())
	var sw: World = TestMaps.diamond()
	for item in RingMenu.items_for(w, 0, 0, 3):
		check(Hints.ring_item(item) != "")
	check(sw != null)

func test_bot_does_not_expand_onto_enemy_half() -> void:
	var w: World = MapLoader.load_file("res://maps/duel.json", 3)["world"]
	var bot := Bot.new(BotView.new(w, 1), 3)
	for i in 20 * 120:
		bot.act()
		w.step()
	var mine_core: int = w.players[1].core_node
	var their_core: int = w.players[0].core_node
	for n in w.nodes:
		if n.owner == 1:
			check(Knowledge.hops(w, n.id, mine_core) < Knowledge.hops(w, n.id, their_core), "%s на чужой половине" % Names.node_label(n))

func test_packet_multimeshes_have_manual_cull_bounds() -> void:
	# Без своих границ движок отсекает пакеты, когда камера уводит начало координат с экрана.
	var pv := PacketView.new()
	pv._ready()
	for mm in pv._mms:
		var box: AABB = mm.custom_aabb
		check(box.size.x >= 20000.0 and box.has_point(Vector3(1500, 900, 0)) and box.has_point(Vector3(-500, -500, 0)), "границы мультимеша малы: %s" % str(box))
	pv.free()
