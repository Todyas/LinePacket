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

## Индекс скорости в Defs.GAME_SPEEDS_PERCENT; помнится между матчами.
static var speed_index: int = Defs.GAME_SPEED_DEFAULT_INDEX

## Случайный сид для нового матча. Вид и меню не входят в sim, здесь случайность допустима.
static func fresh_seed() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r.randi_range(1, 99999)
