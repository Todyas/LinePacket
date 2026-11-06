class_name RingMenu
extends CanvasLayer
## Кольцевое меню по ПКМ: действия для узла под курсором.

signal chosen(item: Dictionary)

var _buttons: Array[Button] = []
var is_open: bool = false

## Какая машина получит боевую роль из меню: выбранная своя, а если выбора нет или цель ей не по дальности,
## ближайшая своя машина в пределах Defs.ROLE_MAX_HOPS. Так меню не зависит от того, успел ли игрок кликнуть узел.
static func source_for(w: World, player: int, selected_node: int, target: int) -> int:
	if target < 0:
		return selected_node
	if selected_node >= 0 and selected_node != target and _can_serve(w, player, selected_node, target):
		return selected_node
	var best: int = -1
	var best_hops: int = 1000000
	for n in w.nodes:
		if n.id == target or not _can_serve(w, player, n.id, target):
			continue
		var h: int = Knowledge.hops(w, n.id, target)
		if h < best_hops:
			best_hops = h
			best = n.id
	return best

static func _can_serve(w: World, player: int, node_id: int, target: int) -> bool:
	var n: NodeState = w.nodes[node_id]
	if n.owner != player or not Roles.can_have_role(n):
		return false
	var h: int = Knowledge.hops(w, node_id, target)
	return h >= 1 and h <= Defs.ROLE_MAX_HOPS

