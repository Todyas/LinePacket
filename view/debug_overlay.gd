class_name DebugOverlay
extends CanvasLayer
## F3 (только в debug-сборке): FPS, тик, пакеты в полёте, потери в секунду, время тика симуляции.

var label: Label
var step_ms: float = 0.0
var drops_per_s: int = 0
var world: World

func _ready() -> void:
	layer = 10
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	add_child(label)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_F3 and OS.is_debug_build():
			visible = not visible

func _process(_delta: float) -> void:
	if not visible or world == null:
		return
	label.text = text_for(world, Engine.get_frames_per_second(), step_ms, drops_per_s)

static func text_for(w: World, fps: int, step_ms_value: float, drops_s: int) -> String:
	return "FPS %d\nтик %d\nпакетов в полёте %d\nпотерь/с %d\nтик симуляции %.2f мс" % [
		fps, w.tick, w.pool.alive_count, drops_s, step_ms_value]
