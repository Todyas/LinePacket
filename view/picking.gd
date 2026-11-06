class_name Picking
extends RefCounted
## Выбор объектов под курсором. Чистые функции — тестируются без сцены.

## Ближайший узел в радиусе radius (в координатах мира) или -1.
static func hit_node(w: World, pos: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for n in w.nodes:
		var d: float = Vector2(n.x, n.y).distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = n.id
	return best
