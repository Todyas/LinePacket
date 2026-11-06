class_name TestCase
extends RefCounted
## Базовый класс тестов: методы test_* вызывает tests/run_tests.gd.

var failures: Array[String] = []
var current_test: String = ""

func check(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: %s" % [current_test, msg if msg != "" else "условие ложно"])

func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: ожидалось %s, получено %s %s" % [current_test, str(expected), str(actual), msg])

func load_duel(seed_value: int = 1) -> World:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", seed_value)
	assert(res["world"] != null, res["error"])
	return res["world"]
