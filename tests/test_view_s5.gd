extends TestCase

func _labels(items: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for it in items:
		out.append(String(it["label"]))
	return " | ".join(out)

func test_ring_menu_offers_scan_within_range_and_nothing_blind() -> void:
	var w: World = TestMaps.scout()
	# Узел 3 — чужое ядро в 3 хопах: известен только силуэт.
	var t: String = _labels(RingMenu.items_for(w, 0, 0, 3))
	check(t.contains("Скан"), t)
	check(not t.contains("PAYLOAD"), "вирус на неизвестную цель не предлагается: " + t)
	check(not t.contains("FLOOD"), t)
	check(not t.contains("Агент сюда"), t)
	check(not _labels(RingMenu.items_for(w, 0, 0, 0)).contains("Скан"), "свой узел не сканируют")

func test_ring_menu_after_scan_knows_enemy() -> void:
	var w: World = TestMaps.scout()
	w.submit(Command.start_flow(0, 0, 0, 3, Defs.PacketType.SCAN, Defs.SCAN_FLOW_RATE))
	w.run(120)
	var t: String = _labels(RingMenu.items_for(w, 0, 0, 3))
	check(t.contains("PAYLOAD"), t)
	check(t.contains("FLOOD"), t)

func test_scan_out_of_range_not_offered() -> void:
	var w: World = TestMaps.build({
		"name": "line", "players": 2,
		"nodes": [
			TestMaps.node(0, "core", 0, 0, 0), TestMaps.node(1, "machine", 200, 0), TestMaps.node(2, "machine", 400, 0),
			TestMaps.node(3, "machine", 600, 0), TestMaps.node(4, "core", 800, 0, 1),
		],
		"links": [TestMaps.link(0, 1), TestMaps.link(1, 2), TestMaps.link(2, 3), TestMaps.link(3, 4)],
	})
	check(not _labels(RingMenu.items_for(w, 0, 0, 4)).contains("Скан"))
	check(_labels(RingMenu.items_for(w, 0, 0, 3)).contains("Скан"))

func test_card_silhouette_hides_state_and_snapshot_shows_age() -> void:
	var w: World = TestMaps.scout()
	w.nodes[3].install_soft(Defs.SoftType.FIREWALL)
	var t: String = NodeCard.text_for(w, 3, 0)
	check(t.contains("Данных нет"), t)
	check(not t.contains("Файрвол") and not t.contains("Игрок 2"), "силуэт ничего не раскрывает: " + t)
	w.submit(Command.start_flow(0, 0, 0, 3, Defs.PacketType.SCAN, Defs.SCAN_FLOW_RATE))
	w.run(300)
	var t2: String = NodeCard.text_for(w, 3, 0)
	check(t2.contains("СНИМОК"), t2)
	check(t2.contains("Файрвол"), t2)
	check(t2.contains("с назад"), t2)

func test_event_feed_lines() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].install_soft(Defs.SoftType.IDS)
	w.submit(Command.start_flow(1, 0, 3, 2, Defs.PacketType.SCAN, 4))
	w.run(100)
	var lines: Array[String] = []
	for e in Knowledge.events_of(w, 0):
		lines.append(EventFeed.line_for(w, e))
	check(lines.size() > 0)
	var joined: String = " ".join(lines)
	check(joined.contains("[IDS] скан на M2 с линка"), joined)

func test_packets_only_visible_near_observed_nodes() -> void:
	var w: World = TestMaps.scout()
	w.step()
	# Пакеты P1 на линке 2–3 (P0 его не видит) и на линке 0–1 (виден).
	for i in 3:
		Network.inject(w, 3, 2, Defs.PacketType.FLOOD, 1, 0)
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	w.run(2)
	var pv := PacketView.new()
	pv._ready()
	pv.refresh(w, 0.0, -1)
	var all: int = pv.counts[0] + pv.counts[1] + pv.counts[2]
	pv.refresh(w, 0.0, 0)
	var mine: int = pv.counts[0] + pv.counts[1] + pv.counts[2]
	check(all > mine, "туман прячет пакеты на невидимых линках: %d против %d" % [all, mine])
	check(mine > 0, "свои линки видны")
	pv.free()
