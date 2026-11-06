extends SceneTree
## Снимок главной сцены для проверки читаемости (нужен дисплей: xvfb-run).
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 -s tools/screenshot.gd -- out.png [секунд]

var _frames: int = 0
var _main: Node
var _out: String = "user://shot.png"
var _target: int = 360
var _scenario: String = "flood"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_target = int(args[1]) * 60
	if args.size() > 2:
		_scenario = args[2]
	if _scenario == "menu":
		root.add_child(load("res://view/menu.tscn").instantiate())
		return
	_main = load("res://view/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _scenario == "menu":
		if _frames >= 10:
			root.get_texture().get_image().save_png(_out)
			quit(0)
		return false
	if _frames == 5 and _main.world != null:
		_setup_scenario()
	if _scenario == "ui" and _frames == _target - 2:
		_main.input_ctl.ring_target = 3
		_main.ring.open(Vector2(420, 640), RingMenu.items_for(_main.world, 0, 2, 3))
	if _scenario == "pan" and _frames > 20:
		_main.camera.position = Vector2(800.0 + 450.0 * sin(float(_frames) * 0.05), 450.0)   # качаем камеру: пакеты не должны пропадать
	if _scenario == "tip" and _frames == _target - 2:
		var nd: NodeState = _main.world.nodes[_main.world.players[0].core_node]
		var pos: Vector2 = _main.camera.get_canvas_transform() * Vector2(nd.x, nd.y)
		_main.tip.show_text(Hints.node(_main.world, 0, nd.id), pos)
	if _scenario == "pause" and _frames == _target - 2:
		_main.set_paused(true)
	if _frames >= _target:
		_main.hud._process(0.0)
		var img: Image = root.get_texture().get_image()
		img.save_png(_out)
		print("SAVED ", _out, " tick=", _main.world.tick, " in_flight=", _main.world.pool.alive_count, " drops=", _main.world.total_drops())
		quit(0)
	return false

func _setup_scenario() -> void:
	# Демонстрационные роли — как если бы игроки назначили их мышью.
	var w: World = _main.world
	match _scenario:
		"eco":
			w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 2))
			w.submit(Command.set_role(0, 0, 1, Defs.Role.CAPTURE, 3))
			w.submit(Command.set_role(0, 300, 1, Defs.Role.CAPTURE, 4))
			w.submit(Command.set_role(0, 400, 2, Defs.Role.CAPTURE, 5))
			w.submit(Command.set_role(1, 0, 10, Defs.Role.CAPTURE, 12))
			w.submit(Command.set_role(1, 0, 11, Defs.Role.CAPTURE, 13))
			w.submit(Command.set_role(1, 100, 11, Defs.Role.CAPTURE, 14))
		"ui":
			w.players[0].bank = 150
			w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 2))
			w.submit(Command.set_role(0, 0, 1, Defs.Role.CAPTURE, 3))
			w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.INSTALL_SOFT, 1, Defs.SoftType.FIREWALL))
			w.submit(Command.queue_task(0, 0, 0, Defs.TaskKind.SET_KEYS, 2))
			w.submit(Command.queue_task(0, 0, 1, Defs.TaskKind.CHANGE_PASSWORD, 3))
			w.submit(Command.queue_task(0, 0, 1, Defs.TaskKind.SET_KEYS, 1))
			_main.input_ctl.selected_node = 2
			_main.input_ctl.selected_agent = 1
		"fog":
			# Дозор до границы тумана: снимки соседей цели рядом с силуэтами остальной карты.
			w.submit(Command.set_role(0, 0, 0, Defs.Role.WATCH))
			w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 2))
			_main.input_ctl.selected_node = 5
		"war":
			# Витрина шкал атаки: заражение, подбор пароля, лежащая машина, экран итогов.
			for i in [1, 2, 3]:
				w.nodes[i].owner = 0
				w.nodes[i].control = Defs.CONTROL_MAX
			w.nodes[2].infect[1] = 62000
			w.nodes[3].brute[1] = 45000
			w.nodes[3].infect[1] = 20000
			w.nodes[1].down = true
			_main.input_ctl.selected_node = 2
			w.winner = 1
			w.finished_tick = 20 * 342
		_:
			w.submit(Command.set_role(0, 0, 0, Defs.Role.PRESSURE, 22))
			w.submit(Command.set_role(0, 0, 1, Defs.Role.PRESSURE, 17))
			w.submit(Command.set_role(0, 0, 0, Defs.Role.PRESSURE, 20))
			w.submit(Command.set_role(1, 0, 10, Defs.Role.PRESSURE, 4))
