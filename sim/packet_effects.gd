class_name PacketEffects
extends RefCounted
## Что делает пакет по прибытии в точку назначения. Растёт вместе со спринтами.

static func deliver(w: World, node: NodeState, idx: int) -> void:
	var owner: int = w.pool.owner[idx]
	match w.pool.ptype[idx]:
		Defs.PacketType.DATA:
			Economy.on_data(w, node, owner)
		Defs.PacketType.KEEPALIVE:
			Economy.on_keepalive(w, node, owner)
		Defs.PacketType.INIT:
			Economy.on_init(w, node, owner)
		Defs.PacketType.AGENT:
			Agents.on_arrived(w, node, owner, w.pool.flow[idx])
		Defs.PacketType.PAYLOAD:
			Economy.on_payload(w, node, owner)
		Defs.PacketType.SCAN:
			Knowledge.scan(w, owner, node.id)
			w.remove_flow(w.pool.flow[idx])   # один поток — один скан
		Defs.PacketType.FLOOD:
			pass   # эффект флуда — плата CPU цели за прибытие, уже списана
