extends TestCase

func _ctl(w: World) -> InputCtl:
	var ic := InputCtl.new()
	ic.world = w
	ic.camera = CameraCtl.new()
	return ic

func _free(ic: InputCtl) -> void:
	ic.camera.free()
	ic.free()

func _grow(w: World) -> void:
	# Игрок 0 владеет ядром, 1 и 2 в siege; дополнительно машины делает захват.
	Economy.capture_node(w, w.nodes[2], 0)

func test_box_selects_only_own_role_capable_nodes() -> void:
	var w: World = TestMaps.siege()
	var ic := _ctl(w)
	ic.select_in_rect(Vector2(-50, -50), Vector2(1000, 1000), false)
	# Свои для игрока 0: ядро 0 и машина 2. Шлюз 1 роли не имеет, чужие 3, 4, 5 не выделяются.
	check_eq(ic.selection, [0, 2])
	ic.select_in_rect(Vector2(350, -50), Vector2(450, 50), false)
	check_eq(ic.selection, [2], "рамка вокруг одной машины")
	check_eq(ic.selected_node, 2)
	_free(ic)

func test_shift_adds_to_selection() -> void:
	var w: World = TestMaps.siege()
	var ic := _ctl(w)
	ic.select_in_rect(Vector2(-50, -50), Vector2(50, 50), false)
	check_eq(ic.selection, [0])
	ic.select_in_rect(Vector2(350, -50), Vector2(450, 50), true)
	check_eq(ic.selection, [0, 2])
	ic.select_in_rect(Vector2(350, -50), Vector2(450, 50), false)
	check_eq(ic.selection, [2], "без Shift выделение заменяется")
	_free(ic)

func test_click_selects_and_shift_toggles() -> void:
	var w: World = TestMaps.siege()
	var ic := _ctl(w)
	ic._select_click(0, false)
	ic._select_click(2, true)
	check_eq(ic.selection, [0, 2])
	ic._select_click(0, true)
	check_eq(ic.selection, [2], "Shift по выделенной снимает её")
	ic._select_click(3, false)
	check(ic.selection.is_empty(), "клик по чужому сбрасывает выделение")
	check_eq(ic.selected_node, 3, "но карточка чужого узла открывается")
	_free(ic)

func test_group_order_sets_role_for_every_machine() -> void:
	var w: World = _line_world()
	var ic := _ctl(w)
	ic.selection = [1, 2, 3]
	ic.selected_node = -1
	var sent: int = ic.order_role(ic._group_for(2), Defs.Role.PRESSURE, 4)
	check_eq(sent, 3)
	w.step()
	for i in [1, 2, 3]:
		check_eq(w.nodes[i].role, Defs.Role.PRESSURE)
		check_eq(w.nodes[i].role_target, 4)
	_free(ic)

## Цепочка 0–1–2–3–4–5–6: машины 1, 2, 3 принадлежат игроку 0, чужая цель — 4 (в 1 хопе от 3, в 3 от 1).
func _line_world() -> World:
	var nodes: Array = [TestMaps.node(0, "core", 0, 0, 0)]
	for i in range(1, 4):
		nodes.append(TestMaps.node(i, "machine", i * 200, 0))
	nodes.append(TestMaps.node(4, "machine", 800, 0))
	nodes.append(TestMaps.node(5, "machine", 1000, 0))
	nodes.append(TestMaps.node(6, "core", 1200, 0, 1))
	var links: Array = []
	for i in 6:
		links.append(TestMaps.link(i, i + 1))
	var w: World = TestMaps.build({"name": "chain7", "players": 2, "nodes": nodes, "links": links})
	for i in range(1, 4):
		Economy.capture_node(w, w.nodes[i], 0)
	Economy.capture_node(w, w.nodes[4], 1)
	return w

