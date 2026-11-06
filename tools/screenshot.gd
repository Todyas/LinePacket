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
	_main = load("res://view/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5 and _main.world != null:
		_setup_scenario()
	if _frames >= _target:
		_main.hud._process(0.0)
		var img: Image = root.get_texture().get_image()
		img.save_png(_out)
		print("SAVED ", _out, " tick=", _main.world.tick, " in_flight=", _main.world.pool.alive_count, " drops=", _main.world.total_drops())
		quit(0)
	return false

func _setup_scenario() -> void:
	# Демонстрационные потоки — как если бы игроки запустили их мышью.
	var w: World = _main.world
	match _scenario:
		"eco":
			w.submit(Command.start_flow(0, 0, 0, 2, Defs.PacketType.INIT, 12))
			w.submit(Command.start_flow(0, 0, 1, 3, Defs.PacketType.INIT, 12))
			w.submit(Command.start_flow(0, 300, 1, 4, Defs.PacketType.INIT, 20))
			w.submit(Command.start_flow(0, 400, 2, 5, Defs.PacketType.INIT, 6))
			w.submit(Command.start_flow(1, 0, 10, 12, Defs.PacketType.INIT, 12))
			w.submit(Command.start_flow(1, 0, 11, 13, Defs.PacketType.INIT, 12))
			w.submit(Command.start_flow(1, 100, 11, 14, Defs.PacketType.INIT, 9))
		_:
			w.submit(Command.start_flow(0, 0, 0, 22, Defs.PacketType.FLOOD, 12))
			w.submit(Command.start_flow(0, 0, 1, 17, Defs.PacketType.FLOOD, 20))
			w.submit(Command.start_flow(0, 0, 0, 20, Defs.PacketType.FLOOD, 20))
			w.submit(Command.start_flow(1, 0, 10, 4, Defs.PacketType.FLOOD, 8))
