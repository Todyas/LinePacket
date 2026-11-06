extends Node2D
## Главная сцена: карта, тик симуляции 20 Гц, граф, пакеты, ввод, отладочный оверлей.

const MAP_PATH: String = GameConfig.MAP_PATH

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
var feed: EventFeed
var pause_screen: PauseScreen
var tip: HoverTip
## Бот ведёт сторону, противоположную человеку. F2 (debug) отключает его.
var bot: Bot
var paused: bool = false
var speed_percent: int = Defs.GAME_SPEEDS_PERCENT[GameConfig.speed_index]
## Туман войны; в debug-сборке клавиша F4 включает всеведущий взгляд для отладки.
var fog_enabled: bool = true
var local_player: int = GameConfig.player_side
var _acc: float = 0.0
var _step_ms_avg: float = 0.0
var _drop_hist: PackedInt32Array = PackedInt32Array()

func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BACKGROUND)
	var res: Dictionary = MapLoader.load_file(MAP_PATH, GameConfig.seed_value)
	if res["world"] == null:
		push_error(res["error"])
		return
	world = res["world"]
	_drop_hist.resize(Defs.TICK_HZ)
	if GameConfig.vs_bot and world.players.size() > 1:
		var bot_side: int = (GameConfig.player_side + 1) % world.players.size()
		bot = Bot.new(BotView.new(world, bot_side), GameConfig.seed_value)
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
	feed = EventFeed.new()
	feed.world = world
	feed.player = local_player
	feed.focus_node.connect(func(nid: int) -> void: camera.position = Vector2(world.nodes[nid].x, world.nodes[nid].y))
	add_child(feed)
	end_screen = EndScreen.new()
	end_screen.world = world
	add_child(end_screen)
	overlay = DebugOverlay.new()
	overlay.world = world
	add_child(overlay)
	tip = HoverTip.new()
	tip.world = world
	tip.camera = camera
	tip.input_ctl = input_ctl
	add_child(tip)
	pause_screen = PauseScreen.new()
	add_child(pause_screen)
	pause_screen.resume_requested.connect(set_paused.bind(false))
	pause_screen.menu_requested.connect(func() -> void: get_tree().change_scene_to_file("res://view/menu.tscn"))
	input_ctl.speed_step.connect(func(dir: int) -> void: set_speed_index(GameConfig.speed_index + dir))
	hud.speed_percent = speed_percent
	input_ctl.pause_toggled.connect(func() -> void:
		if world.winner < 0:
			set_paused(not paused))

func set_speed_index(i: int) -> void:
	GameConfig.speed_index = clampi(i, 0, Defs.GAME_SPEEDS_PERCENT.size() - 1)
	speed_percent = int(Defs.GAME_SPEEDS_PERCENT[GameConfig.speed_index])
	hud.speed_percent = speed_percent

func set_paused(value: bool) -> void:
	paused = value
	input_ctl.paused = value
	pause_screen.visible = value
	if value:
		input_ctl.drag_from = -1
		input_ctl.queue_redraw()
		if input_ctl.ring != null:
			input_ctl.ring.close()

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F4 and OS.is_debug_build():
		fog_enabled = not fog_enabled

func _process(delta: float) -> void:
	if world == null:
		return
	if paused:
		return
	_acc += delta * float(speed_percent) / 100.0
	var step_s: float = 1.0 / float(Defs.TICK_HZ)
	var guard: int = 0
	while _acc >= step_s and guard < 5:
		var t0: int = Time.get_ticks_usec()
		# Бот ходит перед тиком, как игрок: его команды ставятся на текущий тик.
		if bot != null and local_player == GameConfig.player_side:
			bot.act()
		world.step()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		_step_ms_avg = lerpf(_step_ms_avg, ms, 0.1)
		_drop_hist[world.tick % Defs.TICK_HZ] = world.total_drops()
		_acc -= step_s
		guard += 1
	if guard == 5:
		_acc = 0.0
	var frac: float = clampf(_acc / step_s, 0.0, 1.0)
	packets.refresh(world, frac, local_player if fog_enabled else -1)
	drops_fx.ingest(world)
	local_player = input_ctl.local_player
	var viewer: int = local_player if fog_enabled else -1
	feed.player = local_player
	links_view.viewer = viewer
	nodes_view.viewer = viewer
	card.viewer = viewer
	tip.viewer = viewer
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
