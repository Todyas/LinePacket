extends SceneTree
## Печатает хеши сценариев — для сравнения между процессами.
## godot --headless --path . -s tools/hash_scenario.gd

func _initialize() -> void:
	var a: World = Scenarios.build_basic(777)
	a.run(1000)
	var b: World = Scenarios.build_economy(778)
	b.run(1500)
	var c: World = Scenarios.build_agents(779)
	c.run(1500)
	var d: World = Scenarios.build_siege(780)
	d.run(1500)
	print("HASH ", a.state_hash(), " ", b.state_hash(), " ", c.state_hash(), " ", d.state_hash())
	quit(0)
