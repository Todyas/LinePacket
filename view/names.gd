class_name Names
extends RefCounted
## Русские подписи для интерфейса.

static func node_type(t: int) -> String:
	match t:
		Defs.NodeType.CORE:
			return "Ядро"
		Defs.NodeType.MACHINE:
			return "Машина"
		Defs.NodeType.GATEWAY:
			return "Шлюз"
		Defs.NodeType.SWITCH:
			return "Свич"
	return "?"

static func node_label(n: NodeState) -> String:
	var prefix: String = "?"
	match n.type:
		Defs.NodeType.CORE:
			prefix = "C"
		Defs.NodeType.MACHINE:
			prefix = "M"
		Defs.NodeType.GATEWAY:
			prefix = "G"
		Defs.NodeType.SWITCH:
			prefix = "S"
	return "%s%d" % [prefix, n.id]

static func owner_name(owner: int) -> String:
	return "нейтрал" if owner < 0 else "Игрок %d" % (owner + 1)

static func access_mode(m: int, key_version: int) -> String:
	match m:
		Defs.AccessMode.PASSWORD_WEAK:
			return "слабый пароль"
		Defs.AccessMode.PASSWORD_STRONG:
			return "сильный пароль"
		Defs.AccessMode.KEYS:
			return "SSH-ключи (v%d)" % key_version if key_version > 0 else "SSH-ключи"
	return "?"

static func access_list(mask: int) -> String:
	var parts: Array[String] = []
	for p in Defs.MAX_PLAYERS:
		if mask & (1 << p):
			parts.append("И%d" % (p + 1))
	return ", ".join(parts) if not parts.is_empty() else "—"

static func task(kind: int, arg: int, node_lbl: String) -> String:
	if kind == Defs.TaskKind.INSTALL_SOFT:
		return "%s: %s @%s" % [Defs.TASK_NAMES[kind], Defs.SOFT_NAMES[arg], node_lbl]
	return "%s @%s" % [Defs.TASK_NAMES[kind], node_lbl]
