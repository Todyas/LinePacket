class_name CameraCtl
extends Camera2D
## Камера: зум к курсору и сдвиг. События мыши получает от InputCtl.

const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 1.12

## Размер окна в пикселях; обновляется каждый кадр, пока камера в дереве.
var view_size: Vector2 = Vector2(1600, 900)

func _process(_delta: float) -> void:
	view_size = get_viewport_rect().size

func pan_by(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom

func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_world(screen_pos)
	var z: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	var after: Vector2 = screen_to_world(screen_pos)
	position += before - after

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - view_size * 0.5) / zoom
