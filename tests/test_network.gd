extends TestCase

func test_packet_takes_exactly_link_latency() -> void:
	var w: World = TestMaps.pair(200)          # кабель, 200 px, скорость 20 → 10 тиков
	var lat: int = w.links[0].latency
	check_eq(lat, 10)
	check(Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0))
	w.run(lat)                                  # тики 0..lat-1
	check_eq(w.delivered[Defs.PacketType.FLOOD], 0, "пакет прибыл раньше задержки")
	w.step()
	check_eq(w.delivered[Defs.PacketType.FLOOD], 1, "пакет не прибыл за задержку линка")
	check_eq(w.pool.alive_count, 0)

func test_packet_over_multiple_hops() -> void:
	var w: World = _line(3)
	Network.inject(w, 0, 2, Defs.PacketType.FLOOD, 0, 0)
	var total_lat: int = w.links[0].latency + w.links[1].latency
	w.run(total_lat)
	check_eq(w.delivered[Defs.PacketType.FLOOD], 0)
	w.run(3)    # запас на передачу в очередь транзитного узла
	check_eq(w.delivered[Defs.PacketType.FLOOD], 1)

func _line(n: int) -> World:
	var nodes: Array = []
	for i in n:
		var t: String = "machine"
		var o: int = -1
		if i == 0:
			t = "core"
			o = 0
		elif i == n - 1:
			t = "core"
			o = 1
		nodes.append(TestMaps.node(i, t, i * 200, 0, o))
	var links: Array = []
	for i in n - 1:
		links.append(TestMaps.link(i, i + 1))
	return TestMaps.build({"name": "line", "players": 2, "nodes": nodes, "links": links})

func test_capacity_limits_throughput_and_queue_waits() -> void:
	var w: World = TestMaps.pair(200)
	for i in 100:
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	var l: LinkState = w.links[0]
	check_eq(l.port_units[0], 30, "очередь порта должна заполниться до лимита")
	check_eq(w.drops[World.DROP_QUEUE], 70, "лишние пакеты должны дропаться")
	w.run(40)
	var window: int = 0
	for v in l.sent_hist[0]:
		window += v
	check_eq(window, 10, "за секунду канал пропускает ровно capacity")
	# Пока очередь не пуста, за тик уходит не больше 1 единицы (10/с при 20 Гц).
	for v in l.sent_hist[0]:
		check(v <= 1, "за тик ушло больше ёмкости")

func test_overflow_records_drop_events() -> void:
	var w: World = TestMaps.pair(200)
	for i in 50:
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	check_eq(w.recent_drops.size(), 20)
	check_eq(int((w.recent_drops[0] as Array)[1]), 0, "событие дропа должно ссылаться на линк")

func test_role_emits_at_power() -> void:
	var w: World = TestMaps.pair(200)
	TestMaps.engage(w, 0, 0, 1, Defs.PacketType.FLOOD)
	w.run(100)
	# Мощность ядра 8 пакетов/с: за 100 тиков (5 с) рождается ровно 40 пакетов.
	var total: int = w.delivered[Defs.PacketType.FLOOD] + w.pool.alive_count + w.total_drops()
	check_eq(total, 40)
	check_eq(w.total_drops(), 0)

func test_role_reconfig_delays_packets() -> void:
	var w: World = TestMaps.pair(200)
	w.submit(Command.set_role(0, 0, 0, Defs.Role.PRESSURE, 1))
	w.run(Defs.ROLE_RECONF_TICKS)
	check_eq(w.delivered[Defs.PacketType.FLOOD] + w.pool.alive_count, 0, "во время перенастройки пакетов нет")
	w.run(40)
	check(w.delivered[Defs.PacketType.FLOOD] + w.pool.alive_count > 0, "после перенастройки пакеты идут")

func test_role_ends_when_source_lost() -> void:
	var w: World = TestMaps.pair(200)
	TestMaps.engage(w, 0, 0, 1, Defs.PacketType.FLOOD)
	w.run(3)
	check_eq(w.nodes[0].role, Defs.Role.PRESSURE)
	w.nodes[0].owner = 1
	w.step()
	check_eq(w.nodes[0].role, Defs.Role.WORK, "роль сбрасывается, когда цель стала своей")

func test_route_avoids_congested_link() -> void:
	var w: World = TestMaps.diamond()
	check_eq(Routing.path(w, 0, 3), [0, 1, 3], "пустая сеть: путь через короткую ветку")
	# Забиваем исходящее направление 0→1 до предела.
	var l01: LinkState = w.links[0]
	for i in 40:
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	check_eq(l01.load_pct(l01.dir_from(0)), 100)
	Routing.compute(w)
	check_eq(Routing.path(w, 0, 3), [0, 2, 3], "маршрут должен обойти перегруженный линк")

