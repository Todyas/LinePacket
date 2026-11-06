class_name PauseScreen
extends CanvasLayer
## Пауза: мир стоит, видна панель с продолжением, выходом в меню и из игры.

signal resume_requested
signal menu_requested

var _dim: ColorRect
var _panel: Panel

func _ready() -> void:
	layer = 11
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.size = Vector2(1600, 900)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_panel = Panel.new()
	_panel.position = Vector2(600, 300)
	_panel.size = Vector2(400, 300)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	_dim.add_child(_panel)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.position = Vector2(0, 20)
	title.size = Vector2(400, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	_panel.add_child(title)
	_add_button("Продолжить (Пробел / Esc)", 90, func() -> void: resume_requested.emit())
	_add_button("В главное меню", 150, func() -> void: menu_requested.emit())
	_add_button("Выйти из игры", 210, func() -> void: get_tree().quit())
	visible = false

func _add_button(text: String, y: float, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.position = Vector2(60, y)
	b.size = Vector2(280, 46)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(fn)
	_panel.add_child(b)
