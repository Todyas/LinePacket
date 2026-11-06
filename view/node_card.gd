class_name NodeCard
extends CanvasLayer
## Карточка выбранного узла справа: доступ, контроль, слоты ПО, буфер.

var label: Label
var panel: Panel
var world: World
var selected_node: int = -1

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
		label.text = text_for(world, selected_node)

static func text_for(w: World, node_id: int) -> String:
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
	lines.append("CPU: %d%% (свободно %d/с)" % [n.cpu_load_pct(), n.cpu_per_s])
	if n.owner >= 0:
		lines.append("Доступ: %s" % Names.access_mode(n.access_mode, n.key_version))
		lines.append("Доступ имеют: %s" % Names.access_list(n.access_mask))
		var slots: Array[String] = []
		for t in n.soft:
			if t >= 0:
				slots.append("[%s]" % Defs.SOFT_NAMES[t])
		var free: int = n.free_slots()
		for i in free:
			slots.append("[пусто]")
		lines.append("ПО: %s" % " ".join(slots))
		var lim: int = Economy.buffer_limit(n)
		if lim > 0:
			lines.append("Буфер: %d / %d" % [n.buffer, lim])
		var here: Array[String] = []
		for a in w.agents:
			if a.node == node_id:
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
