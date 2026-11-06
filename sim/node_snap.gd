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
var my_access: bool = false      # был ли у игрока доступ (по его же ключам) на момент снимка

static func capture(n: NodeState, player: int, at_tick: int) -> NodeSnap:
	var s := NodeSnap.new()
	s.tick = at_tick
	s.owner = n.owner
	s.control = n.control
	s.access_mode = n.access_mode
	s.soft = n.soft.duplicate()
	s.buffer = n.buffer
	s.down = n.down
	s.my_access = (n.access_mask & (1 << player)) != 0
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
	h.add(1 if my_access else 0)