## Пункты меню: [{label, kind: "task"|"role"|"own_role"|"activate"|"info", task: вид, arg, role}]. Чистая функция — тестируется без сцены.
static func items_for(w: World, player: int, selected_node: int, target: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = _collect(w, player, selected_node, target)
	if items.is_empty() and target >= 0:
		items.append(_info_item(w, player, target))
	return items

static func _info_item(w: World, player: int, target: int) -> Dictionary:
	var t: NodeState = w.nodes[target]
	if t.type == Defs.NodeType.SWITCH:
		return {"label": "Свич: действий нет", "kind": "info", "hint": "Свич ничей, только пересылает пакеты."}
	if Knowledge.owner_of(w, player, target) == Knowledge.UNKNOWN_OWNER:
		return {"label": "Нет данных: нужен дозор", "kind": "info", "hint": "Узел вне видимости. Дозор (T) обновляет снимки в радиусе %d хопов от машины." % Defs.WATCH_RADIUS}
	return {"label": "Действий нет", "kind": "info", "hint": "Для этого узла сейчас нечего делать."}

static func _collect(w: World, player: int, selected_node: int, target: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	if target < 0:
		return items
	var t: NodeState = w.nodes[target]
	# Всё, что не своё, игрок знает только по снимку: меню строится по знаниям, а не по истине.
	var k_owner: int = Knowledge.owner_of(w, player, target)
	var sn: NodeSnap = Knowledge.snap(w, player, target)
	if t.owner == player and Roles.can_have_role(t):
		if t.role != Defs.Role.WORK:
			items.append({"label": "Роль: Работа", "kind": "own_role", "role": Defs.Role.WORK})
		if t.role != Defs.Role.WATCH:
			items.append({"label": "Роль: Дозор", "kind": "own_role", "role": Defs.Role.WATCH})
	if t.owner == player and t.type != Defs.NodeType.SWITCH:
		items.append({"label": "Агент сюда", "kind": "task", "task": Defs.TaskKind.MOVE, "arg": 0})
		var pw: Array = Agents.task_params(Defs.TaskKind.CHANGE_PASSWORD, 0)
		items.append({"label": "Сменить пароль (%d Б, %d с)" % [pw[1], int(pw[0]) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.CHANGE_PASSWORD, "arg": 0})
		var kp: Array = Agents.task_params(Defs.TaskKind.SET_KEYS, 0)
		items.append({"label": "Ключи (%d Б, %d с)" % [kp[1], int(kp[0]) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.SET_KEYS, "arg": 0})
		for s in Defs.PLAYER_SOFT:
			if t.has_soft(s) or t.free_slots() <= 0:
				continue
			var sp: Array = Agents.task_params(Defs.TaskKind.INSTALL_SOFT, s)
			items.append({"label": "%s (%d Б, %d с)" % [Defs.SOFT_NAMES[s], sp[1], int(sp[0]) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.INSTALL_SOFT, "arg": s})
		if t.max_infect() > 0 or Stealth.has_found_threat(t):
			var cp: Array = Agents.task_params(Defs.TaskKind.CLEAN_VIRUS, 0, t)
			items.append({"label": "Вычистить вирус (%d Б, %d с)" % [cp[1], (int(cp[0]) + Defs.TICK_HZ - 1) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.CLEAN_VIRUS, "arg": 0})
		if t.prev_owner >= 0:
			var ep: Array = Agents.task_params(Defs.TaskKind.ENTRENCH, 0)
			items.append({"label": "Закрепиться (%d Б, %d с)" % [ep[1], int(ep[0]) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.ENTRENCH, "arg": 0})
	elif k_owner >= 0 and t.type != Defs.NodeType.SWITCH:
		items.append({"label": "Агент сюда", "kind": "task", "task": Defs.TaskKind.MOVE, "arg": 0})
		items.append({"label": "Украсть ключ (%d с)" % (int(Agents.task_params(Defs.TaskKind.STEAL_KEY, 0)[0]) / Defs.TICK_HZ), "kind": "task", "task": Defs.TaskKind.STEAL_KEY, "arg": 0})
		items.append({"label": "Выкачать буфер", "kind": "task", "task": Defs.TaskKind.DRAIN_BUFFER, "arg": 0})
		var bp: Array = Agents.task_params(Defs.TaskKind.BACKDOOR, 0)
		items.append({"label": "Бэкдор (%d Б, %d с)" % [bp[1], int(bp[0]) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.BACKDOOR, "arg": 0})
		if sn != null and sn.my_virus:
			items.append({"label": "Активировать: перехват", "kind": "activate", "mode": Defs.ActivateMode.TAKEOVER})
			items.append({"label": "Активировать: отключить ПО", "kind": "activate", "mode": Defs.ActivateMode.DISABLE_SOFT})
		if t.prev_owner == player and t.owner != player:
			var rp: Array = Agents.task_params(Defs.TaskKind.ENTRENCH, 0)
			items.append({"label": "Вернуть машину (%d Б, %d с)" % [rp[1], int(rp[0]) / Defs.TICK_HZ], "kind": "task", "task": Defs.TaskKind.ENTRENCH, "arg": 0})
	# Боевые роли: selected_node здесь — машина-исполнитель (её выбирает source_for).
	if selected_node >= 0 and selected_node != target and _can_serve(w, player, selected_node, target):
		if k_owner == Defs.NEUTRAL and Defs.INIT_NEEDED.has(t.type):
			items.append({"label": "Захват (INIT)", "kind": "role", "role": Defs.Role.CAPTURE})
		if k_owner >= 0 and k_owner != player and t.type != Defs.NodeType.SWITCH:
			items.append({"label": "Давление (FLOOD)", "kind": "role", "role": Defs.Role.PRESSURE})
			items.append({"label": "Заражение (PAYLOAD)", "kind": "role", "role": Defs.Role.INFECT})
			if sn != null and not sn.my_virus:
				items.append({"label": "Тайное заражение (%d Б/пакет)" % Defs.PAYLOAD_HIDDEN_COST_BYTES, "kind": "role", "role": Defs.Role.INFECT_HIDDEN})
			if sn != null and sn.access_mode != Defs.AccessMode.KEYS and not sn.my_access:
				items.append({"label": "Подбор пароля (INIT)", "kind": "role", "role": Defs.Role.CAPTURE})
	return items

func open(screen_pos: Vector2, items: Array[Dictionary]) -> void:
	close()
	if items.is_empty():
		return
	layer = 8
	is_open = true
	var n: int = items.size()
	var rx: float = 150.0 + 12.0 * n
	var ry: float = 70.0 + 14.0 * n
	for i in n:
		var ang: float = -PI / 2.0 + TAU * float(i) / float(n)
		var b := Button.new()
		b.text = items[i]["label"]
		b.size = Vector2(210, 32)
		b.tooltip_text = Hints.ring_item(items[i])
		var pos: Vector2 = screen_pos + Vector2(cos(ang) * rx, sin(ang) * ry) - b.size * 0.5
		# Меню целиком остаётся на экране, даже если открыто у края.
		b.position = Vector2(clampf(pos.x, 4.0, 1600.0 - b.size.x - 4.0), clampf(pos.y, 44.0, 900.0 - b.size.y - 4.0))
		b.disabled = items[i]["kind"] == "info"
		var item: Dictionary = items[i]
		b.pressed.connect(func() -> void:
			chosen.emit(item)
			close())
		add_child(b)
		_buttons.append(b)

func close() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	is_open = false
