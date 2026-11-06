extends TestCase

func _labels(items: Array[Dictionary]) -> String:
	var out: Array[String] = []
	for it in items:
		out.append(String(it["label"]))
	return " | ".join(out)

func test_ring_menu_offers_hidden_virus_backdoor_and_activation() -> void:
	var w: World = TestMaps.siege()
	var t: String = _labels(RingMenu.items_for(w, 1, 3, 2))
	check(t.contains("Скрытый вирус"), t)
	check(t.contains("Бэкдор"), t)
	check(not t.contains("Активировать"), "без вируса активировать нечего: " + t)
	w.nodes[2].virus[1] = 1
	w.step()
	var t2: String = _labels(RingMenu.items_for(w, 1, 3, 2))
	check(t2.contains("Активировать: перехват"), t2)
	check(t2.contains("Активировать: отключить ПО"), t2)
	check(not t2.contains("Скрытый вирус ("), "второй вирус на ту же машину не предлагается: " + t2)

func test_ring_menu_clean_appears_only_for_found_threat() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].virus[1] = 1
	check(not _labels(RingMenu.items_for(w, 0, 0, 2)).contains("Вычистить"), "ненайденное в меню не просачивается")
	w.nodes[2].found[NodeState.hidden_slot(Defs.HiddenKind.VIRUS, 1)] = 1
	check(_labels(RingMenu.items_for(w, 0, 0, 2)).contains("Вычистить вирус"))

func test_activate_item_sends_command() -> void:
	var w: World = TestMaps.siege()
	w.nodes[2].virus[1] = 1
	var ic := InputCtl.new()
	ic.world = w
	ic.camera = CameraCtl.new()
	ic.local_player = 1
	ic.ring_target = 2
	ic.apply_item({"kind": "activate", "label": "x", "mode": Defs.ActivateMode.TAKEOVER})
	w.step()
	check_eq(w.nodes[2].owner, 1)
	ic.camera.free()
	ic.free()

func test_hidden_payload_key_and_hud_name() -> void:
	var ic := InputCtl.new()
	ic.world = TestMaps.siege()
	ic.camera = CameraCtl.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_H
	ev.pressed = true
	ic._on_key(ev)
	check_eq(ic.flow_type, Defs.PacketType.PAYLOAD_HIDDEN)
	check_eq(Hud.flow_type_name(Defs.PacketType.PAYLOAD_HIDDEN), "СКРЫТЫЙ [H]")
	ic.camera.free()
	ic.free()

func test_foreign_hidden_packets_not_drawn() -> void:
	var w: World = TestMaps.siege()
	w.step()
	for i in 4:
		Network.inject(w, 3, 2, Defs.PacketType.PAYLOAD_HIDDEN, 1, 0)
	w.run(1)
	var pv := PacketView.new()
	pv._ready()
	pv.refresh(w, 0.0, 0)
	var theirs: int = pv.counts[0] + pv.counts[1] + pv.counts[2]
	pv.refresh(w, 0.0, 1)
	var mine: int = pv.counts[0] + pv.counts[1] + pv.counts[2]
	check(mine > theirs, "свои скрытые пакеты видны, чужие нет: %d против %d" % [mine, theirs])
	pv.free()

func test_event_feed_hidden_lines() -> void:
	var w: World = TestMaps.siege()
	Knowledge.log_event(w, 0, Knowledge.EventKind.HIDDEN_FOUND, 2, -1, Defs.HiddenKind.BACKDOOR * 2)
	Knowledge.log_event(w, 0, Knowledge.EventKind.HIDDEN_FOUND, 2, -1, Defs.HiddenKind.VIRUS * 2 + 1)
	Knowledge.log_event(w, 0, Knowledge.EventKind.AGENT_SEEN, 2)
	var ev: Array = Knowledge.events_of(w, 0)
	check(EventFeed.line_for(w, ev[0]).contains("[IDS] найден бэкдор на M2"), EventFeed.line_for(w, ev[0]))
	check(EventFeed.line_for(w, ev[1]).contains("[Антивирус] найден скрытый вирус"), EventFeed.line_for(w, ev[1]))
	check(EventFeed.line_for(w, ev[2]).contains("чужой агент"))
