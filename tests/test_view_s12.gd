extends TestCase

func _labels(items: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for it in items:
		out.append(String(it["label"]))
	return " | ".join(out)

func _world() -> World:
	return TestMaps.build({
		"name": "rview", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "router", 300, 0),
			TestMaps.node(2, "machine", 600, 0), TestMaps.node(3, "core", 900, 0, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3)],
	})

func test_ring_menu_neutral_router_offers_take() -> void:
	var w: World = _world()
	w.step()
	var t: String = _labels(RingMenu.items_for(w, 0, 0, 1))
	check(t.contains("Взять управление (30 Б, 15 с)"), t)

func test_ring_menu_own_router_offers_rule_toggle() -> void:
	var w: World = _world()
	Economy.capture_node(w, w.nodes[1], 0)
	w.step()
	check(_labels(RingMenu.items_for(w, 0, 0, 1)).contains("Закрыть транзит"))
	w.nodes[1].router_open = false
	check(_labels(RingMenu.items_for(w, 0, 0, 1)).contains("Открыть транзит"))

func test_apply_router_rule_item_sends_command() -> void:
	var w: World = _world()
	Economy.capture_node(w, w.nodes[1], 0)
	var ic := InputCtl.new()
	ic.world = w
	ic.camera = CameraCtl.new()
	ic.ring_target = 1
	ic.apply_item({"label": "x", "kind": "router_rule", "open": false})
	w.step()
	check(not w.nodes[1].router_open)
	ic.camera.free()
	ic.free()

func test_card_shows_rule_and_hints_exist() -> void:
	var w: World = _world()
	Economy.capture_node(w, w.nodes[1], 0)
	w.nodes[1].router_open = false
	w.step()
	check(NodeCard.text_for(w, 1, 0).contains("ЗАКРЫТ"))
	check(Hints.ring_item({"kind": "router_rule", "open": false}).contains("Закрыть"))
	check(Hints.task(Defs.TaskKind.TAKE_ROUTER).contains("маршрутизатор"))
	check(Hints.node(w, 0, 1).contains("Маршрутизатор"))

func test_graph_view_draws_closed_router() -> void:
	var w: World = _world()
	Economy.capture_node(w, w.nodes[1], 0)
	w.nodes[1].router_open = false
	w.step()
	var gv := GraphView.new()
	gv.world = w
	gv.draw_nodes = true
	gv.viewer = 0
	Engine.get_main_loop().root.add_child(gv)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(gv.is_inside_tree())
	gv.queue_free()
