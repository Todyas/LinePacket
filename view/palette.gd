class_name Palette
extends RefCounted
## Цвета игроков. Цвет не единственный носитель смысла: игрока дублируют подписи.

const NEUTRAL: Color = Color(0.55, 0.57, 0.62)
const PLAYERS: Array[Color] = [
	Color(0.25, 0.85, 1.0),   # P1 — голубой
	Color(1.0, 0.62, 0.2),    # P2 — оранжевый
	Color(0.7, 0.9, 0.3),     # P3
	Color(0.9, 0.4, 0.9),     # P4
]
const BACKGROUND: Color = Color(0.055, 0.065, 0.085)
const LINK: Color = Color(0.22, 0.26, 0.32)
const NODE_FILL: Color = Color(0.09, 0.11, 0.14)

static func of_owner(owner: int) -> Color:
	if owner < 0 or owner >= PLAYERS.size():
		return NEUTRAL
	return PLAYERS[owner]
