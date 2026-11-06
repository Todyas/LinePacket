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
		Defs.PacketType.SCAN:
			return "SCAN: разведка. Показывает состояние цели и её соседей (до %d хопов). Достаточно одного пакета." % Defs.SCAN_MAX_HOPS
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
			return "Ретранслятор: исходящие потоки идут на %d%% быстрее, но собственных DATA машина шлёт %d%%." % [Defs.RELAY_FLOW_PERCENT, Defs.RELAY_DATA_PERCENT]
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
		"flow":
			return packet_type(int(item["flow_type"]))
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
		return "%s: %s\nНеизвестно. Скан (клавиша T) покажет." % [Names.node_label(n), Names.node_type(n.type)]
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
	var shown: Array[int] = visible_soft(w, viewer, node_id)
	for t in shown:
		lines.append(soft(t))
	if lvl == Knowledge.Level.SNAPSHOT:
		lines.append("Снимок, данные %d с назад." % (Knowledge.age(w, viewer, node_id) / Defs.TICK_HZ))
	return "\n".join(lines)

## Подсказка по потоку игрока.
static func flow(f: FlowState) -> String:
	return "Поток %s, %d пак/с.\n%s\nКолесо мыши — скорость, X — остановить." % [
		Hud.flow_type_name(f.ptype).split(" ")[0], f.rate, packet_type(f.ptype)]

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
