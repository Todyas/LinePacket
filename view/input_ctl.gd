class_name InputCtl
extends Node2D
## Ввод игрока: превращает мышь и клавиши в команды. Мир только читает.

const NODE_HIT_RADIUS: float = 32.0
const FLOW_HIT_PX: float = 14.0

var world: World
var camera: CameraCtl
var local_player: int = 0
var flow_type: int = Defs.PacketType.FLOOD
var drag_from: int = -1
var selected_node: int = -1
var selected_agent: int = 0
var ring: RingMenu
var _press_pos: Vector2 = Vector2.ZERO
var hover_flow: int = -1
var mouse_world: Vector2 = Vector2.ZERO
var _panning: bool = false
var ring_target: int = -1
## Узел, с которого пойдут потоки из меню: выбранный свой или ближайший свой к цели.
var ring_source: int = -1
## Пауза: ввод в мир заморожен, работают только Пробел и Esc (снять паузу).
var paused: bool = false

signal pause_toggled
signal speed_step(dir: int)

## Типы потоков на левой руке: Q W E R T.
const MODE_KEYS: Dictionary = {
	KEY_Q: Defs.PacketType.INIT,
	KEY_W: Defs.PacketType.FLOOD,
	KEY_E: Defs.PacketType.PAYLOAD,
	KEY_R: Defs.PacketType.PAYLOAD_HIDDEN,
	KEY_T: Defs.PacketType.SCAN,
}

## Подпись клавиши типа потока.
static func key_label(ptype: int) -> String:
	for k in MODE_KEYS:
		if MODE_KEYS[k] == ptype:
			return OS.get_keycode_string(k)
	return "?"

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if paused and not event is InputEventKey:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		mouse_world = camera.screen_to_world(mm.position)
		if _panning:
			camera.pan_by(mm.relative)
		hover_flow = Picking.hit_flow(world, local_player, mouse_world, FLOW_HIT_PX / camera.zoom.x)
		queue_redraw()
	elif event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventKey:
		_on_key(event as InputEventKey)

## Радиус попадания по узлу постоянен на экране, при любом масштабе камеры.
func _hit_radius() -> float:
	return NODE_HIT_RADIUS / camera.zoom.x

func _on_button(mb: InputEventMouseButton) -> void:
	mouse_world = camera.screen_to_world(mb.position)
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if ring != null and ring.is_open:
					ring.close()
				_press_pos = mb.position
				var nid: int = Picking.hit_node(world, mouse_world, _hit_radius())
				if nid >= 0 and world.nodes[nid].owner == local_player:
					drag_from = nid
				else:
					_panning = true
			else:
				_panning = false
				var is_click: bool = mb.position.distance_to(_press_pos) < 6.0
				if drag_from >= 0:
					var target: int = Picking.hit_node(world, mouse_world, _hit_radius())
					if target >= 0 and target != drag_from:
						_finish_drag()
					else:
						selected_node = drag_from
				elif is_click:
					selected_node = Picking.hit_node(world, mouse_world, _hit_radius())
				drag_from = -1
			queue_redraw()
		MOUSE_BUTTON_RIGHT:
			if mb.pressed and ring != null:
				var tgt: int = Picking.hit_node(world, mouse_world, _hit_radius())
				ring_target = tgt
				ring_source = RingMenu.source_for(world, local_player, selected_node, tgt)
				var items: Array[Dictionary] = RingMenu.items_for(world, local_player, ring_source, tgt)
				ring.open(mb.position, items)
		MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_wheel(mb.position, 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_wheel(mb.position, -1)

func _finish_drag() -> void:
	var target: int = Picking.hit_node(world, mouse_world, _hit_radius())
	if target >= 0 and target != drag_from:
		submit(Command.start_flow(local_player, world.tick, drag_from, target, flow_type, flow_rate_for(flow_type)))

func _wheel(screen_pos: Vector2, dir: int) -> void:
	hover_flow = Picking.hit_flow(world, local_player, mouse_world, FLOW_HIT_PX / camera.zoom.x)
	if hover_flow >= 0:
		var f: FlowState = world.get_flow(hover_flow)
		var nr: int = clampi(f.rate + dir, Defs.FLOW_MIN_RATE, Defs.FLOW_MAX_RATE)
		if nr != f.rate:
			submit(Command.set_flow_rate(local_player, world.tick, f.id, nr))
	else:
		camera.zoom_at(screen_pos, CameraCtl.ZOOM_STEP if dir > 0 else 1.0 / CameraCtl.ZOOM_STEP)

func _on_key(k: InputEventKey) -> void:
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		pause_toggled.emit()
		return
	if k.keycode == KEY_MINUS or k.keycode == KEY_KP_SUBTRACT:
		speed_step.emit(-1)
		return
	if k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD:
		speed_step.emit(1)
		return
	if paused:
		if k.keycode == KEY_ESCAPE:
			pause_toggled.emit()
		return
	if MODE_KEYS.has(k.keycode):
		var t: int = MODE_KEYS[k.keycode]
		if Defs.PLAYER_FLOW_TYPES.has(t):
			flow_type = t
	elif k.keycode >= KEY_1 and k.keycode <= KEY_3:
		selected_agent = k.keycode - KEY_1
	elif k.keycode == KEY_F2 and OS.is_debug_build():
		switch_side()
	elif k.keycode == KEY_ESCAPE:
		if ring != null and ring.is_open:
			ring.close()
		elif selected_node >= 0 or drag_from >= 0:
			selected_node = -1
			drag_from = -1
			queue_redraw()
		else:
			pause_toggled.emit()   # нечего закрывать: Esc открывает паузу
	elif k.keycode == KEY_X or k.keycode == KEY_DELETE:
		if hover_flow >= 0:
			submit(Command.stop_flow(local_player, world.tick, hover_flow))
			hover_flow = -1

## Скан — разовый: поток сам заканчивается, когда скан дошёл.
static func flow_rate_for(ptype: int) -> int:
	return Defs.SCAN_FLOW_RATE if ptype == Defs.PacketType.SCAN else Defs.FLOW_DEFAULT_RATE

## Отладка (только в debug-сборке): переключиться на другую сторону, чтобы играть за обоих.
func switch_side() -> void:
	local_player = (local_player + 1) % world.players.size()
	selected_node = -1
	selected_agent = 0
	drag_from = -1
	hover_flow = -1
	if ring != null:
		ring.close()
	queue_redraw()

## Выбран пункт кольцевого меню.
func apply_item(item: Dictionary) -> void:
	if item["kind"] == "task":
		submit(Command.queue_task(local_player, world.tick, selected_agent, int(item["task"]), ring_target, int(item["arg"])))
	elif item["kind"] == "activate":
		submit(Command.activate(local_player, world.tick, ring_target, int(item["mode"])))
	elif item["kind"] == "flow" and ring_source >= 0:
		submit(Command.start_flow(local_player, world.tick, ring_source, ring_target, int(item["flow_type"]), flow_rate_for(int(item["flow_type"]))))

func submit(cmd: Command) -> void:
	world.submit(cmd)

func _draw() -> void:
	if world == null or drag_from < 0:
		return
	var n: NodeState = world.nodes[drag_from]
	var target: int = Picking.hit_node(world, mouse_world, _hit_radius())
	var col: Color = Palette.of_owner(local_player)
	var end: Vector2 = mouse_world
	if target >= 0 and target != drag_from:
		var t: NodeState = world.nodes[target]
		end = Vector2(t.x, t.y)
		draw_arc(end, 34.0, 0.0, TAU, 32, col, 2.0)
	draw_line(Vector2(n.x, n.y), end, col, 2.0, true)
