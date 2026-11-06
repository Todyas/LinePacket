class_name IntQueue
extends RefCounted
## Кольцевая очередь целых (FIFO) на PackedInt64Array. Размер буфера — степень двойки.

var _buf: PackedInt64Array = PackedInt64Array()
var _head: int = 0
var _count: int = 0
var _mask: int = 15

func _init() -> void:
	_buf.resize(16)

func size() -> int:
	return _count

func is_empty() -> bool:
	return _count == 0

func push(v: int) -> void:
	if _count == _buf.size():
		_grow()
	_buf[(_head + _count) & _mask] = v
	_count += 1

func peek() -> int:
	return _buf[_head]

func pop() -> int:
	var v: int = _buf[_head]
	_head = (_head + 1) & _mask
	_count -= 1
	return v

## i-й элемент от головы (0 — голова).
func at(i: int) -> int:
	return _buf[(_head + i) & _mask]

func clear() -> void:
	_head = 0
	_count = 0

func _grow() -> void:
	var n: int = _buf.size()
	var nb := PackedInt64Array()
	nb.resize(n * 2)
	for i in _count:
		nb[i] = _buf[(_head + i) & _mask]
	_buf = nb
	_head = 0
	_mask = n * 2 - 1

func hash_into(h: Hasher) -> void:
	h.add(_count)
	for i in _count:
		h.add(at(i))
