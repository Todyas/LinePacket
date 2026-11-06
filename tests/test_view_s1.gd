extends TestCase

func test_picking_node() -> void:
	var w: World = load_duel()
	check_eq(Picking.hit_node(w, Vector2(90, 450), 30.0), 0)
	check_eq(Picking.hit_node(w, Vector2(95, 455), 30.0), 0)
	check_eq(Picking.hit_node(w, Vector2(700, 800), 30.0), -1)

func test_picking_flow_follows_route() -> void:
	var w: World = TestMaps.diamond()
	w.submit(Command.start_flow(0, 0, 0, 3, Defs.PacketType.FLOOD, 5))
	w.step()
	var fid: int = w.flows[0].id
	# середина первой ветки 0→1: ((0,300)+(300,0))/2
	check_eq(Picking.hit_flow(w, 0, Vector2(150, 150), 10.0), fid)
	check_eq(Picking.hit_flow(w, 0, Vector2(150, 800), 10.0), -1, "точка далеко от маршрута")
	check_eq(Picking.hit_flow(w, 1, Vector2(150, 150), 10.0), -1, "чужой поток выбираться не должен")

func test_link_color_by_load() -> void:
	var idle: Color = GraphView.link_color(0)
	var busy: Color = GraphView.link_color(60)
	var jam: Color = GraphView.link_color(100)
	check(busy.get_luminance() > idle.get_luminance(), "загруженный линк должен быть ярче")
	check_eq(jam, Palette.OVERLOAD)

func test_packet_view_counts_match_channels() -> void:
	var w: World = TestMaps.grid(3, 600)
	for i in 6:
		Network.inject(w, 0, 8, Defs.PacketType.FLOOD, 0, 0)
	Network.inject(w, 0, 8, Defs.PacketType.AGENT, 0, 0)
	w.run(3)
	var pv := PacketView.new()
	pv._ready()
	pv.refresh(w, 0.5)
	var in_channels: int = 0
	for l in w.links:
		in_channels += l.in_flight_count()
	check(in_channels > 0)
	check_eq(pv.counts[0] + pv.counts[1] + pv.counts[2], in_channels)
	check(pv.counts[PacketView.CAT_ATTACK] > 0)
	pv.free()

func test_drop_fx_spawns_particles() -> void:
	var w: World = TestMaps.pair(200)
	for i in 50:
		Network.inject(w, 0, 1, Defs.PacketType.FLOOD, 0, 0)
	var fx := DropFx.new()
	fx.ingest(w)
	check_eq(fx.particle_count(), 20 * DropFx.PER_DROP)
	fx.ingest(w)   # повторно те же события не порождают новых искр
	check_eq(fx.particle_count(), 20 * DropFx.PER_DROP)
	fx.free()

func test_overlay_text() -> void:
	var w: World = TestMaps.pair(200)
	var t: String = DebugOverlay.text_for(w, 60, 1.25, 7)
	check(t.contains("FPS 60"))
	check(t.contains("1.25"))
	check(t.contains("потерь/с 7"))

func test_packet_view_frame_cost() -> void:
	var w: World = TestMaps.grid(8, 1200)
	var rng := Rng.new(7)
	for i in 300:
		var s: int = rng.range_int(0, 63)
		var d: int = rng.range_int(0, 64)
		if s != d and w.nodes[s].owner == 0:
			w.submit(Command.start_flow(0, 0, s, d, Defs.PacketType.FLOOD, 20))
	w.run(400)
	var pv := PacketView.new()
	pv._ready()
	var t0: int = Time.get_ticks_usec()
	for i in 20:
		pv.refresh(w, 0.5)
	var ms: float = float(Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	var n: int = pv.counts[0] + pv.counts[1] + pv.counts[2]
	print("    [кадр] пакетов нарисовано: %d, обновление буферов: %.2f мс" % [n, ms])
	check(n > 1500, "слишком мало пакетов для замера: %d" % n)
	check(ms < 14.0, "обновление PacketView слишком долгое: %.2f мс" % ms)
	pv.free()
