extends TestCase

func test_hud_text() -> void:
	var w: World = TestMaps.eco_fan(0, 0)
	w.players[0].bank = 123
	w.players[0].income_hist[0] = 8
	var t: String = Hud.text_for(w, 0, Defs.PacketType.INIT)
	check(t.contains("123"), t)
	check(t.contains("+8/с"), t)
	check(t.contains("INIT"), t)

func test_control_fill_and_capture_ring_draw_without_errors() -> void:
	# Рисование узлов с заливкой, кольцом захвата и буфером не должно давать ошибок скриптов.
	var w: World = TestMaps.chain()
	w.nodes[2].capture[0] = 12
	w.nodes[1].control = 60000
	w.nodes[1].buffer = 5
	var scene: PackedScene = load("res://view/main.tscn")
	var main: Node = scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	main.nodes_view.world = w
	main.nodes_view.queue_redraw()
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(main.nodes_view != null)
	main.queue_free()

func test_init_mode_key_enabled() -> void:
	check(Defs.PLAYER_FLOW_TYPES.has(Defs.PacketType.INIT))
	var ic := InputCtl.new()
	ic.world = TestMaps.pair(200)
	ic.camera = CameraCtl.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_I
	ev.pressed = true
	ic._on_key(ev)
	check_eq(ic.flow_type, Defs.PacketType.INIT)
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_S
	ev2.pressed = true
	ic._on_key(ev2)
	check_eq(ic.flow_type, Defs.PacketType.SCAN)
	ic.camera.free()
	ic.free()