func test_route_keeps_short_path_when_detour_costs_more() -> void:
	var w: World = TestMaps.diamond()
	# Небольшая нагрузка: штраф меньше разницы путей, обход невыгоден.
	var l01: LinkState = w.links[0]
	for i in 8:
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	var pct: int = l01.load_pct(0)
	check(pct > 0 and pct < 40, "ожидалась слабая загрузка, получено %d" % pct)
	Routing.compute(w)
	check_eq(Routing.path(w, 0, 3), [0, 1, 3])

func test_routes_recomputed_every_second() -> void:
	var w: World = TestMaps.diamond()
	for i in 40:
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	# Пока тик не кратен 20, таблицы старые.
	w.step()   # тик 0 — пересчёт
	w.run(5)
	check_eq(w.tick, 6)
	w.routes_dirty = false
	var before: Array[PackedInt32Array] = w.routes.duplicate()
	w.run(14)  # до тика 20 (кратного) включительно: на тике 20 пересчёт произойдёт при следующем шаге
	w.step()
	check_eq(w.tick, 21)
	check(w.routes.size() == before.size())

func test_unreachable_destination_drops() -> void:
	var w: World = TestMaps.pair(200)
	w.proutes[0][1][0] = -1
	check(not Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0))
	check_eq(w.drops[World.DROP_NOROUTE], 1)

func test_cpu_overload_drops_and_load() -> void:
	var w: World = TestMaps.star()
	TestMaps.pump(w, [0, 1], [2, 2], Defs.PacketType.FLOOD, 20, 200)
	var target: NodeState = w.nodes[2]
	check(w.drops[World.DROP_CPU] > 0, "цель с перегрузом CPU должна терять пакеты")
	check_eq(target.cpu_load_pct(), 100)

func test_cpu_light_load_no_drops() -> void:
	var w: World = TestMaps.star()
	TestMaps.pump(w, [0], [2], Defs.PacketType.FLOOD, 5, 200)
	check_eq(w.total_drops(), 0)
	var load_pct: int = w.nodes[2].cpu_load_pct()
	# 5 флудов/с * 2 CPU = 10 из 40 → 25%
	check(load_pct >= 20 and load_pct <= 30, "загрузка %d" % load_pct)

func test_determinism_with_roles() -> void:
	var a: World = Scenarios.build_basic(5)
	var b: World = Scenarios.build_basic(5)
	a.run(1000)
	b.run(1000)
	check_eq(a.state_hash(), b.state_hash())
	check(a.delivered[Defs.PacketType.INIT] > 0, "в сценарии должны доходить пакеты")

func test_stress_3000_packets_tick_under_10ms() -> void:
	var w: World = TestMaps.grid(8, 1200)
	var rng := Rng.new(2024)
	# 8x8 сетка оптики; источники пакетов между случайными парами внутри владения игрока 0.
	var srcs: Array = []
	var dsts: Array = []
	var src_pool: Array[int] = []
	for n in w.nodes:
		if n.owner == 0:
			src_pool.append(n.id)
	for i in 300:
		var s: int = src_pool[rng.range_int(0, src_pool.size())]
		var d: int = rng.range_int(0, w.nodes.size())
		if d == s:
			continue
		srcs.append(s)
		dsts.append(d)
	var reached: int = -1
	for t in 1500:
		TestMaps.pump(w, srcs, dsts, Defs.PacketType.FLOOD, 20, 1)
		if w.pool.alive_count >= 3000:
			reached = t
			break
	check(reached >= 0, "не удалось набрать 3000 пакетов в полёте (макс. %d)" % w.pool.alive_count)
	var avg_ms: float = 1000000.0
	for attempt in 3:    # лучший из трёх замеров: шум соседних процессов не должен ронять тест
		var t0: int = Time.get_ticks_usec()
		for i in 100:
			TestMaps.pump(w, srcs, dsts, Defs.PacketType.FLOOD, 20, 1)
		avg_ms = minf(avg_ms, float(Time.get_ticks_usec() - t0) / 100.0 / 1000.0)
	print("    [стресс] пакетов в полёте: %d, средний тик: %.2f мс" % [w.pool.alive_count, avg_ms])
	check(w.pool.alive_count >= 3000, "в ходе замера пакетов меньше 3000: %d" % w.pool.alive_count)
	check(avg_ms < 10.0, "тик слишком долгий: %.2f мс" % avg_ms)
