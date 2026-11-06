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
## Выделенные свои машины (рамкой или кликом): роль, назначенная потягиванием или из меню, достаётся всем.
var selection: Array[int] = []
## Сообщения об отказах приказа: [тик, текст]. Показываются в верхней панели несколько секунд.
var notices: Array = []
const NOTICE_TICKS: int = 100
const NOTICE_MAX: int = 4
var box_active: bool = false
var box_from_world: Vector2 = Vector2.ZERO
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
					box_active = true
					box_from_world = mouse_world
			else:
				var is_click: bool = mb.position.distance_to(_press_pos) < 6.0
				if drag_from >= 0:
					if is_click:
						_select_click(drag_from, mb.shift_pressed)
					else:
						_finish_drag()
				elif box_active:
					if is_click:
						_select_click(Picking.hit_node(world, mouse_world, _hit_radius()), mb.shift_pressed)
					else:
						select_in_rect(box_from_world, mouse_world, mb.shift_pressed)
				box_active = false
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

## Клик по узлу: свой — выделяется (Shift добавляет или снимает), чужой или пустота — выбор для карточки и сброс выделения.
func _select_click(nid: int, additive: bool) -> void:
	if nid >= 0 and world.nodes[nid].owner == local_player and Roles.can_have_role(world.nodes[nid]):
		if additive:
			if selection.has(nid):
				selection.erase(nid)
			else:
				selection.append(nid)
		else:
			selection = [nid]
		selected_node = nid
		return
	if not additive:
		selection.clear()
	selected_node = nid

## Рамка в мировых координатах: выделяет свои машины внутри; чужие и нейтральные игнорируются.
func select_in_rect(a: Vector2, b: Vector2, additive: bool) -> void:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	var found: Array[int] = []
	if additive:
		found.assign(selection)
	for n in world.nodes:
		if n.owner == local_player and Roles.can_have_role(n) and r.has_point(Vector2(n.x, n.y)) and not found.has(n.id):
			found.append(n.id)
	selection = found
	selected_node = selection[0] if selection.size() == 1 else (selected_node if selection.has(selected_node) else -1)

## Кто получает приказ: все выделенные, если тянули одну из них, иначе только потянутая машина.
func _group_for(node: int) -> Array[int]:
	var out: Array[int] = []
	if selection.size() > 1 and selection.has(node):
		out.assign(selection)
	else:
		out.append(node)
	return out

## Роль по режиму: боевая — на узел под курсором (цель проверяет sim), дозор — сразу на машину.
func _finish_drag() -> void:
	var group: Array[int] = _group_for(drag_from)
	if role_mode == Defs.Role.WATCH:
		order_role(group, Defs.Role.WATCH, -1)
	else:
		var target: int = Picking.hit_node(world, mouse_world, _hit_radius())
		if target < 0 or target == drag_from:
			return
		order_role(group, role_mode, target)
	if group.size() == 1:
		selection = [drag_from]
		selected_node = drag_from

## Приказ роли группе: каждая машина проверяет цель и дальность сама; кто не может — остаётся в прежней роли и пишет причину.
func order_role(group: Array[int], role: int, target: int) -> int:
	var sent: int = 0
	for nid in group:
		var reason: String = refusal_reason(nid, role, target)
		if reason != "":
			add_notice("%s: %s, роль не изменена" % [Names.node_label(world.nodes[nid]), reason])
			continue
		submit(Command.set_role(local_player, world.tick, nid, role, target))
		sent += 1
	return sent

## Почему машина не может принять роль: пустая строка, если может.
func refusal_reason(nid: int, role: int, target: int) -> String:
	var n: NodeState = world.nodes[nid]
	if n.owner != local_player or not Roles.can_have_role(n):
		return "не ваша машина"
	if not Defs.COMBAT_ROLES.has(role):
		return ""
	if target == nid:
		return "цель — сама машина"
	if not Roles.target_ok(world, n, role, target):
		return "цель не подходит для роли «%s»" % Defs.ROLE_NAMES[role]
	var hp: int = Knowledge.hops(world, nid, target)
	if hp < 0 or hp > Defs.ROLE_MAX_HOPS:
		return "цель дальше %d хопов" % Defs.ROLE_MAX_HOPS
	return ""

func add_notice(text: String) -> void:
	notices.append([world.tick, text])
	while notices.size() > NOTICE_MAX:
		notices.pop_front()

## Свежие сообщения об отказах (не старше NOTICE_TICKS).
func fresh_notices() -> Array[String]:
	var out: Array[String] = []
	for nt in notices:
		if world.tick - int(nt[0]) <= NOTICE_TICKS:
			out.append(String(nt[1]))
	return out

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
		elif selected_node >= 0 or drag_from >= 0 or not selection.is_empty():
			selected_node = -1
			drag_from = -1
			selection.clear()
			queue_redraw()
		else:
			pause_toggled.emit()   # нечего закрывать: Esc открывает паузу

## Отладка (только в debug-сборке): переключиться на другую сторону, чтобы играть за обоих.
func switch_side() -> void:
	local_player = (local_player + 1) % world.players.size()
	selected_node = -1
	selection.clear()
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
		# При выделении группы приказ получают все выделенные, иначе только подобранная машина.
		var group: Array[int] = []
		if selection.size() > 1:
			group.assign(selection)
		else:
			group.append(ring_source)
		order_role(group, int(item["role"]), ring_target)
	elif item["kind"] == "router_rule":
		submit(Command.set_router_rule(local_player, world.tick, ring_target, bool(item["open"])))
	elif item["kind"] == "own_role":
		order_role(_group_for(ring_target), int(item["role"]), -1)

func submit(cmd: Command) -> void:
	world.submit(cmd)

func _draw() -> void:
	if world == null:
		return
	if box_active:
		var r := Rect2(box_from_world, Vector2.ZERO).expand(mouse_world)
		draw_rect(r, Color(Palette.of_owner(local_player), 0.12), true)
		draw_rect(r, Color(Palette.of_owner(local_player), 0.8), false, 1.5)
	if drag_from < 0:
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
