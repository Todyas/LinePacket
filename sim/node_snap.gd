class_name NodeSnap
extends RefCounted
## Снимок чужого или давно не виденного узла: что игрок знал на тике tick.

var tick: int = 0
var owner: int = Defs.NEUTRAL
var control: int = 0
var access_mode: int = Defs.AccessMode.PASSWORD_WEAK
var soft: PackedInt32Array = PackedInt32Array()
var buffer: int = 0
var down: bool = false
var role: int = Defs.Role.WORK
var role_target: int = -1
var my_access: bool = false      # был ли у игрока доступ (по его же ключам) на момент снимка
## Скрытое: только то, что игрок вправе знать (свой вирус и бэкдор, найденное у себя, найденный сниффер).
var my_virus: bool = false
var my_backdoor: bool = false
var my_entry: bool = false       # есть ли у игрока вход на узел для агента: доступ, бэкдор, заражение, дверь или узел лежит
var my_infected: bool = false    # игрок заразил узел на 100%
var found_virus: bool = false       # на своей машине найден чужой вирус
var found_backdoor: bool = false
var sniffer_known: bool = false

static func capture(n: NodeState, player: int, at_tick: int) -> NodeSnap:
	var s := NodeSnap.new()
	s.tick = at_tick
	s.owner = n.owner
	s.control = n.control
	s.access_mode = n.access_mode
	s.soft = n.soft.duplicate()
	s.sniffer_known = n.owner == player or n.found[NodeState.hidden_slot(Defs.HiddenKind.SNIFFER, player)] == 1
	if not s.sniffer_known:
		for i in s.soft.size():
			if s.soft[i] == Defs.SoftType.SNIFFER:
				s.soft[i] = -1      # чужой сниффер без находки IDS не виден
	s.buffer = n.buffer
	s.down = n.down
	s.role = n.role
	s.role_target = n.role_target
	s.my_access = (n.access_mask & (1 << player)) != 0
	s.my_virus = n.virus[player] == 1
	s.my_backdoor = n.backdoor[player] == 1
	s.my_infected = n.infected_by(player)
	s.my_entry = n.owner != player and Agents.can_enter(n, player)
	if n.owner == player:
		for a in Defs.MAX_PLAYERS:
			if n.virus[a] == 1 and n.found[NodeState.hidden_slot(Defs.HiddenKind.VIRUS, a)] == 1:
				s.found_virus = true
			if n.backdoor[a] == 1 and n.found[NodeState.hidden_slot(Defs.HiddenKind.BACKDOOR, a)] == 1:
				s.found_backdoor = true
	return s

func has_soft(t: int) -> bool:
	return soft.has(t)

func hash_into(h: Hasher) -> void:
	h.add(tick)
	h.add(owner)
	h.add(control)
	h.add(access_mode)
	h.add_array(soft)
	h.add(buffer)
	h.add(1 if down else 0)
	h.add(role)
	h.add(role_target)
	h.add(1 if my_access else 0)
	h.add(1 if my_virus else 0)
	h.add(1 if my_backdoor else 0)
	h.add(1 if my_entry else 0)
	h.add(1 if my_infected else 0)
	h.add(1 if found_virus else 0)
	h.add(1 if found_backdoor else 0)
	h.add(1 if sniffer_known else 0)
