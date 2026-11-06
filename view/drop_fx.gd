class_name DropFx
extends Node2D
## Потерянные пакеты осыпаются красными искрами. Чисто визуальный эффект.

const LIFE: float = 0.9
const PER_DROP: int = 3
const MAX_PARTICLES: int = 600

var _parts: Array = []     # [x, y, vx, vy, age]
var _last_tick: int = -1
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.seed = 12345
	z_index = 3

func ingest(w: World) -> void:
	for ev in w.recent_drops:
		var t: int = ev[0]
		if t <= _last_tick:
			continue
		var l: LinkState = w.links[ev[1]]
		var from_n: NodeState = w.nodes[l.a if ev[2] == 0 else l.b]
		var to_n: NodeState = w.nodes[l.b if ev[2] == 0 else l.a]
		var dir: Vector2 = (Vector2(to_n.x, to_n.y) - Vector2(from_n.x, from_n.y)).normalized()
		var base: Vector2 = Vector2(from_n.x, from_n.y) + dir * 40.0
		for i in PER_DROP:
			if _parts.size() >= MAX_PARTICLES:
				break
			_parts.append([base.x, base.y, _rng.randf_range(-30.0, 30.0), _rng.randf_range(-40.0, -5.0), 0.0])
	if not w.recent_drops.is_empty():
		_last_tick = maxi(_last_tick, int((w.recent_drops[w.recent_drops.size() - 1] as Array)[0]))

func _process(delta: float) -> void:
	var i: int = 0
	while i < _parts.size():
		var p: Array = _parts[i]
		p[4] += delta
		if p[4] >= LIFE:
			_parts.remove_at(i)
			continue
		p[3] += 220.0 * delta   # «осыпаются» вниз
		p[0] += p[2] * delta
		p[1] += p[3] * delta
		i += 1
	queue_redraw()

func particle_count() -> int:
	return _parts.size()

func _draw() -> void:
	for p in _parts:
		var a: float = 1.0 - float(p[4]) / LIFE
		draw_rect(Rect2(Vector2(p[0], p[1]), Vector2(3, 3)), Color(1.0, 0.25, 0.2, a))
