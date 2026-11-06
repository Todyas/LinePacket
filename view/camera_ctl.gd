class_name CameraCtl
extends Camera2D
## Перетаскивание ЛКМ/СКМ и зум колёсиком к курсору.

const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 1.12

var dragging: bool = false
## Размер окна в пикселях; обновляется каждый кадр, пока камера в дереве.
var view_size: Vector2 = Vector2(1600, 900)
## Если задан и возвращает true — ЛКМ-перетаскивание камеры блокируется (ввод потоков).
var drag_blocker: Callable = Callable()

func _process(_delta: float) -> void:
	view_size = get_viewport_rect().size

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if not _wheel_blocked():
				zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if not _wheel_blocked():
				zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT:
			dragging = mb.pressed
	elif event is InputEventMouseMotion and dragging:
		var mm: InputEventMouseMotion = event
		position -= mm.relative / zoom

func _wheel_blocked() -> bool:
	return false

func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_world(screen_pos)
	var z: float = clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	var after: Vector2 = screen_to_world(screen_pos)
	position += before - after

func screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - view_size * 0.5) / zoom
