extends SceneTree
## Матч бот против бота без графики со статистикой.
## godot --headless --path . -s tools/bot_match.gd -- <seed> [минут] [карта]

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1
	var max_min: int = int(args[1]) if args.size() > 1 else 30
	var map_path: String = args[2] if args.size() > 2 else "res://maps/duel.json"
	var res: Dictionary = MapLoader.load_file(map_path, seed_value)
	if res["world"] == null:
		push_error(res["error"])
		quit(2)
		return
	var w: World = res["world"]
	var bots: Array[Bot] = []
	for p in w.players.size():
		bots.append(Bot.new(BotView.new(w, p), seed_value))
	var t0: int = Time.get_ticks_msec()
	var limit: int = max_min * 60 * Defs.TICK_HZ
	while w.winner < 0 and w.tick < limit:
		for b in bots:
			b.act()
		w.step()
	print("MATCH seed=%d ticks=%d minutes=%.1f winner=%d captures=%s earned=%s hash=%d ms=%d" % [
		seed_value, w.tick, float(w.tick) / float(Defs.TICK_HZ) / 60.0, w.winner,
		str([w.players[0].captures, w.players[1].captures]), str([w.players[0].earned_total, w.players[1].earned_total]),
		w.state_hash(), Time.get_ticks_msec() - t0])
	quit(0)
