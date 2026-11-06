extends SceneTree
## Путь «меню → матч → итоги» без мыши: человек бездействует, бот доводит матч до конца.
## godot --headless --path . -s tools/flow_check.gd -- <seed> [минут]

var _stage: int = 0
var _frames: int = 0
var _menu: Node
var _main: Node
var _seed: int = 1
var _max_min: int = 40

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_seed = int(args[0])
	if args.size() > 1:
		_max_min = int(args[1])
	_menu = load("res://view/menu.tscn").instantiate()
	root.add_child(_menu)

func _process(_delta: float) -> bool:
	_frames += 1
	if _stage == 0 and _frames == 3:
		_menu.seed_edit.text = str(_seed)
		_menu.start_game()
		_stage = 1
	elif _stage == 1 and _frames == 8:
		_main = current_scene
		if _main == null or _main.get("world") == null:
			print("FLOW FAIL: сцена матча не загрузилась")
			quit(1)
			return true
		_stage = 2
	elif _stage == 2:
		for i in 400:
			_main._process(0.05)
			if _main.world.winner >= 0 or _main.world.tick > _max_min * 60 * Defs.TICK_HZ:
				break
		var over: bool = _main.world.winner >= 0 or _main.world.tick > _max_min * 60 * Defs.TICK_HZ
		if not over:
			return false
		_main.end_screen._process(0.0)
		print("FLOW seed=", _main.world.seed_value, " tick=", _main.world.tick, " winner=", _main.world.winner,
			" end_screen_visible=", _main.end_screen._panel.visible)
		if _main.world.winner >= 0:
			print(_main.end_screen._label.text)
		quit(0 if _main.world.winner >= 0 else 1)
	return false
