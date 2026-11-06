extends SceneTree
## Печатает хеш базового сценария — для сравнения между процессами.
## godot --headless --path . -s tools/hash_scenario.gd

func _initialize() -> void:
	var w: World = Scenarios.build_basic(777)
	w.run(1000)
	print("HASH ", w.state_hash())
	quit(0)
