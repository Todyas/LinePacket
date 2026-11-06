class_name Roles
extends RefCounted
## Роли машин: что своя машина или ядро делает сейчас. Боевая роль шлёт пакеты на цель вместо DATA.

static func power(n: NodeState) -> int:
	var p: int = int(Defs.ROLE_POWER.get(n.type, 0))
	if n.soft_active(Defs.SoftType.RELAY):
		p = p * Defs.RELAY_COMBAT_PERCENT / 100
	return p

## Роль может быть у своей машины и ядра; у шлюза её нет.
static func can_have_role(n: NodeState) -> bool:
	return n.type == Defs.NodeType.MACHINE or n.type == Defs.NodeType.CORE

## Годится ли узел target боевой роли role машины n прямо сейчас (правила цели, без дальности).
static func target_ok(w: World, n: NodeState, role: int, target: int) -> bool:
	if target < 0 or target >= w.nodes.size() or target == n.id:
		return false
	var t: NodeState = w.nodes[target]
	var me: int = n.owner
	match role:
		Defs.Role.CAPTURE:
			if t.owner == Defs.NEUTRAL:
				return Defs.INIT_NEEDED.has(t.type)
			if t.owner == me or t.type == Defs.NodeType.SWITCH:
				return false
			# На чужой машине INIT подбирает пароль: пока нет доступа и пароль подбираем.
			return (t.access_mask & (1 << me)) == 0 and int(Defs.BRUTE_GAIN[t.access_mode]) > 0
		Defs.Role.PRESSURE:
			return t.owner >= 0 and t.owner != me and t.type != Defs.NodeType.SWITCH
		Defs.Role.INFECT:
			return t.owner >= 0 and t.owner != me and t.type != Defs.NodeType.SWITCH
		Defs.Role.INFECT_HIDDEN:
			return t.owner >= 0 and t.owner != me and t.type != Defs.NodeType.SWITCH and t.virus[me] != 1
	return false

## Команда SET_ROLE: [узел, роль, цель].
static func apply_set_role(w: World, player: int, args: Array) -> bool:
	if args.size() != 3 or player < 0 or player >= w.players.size():
		return false
	var nid: int = args[0]
	var role: int = args[1]
	var target: int = args[2]
	if nid < 0 or nid >= w.nodes.size() or not Defs.ROLE_NAMES.has(role):
		return false
	var n: NodeState = w.nodes[nid]
	if n.owner != player or not can_have_role(n):
		return false
	if Defs.COMBAT_ROLES.has(role):
		if not target_ok(w, n, role, target):
			return false
		var hp: int = Knowledge.hops(w, nid, target)
		if hp < 0 or hp > Defs.ROLE_MAX_HOPS:
			return false
	else:
		target = -1
	if n.role == role and n.role_target == target:
		return true    # та же роль на ту же цель: перенастройка не нужна
	n.role = role
	n.role_target = target
	n.role_acc = 0
	n.reconf = Defs.ROLE_RECONF_TICKS
	return true

## Раз в тик: перенастройка, пакеты боевых ролей, снимки дозора.
static func step(w: World) -> void:
	for n in w.nodes:
		if n.owner < 0 or not can_have_role(n):
			continue
		if n.reconf > 0:
			n.reconf -= 1
			continue
		if n.role == Defs.Role.WATCH:
			if not n.down:
				n.role_acc += 1
				if n.role_acc >= Defs.WATCH_INTERVAL_TICKS:
					n.role_acc = 0
					Knowledge.watch(w, n.owner, n.id, Defs.WATCH_RADIUS)
			continue
		if not n.is_combat():
			continue
		if not target_ok(w, n, n.role, n.role_target):
			n.reset_role()    # цель исчезла (захвачена, стала своей, пароль взят): машина возвращается к работе
			continue
		if n.down:
			continue
		var pl: PlayerState = w.players[n.owner]
		var ptype: int = int(Defs.ROLE_PACKET[n.role])
		var cost: int = Defs.flow_byte_cost(ptype)
		n.role_acc += power(n)
		while n.role_acc >= Defs.TICK_HZ:
			n.role_acc -= Defs.TICK_HZ
			if pl.bank < cost:
				continue    # PAYLOAD стоит байты: без них пакет не рождается
			if not n.spend_cpu(Defs.CPU_COST_EMIT):
				w.drops[World.DROP_CPU] += 1
				continue
			pl.bank -= cost
			Network.inject(w, n.id, n.role_target, ptype, n.owner, 0)

## Сколько своих машин в работе и сколько в бою (дозор считается за работу).
static func counts(w: World, player: int) -> Array[int]:
	var work: int = 0
	var combat: int = 0
	for n in w.nodes:
		if n.owner != player or not can_have_role(n):
			continue
		if n.is_combat():
			combat += 1
		else:
			work += 1
	return [work, combat]

## Сколько своих машин сейчас перенастраиваются.
static func reconfiguring(w: World, player: int) -> int:
	var c: int = 0
	for n in w.nodes:
		if n.owner == player and can_have_role(n) and n.reconf > 0:
			c += 1
	return c
