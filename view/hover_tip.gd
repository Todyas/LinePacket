class_name HoverTip
extends CanvasLayer
## Подсказка у курсора: узлы, потоки, тип потока в панели, задачи агентов, ПО в карточке.
## Показывается, когда мышь постояла на месте.

const DELAY_S: float = 0.3
const HUD_HEIGHT: float = 40.0
const AGENT_TOP: float = 770.0
const CARD_RECT: Rect2 = Rect2(1290, 52, 296, 330)

var world: World
var camera: CameraCtl
var input_ctl: InputCtl
var viewer: int = 0
var enabled: bool = true
var _panel: Panel
var _label: Label
var _last_pos: Vector2 = Vector2(-1, -1)
var _still: float = 0.0

func _ready() -> void:
	layer = 9
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(0.5, 0.6, 0.7)))
	add_child(_panel)
	_label = Label.new()
	_label.position = Vector2(10, 6)
	_label.add_theme_font_size_override("font_size", 15)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(320, 0)
	_label.size = Vector2(320, 10)
	_panel.add_child(_label)
	_panel.visible = false

func _process(delta: float) -> void:
	if world == null or camera == null or input_ctl == null:
		return
	var pos: Vector2 = get_viewport().get_mouse_position()
	if pos.distance_to(_last_pos) > 1.5:
		_still = 0.0
	else:
		_still += delta
	_last_pos = pos
	var busy: bool = not enabled or (input_ctl.ring != null and input_ctl.ring.is_open) or input_ctl.drag_from >= 0
	if busy or _still < DELAY_S:
		_panel.visible = false
		return
	var txt: String = text_at(world, viewer, input_ctl.local_player, pos, camera.screen_to_world(pos),
		camera.zoom.x, input_ctl.role_mode, input_ctl.selected_node)
	if txt == "":
		_panel.visible = false
		return
	show_text(txt, pos)

func show_text(txt: String, pos: Vector2) -> void:
	_label.text = txt
	_label.size = Vector2(320, 10)
	var h: float = _label.get_minimum_size().y + 12.0
	_panel.size = Vector2(340, h)
	var at: Vector2 = pos + Vector2(18, 20)
	at.x = minf(at.x, 1600.0 - _panel.size.x - 4.0)
	at.y = minf(at.y, 900.0 - h - 4.0)
	_panel.position = at
	_panel.visible = true

## Текст подсказки для точки экрана. Чистая функция: тестируется без сцены.
static func text_at(w: World, viewer: int, player: int, screen_pos: Vector2, world_pos: Vector2, zoom: float,
		role_mode: int, selected_node: int) -> String:
	if screen_pos.y < HUD_HEIGHT:
		return "Режим перетаскивания: машину тянете к цели. Сменить: Q W E R T.\n" + Hints.role(role_mode)
	if screen_pos.y >= AGENT_TOP:
		var i: int = int((screen_pos.x - 14.0) / 520.0)
		if i < 0 or i >= Defs.AGENTS_PER_PLAYER:
			return ""
		return agent_tip(w, player, i)
	if selected_node >= 0 and CARD_RECT.has_point(screen_pos):
		return soft_tip(w, viewer, selected_node)
	var nid: int = Picking.hit_node(w, world_pos, InputCtl.NODE_HIT_RADIUS / zoom)
	if nid >= 0:
		return Hints.node(w, viewer, nid)
	return ""

static func agent_tip(w: World, player: int, idx: int) -> String:
	var a: AgentState = Agents.agent_of(w, player, idx)
	if a.queue.is_empty():
		return "Агент %d. Очередь пуста: выберите клавишей %d, затем ПКМ по узлу." % [idx + 1, idx + 1]
	var head: Array = a.queue[0]
	return "Агент %d, текущая задача.\n%s" % [idx + 1, Hints.task(int(head[0]), int(head[2]))]

## ПО, которое игрок видит на узле, с описаниями.
static func soft_tip(w: World, viewer: int, node_id: int) -> String:
	var lines: Array[String] = []
	var shown: Array[int] = Hints.visible_soft(w, viewer, node_id)
	for t in shown:
		lines.append(Hints.soft(t))
	return "\n".join(lines)
