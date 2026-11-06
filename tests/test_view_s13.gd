extends TestCase
## Интерфейс строительства (S13): подменю кольцевого меню, команды из пунктов, линк двумя кликами, карточка.

func _map() -> World:
	var w: World = TestMaps.build({
		"name": "bui", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 300, 0, 0),
			TestMaps.node(2, "machine", 600, 0, 0), TestMaps.node(3, "core", 600, 600, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3)],
	})
	w.players[0].bank = 500
	return w

func _free(c: InputCtl) -> void:
	c.camera.free()
	c.ring.free()
	c.free()

func _ctl(w: World) -> InputCtl:
	var c := InputCtl.new()
	c.world = w
	c.camera = CameraCtl.new()
	c.ring = RingMenu.new()
	return c

func test_own_node_menu_has_build_entry_and_submenu() -> void:
	var w: World = _map()
	w.step()
	var items: Array[Dictionary] = RingMenu.items_for(w, 0, -1, 1)
	var kinds: Array[String] = []
	for it in items:
		kinds.append(String(it["kind"]))
	check(kinds.has("build_menu"))
	var sub: Array[Dictionary] = RingMenu.build_items_for(w, 0, 1)
	check_eq(sub.size(), 5)
	for it in sub:
		check_eq(it["kind"] == "info", false, "всё доступно при деньгах: " + String(it["label"]))
	check(RingMenu.build_items_for(w, 0, 3).is_empty(), "чужому узлу строить нельзя")

func test_submenu_marks_unavailable_with_reason() -> void:
	var w: World = _map()
	w.players[0].bank = 10
	w.step()
	var sub: Array[Dictionary] = RingMenu.build_items_for(w, 0, 1)
	for it in sub:
		check_eq(it["kind"], "info")
		check(String(it["hint"]).contains("байт"), String(it["hint"]))

func test_apply_build_item_sends_command() -> void:
	var w: World = _map()
	var c: InputCtl = _ctl(w)
	c.apply_item({"kind": "build", "build": Defs.BuildKind.CPU, "node": 1, "label": ""})
	w.step()
	w.step()
	check_eq(w.builds.size(), 1)
	check_eq(w.nodes[1].upgrading, 1)
	c.apply_item({"kind": "build", "build": Defs.BuildKind.CPU, "node": 1, "label": ""})
	check_eq(c.fresh_notices().size(), 1, "повторный апгрейд даёт сообщение, а не команду")
	_free(c)

func test_link_build_by_two_clicks() -> void:
	var w: World = _map()
	var c: InputCtl = _ctl(w)
	c.apply_item({"kind": "build_link", "build": Defs.BuildKind.CABLE, "node": 0, "label": ""})
	check_eq(c.link_kind, Defs.BuildKind.CABLE)
	c.finish_link(2)
	check_eq(c.link_kind, -1)
	w.step()
	w.step()
	check_eq(w.builds.size(), 1)
	check_eq(int(w.builds[0][Builds.F_B]), 2)
	c.apply_item({"kind": "build_link", "build": Defs.BuildKind.CABLE, "node": 0, "label": ""})
	c.finish_link(-1)
	check_eq(c.link_kind, -1, "клик в пустоту отменяет режим")
	c.apply_item({"kind": "build_link", "build": Defs.BuildKind.CABLE, "node": 0, "label": ""})
	c.finish_link(3)
	check(not c.fresh_notices().is_empty(), "чужое ядро — отказ с причиной")
	_free(c)

func test_node_card_shows_build_progress_and_upgrades() -> void:
	var w: World = _map()
	w.submit(Command.build(0, 0, Defs.BuildKind.CPU, 1))
	w.run(Defs.TICK_HZ * 15)
	var txt: String = NodeCard.text_for(w, 1, 0)
	check(txt.contains("СТРОЙКА: Апгрейд CPU, 5"), txt)
	check(not NodeCard.text_for(w, 1, 1).contains("СТРОЙКА"), "противник стройку не видит")
	w.run(Defs.TICK_HZ * 16)
	check(NodeCard.text_for(w, 1, 0).contains("CPU ур. 1/2"))

func test_builds_visible_for_viewer() -> void:
	var w: World = _map()
	w.submit(Command.build(0, 0, Defs.BuildKind.CABLE, 0, 2))
	w.submit(Command.build(0, 0, Defs.BuildKind.MACHINE, 2))
	w.run(60)
	check_eq(Builds.visible_to(w, 0).size(), 2)
	check_eq(Builds.visible_to(w, 1).size(), 2, "ядро противника рядом с узлом 2: он наблюдает его и видит стройки")
