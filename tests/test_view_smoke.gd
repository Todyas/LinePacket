extends TestCase
## Дым-тест сцены: грузится, тикает, рисуется без ошибок.

func test_main_scene_runs() -> void:
	var scene: PackedScene = load("res://view/main.tscn")
	check(scene != null, "сцена не загрузилась")
	var main: Node = scene.instantiate()
	Engine.get_main_loop().root.add_child(main)
	await Engine.get_main_loop().process_frame
	await Engine.get_main_loop().process_frame
	check(main.world != null, "мир не создан")
	check_eq(main.world.nodes.size(), 24)
	main._process(0.05)
	check(main.world.tick >= 1, "симуляция не тикает")
	main.queue_free()

func test_shapes_by_type() -> void:
	var g := GraphView.new()
	check_eq(g.shape_points(Defs.NodeType.CORE, Vector2.ZERO, 10.0).size(), 6)
	check_eq(g.shape_points(Defs.NodeType.GATEWAY, Vector2.ZERO, 10.0).size(), 4)
	check_eq(g.shape_points(Defs.NodeType.ROUTER, Vector2.ZERO, 10.0).size(), 4)
	check(g.shape_points(Defs.NodeType.MACHINE, Vector2.ZERO, 10.0).size() > 8)
	g.free()

func test_camera_zoom_clamped() -> void:
	var cam := CameraCtl.new()
	for i in 100:
		cam.zoom = Vector2(cam.zoom.x * 1.2, cam.zoom.y * 1.2)
		cam.zoom_at(Vector2.ZERO, 1.2)
	check(cam.zoom.x <= CameraCtl.ZOOM_MAX + 0.001)
	cam.free()
