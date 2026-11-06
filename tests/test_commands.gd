extends TestCase

func test_role_only_on_own_machine_or_core() -> void:
	var w: World = load_duel()
	w.submit(Command.set_role(0, 0, 10, Defs.Role.CAPTURE, 12))    # 10 — ядро игрока 1
	w.submit(Command.set_role(0, 0, 1, Defs.Role.CAPTURE, 2))      # 1 — шлюз: роли у шлюза нет
	w.step()
	check_eq(w.rejected_count, 2)
	check_eq(w.nodes[0].role, Defs.Role.WORK)
	w.submit(Command.set_role(0, 1, 0, Defs.Role.CAPTURE, 2))      # ядро игрока 0 берёт нейтральную машину рядом
	w.step()
	check_eq(w.rejected_count, 2)
	check_eq(w.nodes[0].role, Defs.Role.CAPTURE)
	check_eq(w.nodes[0].role_target, 2)

func test_role_validation() -> void:
	var w: World = load_duel()
	w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 0))       # сам в себя
	w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 99))      # нет цели
	w.submit(Command.set_role(0, 0, 0, Defs.Role.PRESSURE, 2))      # давить нейтрала нельзя
	w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 1))       # свой шлюз
	w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 22))      # дальше 3 хопов
	w.submit(Command.set_role(0, 0, 0, 99, 2))                      # нет такой роли
	w.submit(Command.set_role(7, 0, 0, Defs.Role.CAPTURE, 2))       # нет такого игрока
	w.submit(Command.make(Command.Type.SET_ROLE, 0, 0, [0, Defs.Role.CAPTURE]))   # не хватает аргумента
	w.step()
	check_eq(w.rejected_count, 8)
	check_eq(w.nodes[0].role, Defs.Role.WORK)

func test_role_reconfiguration_takes_five_seconds() -> void:
	var w: World = load_duel()
	w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 2))
	w.step()
	check(w.nodes[0].reconf > 0 and w.nodes[0].reconf <= Defs.ROLE_RECONF_TICKS, "счётчик перенастройки пошёл")
	var made: int = w.nodes[0].produce_acc
	w.run(Defs.ROLE_RECONF_TICKS - 5)
	check_eq(w.nodes[2].capture[0], 0, "пока идёт перенастройка, INIT не шлётся")
	check_eq(w.nodes[0].produce_acc, made, "ядро в перенастройке DATA не производит")
	w.run(60)
	check(w.nodes[2].capture[0] > 0 or w.nodes[2].owner == 0, "после перенастройки пошёл INIT")

func test_same_role_same_target_is_not_reconfigured() -> void:
	var w: World = load_duel()
	w.submit(Command.set_role(0, 0, 0, Defs.Role.CAPTURE, 2))
	w.run(Defs.ROLE_RECONF_TICKS + 5)
	var rc: int = w.nodes[0].reconf
	check_eq(rc, 0)
	w.submit(Command.set_role(0, w.tick, 0, Defs.Role.CAPTURE, 2))
	w.step()
	check_eq(w.nodes[0].reconf, 0, "та же роль на ту же цель не перенастраивается")

func test_commands_apply_on_their_tick() -> void:
	var w: World = load_duel()
	w.submit(Command.set_role(0, 5, 0, Defs.Role.CAPTURE, 2))
	w.run(5)
	check_eq(w.nodes[0].role, Defs.Role.WORK, "команда применилась раньше тика")
	w.step()
	check_eq(w.nodes[0].role, Defs.Role.CAPTURE)
	check_eq(w.applied_log[0].tick, 5)
