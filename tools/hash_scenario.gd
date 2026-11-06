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
	var e: World = Scenarios.build_stealth(781)
	e.run(2000)
	# Основной тест детерминизма: матч бот против бота.
	var f: World = MapLoader.load_file("res://maps/duel.json", 782)["world"]
	var bots: Array[Bot] = []
	for p in f.players.size():
		bots.append(Bot.new(BotView.new(f, p), 782))
	while f.tick < 6000 and f.winner < 0:
		for bot in bots:
			bot.act()
		f.step()
	print("HASH ", a.state_hash(), " ", b.state_hash(), " ", c.state_hash(), " ", d.state_hash(), " ", e.state_hash(), " ", f.state_hash())
	quit(0)
