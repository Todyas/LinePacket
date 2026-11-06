class_name GraphView
extends Node2D
## Рисует граф: форма узла по типу, цвет обводки по владельцу. Только читает мир.

var world: World
## Что рисует экземпляр: линки и потоки или узлы (так пакеты оказываются между слоями).
var draw_links: bool = true
var draw_nodes: bool = false
var hover_flow: int = -1
var selected_node: int = -1
var agent_player: int = 0

const NODE_RADIUS: float = 22.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	if draw_links:
		_draw_links()
		_draw_flows()
	if draw_nodes:
		var font: Font = ThemeDB.fallback_font
		for n in world.nodes:
			_draw_node(n, font)

func _draw_links() -> void:
	for l in world.links:
		var a: NodeState = world.nodes[l.a]
		var b: NodeState = world.nodes[l.b]
		var width: float = 2.0
		match l.kind:
			Defs.LinkKind.OPTIC:
				width = 4.0
			Defs.LinkKind.WIFI:
				width = 1.5
		var load_pct: int = maxi(l.load_pct(0), l.load_pct(1))
		draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), link_color(load_pct), width, true)

## Яркость растёт с загрузкой, перегруз — красный.
static func link_color(load_pct: int) -> Color:
	if load_pct >= 90:
		return Palette.OVERLOAD
	return Palette.LINK.lerp(Palette.LINK_HOT, float(load_pct) / 90.0)

func _draw_flows() -> void:
	var font: Font = ThemeDB.fallback_font
	for f in world.flows:
		var path: Array[int] = Routing.path(world, f.src, f.dst)
		if path.size() < 2:
			continue
		var col: Color = Palette.of_owner(f.owner)
		var hot: bool = f.id == hover_flow
		col.a = 0.9 if hot else 0.35
		var pts := PackedVector2Array()
		for nid in path:
			pts.append(Vector2(world.nodes[nid].x, world.nodes[nid].y))
		draw_polyline(pts, col, 5.0 if hot else 2.5, true)
		var mid: Vector2 = (pts[0] + pts[1]) * 0.5 + Vector2(6, -8)
		draw_string(font, mid, "%d/с" % f.rate, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

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
	var owner_col: Color = Palette.of_owner(n.owner)
	if n.owner >= 0 and n.type != Defs.NodeType.CORE:
		_draw_control_fill(pts, c, n.control, owner_col)
	elif n.owner >= 0:
		draw_colored_polygon(pts, Color(owner_col, 0.35))
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, owner_col, 3.0, true)
	# Кольцо захвата: чем полнее, тем ближе нейтрал к сдаче.
	if n.owner < 0 and Defs.INIT_NEEDED.has(n.type):
		var needed: int = int(Defs.INIT_NEEDED[n.type])
		for p in Defs.MAX_PLAYERS:
			if n.capture[p] > 0:
				var frac: float = clampf(float(n.capture[p]) / float(needed), 0.0, 1.0)
				draw_arc(c, NODE_RADIUS + 12.0 + 4.0 * p, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Palette.of_owner(p), 4.0, true)
	if n.owner >= 0:
		_draw_attack_meters(n, c)
	if n.down:
		var d: float = NODE_RADIUS * 0.7
		draw_line(c + Vector2(-d, -d), c + Vector2(d, d), Palette.OVERLOAD, 3.0, true)
		draw_line(c + Vector2(-d, d), c + Vector2(d, -d), Palette.OVERLOAD, 3.0, true)
	if n.id == selected_node:
		draw_arc(c, NODE_RADIUS + 8.0, 0.0, TAU, 48, Color(1, 1, 1, 0.85), 2.0, true)
	_draw_agent_marks(n, c, font)
	var label: String = Names.node_label(n)
	draw_string(font, c + Vector2(-20, NODE_RADIUS + 22), label, HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Palette.NEUTRAL)
	if n.owner >= 0 and n.buffer > 0:
		draw_string(font, c + Vector2(NODE_RADIUS + 6, -NODE_RADIUS), "%d" % n.buffer, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.85, 0.3))

## Шкалы заражения (толстая дуга) и подбора пароля (тонкая) цветом атакующего.
func _draw_attack_meters(n: NodeState, c: Vector2) -> void:
	for p in Defs.MAX_PLAYERS:
		if p == n.owner:
			continue
		if n.infect[p] > 0:
			var f: float = clampf(float(n.infect[p]) / float(Defs.INFECT_MAX), 0.0, 1.0)
			draw_arc(c, NODE_RADIUS + 6.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Palette.of_owner(p), 4.0, true)
		if n.brute[p] > 0:
			var g: float = clampf(float(n.brute[p]) / float(Defs.BRUTE_MAX), 0.0, 1.0)
			draw_arc(c, NODE_RADIUS + 13.0, -PI / 2.0, -PI / 2.0 + TAU * g, 40, Color(Palette.of_owner(p), 0.7), 2.0, true)

## Заливка снизу вверх пропорционально контролю.
func _draw_control_fill(pts: PackedVector2Array, c: Vector2, control: int, col: Color) -> void:
	var frac: float = clampf(float(control) / float(Defs.CONTROL_MAX), 0.0, 1.0)
	if frac <= 0.0:
		return
	var ext: float = NODE_RADIUS * 1.4
	var top: float = c.y + ext - 2.0 * ext * frac
	var rect := PackedVector2Array([
		Vector2(c.x - ext * 2.0, top), Vector2(c.x + ext * 2.0, top),
		Vector2(c.x + ext * 2.0, c.y + ext * 2.0), Vector2(c.x - ext * 2.0, c.y + ext * 2.0)])
	var parts: Array[PackedVector2Array] = Geometry2D.intersect_polygons(pts, rect)
	for poly in parts:
		if poly.size() >= 3:
			draw_colored_polygon(poly, Color(col, 0.55))

## Номера своих агентов, стоящих на узле.
func _draw_agent_marks(n: NodeState, c: Vector2, font: Font) -> void:
	var k: int = 0
	for a in world.agents:
		if a.node != n.id or a.owner != agent_player:
			continue
		var pos: Vector2 = c + Vector2(-NODE_RADIUS - 14.0 - 16.0 * k, -NODE_RADIUS)
		draw_rect(Rect2(pos - Vector2(7, 9), Vector2(14, 16)), Palette.of_owner(a.owner))
		draw_string(font, pos + Vector2(-4, 4), "%d" % (a.id + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.BACKGROUND)
		k += 1
