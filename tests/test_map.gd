extends TestCase

func test_duel_loads() -> void:
	var res: Dictionary = MapLoader.load_file("res://maps/duel.json", 1)
	check(res["world"] != null, "карта не грузится: " + str(res["error"]))
	var w: World = res["world"]
	check_eq(w.nodes.size(), 24)
	check_eq(w.players.size(), 2)
	check_eq(w.links.size(), 33)

func test_duel_composition() -> void:
	var w: World = load_duel()
	var counts: Dictionary = {}
	for n in w.nodes:
		counts[n.type] = int(counts.get(n.type, 0)) + 1
	check_eq(counts[Defs.NodeType.CORE], 2)
	check_eq(counts[Defs.NodeType.GATEWAY], 4)
	check_eq(counts[Defs.NodeType.SWITCH], 4)
	check_eq(counts[Defs.NodeType.MACHINE], 14)

func test_duel_start_ownership() -> void:
	var w: World = load_duel()
	for p in 2:
		var owned: Array[int] = []
		for n in w.nodes:
			if n.owner == p:
				owned.append(n.type)
		owned.sort()
		check_eq(owned, [Defs.NodeType.CORE, Defs.NodeType.GATEWAY], "стартовые узлы игрока %d" % p)

func test_duel_is_mirrored() -> void:
	var w: World = load_duel()
	# Зеркало по вертикальной оси x=800: узел i <-> i+10, центр на оси.
	for i in 10:
		var l: NodeState = w.nodes[i]
		var r: NodeState = w.nodes[i + 10]
		check_eq(l.type, r.type, "тип узла %d" % i)
		check_eq(l.x + r.x, 1600, "x узла %d" % i)
		check_eq(l.y, r.y, "y узла %d" % i)
	for i in range(20, 24):
		check_eq(w.nodes[i].x, 800)
	# Множество линков совпадает с зеркальным.
	var set_l: Dictionary = {}
	for l in w.links:
		set_l["%d-%d-%d" % [mini(l.a, l.b), maxi(l.a, l.b), l.kind]] = true
	for l in w.links:
		var a: int = _mirror(l.a)
		var b: int = _mirror(l.b)
		var key: String = "%d-%d-%d" % [mini(a, b), maxi(a, b), l.kind]
		check(set_l.has(key), "нет зеркального линка для %d-%d" % [l.a, l.b])

func _mirror(i: int) -> int:
	if i < 10:
		return i + 10
	if i < 20:
		return i - 10
	if i == 20 or i == 21 or i == 22 or i == 23:
		return i
	return i

func test_broken_maps_give_clear_errors() -> void:
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/duel.json"))
	# неизвестный тип узла
	var m1: Dictionary = good.duplicate(true)
	m1["nodes"][3]["type"] = "toaster"
	var r1: Dictionary = MapLoader.load_dict(m1, 1)
	check(r1["world"] == null, "карта с toaster принята")
	check(String(r1["error"]).contains("toaster"), "ошибка не называет проблему: " + str(r1["error"]))
	# линк на несуществующий узел
	var m2: Dictionary = good.duplicate(true)
	m2["links"][0]["b"] = 999
	var r2: Dictionary = MapLoader.load_dict(m2, 1)
	check(r2["world"] == null)
	check(String(r2["error"]).contains("999"), str(r2["error"]))
	# нет ядра игрока
	var m3: Dictionary = good.duplicate(true)
	m3["nodes"][0]["type"] = "machine"
	var r3: Dictionary = MapLoader.load_dict(m3, 1)
	check(r3["world"] == null)
	check(String(r3["error"]).contains("нет ядра"), str(r3["error"]))
	# несвязный граф
	var m4: Dictionary = good.duplicate(true)
	var keep: Array = []
	for l in m4["links"]:
		if l["a"] != 9 and l["b"] != 9:
			keep.append(l)
	m4["links"] = keep
	var r4: Dictionary = MapLoader.load_dict(m4, 1)
	check(r4["world"] == null)
	check(String(r4["error"]).contains("несвязный"), str(r4["error"]))
	# нет файла и мусор
	check(MapLoader.load_file("res://maps/nope.json", 1)["world"] == null)
	check(MapLoader.load_dict({}, 1)["world"] == null)

func test_link_latency_from_length() -> void:
	var w: World = load_duel()
	for l in w.links:
		check(l.latency >= Defs.LINK_MIN_LATENCY)
		check(l.length > 0)
