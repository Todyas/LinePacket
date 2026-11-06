extends TestCase

func test_slots_limit_and_no_duplicates() -> void:
	var w: World = TestMaps.chain()
	var m: NodeState = w.nodes[1]                   # машина: 2 слота
	check(m.install_soft(Defs.SoftType.FIREWALL))
	check(not m.install_soft(Defs.SoftType.FIREWALL), "дубликат не ставится")
	check(m.install_soft(Defs.SoftType.STORAGE))
	check(not m.install_soft(Defs.SoftType.RELAY), "третье ПО в машину не помещается")
	var core: NodeState = w.nodes[0]                # ядро: 3 слота
	check(core.install_soft(Defs.SoftType.FIREWALL))
	check(core.install_soft(Defs.SoftType.STORAGE))
	check(core.install_soft(Defs.SoftType.RELAY))
	check_eq(core.free_slots(), 0)

func test_software_eats_cpu() -> void:
	var w: World = TestMaps.chain()
	var m: NodeState = w.nodes[1]
	var base: int = m.cpu_per_s
	m.install_soft(Defs.SoftType.RELAY)
	check_eq(m.cpu_per_s, base - int(Defs.SOFT_DEFS[Defs.SoftType.RELAY]["cpu_per_s"]))
	check(m.cpu_load_pct() > 0, "постоянная нагрузка ПО видна в загрузке")

func test_firewall_cuts_foreign_flood_to_limit_and_eats_cpu() -> void:
	var plain: World = _flooded(false)
	var guarded: World = _flooded(true)
	plain.run(400)
	guarded.run(400)
	var secs: int = 20
	var passed_plain: int = plain.delivered[Defs.PacketType.FLOOD]
	var passed_fw: int = guarded.delivered[Defs.PacketType.FLOOD]
	check(passed_plain > passed_fw * 2, "без файрвола флуда доходит заметно больше (%d против %d)" % [passed_plain, passed_fw])
	var per_s: int = passed_fw / secs
	check(per_s >= Defs.FIREWALL_LIMIT_PER_S - 1 and per_s <= Defs.FIREWALL_LIMIT_PER_S + 2, "через файрвол %d/с при лимите %d" % [per_s, Defs.FIREWALL_LIMIT_PER_S])
	check(guarded.drops[World.DROP_FIREWALL] > 0, "файрвол должен сбрасывать излишек")
	check_eq(plain.drops[World.DROP_FIREWALL], 0)
	# Файрвол ест CPU: проверка каждого пакета.
	check(guarded.nodes[2].cpu_load_pct() >= 75, "файрвол должен грузить CPU, загрузка %d" % guarded.nodes[2].cpu_load_pct())

func _flooded(with_firewall: bool) -> World:
	var w: World = TestMaps.star()
	Economy.capture_node(w, w.nodes[2], 0)      # цель — машина игрока 0
	if with_firewall:
		w.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	w.submit(Command.start_flow(1, 0, 1, 2, Defs.PacketType.FLOOD, 20))
	return w

func test_firewall_ignores_own_traffic() -> void:
	var w: World = TestMaps.star()
	Economy.capture_node(w, w.nodes[2], 0)
	w.nodes[2].install_soft(Defs.SoftType.FIREWALL)
	w.submit(Command.start_flow(0, 0, 0, 2, Defs.PacketType.FLOOD, 20))
	w.run(200)
	check_eq(w.drops[World.DROP_FIREWALL], 0, "свой трафик файрвол не режет")

func test_relay_multiplies_outgoing_flow_and_cuts_own_income() -> void:
	var a: World = TestMaps.pair(200, "optic")
	var b: World = TestMaps.pair(200, "optic")
	b.nodes[0].install_soft(Defs.SoftType.RELAY)
	a.submit(Command.start_flow(0, 0, 0, 1, Defs.PacketType.FLOOD, 5))
	b.submit(Command.start_flow(0, 0, 0, 1, Defs.PacketType.FLOOD, 5))
	a.run(201)
	b.run(201)
	var ta: int = a.delivered[Defs.PacketType.FLOOD] + a.pool.alive_count + a.total_drops()
	var tb: int = b.delivered[Defs.PacketType.FLOOD] + b.pool.alive_count + b.total_drops()
	check_eq(tb, ta * 2, "ретранслятор удваивает исходящий поток (%d → %d)" % [ta, tb])
	# Меньше своего дохода: буфер без шлюза копится вдвое медленнее.
	var c: World = TestMaps.eco_fan(0, -1)
	var d: World = TestMaps.eco_fan(0, -1)
	d.nodes[0].install_soft(Defs.SoftType.RELAY)
	c.run(200)
	d.run(200)
	check_eq(c.nodes[0].buffer, 2 * d.nodes[0].buffer, "выработка DATA с ретранслятором вдвое меньше")

func test_storage_raises_buffer_limit() -> void:
	var w: World = TestMaps.eco_fan(1, -1)
	var m: NodeState = w.nodes[4]
	m.install_soft(Defs.SoftType.STORAGE)
	w.run(120 * 20)
	var expect: int = int(Defs.BUFFER_LIMIT[Defs.NodeType.MACHINE]) + Defs.STORAGE_BUFFER_BONUS
	check_eq(m.buffer, expect, "хранилище должно поднять лимит буфера")

func test_software_cleared_when_node_released_or_recaptured() -> void:
	var w: World = TestMaps.chain()
	w.nodes[1].install_soft(Defs.SoftType.FIREWALL)
	Economy.release_node(w, w.nodes[1])
	check_eq(w.nodes[1].free_slots(), 2)
	check_eq(w.nodes[1].access_mask, 0)
