extends TestCase

func test_flow_only_from_own_node() -> void:
	var w: World = load_duel()
	w.submit(Command.start_flow(0, 0, 10, 22, Defs.PacketType.FLOOD, 5))   # 10 — ядро игрока 1
	w.step()
	check_eq(w.flows.size(), 0, "поток с чужого узла принят")
	check_eq(w.rejected_count, 1)
	w.submit(Command.start_flow(0, 1, 0, 22, Defs.PacketType.FLOOD, 5))
	w.step()
	check_eq(w.flows.size(), 1)
	check_eq(w.flows[0].src, 0)
	check_eq(w.flows[0].owner, 0)

func test_flow_validation() -> void:
	var w: World = load_duel()
	w.submit(Command.start_flow(0, 0, 0, 0, Defs.PacketType.FLOOD, 5))      # сам в себя
	w.submit(Command.start_flow(0, 0, 0, 99, Defs.PacketType.FLOOD, 5))     # нет цели
	w.submit(Command.start_flow(0, 0, 0, 5, Defs.PacketType.FLOOD, 0))      # нулевая интенсивность
	w.submit(Command.start_flow(0, 0, 0, 5, Defs.PacketType.FLOOD, 999))    # слишком большая
	w.submit(Command.start_flow(0, 0, 0, 5, Defs.PacketType.DATA, 5))       # DATA вручную нельзя
	w.submit(Command.start_flow(7, 0, 0, 5, Defs.PacketType.FLOOD, 5))      # нет такого игрока
	w.step()
	check_eq(w.flows.size(), 0)
	check_eq(w.rejected_count, 6)

func test_stop_flow_only_owner() -> void:
	var w: World = load_duel()
	w.submit(Command.start_flow(0, 0, 0, 22, Defs.PacketType.FLOOD, 5))
	w.step()
	var fid: int = w.flows[0].id
	w.submit(Command.stop_flow(1, 1, fid))
	w.step()
	check_eq(w.flows.size(), 1, "чужой игрок остановил поток")
	w.submit(Command.stop_flow(0, 2, fid))
	w.step()
	check_eq(w.flows.size(), 0)

func test_commands_apply_on_their_tick() -> void:
	var w: World = load_duel()
	w.submit(Command.start_flow(0, 5, 0, 22, Defs.PacketType.FLOOD, 5))
	w.run(5)
	check_eq(w.flows.size(), 0, "команда применилась раньше тика")
	w.step()
	check_eq(w.flows.size(), 1)
	check_eq(w.applied_log[0].tick, 5)
