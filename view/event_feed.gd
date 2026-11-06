class_name EventFeed
extends CanvasLayer
## Лента событий слева в стиле системного лога. Клик по строке центрирует камеру на узле.

signal focus_node(node_id: int)

const MAX_LINES: int = 9

var world: World
var player: int = 0
var _buttons: Array[Button] = []
var _shown_key: int = -1

func _ready() -> void:
	layer = 5
	for i in MAX_LINES:
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.position = Vector2(10, 52 + i * 26)
		b.size = Vector2(330, 24)
		b.add_theme_font_size_override("font_size", 14)
		b.visible = false
		var idx: int = i
		b.pressed.connect(func() -> void: _on_pressed(idx))
		add_child(b)
		_buttons.append(b)

var _nodes: Array[int] = []

func _on_pressed(i: int) -> void:
	if i < _nodes.size():
		focus_node.emit(_nodes[i])

func _process(_delta: float) -> void:
	if world == null:
		return
	var ev: Array = Knowledge.events_of(world, player)
	var key: int = ev.size() * 100003 + (int(ev.back()[0]) if not ev.is_empty() else 0) + player * 7919
	if key == _shown_key:
		return
	_shown_key = key
	_nodes.clear()
	for i in MAX_LINES:
		var b: Button = _buttons[i]
		var k: int = ev.size() - 1 - i
		if k < 0:
			b.visible = false
			continue
		var e: Array = ev[k]
		b.visible = true
		b.text = line_for(world, e)
		b.add_theme_color_override("font_color", color_for(int(e[1])))
		_nodes.append(int(e[2]))

static func color_for(kind: int) -> Color:
	match kind:
		Knowledge.EventKind.IDS_ATTACK:
			return Color(1.0, 0.75, 0.3)
		Knowledge.EventKind.NODE_LOST, Knowledge.EventKind.NODE_DOWN, Knowledge.EventKind.HIDDEN_FOUND:
			return Color(1.0, 0.4, 0.35)
		Knowledge.EventKind.AGENT_SEEN:
			return Color(1.0, 0.75, 0.3)
	return Color(0.6, 0.95, 0.7)

static func attack_name(ptype: int) -> String:
	match ptype:
		Defs.PacketType.FLOOD:
			return "флуд"
		Defs.PacketType.PAYLOAD, Defs.PacketType.PAYLOAD_HIDDEN:
			return "вирус"
		Defs.PacketType.INIT:
			return "подбор доступа"
	return "пакеты"

static func link_name(w: World, link_id: int) -> String:
	var l: LinkState = w.links[link_id]
	return "%s–%s" % [Names.node_label(w.nodes[l.a]), Names.node_label(w.nodes[l.b])]

static func line_for(w: World, e: Array) -> String:
	var secs: int = int(e[0]) / Defs.TICK_HZ
	var stamp: String = "%d:%02d" % [secs / 60, secs % 60]
	var node_lbl: String = Names.node_label(w.nodes[int(e[2])])
	match int(e[1]):
		Knowledge.EventKind.IDS_ATTACK:
			return "%s [IDS] %s на %s с линка %s" % [stamp, attack_name(int(e[4])), node_lbl, link_name(w, int(e[3]))]
		Knowledge.EventKind.NODE_CAPTURED:
			return "%s захвачена %s" % [stamp, node_lbl]
		Knowledge.EventKind.NODE_LOST:
			return "%s потеряна %s" % [stamp, node_lbl]
		Knowledge.EventKind.NODE_DOWN:
			return "%s %s легла от перегрузки" % [stamp, node_lbl]
		Knowledge.EventKind.HIDDEN_FOUND:
			var extra: int = int(e[4])
			var src: String = "Антивирус" if extra % 2 == 1 else "IDS"
			return "%s [%s] найден %s на %s" % [stamp, src, Defs.HIDDEN_NAMES[extra / 2], node_lbl]
		Knowledge.EventKind.AGENT_SEEN:
			return "%s [IDS] чужой агент на %s" % [stamp, node_lbl]
	return stamp
