class_name Menu
extends Control
## Главное меню: новая игра против бота с выбором сида и стороны, выход.

const GAME_SCENE: String = "res://view/main.tscn"

var seed_edit: LineEdit
var side_pick: OptionButton
var map_pick: OptionButton

func _ready() -> void:
	RenderingServer.set_default_clear_color(Palette.BACKGROUND)
	var title := Label.new()
	title.text = "LinePacket"
	title.position = Vector2(0, 150)
	title.size = Vector2(1600, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	add_child(title)
	var sub := Label.new()
	sub.text = "Дуэль в сети: захватите ядро соперника"
	sub.position = Vector2(0, 245)
	sub.size = Vector2(1600, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	add_child(sub)
	var panel := Panel.new()
	panel.position = Vector2(550, 330)
	panel.size = Vector2(500, 500)
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(panel)
	_add_label(panel, "Сид матча", Vector2(40, 30))
	seed_edit = LineEdit.new()
	seed_edit.position = Vector2(40, 62)
	seed_edit.size = Vector2(420, 40)
	seed_edit.text = str(GameConfig.fresh_seed())
	seed_edit.add_theme_font_size_override("font_size", 20)
	panel.add_child(seed_edit)
	_add_label(panel, "Ваша сторона", Vector2(40, 124))
	side_pick = OptionButton.new()
	side_pick.position = Vector2(40, 156)
	side_pick.size = Vector2(420, 40)
	side_pick.add_theme_font_size_override("font_size", 20)
	side_pick.add_item("Игрок 1 (голубой)")
	side_pick.add_item("Игрок 2 (оранжевый)")
	side_pick.selected = GameConfig.player_side
	panel.add_child(side_pick)
	_add_label(panel, "Карта", Vector2(40, 208))
	map_pick = OptionButton.new()
	map_pick.position = Vector2(40, 240)
	map_pick.size = Vector2(420, 40)
	map_pick.add_theme_font_size_override("font_size", 20)
	for m in GameConfig.MAPS:
		map_pick.add_item(String(m["name"]))
	map_pick.selected = GameConfig.map_index
	panel.add_child(map_pick)
	var start := Button.new()
	start.text = "Новая игра против бота"
	start.position = Vector2(40, 312)
	start.size = Vector2(420, 56)
	start.add_theme_font_size_override("font_size", 22)
	start.pressed.connect(start_game)
	panel.add_child(start)
	var quit_btn := Button.new()
	quit_btn.text = "Выход"
	quit_btn.position = Vector2(40, 384)
	quit_btn.size = Vector2(420, 46)
	quit_btn.add_theme_font_size_override("font_size", 20)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	panel.add_child(quit_btn)
	var help := Label.new()
	help.text = "ЛКМ-перетаскивание: поток · ПКМ: меню узла · F I P H S: тип потока · 1–5: агент · H: нанять · Пробел: пауза"
	help.position = Vector2(0, 790)
	help.size = Vector2(1600, 30)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", Color(0.5, 0.58, 0.66))
	add_child(help)
	_add_label(panel, "Тот же сид и сторона дают тот же матч.", Vector2(40, 452), 14)

func _add_label(parent: Control, text: String, pos: Vector2, font: int = 18) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font)
	parent.add_child(l)

func apply_config() -> void:
	GameConfig.seed_value = GameConfig.parse_seed(seed_edit.text, 1)
	GameConfig.player_side = side_pick.selected
	GameConfig.map_index = map_pick.selected
	GameConfig.vs_bot = true

func start_game() -> void:
	apply_config()
	get_tree().change_scene_to_file(GAME_SCENE)
