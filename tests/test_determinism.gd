extends TestCase

func test_same_seed_same_commands_same_hash() -> void:
	var a: World = Scenarios.build_basic(42)
	var b: World = Scenarios.build_basic(42)
	a.run(1000)
	b.run(1000)
	check_eq(a.tick, 1000)
	check_eq(a.state_hash(), b.state_hash(), "хеш на 1000-м тике расходится")

func test_hash_changes_with_commands() -> void:
	var a: World = Scenarios.build_basic(42)
	var b: World = Scenarios.build_basic(42)
	b.submit(Command.start_flow(0, 100, 0, 23, Defs.PacketType.FLOOD, 3))
	a.run(1000)
	b.run(1000)
	check(a.state_hash() != b.state_hash(), "команда не повлияла на хеш")

func test_hash_changes_with_tick() -> void:
	var a: World = Scenarios.build_basic(42)
	a.run(10)
	var h10: int = a.state_hash()
	a.run(1)
	check(a.state_hash() != h10)

func test_replay_gives_same_hash() -> void:
	var w: World = Scenarios.build_basic(99)
	w.run(1000)
	var rep: Replay = Replay.from_world(w, "res://maps/duel.json")
	var path: String = "user://test_replay.json"
	check(rep.save(path), "реплей не сохранился")
	var loaded: Replay = Replay.load_file(path)
	check(loaded != null, "реплей не загрузился")
	var w2: World = loaded.play()
	check(w2 != null)
	check_eq(w2.tick, 1000)
	check_eq(w2.state_hash(), w.state_hash(), "реплей даёт другой хеш")
