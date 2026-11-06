class_name GraphView
extends Node2D
## Рисует граф: форма узла по типу, цвет обводки по владельцу, значок роли внутри. Только читает мир.

var world: World
## Что рисует экземпляр: линки и линии ролей или узлы (так пакеты оказываются между слоями).
var draw_links: bool = true
var draw_nodes: bool = false
var selected_node: int = -1
var agent_player: int = 0
## Чьими глазами рисуем; -1 — всеведущий взгляд (отладка и тесты).
var viewer: int = -1

const NODE_RADIUS: float = 22.0

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	if draw_links:
		_draw_links()
		_draw_role_lines()
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
		var seen: bool = viewer < 0 or Knowledge.link_visible(world, viewer, l.id)
		var col: Color = Palette.LINK
		if seen:
			col = link_color(maxi(l.load_pct(0), l.load_pct(1)))
		else:
			col = Palette.BACKGROUND.lerp(Palette.LINK, 0.6)   # загрузку не видно: линк тусклый
		draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), col, width, true)

## Яркость растёт с загрузкой, перегруз — красный.
static func link_color(load_pct: int) -> Color:
	if load_pct >= 90:
		return Palette.OVERLOAD
	return Palette.LINK.lerp(Palette.LINK_HOT, float(load_pct) / 90.0)

## Линии от боевых машин к целям: цвет владельца, свои ярче; чужие видны, только если узел наблюдается или есть снимок.
func _draw_role_lines() -> void:
	for n in world.nodes:
		var role: int = n.role
		var target: int = n.role_target
		if viewer >= 0 and n.owner != viewer:
			var sn: NodeSnap = Knowledge.snap(world, viewer, n.id)
			if sn == null or sn.owner < 0 or sn.owner == viewer:
				continue
			role = sn.role
			target = sn.role_target
		if n.owner < 0 or not Defs.COMBAT_ROLES.has(role) or target < 0:
			continue
		var col: Color = role_color(role)
		var mine: bool = viewer < 0 or n.owner == viewer
		col.a = 0.75 if mine else 0.45
		var a: Vector2 = Vector2(n.x, n.y)
		var b: Vector2 = Vector2(world.nodes[target].x, world.nodes[target].y)
		draw_dashed_line(a, b, col, 2.5 if mine else 2.0, 10.0, true)
		var dir: Vector2 = (b - a).normalized()
		var tip: Vector2 = b - dir * (NODE_RADIUS + 6.0)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12.0 + dir.orthogonal() * 6.0, tip - dir * 12.0 - dir.orthogonal() * 6.0]), col)

static func role_color(role: int) -> Color:
	match role:
		Defs.Role.CAPTURE:
			return Color(0.45, 0.95, 0.55)
		Defs.Role.PRESSURE:
			return Color(1.0, 0.35, 0.3)
		Defs.Role.INFECT:
			return Color(0.8, 0.45, 1.0)
		Defs.Role.INFECT_HIDDEN:
			return Color(0.55, 0.4, 0.8)
		Defs.Role.WATCH:
			return Color(0.9, 0.9, 0.55)
	return Color(1.0, 0.85, 0.3)

## Значок роли внутри узла: монета — работа, флаг — захват, молния — давление, капля — заражение, пустая капля — тайное, глаз — дозор.
func draw_role_glyph(role: int, c: Vector2, col: Color) -> void:
	match role:
		Defs.Role.WORK:
			draw_circle(c, 6.0, col)
			draw_circle(c, 2.5, Palette.NODE_FILL)
		Defs.Role.CAPTURE:
			draw_line(c + Vector2(-4, 9), c + Vector2(-4, -9), col, 2.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -9), c + Vector2(8, -4), c + Vector2(-4, 1)]), col)
		Defs.Role.PRESSURE:
			draw_polyline(PackedVector2Array([c + Vector2(3, -10), c + Vector2(-5, 1), c + Vector2(1, 1), c + Vector2(-3, 10), c + Vector2(6, -2), c + Vector2(0, -2), c + Vector2(3, -10)]), col, 2.5, true)
		Defs.Role.INFECT:
			draw_circle(c + Vector2(0, 3), 6.0, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 1), c + Vector2(5, 1), c + Vector2(0, -10)]), col)
		Defs.Role.INFECT_HIDDEN:
			draw_arc(c + Vector2(0, 3), 6.0, 0.0, TAU, 24, col, 2.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-5, 1), c + Vector2(0, -10), c + Vector2(5, 1)]), col, 2.0, true)
		Defs.Role.WATCH:
			draw_arc(c + Vector2(0, 7), 11.0, -PI * 0.8, -PI * 0.2, 12, col, 2.0, true)
			draw_arc(c + Vector2(0, -7), 11.0, PI * 0.2, PI * 0.8, 12, col, 2.0, true)
			draw_circle(c, 3.5, col)

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
	var lvl: int = Knowledge.Level.OBSERVED
	if viewer >= 0:
		lvl = Knowledge.level(world, viewer, n.id)
	var live: bool = lvl == Knowledge.Level.OBSERVED
	var v_owner: int = n.owner
	var v_control: int = n.control
	var alpha: float = 1.0
	var age_s: int = 0
	if lvl == Knowledge.Level.SNAPSHOT:
		var s: NodeSnap = Knowledge.snap(world, viewer, n.id)
		v_owner = s.owner
		v_control = s.control
		age_s = Knowledge.age(world, viewer, n.id) / Defs.TICK_HZ
		alpha = lerpf(0.75, 0.3, clampf(float(age_s) / float(Defs.SNAPSHOT_FADE_S), 0.0, 1.0))
	elif lvl == Knowledge.Level.SILHOUETTE:
		v_owner = Defs.NEUTRAL
		v_control = 0
		alpha = 0.3
	var owner_col: Color = Palette.of_owner(v_owner)
	var line_col: Color = Palette.BACKGROUND.lerp(owner_col, alpha)
	if v_owner >= 0 and n.type != Defs.NodeType.CORE:
		_draw_control_fill(pts, c, v_control, Color(owner_col, alpha))
	elif v_owner >= 0:
		draw_colored_polygon(pts, Color(owner_col, 0.35 * alpha))
	var closed: PackedVector2Array = pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, line_col, 3.0, true)
	if v_owner >= 0 and lvl != Knowledge.Level.SILHOUETTE and (n.type == Defs.NodeType.MACHINE or n.type == Defs.NodeType.CORE):
		var g_role: int = n.role if live else Knowledge.snap(world, viewer, n.id).role
		draw_role_glyph(g_role, c, Color(Palette.of_owner(v_owner), 0.9 * alpha) if g_role == Defs.Role.WORK else Color(role_color(g_role), alpha))
	if live:
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
	var label_col: Color = Palette.BACKGROUND.lerp(Palette.NEUTRAL, 1.0 if live else maxf(alpha, 0.45))
	draw_string(font, c + Vector2(-20, NODE_RADIUS + 22), Names.node_label(n), HORIZONTAL_ALIGNMENT_CENTER, 40, 14, label_col)
	if lvl == Knowledge.Level.SNAPSHOT:
		draw_string(font, c + Vector2(-40, NODE_RADIUS + 36), "%d с назад" % age_s, HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(label_col, 0.9))
	if live and n.owner >= 0 and n.buffer > 0:
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
