extends SceneTree
## Снимок главной сцены для проверки читаемости (нужен дисплей: xvfb-run).
## xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 -s tools/screenshot.gd -- out.png [секунд]

var _frames: int = 0
var _main: Node
var _out: String = "user://shot.png"
var _target: int = 360

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_target = int(args[1]) * 60
	_main = load("res://view/main.tscn").instantiate()
	root.add_child(_main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5 and _main.world != null:
		# Демонстрационные потоки игрока 0 — как если бы он их запустил мышью.
		_main.world.submit(Command.start_flow(0, 0, 0, 22, Defs.PacketType.FLOOD, 12))
		_main.world.submit(Command.start_flow(0, 0, 1, 17, Defs.PacketType.FLOOD, 20))
		_main.world.submit(Command.start_flow(0, 0, 0, 20, Defs.PacketType.FLOOD, 20))
		_main.world.submit(Command.start_flow(1, 0, 10, 4, Defs.PacketType.FLOOD, 8))
	if _frames >= _target:
		var img: Image = root.get_texture().get_image()
		img.save_png(_out)
		print("SAVED ", _out, " tick=", _main.world.tick, " in_flight=", _main.world.pool.alive_count, " drops=", _main.world.total_drops())
		quit(0)
	return false