func test_far_machines_refuse_and_report() -> void:
	var w: World = _line_world()
	var ic := _ctl(w)
	# Цель 5 (чужая машина в 4 хопах от 1, в 3 от 2, в 2 от 3). Ядро 0 далеко (5 хопов).
	Economy.capture_node(w, w.nodes[5], 1)
	ic.selection = [0, 1, 2, 3]
	var sent: int = ic.order_role([0, 1, 2, 3], Defs.Role.PRESSURE, 5)
	check_eq(sent, 2, "дотянулись только 2 и 3")
	var notes: Array[String] = ic.fresh_notices()
	check_eq(notes.size(), 2)
	check(notes[0].contains("дальше 3 хопов"), notes[0])
	w.step()
	check_eq(w.nodes[1].role, Defs.Role.WORK, "не дотянувшийся остаётся в прежней роли")
	check_eq(w.nodes[2].role, Defs.Role.PRESSURE)
	_free(ic)

func test_notices_expire() -> void:
	var w: World = _line_world()
	var ic := _ctl(w)
	ic.add_notice("тест")
	check_eq(ic.fresh_notices().size(), 1)
	w.run(InputCtl.NOTICE_TICKS + 5)
	check_eq(ic.fresh_notices().size(), 0)
	_free(ic)

func test_ring_menu_role_applies_to_whole_selection() -> void:
	var w: World = _line_world()
	var ic := _ctl(w)
	ic.selection = [2, 3]
	ic.ring_target = 4
	ic.ring_source = 3
	ic.apply_item({"label": "x", "kind": "role", "role": Defs.Role.INFECT})
	w.step()
	check_eq(w.nodes[2].role, Defs.Role.INFECT)
	check_eq(w.nodes[3].role, Defs.Role.INFECT)
	_free(ic)

func test_own_role_item_applies_to_group_when_target_selected() -> void:
	var w: World = _line_world()
	var ic := _ctl(w)
	for i in [1, 2]:
		TestMaps.engage(w, 0, i, 4, Defs.PacketType.FLOOD)
	ic.selection = [1, 2]
	ic.ring_target = 1
	ic.apply_item({"label": "w", "kind": "own_role", "role": Defs.Role.WORK})
	w.step()
	check_eq(w.nodes[1].role, Defs.Role.WORK)
	check_eq(w.nodes[2].role, Defs.Role.WORK)
	_free(ic)

func test_escape_clears_selection() -> void:
	var w: World = _line_world()
	var ic := _ctl(w)
	ic.selection = [1, 2]
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	ic._on_key(ev)
	check(ic.selection.is_empty())
	_free(ic)

func test_hud_counts_work_and_combat_and_reconfig() -> void:
	var w: World = _line_world()
	var t0: String = Hud.text_for(w, 0, Defs.Role.PRESSURE)
	check(t0.contains("В работе 4 / в бою 0"), t0)
	TestMaps.engage(w, 0, 3, 4, Defs.PacketType.FLOOD)
	var t1: String = Hud.text_for(w, 0, Defs.Role.PRESSURE)
	check(t1.contains("В работе 3 / в бою 1"), t1)
	w.submit(Command.set_role(0, w.tick, 2, Defs.Role.WATCH))
	w.step()
	check(Hud.text_for(w, 0, Defs.Role.PRESSURE).contains("перенастройка: 1"))

func test_graph_view_draws_selection_reconf_and_watch_zone() -> void:
	var w: World = _line_world()
	w.submit(Command.set_role(0, 0, 3, Defs.Role.WATCH))
	w.run(Defs.ROLE_RECONF_TICKS + 5)
	w.submit(Command.set_role(0, w.tick, 1, Defs.Role.PRESSURE, 4))
	w.run(10)
	var gv := GraphView.new()
	gv.world = w
	gv.draw_nodes = true
	gv.selection = [1, 2]
	gv.viewer = 0
	Engine.get_main_loop().root.add_child(gv)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(gv.is_inside_tree())
	gv.queue_free()

func test_enemy_role_visible_in_observed_neighbour_snapshot() -> void:
	var w: World = TestMaps.siege()
	TestMaps.engage(w, 1, 3, 2, Defs.PacketType.FLOOD)
	w.step()
	var sn: NodeSnap = Knowledge.snap(w, 0, 3)
	check(sn != null, "сосед своей машины наблюдается")
	check_eq(sn.role, Defs.Role.PRESSURE)
	check_eq(sn.role_target, 2)
	var far: World = TestMaps.scout()
	check_eq(Knowledge.snap(far, 0, 3), null, "дальнее ядро противника игрок не знает")
