class_name Hud
extends CanvasLayer
## Верхняя панель: банк, доход в секунду, текущий тип потока.

var label: Label
var world: World
var player: int = 0
var input_ctl: InputCtl
var speed_percent: int = 100

func _ready() -> void:
	layer = 5
	var bar := ColorRect.new()
	bar.color = Color(0.03, 0.04, 0.06, 0.8)
	bar.position = Vector2.ZERO
	bar.size = Vector2(1600, 40)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	label = Label.new()
	label.position = Vector2(14, 6)
	label.add_theme_font_size_override("font_size", 20)
	add_child(label)

func _process(_delta: float) -> void:
	if world == null:
		return
	var t: int = input_ctl.flow_type if input_ctl != null else Defs.PacketType.FLOOD
	label.text = text_for(world, player, t, speed_percent)
	label.add_theme_color_override("font_color", Palette.of_owner(player))

static func flow_type_name(t: int) -> String:
	match t:
		Defs.PacketType.FLOOD:
			return "FLOOD [W]"
		Defs.PacketType.INIT:
			return "INIT [Q]"
		Defs.PacketType.PAYLOAD:
			return "PAYLOAD [E]"
		Defs.PacketType.PAYLOAD_HIDDEN:
			return "СКРЫТЫЙ [R]"
		Defs.PacketType.SCAN:
			return "SCAN [T]"
	return "?"

static func text_for(w: World, player: int, flow_type: int, speed: int = -1) -> String:
	var p: PlayerState = w.players[player]
	var txt: String = "Игрок %d    Байты: %d    Доход: +%d/с    Поток: %s" % [player + 1, p.bank, p.income_per_s(), flow_type_name(flow_type)]
	if speed > 0:
		txt += "    Скорость: ×%s [-/+]" % ("%.2f" % (float(speed) / 100.0)).rstrip("0").rstrip(".")
	return txt
