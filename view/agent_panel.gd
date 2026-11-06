class_name AgentPanel
extends CanvasLayer
## Нижняя панель: очереди задач трёх агентов с прогрессом. Клавиши 1–5 выбирают агента, H нанимает следующего.

var world: World
var player: int = 0
const BOX_STEP: float = 316.0
var selected_agent: int = 0
var _labels: Array[Label] = []
var _bars: Array[ProgressBar] = []
var _boxes: Array[Panel] = []

func _ready() -> void:
	layer = 5
	for i in Defs.AGENTS_PER_PLAYER:
		var box := Panel.new()
		box.position = Vector2(14 + i * BOX_STEP, 770)
		box.size = Vector2(BOX_STEP - 8, 120)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", UiStyle.panel())
		add_child(box)
		_boxes.append(box)
		var lbl := Label.new()
		lbl.position = Vector2(10, 6)
		lbl.size = Vector2(BOX_STEP - 28, 90)
		lbl.add_theme_font_size_override("font_size", 15)
		box.add_child(lbl)
		_labels.append(lbl)
		var bar := ProgressBar.new()
		bar.position = Vector2(10, 98)
		bar.size = Vector2(BOX_STEP - 28, 14)
		bar.max_value = 1000
		bar.show_percentage = false
		box.add_child(bar)
		_bars.append(bar)

func _process(_delta: float) -> void:
	if world == null:
		return
	for i in Defs.AGENTS_PER_PLAYER:
		_labels[i].text = lines_for(world, player, i, i == selected_agent)
		_bars[i].value = Agents.agent_of(world, player, i).progress_permille() if Agents.agent_of(world, player, i).hired else 0
		_boxes[i].add_theme_stylebox_override("panel", UiStyle.panel(Palette.of_owner(player) if i == selected_agent else Color(0.25, 0.3, 0.38)))

static func status_text(w: World, a: AgentState) -> String:
	match a.mode:
		AgentState.Mode.IDLE:
			return "на %s" % Names.node_label(w.nodes[a.node])
		AgentState.Mode.TRAVEL:
			return "в пути"
		AgentState.Mode.WORK:
			var head: Array = a.queue[0]
			return "работает: %s %d%%" % [Names.task(int(head[0]), int(head[2]), Names.node_label(w.nodes[int(head[1])])), a.progress_permille() / 10]
		AgentState.Mode.LOST:
			return "вернётся на ядро через %d с" % ((a.lost_timer + Defs.TICK_HZ - 1) / Defs.TICK_HZ)
	return "?"

## Место ещё не нанятого агента: цена и время найма, либо идущий наём.
static func hire_line(w: World, player: int, idx: int) -> String:
	var ps: PlayerState = w.players[player]
	var next_idx: int = Agents.hired_count(w, player)
	if idx != next_idx:
		return "Агент %d\nнужно нанять агента %d" % [idx + 1, next_idx + 1]
	if ps.hire_left > 0:
		return "Агент %d — наём\nвыйдет на ядре через %d с" % [idx + 1, (ps.hire_left + Defs.TICK_HZ - 1) / Defs.TICK_HZ]
	return "Агент %d — свободное место\nнанять на ядре: клавиша H (%d Б, %d с)" % [idx + 1, Agents.hire_cost(w, player), Defs.HIRE_SECONDS]

static func lines_for(w: World, player: int, idx: int, selected: bool) -> String:
	var a: AgentState = Agents.agent_of(w, player, idx)
	if not a.hired:
		return hire_line(w, player, idx)
	var out: Array[String] = []
	out.append("%sАгент %d [%d] — %s" % ["▶ " if selected else "", idx + 1, idx + 1, status_text(w, a)])
	if a.queue.is_empty():
		out.append("очередь пуста")
	else:
		for i in a.queue.size():
			var t: Array = a.queue[i]
			var line: String = "%d. %s" % [i + 1, Names.task(int(t[0]), int(t[2]), Names.node_label(w.nodes[int(t[1])]))]
			if i == 0 and a.mode == AgentState.Mode.IDLE and int(t[0]) != Defs.TaskKind.MOVE:
				var params: Array = Agents.task_params(int(t[0]), int(t[2]))
				if w.players[player].bank < int(params[1]):
					line += "  (ждёт байт: %d)" % int(params[1])
			out.append(line)
	return "\n".join(out)
