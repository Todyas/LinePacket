class_name Hints
extends RefCounted
## Подсказки по наведению: пакеты, ПО, задачи, узлы. Числа берутся из defs.

static func packet_type(t: int) -> String:
	match t:
		Defs.PacketType.DATA:
			return "DATA: полезные байты. Машины шлют их в шлюз, каждый дошедший пакет — доход (+%d Б)." % Defs.DATA_VALUE
		Defs.PacketType.KEEPALIVE:
			return "KEEPALIVE: сигнал «я жив». Каждый пакет прибавляет контроль машине; без него контроль тает."
		Defs.PacketType.INIT:
			return "INIT: захват нейтральной машины или шлюза. Против чужой машины подбирает пароль (ключи не подбираются)."
		Defs.PacketType.FLOOD:
			return "FLOOD: забивает CPU цели. Перегруженная машина «ложится»: не шлёт байты, ПО не работает, её легче заразить."
		Defs.PacketType.PAYLOAD:
			return "PAYLOAD: вирус. Каждый пакет (%d Б) растит шкалу заражения; на 100%% машина ваша. Антивирус замедляет." % Defs.PAYLOAD_COST_BYTES
		Defs.PacketType.PAYLOAD_HIDDEN:
			return "Скрытый PAYLOAD: %d Б за пакет, медленнее. На 100%% машина остаётся владельцу, но вы получаете тайный вирус." % Defs.PAYLOAD_HIDDEN_COST_BYTES
		Defs.PacketType.AGENT:
			return "Агент: ваш исполнитель задач едет по сети. Потерянный пакет — потерянный агент."
	return ""

static func soft(s: int) -> String:
	match s:
		Defs.SoftType.FIREWALL:
			return "Файрвол: пропускает чужие FLOOD и PAYLOAD не чаще %d в секунду." % Defs.FIREWALL_LIMIT_PER_S
		Defs.SoftType.ANTIVIRUS:
			return "Антивирус: режет прирост заражения до %d%% и быстро сбивает шкалу; ищет скрытое на этой машине." % Defs.ANTIVIRUS_GAIN_PERCENT
		Defs.SoftType.IDS:
			return "IDS: пишет в ленту чужие атаки с линком-источником и ищет скрытое на машине и соседях. Показывает чужих агентов."
		Defs.SoftType.SNIFFER:
			return "Сниффер: забирает %d%% чужих DATA, идущих через машину; байты уходят вам. Скрыт, пока его не найдёт IDS соседа." % Defs.SNIFFER_STEAL_PERCENT
		Defs.SoftType.STORAGE:
			return "Хранилище: буфер машины больше на %d байт." % Defs.STORAGE_BUFFER_BONUS
		Defs.SoftType.RELAY:
			return "Ретранслятор: боевая мощность машины %d%%, но собственных DATA машина шлёт %d%%." % [Defs.RELAY_COMBAT_PERCENT, Defs.RELAY_DATA_PERCENT]
	return ""

static func task(kind: int, arg: int = 0) -> String:
	match kind:
		Defs.TaskKind.MOVE:
			return "Агент идёт на машину по сети. Чужая машина пустит его при доступе или если лежит."
		Defs.TaskKind.CHANGE_PASSWORD:
			return "Сильный пароль: подбирается заметно дольше. Доступ остаётся только у вас (бэкдор переживает смену)."
		Defs.TaskKind.SET_KEYS:
			return "SSH-ключи: подобрать нельзя, доступ только у вас, пока ключ не украден."
		Defs.TaskKind.INSTALL_SOFT:
			return soft(arg)
		Defs.TaskKind.CLEAN_VIRUS:
			return "Вычищает заражение и найденные скрытые вирус и бэкдор на вашей машине."
		Defs.TaskKind.STEAL_KEY:
			return "Агент крадёт ключ чужой машины: дальше он входит без подбора."
		Defs.TaskKind.DRAIN_BUFFER:
			return "Агент забирает %d Б/с из буфера чужой машины, пока стоит рядом." % Defs.DRAIN_PER_S
		Defs.TaskKind.ENTRENCH:
			return "Закрепиться: чужие доступы и ПО вылетают, ставится сильный пароль. Если прежний владелец успел раньше, машина вернётся ему."
		Defs.TaskKind.BACKDOOR:
			return "Бэкдор: агент входит на эту машину без пароля и ключей. Переживает смену пароля; найденный IDS бэкдор чистят."
	return ""

## Подсказка к пункту кольцевого меню.
static func ring_item(item: Dictionary) -> String:
	match String(item.get("kind", "")):
		"info":
			return String(item.get("hint", ""))
		"task":
			return task(int(item["task"]), int(item.get("arg", 0)))
		"role", "own_role":
			return role(int(item["role"]))
		"activate":
			if int(item["mode"]) == Defs.ActivateMode.TAKEOVER:
				return "Перехват: машина становится вашей за один тик. Вирус расходуется."
			return "Отключить ПО: на %d с ПО машины не работает. Вирус расходуется." % (Defs.ACTIVATE_DISABLE_SOFT_TICKS / Defs.TICK_HZ)
	return ""

