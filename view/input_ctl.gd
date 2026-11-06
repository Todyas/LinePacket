class_name InputCtl
extends Node2D
## Ввод игрока: превращает мышь и клавиши в команды. Мир только читает.

const NODE_HIT_RADIUS: float = 32.0

var world: World
var camera: CameraCtl
var local_player: int = 0
## Режим перетаскивания: какую роль получит машина, которую потянули к цели.
var role_mode: int = Defs.Role.PRESSURE
var drag_from: int = -1
var selected_node: int = -1
var selected_agent: int = 0
var ring: RingMenu
var _press_pos: Vector2 = Vector2.ZERO
var mouse_world: Vector2 = Vector2.ZERO
var _panning: bool = false
var ring_target: int = -1
## Узел, с которого пойдут потоки из меню: выбранный свой или ближайший свой к цели.
var ring_source: int = -1
## Пауза: ввод в мир заморожен, работают только Пробел и Esc (снять паузу).
var paused: bool = false

signal pause_toggled
signal speed_step(dir: int)

## Роли на левой руке: Q W E R T.
const MODE_KEYS: Dictionary = {
	KEY_Q: Defs.Role.CAPTURE,
	KEY_W: Defs.Role.PRESSURE,
	KEY_E: Defs.Role.INFECT,
	KEY_R: Defs.Role.INFECT_HIDDEN,
	KEY_T: Defs.Role.WATCH,
}

## Подпись клавиши режима роли.
static func key_label(role: int) -> String:
	for k in MODE_KEYS:
		if MODE_KEYS[k] == role:
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
				if nid >= 0 and world.nodes[nid].owner == local_player and Roles.can_have_role(world.nodes[nid]):
					drag_from = nid
				else:
					_panning = true
			else:
				_panning = false
				var is_click: bool = mb.position.distance_to(_press_pos) < 6.0
				if drag_from >= 0:
					if is_click:
						selected_node = drag_from
					else:
						_finish_drag()
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

## Роль по режиму: боевая — на узел под курсором (цель проверяет sim), дозор — сразу на машину.
func _finish_drag() -> void:
	if role_mode == Defs.Role.WATCH:
		submit(Command.set_role(local_player, world.tick, drag_from, Defs.Role.WATCH))
		selected_node = drag_from
		return
	var target: int = Picking.hit_node(world, mouse_world, _hit_radius())
	if target >= 0 and target != drag_from:
		submit(Command.set_role(local_player, world.tick, drag_from, role_mode, target))
		selected_node = drag_from

func _wheel(screen_pos: Vector2, dir: int) -> void:
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
		role_mode = MODE_KEYS[k.keycode]
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

## Отладка (только в debug-сборке): переключиться на другую сторону, чтобы играть за обоих.
func switch_side() -> void:
	local_player = (local_player + 1) % world.players.size()
	selected_node = -1
	selected_agent = 0
	drag_from = -1
	if ring != null:
		ring.close()
	queue_redraw()

## Выбран пункт кольцевого меню.
func apply_item(item: Dictionary) -> void:
	if item["kind"] == "task":
		submit(Command.queue_task(local_player, world.tick, selected_agent, int(item["task"]), ring_target, int(item["arg"])))
	elif item["kind"] == "activate":
		submit(Command.activate(local_player, world.tick, ring_target, int(item["mode"])))
	elif item["kind"] == "role" and ring_source >= 0:
		submit(Command.set_role(local_player, world.tick, ring_source, int(item["role"]), ring_target))
	elif item["kind"] == "own_role":
		submit(Command.set_role(local_player, world.tick, ring_target, int(item["role"])))

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
