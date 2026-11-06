class_name GameConfig
extends RefCounted
## Настройки матча, выбранные в меню. Живут между сценами; sim их не видит.

const MAP_PATH: String = "res://maps/duel.json"
const SEED_MAX: int = 999999999

static var seed_value: int = 1
## За какую сторону играет человек; бот ведёт другую.
static var player_side: int = 0
static var vs_bot: bool = true

## Сид из текста поля: пустой или неверный ввод даёт fallback.
static func parse_seed(text: String, fallback: int = 1) -> int:
	var t: String = text.strip_edges()
	if not t.is_valid_int():
		return fallback
	var v: int = absi(t.to_int())
	return clampi(v, 1, SEED_MAX)
