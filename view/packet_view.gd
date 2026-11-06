class_name PacketView
extends Node2D
## Все пакеты в пути рисуются тремя MultiMesh (точка, треугольник, крупный значок).
## Позиция считается на кадре из тика входа и длины линка — в симуляции её нет.

const CAT_DOT: int = 0
const CAT_ATTACK: int = 1
const CAT_BIG: int = 2
const FLOATS: int = 12      # 8 на Transform2D + 4 на цвет
const SIZES: Array[float] = [10.0, 14.0, 22.0]
const LANE_OFFSET: float = 3.0   # смещение встречных направлений друг от друга

var _mms: Array[MultiMesh] = []
var _bufs: Array[PackedFloat32Array] = []
var _caps: Array[int] = [0, 0, 0]
var counts: Array[int] = [0, 0, 0]   # сколько пакетов нарисовано в последнем кадре

func _ready() -> void:
	z_index = 1
	var shapes: Array[String] = ["dot", "triangle", "big"]
	for i in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		var quad := QuadMesh.new()
		quad.size = Vector2(SIZES[i], SIZES[i])
		mm.mesh = quad
		_mms.append(mm)
		_bufs.append(PackedFloat32Array())
		_resize(i, 512)
		var inst := MultiMeshInstance2D.new()
		inst.multimesh = mm
		inst.texture = _make_texture(shapes[i])
		add_child(inst)

func _resize(cat: int, cap: int) -> void:
	_caps[cat] = cap
	_mms[cat].instance_count = cap
	_mms[cat].visible_instance_count = 0
	_bufs[cat].resize(cap * FLOATS)

static func category(ptype: int) -> int:
	match ptype:
		Defs.PacketType.AGENT:
			return CAT_BIG
		Defs.PacketType.FLOOD, Defs.PacketType.PAYLOAD, Defs.PacketType.PAYLOAD_HIDDEN:
			return CAT_ATTACK
		_:
			return CAT_DOT

static func _make_texture(shape: String) -> ImageTexture:
	var sz: int = 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c: float = float(sz) * 0.5
	for y in sz:
		for x in sz:
			var inside: bool = false
			var fx: float = float(x) + 0.5
			var fy: float = float(y) + 0.5
			match shape:
				"dot":
					inside = Vector2(fx - c, fy - c).length() <= c - 1.0
				"triangle":
					# вершина вверху, основание внизу
					var t: float = fy / float(sz)
					inside = t > 0.08 and t < 0.95 and absf(fx - c) <= (t - 0.08) * c * 1.15
				_:
					inside = absf(fx - c) + absf(fy - c) <= c - 1.0
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
	return ImageTexture.create_from_image(img)

## Скрытый PAYLOAD чужого игрока не рисуется: владелец цели его не видит.
static func _stealthy(pool: PacketPool, idx: int, viewer: int) -> bool:
	return viewer >= 0 and pool.ptype[idx] == Defs.PacketType.PAYLOAD_HIDDEN and pool.owner[idx] != viewer

## Обновить буферы. frac — доля тика (0..1) для интерполяции между тиками.
## viewer >= 0: рисуются только пакеты на линках рядом с наблюдаемыми узлами этого игрока.
func refresh(w: World, frac: float, viewer: int = -1) -> void:
	if _mms.is_empty():
		return
	var need: Array[int] = [0, 0, 0]
	var pool: PacketPool = w.pool
	var tf: float = float(w.tick) + frac
	counts = [0, 0, 0]
	# Первый проход: сколько нужно мест по категориям.
	for l in w.links:
		if viewer >= 0 and not Knowledge.link_visible(w, viewer, l.id):
			continue
		for d in 2:
			var q: IntQueue = l.chan[d]
			for i in q.size():
				var pi: int = q.at(i) & LinkState.IDX_MASK
				if _stealthy(pool, pi, viewer):
					continue
				need[category(pool.ptype[pi])] += 1
	for cat in 3:
		if need[cat] > _caps[cat]:
			var cap: int = _caps[cat]
			while cap < need[cat]:
				cap *= 2
			_resize(cat, cap)
	# Второй проход: запись.
	for l in w.links:
		if viewer >= 0 and not Knowledge.link_visible(w, viewer, l.id):
			continue
		var na: NodeState = w.nodes[l.a]
		var nb: NodeState = w.nodes[l.b]
		var vx: float = float(nb.x - na.x)
		var vy: float = float(nb.y - na.y)
		var ln: float = maxf(1.0, sqrt(vx * vx + vy * vy))
		var ux: float = vx / ln
		var uy: float = vy / ln
		var px: float = -uy * LANE_OFFSET
		var py: float = ux * LANE_OFFSET
		var lat: float = float(l.latency)
		for d in 2:
			var q: IntQueue = l.chan[d]
			var n: int = q.size()
			if n == 0:
				continue
			var sx: float = float(na.x)
			var sy: float = float(na.y)
			var dx: float = vx
			var dy: float = vy
			var ox: float = px
			var oy: float = py
			if d == 1:
				sx = float(nb.x)
				sy = float(nb.y)
				dx = -vx
				dy = -vy
				ox = -px
				oy = -py
			for i in n:
				var e: int = q.at(i)
				var idx: int = e & LinkState.IDX_MASK
				if _stealthy(pool, idx, viewer):
					continue
				var t: float = clampf((tf - float(e >> LinkState.IDX_BITS)) / lat, 0.0, 1.0)
				var cat: int = category(pool.ptype[idx])
				var k: int = counts[cat] * FLOATS
				counts[cat] += 1
				var buf: PackedFloat32Array = _bufs[cat]
				var col: Color = Palette.of_owner(pool.owner[idx])
				buf[k] = 1.0
				buf[k + 1] = 0.0
				buf[k + 2] = 0.0
				buf[k + 3] = sx + dx * t + ox
				buf[k + 4] = 0.0
				buf[k + 5] = 1.0
				buf[k + 6] = 0.0
				buf[k + 7] = sy + dy * t + oy
				buf[k + 8] = col.r
				buf[k + 9] = col.g
				buf[k + 10] = col.b
				buf[k + 11] = 1.0
				_bufs[cat] = buf
	for cat in 3:
		_mms[cat].buffer = _bufs[cat]
		_mms[cat].visible_instance_count = counts[cat]
