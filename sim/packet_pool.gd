class_name PacketPool
extends RefCounted
## Пакеты хранятся в плоских массивах; индекс пакета — его id. Освобождённые места переиспользуются
## в порядке LIFO, поэтому выдача индексов детерминирована.

var ptype: PackedInt32Array = PackedInt32Array()
var owner: PackedInt32Array = PackedInt32Array()
var src: PackedInt32Array = PackedInt32Array()
var dst: PackedInt32Array = PackedInt32Array()
var flow: PackedInt32Array = PackedInt32Array()
var size: PackedInt32Array = PackedInt32Array()
var alive: PackedByteArray = PackedByteArray()
var _free: PackedInt32Array = PackedInt32Array()
var alive_count: int = 0

func alloc(t: int, own: int, from_node: int, to_node: int, flow_id: int) -> int:
	var i: int
	if _free.is_empty():
		i = ptype.size()
		ptype.append(t)
		owner.append(own)
		src.append(from_node)
		dst.append(to_node)
		flow.append(flow_id)
		size.append(int(Defs.PACKET_SIZE[t]))
		alive.append(1)
	else:
		i = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		ptype[i] = t
		owner[i] = own
		src[i] = from_node
		dst[i] = to_node
		flow[i] = flow_id
		size[i] = int(Defs.PACKET_SIZE[t])
		alive[i] = 1
	alive_count += 1
	return i

func release(i: int) -> void:
	alive[i] = 0
	_free.append(i)
	alive_count -= 1

func hash_into(h: Hasher) -> void:
	h.add(alive_count)
	for i in ptype.size():
		if alive[i] == 1:
			h.add(i)
			h.add(ptype[i])
			h.add(owner[i])
			h.add(src[i])
			h.add(dst[i])
			h.add(flow[i])
	h.add(_free.size())
