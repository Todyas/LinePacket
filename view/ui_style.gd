class_name UiStyle
extends RefCounted
## Общий вид панелей интерфейса.

static func panel(border: Color = Color(0.25, 0.3, 0.38)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb
