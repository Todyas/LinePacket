class_name NodeCard
extends CanvasLayer
## Карточка выбранного узла справа: доступ, контроль, слоты ПО, буфер.

var label: Label
var panel: Panel
var world: World
var selected_node: int = -1
var viewer: int = -1

func _ready() -> void:
	layer = 5
	panel = Panel.new()
	panel.position = Vector2(1290, 52)
	panel.size = Vector2(296, 330)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(panel)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.size = Vector2(272, 314)
	label.add_theme_font_size_override("font_size", 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	panel.visible = false

func _process(_delta: float) -> void:
	if world == null:
		return
	panel.visible = selected_node >= 0
	if selected_node >= 0:
		label.text = text_for(world, selected_node, viewer)

## Текст карточки глазами viewer (-1 — без тумана). Силуэт — почти ничего, снимок — данные с возрастом.
static func text_for(w: World, node_id: int, viewer: int = -1) -> String:
	if viewer >= 0:
		var lvl: int = Knowledge.level(w, viewer, node_id)
		if lvl == Knowledge.Level.SILHOUETTE:
			return "%s — %s\nДанных нет: узел за пределами видимости.\nСкан (клавиша T, ПКМ) покажет его состояние." % [Names.node_label(w.nodes[node_id]), Names.node_type(w.nodes[node_id].type)]
		if lvl == Knowledge.Level.SNAPSHOT:
			return _snapshot_text(w, node_id, viewer)
	var n: NodeState = w.nodes[node_id]
	var lines: Array[String] = []
	lines.append("%s — %s" % [Names.node_label(n), Names.node_type(n.type)])
	lines.append("Владелец: %s" % Names.owner_name(n.owner))
	if n.type == Defs.NodeType.SWITCH:
		lines.append("Нейтральная инфраструктура")
		lines.append("CPU: %d%%" % n.cpu_load_pct())
		return "\n".join(lines)
	if n.owner >= 0:
		lines.append("Контроль: %d%%" % (n.control * 100 / Defs.CONTROL_MAX))
	if n.down:
		lines.append("ЛЕЖИТ: перегрузка CPU, не шлёт пакеты, ПО отключено")
	lines.append("CPU: %d%% (свободно %d/с)" % [n.cpu_load_pct(), n.cpu_per_s])
	if n.owner >= 0:
		lines.append("Доступ: %s" % Names.access_mode(n.access_mode, n.key_version))
		lines.append("Доступ имеют: %s" % Names.access_list(n.access_mask))
		var slots: Array[String] = []
		var shown: Array[int] = []
		if viewer >= 0:
			shown = Knowledge.soft_visible(w, viewer, node_id)
		else:
			for t in n.soft:
				if t >= 0:
					shown.append(t)
		for t in shown:
			slots.append("[%s]" % Defs.SOFT_NAMES[t])
		if n.owner == viewer or viewer < 0:
			for i in n.free_slots():
				slots.append("[пусто]")
		lines.append("ПО: %s" % (" ".join(slots) if not slots.is_empty() else "—"))
		for p in Defs.MAX_PLAYERS:
			if p == n.owner or (viewer >= 0 and p != viewer and n.owner != viewer):
				continue
			if n.infect[p] > 0:
				lines.append("Заражение (%s): %d%%" % [Names.owner_name(p), n.infect[p] * 100 / Defs.INFECT_MAX])
			if n.brute[p] > 0:
				lines.append("Подбор пароля (%s): %d%%" % [Names.owner_name(p), n.brute[p] * 100 / Defs.BRUTE_MAX])
		lines.append_array(_hidden_lines(w, n, viewer))
		var lim: int = Economy.buffer_limit(n)
		if lim > 0:
			lines.append("Буфер: %d / %d" % [n.buffer, lim])
		var here: Array[String] = []
		for a in w.agents:
			if a.node == node_id and (viewer < 0 or Knowledge.agent_visible(w, viewer, a)):
				here.append("%d(И%d)" % [a.id + 1, a.owner + 1])
		if not here.is_empty():
			lines.append("Агенты здесь: %s" % ", ".join(here))
	else:
		if Defs.INIT_NEEDED.has(n.type):
			lines.append("Захват: INIT ×%d" % int(Defs.INIT_NEEDED[n.type]))
			for p in Defs.MAX_PLAYERS:
				if n.capture[p] > 0:
					lines.append("  Игрок %d: %d" % [p + 1, n.capture[p]])
	return "\n".join(lines)


static func _snapshot_text(w: World, node_id: int, viewer: int) -> String:
	var n: NodeState = w.nodes[node_id]
	var sn: NodeSnap = Knowledge.snap(w, viewer, node_id)
	var lines: Array[String] = []
	lines.append("%s — %s" % [Names.node_label(n), Names.node_type(n.type)])
	lines.append("СНИМОК: данные %d с назад" % (Knowledge.age(w, viewer, node_id) / Defs.TICK_HZ))
	lines.append("Владелец: %s" % Names.owner_name(sn.owner))
	if n.type == Defs.NodeType.SWITCH:
		return "\n".join(lines)
	if sn.owner >= 0:
		lines.append("Контроль: %d%%" % (sn.control * 100 / Defs.CONTROL_MAX))
		lines.append("Доступ: %s" % Names.access_mode(sn.access_mode, 0).replace(" (v0)", ""))
		lines.append("Ваш доступ: %s" % ("есть" if sn.my_access else "нет"))
		var soft: Array[String] = []
		for t in sn.soft:
			if t >= 0:
				soft.append("[%s]" % Defs.SOFT_NAMES[t])
		lines.append("ПО: %s" % (" ".join(soft) if not soft.is_empty() else "нет"))
		lines.append("Буфер: %d" % sn.buffer)
		if sn.my_virus:
			lines.append("Ваш скрытый вирус: ПКМ → активировать")
		if sn.my_backdoor:
			lines.append("Ваш бэкдор")
		if sn.found_virus or sn.found_backdoor:
			lines.append("Найдено скрытое: вычистите")
		if sn.down:
			lines.append("Лежала в момент снимка")
	return "\n".join(lines)


## Скрытое на узле: вор видит свои вирус и бэкдор, владелец — только найденное. Без тумана (viewer < 0) — всё.
static func _hidden_lines(w: World, n: NodeState, viewer: int) -> Array[String]:
	var out: Array[String] = []
	if viewer < 0:
		for a in Defs.MAX_PLAYERS:
			if n.virus[a] == 1:
				out.append("Тайный вирус (%s)" % Names.owner_name(a))
			if n.backdoor[a] == 1:
				out.append("Бэкдор (%s)" % Names.owner_name(a))
		return out
	var sn: NodeSnap = Knowledge.snap(w, viewer, n.id)
	if sn == null:
		return out
	if sn.my_virus:
		out.append("Ваш скрытый вирус: ПКМ → активировать")
	if sn.my_backdoor:
		out.append("Ваш бэкдор: агент войдёт без пароля")
	if sn.found_virus:
		out.append("НАЙДЕН чужой скрытый вирус: вычистите")
	if sn.found_backdoor:
		out.append("НАЙДЕН чужой бэкдор: вычистите")
	return out
