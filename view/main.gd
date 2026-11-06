extends Node2D
## Главная сцена S0: грузит карту, тикает симуляцию с частотой 20 Гц, рисует граф.

const MAP_PATH: String = "res://maps/duel.json"

var world: World
var graph: GraphView
var camera: CameraCtl
var _acc: float = 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BACKGROUND)
	var res: Dictionary = MapLoader.load_file(MAP_PATH, 1)
	if res["world"] == null:
		push_error(res["error"])
		return
	world = res["world"]
	graph = GraphView.new()
	graph.world = world
	add_child(graph)
	camera = CameraCtl.new()
	camera.position = Vector2(800, 450)
	add_child(camera)
	camera.make_current()

func _process(delta: float) -> void:
	if world == null:
		return
	_acc += delta
	var step_s: float = 1.0 / float(Defs.TICK_HZ)
	var guard: int = 0
	while _acc >= step_s and guard < 5:
		world.step()
		_acc -= step_s
		guard += 1
	if guard == 5:
		_acc = 0.0
