extends TestCase

func _duel(seed_value: int) -> World:
	return MapLoader.load_file("res://maps/duel.json", seed_value)["world"]

func _bots(w: World, seed_value: int) -> Array[Bot]:
	var out: Array[Bot] = []
	for p in w.players.size():
		out.append(Bot.new(BotView.new(w, p), seed_value))
	return out

func _play(w: World, bots: Array[Bot], ticks: int) -> void:
	for i in ticks:
		for b in bots:
			b.act()
		w.step()

func test_bot_source_never_touches_true_world_state() -> void:
	# Бот не обращается к истинному состоянию: в его коде нет мира, узлов, игроков и прямых чтений знаний.
	var src: String = FileAccess.get_file_as_string("res://ai/bot.gd")
	check(src.length() > 1000, "исходник бота прочитан")
	for token in ["World", "NodeState", "PlayerState", "LinkState", ".nodes", ".links", ".players", "state_hash",
			"Knowledge.snap", "Knowledge.level", "Knowledge.owner_of", "Knowledge.age", "Knowledge.events_of", "Stealth.", "Economy.", "Network."]:
		check(not src.contains(token), "бот не должен обращаться к «%s»" % token)

func test_bot_view_hides_enemy_state_without_scan() -> void:
	var w: World = TestMaps.scout()
	var v := BotView.new(w, 0)
	check(not v.own(0).is_empty(), "свой узел виден подробно")
	check(v.own(3).is_empty(), "чужой узел подробно не виден")
	check_eq(v.owner_of(3), Knowledge.UNKNOWN_OWNER)
	check(v.snap(3) == null)
	check_eq(v.age(3), -1)
	var mine: Array[int] = v.my_nodes()
	check(not mine.has(3) and mine.has(0))

func test_bot_expands_fortifies_and_scouts() -> void:
	var w: World = _duel(3)
	var bots: Array[Bot] = _bots(w, 3)
	_play(w, bots, 20 * 120)
	var v := BotView.new(w, 0)
	check(v.my_nodes().size() >= 7, "бот должен расширяться: %d узлов" % v.my_nodes().size())
	check(w.nodes[0].has_soft(Defs.SoftType.IDS), "IDS на ядро — первым делом")
	var scanned: int = 0
	for n in w.nodes:
		if Knowledge.level(w, 0, n.id) == Knowledge.Level.SNAPSHOT:
			scanned += 1
	check(scanned > 0, "разведка оставила снимки")

func test_bot_responds_to_ids_log_with_defence() -> void:
	var w: World = TestMaps.siege()
	w.players[0].bank = 500
	w.step()
	var bot := Bot.new(BotView.new(w, 0), 1)
	Knowledge.log_event(w, 0, Knowledge.EventKind.IDS_ATTACK, 2, 1, Defs.PacketType.FLOOD)
	var queued: Array = []
	for i in 30:
		bot.act()
		w.step()
	for a in w.agents:
		if a.owner == 0:
			for t in a.queue:
				queued.append(t)
	var mentions: bool = w.nodes[2].has_soft(Defs.SoftType.FIREWALL) or w.nodes[2].has_soft(Defs.SoftType.ANTIVIRUS)
	for t in queued:
		if int(t[1]) == 2:
			mentions = true
	check(mentions, "под атакой по логу IDS бот укрепляет узел 2")

func test_bot_activates_its_hidden_virus() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].virus[1] = 1
	w.step()
	var bot := Bot.new(BotView.new(w, 1), 1)
	for i in 20:
		bot.act()
		w.step()
	check_eq(w.nodes[2].owner, 1, "готовый вирус бот активирует")

func test_bot_match_is_deterministic() -> void:
	var a: World = _duel(5)
	var b: World = _duel(5)
	_play(a, _bots(a, 5), 3000)
	_play(b, _bots(b, 5), 3000)
	check_eq(a.state_hash(), b.state_hash(), "матч бот против бота даёт один хеш")
	var c: World = _duel(6)
	_play(c, _bots(c, 6), 3000)
	check(c.state_hash() != a.state_hash(), "другой сид — другой матч")

func test_bot_rarely_issues_rejected_commands() -> void:
	var w: World = _duel(7)
	_play(w, _bots(w, 7), 20 * 240)
	check(w.rejected_count <= w.applied_log.size() / 10 + 3, "отвергнуто %d из %d команд" % [w.rejected_count, w.applied_log.size() + w.rejected_count])

func test_bot_yields_contested_neutral_instead_of_deadlocking() -> void:
	# Оба бьют INIT в один нейтрал с равной скоростью: шкалы гасят друг друга. Бот должен уступить.
	var w: World = TestMaps.build({
		"name": "dispute", "players": 2,
		"nodes": [TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 300, 0), TestMaps.node(2, "machine", 600, 0), TestMaps.node(3, "core", 900, 0, 1)],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3)],
	})
	var bot := Bot.new(BotView.new(w, 0), 1)
	w.submit(Command.set_role(1, 0, 3, Defs.Role.CAPTURE, 1))   # оба начинают одновременно
	for i in 20 * 25:
		bot.act()
		w.step()
	check_eq(w.nodes[1].owner, Defs.NEUTRAL, "спор: никто не взял за 25 с")
	var bot_init: int = _capture_roles_on(w, 0, 1)
	check(bot_init > 0, "бот пока бьёт в цель")
	for i in 20 * 50:
		bot.act()
		w.step()
	check_eq(w.nodes[1].owner, 1, "бот уступил, соперник взял узел")

func _capture_roles_on(w: World, player: int, target: int) -> int:
	var c: int = 0
	for n in w.nodes:
		if n.owner == player and n.role == Defs.Role.CAPTURE and n.role_target == target:
			c += 1
	return c