## Подсказка по узлу глазами игрока: только то, что он имеет право знать.
static func node(w: World, viewer: int, node_id: int) -> String:
	var n: NodeState = w.nodes[node_id]
	var lines: Array[String] = []
	var lvl: int = Knowledge.level(w, viewer, node_id) if viewer >= 0 else Knowledge.Level.OBSERVED
	if lvl == Knowledge.Level.SILHOUETTE:
		return "%s: %s\nНеизвестно. Дозор (клавиша T) покажет." % [Names.node_label(n), Names.node_type(n.type)]
	var owner_id: int = Knowledge.owner_of(w, viewer, node_id) if viewer >= 0 else n.owner
	lines.append("%s: %s, %s" % [Names.node_label(n), Names.node_type(n.type), Names.owner_name(owner_id)])
	match n.type:
		Defs.NodeType.CORE:
			lines.append("Ядро. Потеря ядра — поражение.")
		Defs.NodeType.GATEWAY:
			lines.append("Шлюз: сюда приходят DATA, это доход. Пропускает до %d DATA/с." % Defs.GATEWAY_CAP_PER_S)
		Defs.NodeType.MACHINE:
			lines.append("Машина: производит DATA и KEEPALIVE.")
		Defs.NodeType.SWITCH:
			lines.append("Свич: ничей, только пересылает пакеты.")
	var rl: String = role_line(w, viewer, node_id)
	if rl != "":
		lines.append(rl)
	var shown: Array[int] = visible_soft(w, viewer, node_id)
	for t in shown:
		lines.append(soft(t))
	if lvl == Knowledge.Level.SNAPSHOT:
		lines.append("Снимок, данные %d с назад." % (Knowledge.age(w, viewer, node_id) / Defs.TICK_HZ))
	return "\n".join(lines)

## Что делает роль машины.
static func role(r: int) -> String:
	match r:
		Defs.Role.WORK:
			return "Работа: машина шлёт DATA в свой шлюз, это доход (%d Б/с). Боевая машина дохода не даёт." % Defs.DATA_RATE
		Defs.Role.CAPTURE:
			return "Захват: машина шлёт INIT. Нейтрала берёт целиком, на чужой машине подбирает пароль. Цель в пределах %d хопов." % Defs.ROLE_MAX_HOPS
		Defs.Role.PRESSURE:
			return "Давление: машина шлёт FLOOD и забивает CPU цели, пока та не ляжет. Несколько машин на одной цели складываются."
		Defs.Role.INFECT:
			return "Заражение: машина шлёт PAYLOAD (%d Б за пакет), растёт шкала заражения цели." % Defs.PAYLOAD_COST_BYTES
		Defs.Role.INFECT_HIDDEN:
			return "Тайное заражение: %d Б за пакет, медленнее; в итоге тайный вирус, владелец ничего не видит." % Defs.PAYLOAD_HIDDEN_COST_BYTES
		Defs.Role.WATCH:
			return "Дозор: машина обновляет снимки узлов в радиусе %d хопов раз в %d с и даёт %d%% дохода." % [Defs.WATCH_RADIUS, Defs.WATCH_INTERVAL_TICKS / Defs.TICK_HZ, Defs.WATCH_DATA_PERCENT]
	return ""

## Строка «Роль: ... → цель» для узла глазами игрока; пусто, если роли нет или она неизвестна.
static func role_line(w: World, viewer: int, node_id: int) -> String:
	var n: NodeState = w.nodes[node_id]
	if not Roles.can_have_role(n):
		return ""
	var r: int = n.role
	var tg: int = n.role_target
	if viewer >= 0:
		var sn: NodeSnap = Knowledge.snap(w, viewer, node_id)
		if sn == null or sn.owner < 0:
			return ""
		r = sn.role
		tg = sn.role_target
	elif n.owner < 0:
		return ""
	var txt: String = "Роль: %s" % Defs.ROLE_NAMES[r]
	if tg >= 0:
		txt += " → %s" % Names.node_label(w.nodes[tg])
	if n.reconf > 0 and (viewer < 0 or n.owner == viewer):
		txt += " (перенастройка %d с)" % ((n.reconf + Defs.TICK_HZ - 1) / Defs.TICK_HZ)
	return txt

## ПО узла, которое игрок знает: по снимку для неналюдаемых, по наблюдению для остальных.
static func visible_soft(w: World, viewer: int, node_id: int) -> Array[int]:
	var out: Array[int] = []
	if viewer < 0:
		for t in w.nodes[node_id].soft:
			if t >= 0:
				out.append(t)
		return out
	var lvl: int = Knowledge.level(w, viewer, node_id)
	if lvl == Knowledge.Level.SILHOUETTE:
		return out
	if lvl == Knowledge.Level.SNAPSHOT:
		var sn: NodeSnap = Knowledge.snap(w, viewer, node_id)
		if sn != null:
			for t in sn.soft:
				if t >= 0:
					out.append(t)
		return out
	return Knowledge.soft_visible(w, viewer, node_id)
