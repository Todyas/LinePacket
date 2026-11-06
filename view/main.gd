extends Node2D
## Главная сцена: карта, тик симуляции 20 Гц, граф, пакеты, ввод, отладочный оверлей.

const MAP_PATH: String = "res://maps/duel.json"

var world: World
var links_view: GraphView
var nodes_view: GraphView
var packets: PacketView
var drops_fx: DropFx
var input_ctl: InputCtl
var camera: CameraCtl
var overlay: DebugOverlay
var hud: Hud
var card: NodeCard
var agent_panel: AgentPanel
var ring: RingMenu
var end_screen: EndScreen
var local_player: int = 0
var _acc: float = 0.0
var _step_ms_avg: float = 0.0
var _drop_hist: PackedInt32Array = PackedInt32Array()

func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BACKGROUND)
	var res: Dictionary = MapLoader.load_file(MAP_PATH, 1)
	if res["world"] == null:
		push_error(res["error"])
		return
	world = res["world"]
	_drop_hist.resize(Defs.TICK_HZ)
	links_view = GraphView.new()
	links_view.world = world
	add_child(links_view)
	packets = PacketView.new()
	add_child(packets)
	nodes_view = GraphView.new()
	nodes_view.world = world
	nodes_view.draw_links = false
	nodes_view.draw_nodes = true
	nodes_view.z_index = 2
	add_child(nodes_view)
	drops_fx = DropFx.new()
	add_child(drops_fx)
	camera = CameraCtl.new()
	camera.position = Vector2(800, 450)
	add_child(camera)
	camera.make_current()
	input_ctl = InputCtl.new()
	input_ctl.world = world
	input_ctl.camera = camera
	input_ctl.local_player = local_player
	input_ctl.z_index = 4
	add_child(input_ctl)
	ring = RingMenu.new()
	add_child(ring)
	input_ctl.ring = ring
	ring.chosen.connect(input_ctl.apply_item)
	card = NodeCard.new()
	card.world = world
	add_child(card)
	agent_panel = AgentPanel.new()
	agent_panel.world = world
	agent_panel.player = local_player
	add_child(agent_panel)
	hud = Hud.new()
	hud.world = world
	hud.player = local_player
	hud.input_ctl = input_ctl
	add_child(hud)
	end_screen = EndScreen.new()
	end_screen.world = world
	add_child(end_screen)
	overlay = DebugOverlay.new()
	overlay.world = world
	add_child(overlay)

func _process(delta: float) -> void:
	if world == null:
		return
	_acc += delta
	var step_s: float = 1.0 / float(Defs.TICK_HZ)
	var guard: int = 0
	while _acc >= step_s and guard < 5:
		var t0: int = Time.get_ticks_usec()
		world.step()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		_step_ms_avg = lerpf(_step_ms_avg, ms, 0.1)
		_drop_hist[world.tick % Defs.TICK_HZ] = world.total_drops()
		_acc -= step_s
		guard += 1
	if guard == 5:
		_acc = 0.0
	var frac: float = clampf(_acc / step_s, 0.0, 1.0)
	packets.refresh(world, frac)
	drops_fx.ingest(world)
	local_player = input_ctl.local_player
	hud.player = local_player
	agent_panel.player = local_player
	end_screen.local_player = local_player
	links_view.hover_flow = input_ctl.hover_flow
	nodes_view.selected_node = input_ctl.selected_node
	nodes_view.agent_player = local_player
	card.selected_node = input_ctl.selected_node
	agent_panel.selected_agent = input_ctl.selected_agent
	overlay.step_ms = _step_ms_avg
	overlay.drops_per_s = world.total_drops() - _drop_hist[(world.tick + 1) % Defs.TICK_HZ]
