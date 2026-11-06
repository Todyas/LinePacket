class_name GraphView
extends Node2D
## Рисует граф: форма узла по типу, цвет обводки по владельцу. Только читает мир.

var world: World

const NODE_RADIUS: float = 22.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	for l in world.links:
		var a: NodeState = world.nodes[l.a]
		var b: NodeState = world.nodes[l.b]
		var width: float = 2.0
		match l.kind:
			Defs.LinkKind.OPTIC:
				width = 4.0
			Defs.LinkKind.WIFI:
				width = 1.5
		draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), Palette.LINK, width, true)
	var font: Font = ThemeDB.fallback_font
	for n in world.nodes:
		_draw_node(n, font)

func shape_points(type: int, center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match type:
		Defs.NodeType.CORE:   # шестиугольник
			for i in 6:
				var ang: float = TAU * float(i) / 6.0
				pts.append(center + Vector2(cos(ang), sin(ang)) * r * 1.25)
		Defs.NodeType.GATEWAY:   # ромб
			pts.append(center + Vector2(0, -r * 1.3))
			pts.append(center + Vector2(r * 1.3, 0))
			pts.append(center + Vector2(0, r * 1.3))
			pts.append(center + Vector2(-r * 1.3, 0))
		Defs.NodeType.SWITCH:   # квадрат
			pts.append(center + Vector2(-r, -r))
			pts.append(center + Vector2(r, -r))
			pts.append(center + Vector2(r, r))
			pts.append(center + Vector2(-r, r))
		_:   # машина — круг
			for i in 24:
				var ang2: float = TAU * float(i) / 24.0
				pts.append(center + Vector2(cos(ang2), sin(ang2)) * r)
	return pts

func _draw_node(n: NodeState, font: Font) -> void:
	var c: Vector2 = Vector2(n.x, n.y)
	var pts: PackedVector2Array = shape_points(n.type, c, NODE_RADIUS)
	draw_colored_polygon(pts, Palette.NODE_FILL)
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Palette.of_owner(n.owner), 3.0, true)
	var label: String = _node_label(n)
	draw_string(font, c + Vector2(-20, NODE_RADIUS + 22), label, HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Palette.NEUTRAL)

func _node_label(n: NodeState) -> String:
	var prefix: String = "?"
	match n.type:
		Defs.NodeType.CORE:
			prefix = "C"
		Defs.NodeType.MACHINE:
			prefix = "M"
		Defs.NodeType.GATEWAY:
			prefix = "G"
		Defs.NodeType.SWITCH:
			prefix = "S"
	return "%s%d" % [prefix, n.id]
