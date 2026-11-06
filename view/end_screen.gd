class_name EndScreen
extends CanvasLayer
## Экран конца матча: кто победил, сколько шло, захваты. Мир к этому моменту заморожен.

var world: World
var local_player: int = 0
var _panel: Panel
var _label: Label
var _button: Button
var _menu_button: Button

func _ready() -> void:
	layer = 10
	_panel = Panel.new()
	_panel.position = Vector2(500, 240)
	_panel.size = Vector2(600, 360)
	_panel.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(_panel)
	_label = Label.new()
	_label.position = Vector2(24, 18)
	_label.size = Vector2(552, 250)
	_label.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_label)
	_button = Button.new()
	_button.text = "Сыграть ещё раз"
	_button.position = Vector2(60, 296)
	_button.size = Vector2(220, 44)
	_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_panel.add_child(_button)
	_menu_button = Button.new()
	_menu_button.text = "В главное меню"
	_menu_button.position = Vector2(320, 296)
	_menu_button.size = Vector2(220, 44)
	_menu_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://view/menu.tscn"))
	_panel.add_child(_menu_button)
	_panel.visible = false

func _process(_delta: float) -> void:
	if world == null:
		return
	_panel.visible = world.winner >= 0
	if world.winner >= 0:
		_label.text = text_for(world, local_player)

static func text_for(w: World, viewer: int) -> String:
	var lines: Array[String] = []
	if w.winner < 0:
		return ""
	lines.append("ПОБЕДА" if w.winner == viewer else "ПОРАЖЕНИЕ")
	lines.append("Ядро захвачено: %s победил" % Names.owner_name(w.winner))
	var secs: int = w.finished_tick / Defs.TICK_HZ
	lines.append("Время матча: %d:%02d" % [secs / 60, secs % 60])
	for p in w.players.size():
		var pl: PlayerState = w.players[p]
		lines.append("%s: захватов %d, заработано %d Б, банк %d Б" % [Names.owner_name(p), pl.captures, pl.earned_total, pl.bank])
	return "\n".join(lines)
