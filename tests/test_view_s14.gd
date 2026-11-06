extends TestCase
## Интерфейс S14: выбор карты в меню, панель пяти агентов, наём из меню и клавишей.

func test_map_list_and_default_is_large() -> void:
	check_eq(GameConfig.MAPS.size(), 2)
	check_eq(GameConfig.map_index, 1, "по умолчанию Большая Дуэль")
	check(GameConfig.map_path().ends_with("duel_large.json"))
	for m in GameConfig.MAPS:
		check(FileAccess.file_exists(String(m["path"])), String(m["path"]))

func test_menu_map_pick_sets_config() -> void:
	var m := Menu.new()
	m._ready()
	m.map_pick.selected = 0
	m.apply_config()
	check_eq(GameConfig.map_index, 0)
	check(GameConfig.map_path().ends_with("duel.json"))
	GameConfig.map_index = 1
	m.free()

func test_agent_panel_shows_hire_slot() -> void:
	var w: World = MapLoader.load_file("res://maps/duel_large.json", 1)["world"]
	var txt: String = AgentPanel.lines_for(w, 0, 3, false)
	check(txt.contains("H") and txt.contains("300"), txt)
	check(AgentPanel.lines_for(w, 0, 4, false).contains("нужно нанять агента 4"))
	w.players[0].bank = 500
	w.submit(Command.hire_agent(0, 0))
	w.run(30)
	check(AgentPanel.lines_for(w, 0, 3, false).contains("наём"))
	w.run(Defs.TICK_HZ * 31)
	check(AgentPanel.lines_for(w, 0, 3, false).contains("Агент 4"))
	check(AgentPanel.lines_for(w, 0, 3, false).contains("на "))

func test_hire_from_core_menu_and_key() -> void:
	var w: World = MapLoader.load_file("res://maps/duel_large.json", 1)["world"]
	w.players[0].bank = 400
	w.step()
	var items: Array[Dictionary] = RingMenu.items_for(w, 0, -1, 0)
	var kinds: Array[String] = []
	for it in items:
		kinds.append(String(it["kind"]))
	check(kinds.has("hire"), "на своём ядре есть «Нанять агента»")
	var c := InputCtl.new()
	c.world = w
	c.camera = CameraCtl.new()
	c.ring = RingMenu.new()
	c.apply_item({"kind": "hire", "label": ""})
	w.step()
	w.step()
	check(w.players[0].hire_left > 0)
	c.hire_agent()
	check(not c.fresh_notices().is_empty(), "повторный наём — сообщение, не команда")
	c.camera.free()
	c.ring.free()
	c.free()
	var machine_items: Array[Dictionary] = RingMenu.items_for(w, 0, -1, 1)
	for it in machine_items:
		check(it["kind"] != "hire", "на машине нанять нельзя")
