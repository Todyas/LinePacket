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
var hover_flow: int = -1
var mouse_world: Vector2 = Vector2.ZERO
var _panning: bool = false

const MODE_KEYS: Dictionary = {
	KEY_F: Defs.PacketType.FLOOD,
	KEY_I: Defs.PacketType.INIT,
	KEY_S: Defs.PacketType.SCAN,
}

func _unhandled_input(event: InputEvent) -> void:
	if world == null:
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

func _on_button(mb: InputEventMouseButton) -> void:
	mouse_world = camera.screen_to_world(mb.position)
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var nid: int = Picking.hit_node(world, mouse_world, NODE_HIT_RADIUS)
				if nid >= 0 and world.nodes[nid].owner == local_player:
					drag_from = nid
				else:
					_panning = true
			else:
				_panning = false
				if drag_from >= 0:
					_finish_drag()
				drag_from = -1
			queue_redraw()
		MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_wheel(mb.position, 1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_wheel(mb.position, -1)

func _finish_drag() -> void:
	var target: int = Picking.hit_node(world, mouse_world, NODE_HIT_RADIUS)
	if target >= 0 and target != drag_from:
		submit(Command.start_flow(local_player, world.tick, drag_from, target, flow_type, Defs.FLOW_DEFAULT_RATE))

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
	if MODE_KEYS.has(k.keycode):
		var t: int = MODE_KEYS[k.keycode]
		if Defs.PLAYER_FLOW_TYPES.has(t):
			flow_type = t
	elif k.keycode == KEY_X or k.keycode == KEY_DELETE:
		if hover_flow >= 0:
			submit(Command.stop_flow(local_player, world.tick, hover_flow))
			hover_flow = -1

func submit(cmd: Command) -> void:
	world.submit(cmd)

func _draw() -> void:
	if world == null or drag_from < 0:
		return
	var n: NodeState = world.nodes[drag_from]
	var target: int = Picking.hit_node(world, mouse_world, NODE_HIT_RADIUS)
	var col: Color = Palette.of_owner(local_player)
	var end: Vector2 = mouse_world
	if target >= 0 and target != drag_from:
		var t: NodeState = world.nodes[target]
		end = Vector2(t.x, t.y)
		draw_arc(end, 34.0, 0.0, TAU, 32, col, 2.0)
	draw_line(Vector2(n.x, n.y), end, col, 2.0, true)
