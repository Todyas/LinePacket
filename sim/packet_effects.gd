class_name PacketEffects
extends RefCounted
## Что делает пакет по прибытии в точку назначения. Растёт вместе со спринтами.

static func deliver(_w: World, _node: NodeState, _idx: int) -> void:
	# FLOOD сам по себе бесполезен: его эффект — плата CPU цели за прибытие (уже списана).
	pass
