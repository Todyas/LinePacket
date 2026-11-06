extends TestCase

func _labels(items: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for it in items:
		out.append(String(it["label"]))
	return " | ".join(out)

func test_ring_menu_on_enemy_machine_offers_attacks() -> void:
	var w: World = TestMaps.siege()
	var items: Array[Dictionary] = RingMenu.items_for(w, 1, 3, 2)
	var t: String = _labels(items)
	check(t.contains("PAYLOAD"), t)
	check(t.contains("FLOOD"), t)
	check(t.contains("INIT"), t)
	check(t.contains("Украсть ключ"), t)
	check(t.contains("Выкачать буфер"), t)
	check(not t.contains("Сменить пароль"), "чужой пароль так не сменить: " + t)

func test_ring_menu_hides_password_cracking_for_keys_or_known_access() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].access_mode = Defs.AccessMode.KEYS
	Knowledge.update(w)    # игрок видит новое состояние соседней машины
	check(not _labels(RingMenu.items_for(w, 1, 3, 2)).contains("Подбор"))
	w.nodes[2].access_mode = Defs.AccessMode.PASSWORD_WEAK
	w.nodes[2].access_mask |= 2
	Knowledge.update(w)
	check(not _labels(RingMenu.items_for(w, 1, 3, 2)).contains("Подбор"))

func test_ring_menu_own_node_clean_and_entrench() -> void:
	var w: World = TestMaps.siege()
	check(not _labels(RingMenu.items_for(w, 0, 0, 2)).contains("Вычистить"))
	w.nodes[2].infect[1] = 30000
	check(_labels(RingMenu.items_for(w, 0, 0, 2)).contains("Вычистить вирус"))
	check(not _labels(RingMenu.items_for(w, 0, 0, 2)).contains("Закрепиться"))
	Economy.takeover(w, w.nodes[2], 1)
	check(_labels(RingMenu.items_for(w, 1, 3, 2)).contains("Закрепиться"))
	w.step()    # знания обновляются раз в тик
	check(_labels(RingMenu.items_for(w, 0, 0, 2)).contains("Захватить"), "прошлый владелец по старым ключам может вернуть машину")

func test_node_card_shows_down_infection_and_brute() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].down = true
	w.nodes[2].infect[1] = 40000
	w.nodes[2].brute[1] = 25000
	var t: String = NodeCard.text_for(w, 2)
	check(t.contains("ЛЕЖИТ"), t)
	check(t.contains("Заражение (Игрок 2): 40%"), t)
	check(t.contains("Подбор пароля (Игрок 2): 25%"), t)
	# Другой игрок (не владелец, не атакующий) чужих шкал не видит.
	var spy: String = NodeCard.text_for(w, 2, 0)
	check(spy.contains("Заражение"), "владелец видит заражение")
	check(NodeCard.text_for(w, 2, 1).contains("Подбор"), "атакующий видит свою шкалу подбора")

func test_end_screen_text() -> void:
	var w: World = TestMaps.rush()
	check_eq(EndScreen.text_for(w, 0), "")
	w.winner = 1
	w.finished_tick = 20 * 75
	var t0: String = EndScreen.text_for(w, 0)
	check(t0.contains("ПОРАЖЕНИЕ"), t0)
	check(t0.contains("1:15"), t0)
	check(EndScreen.text_for(w, 1).contains("ПОБЕДА"))

func test_hud_names_payload_mode() -> void:
	check_eq(Hud.role_mode_name(Defs.Role.INFECT), "Заражение [E]")

func test_attack_meters_and_end_screen_draw_without_errors() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].down = true
	w.nodes[2].infect[1] = 50000
	w.nodes[2].brute[1] = 50000
	var scene: PackedScene = load("res://view/main.tscn")
	var main: Node = scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	main.nodes_view.world = w
	main.end_screen.world = w
	w.winner = 0
	w.finished_tick = 100
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(main.end_screen._panel.visible, "после победы виден экран итогов")
	main.queue_free()

func test_debug_side_switch() -> void:
	var ic := InputCtl.new()
	ic.world = TestMaps.siege()
	ic.camera = CameraCtl.new()
	ic.selected_node = 2
	var ev := InputEventKey.new()
	ev.keycode = KEY_F2
	ev.pressed = true
	ic._on_key(ev)
	if OS.is_debug_build():
		check_eq(ic.local_player, 1)
		check_eq(ic.selected_node, -1)
		ic._on_key(ev)
		check_eq(ic.local_player, 0)
	else:
		check_eq(ic.local_player, 0, "в релизе F2 не работает")
	ic.camera.free()
	ic.free()
