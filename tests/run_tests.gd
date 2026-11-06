extends SceneTree
## Запуск: godot --headless --path . -s tests/run_tests.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dir := DirAccess.open("res://tests")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total: int = 0
	var failed: int = 0
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var t: TestCase = script.new()
		var names: Array[String] = []
		for m in script.get_script_method_list():
			if String(m["name"]).begins_with("test_"):
				names.append(m["name"])
		names.sort()
		for n in names:
			total += 1
			t.current_test = "%s::%s" % [f, n]
			var before: int = t.failures.size()
			await t.call(n)
			if t.failures.size() > before:
				failed += 1
				for i in range(before, t.failures.size()):
					print("FAIL ", t.failures[i])
			else:
				print("ok   ", t.current_test)
	print("--- тестов: %d, провалено: %d" % [total, failed])
	quit(1 if failed > 0 else 0)
