class_name LinkState
extends RefCounted
## Линк = два независимых канала. Направление 0: a→b, 1: b→a.
## На каждом направлении: очередь выходного порта (пакеты ждут входа в канал)
## и канал (пакеты «в пути», запись = тик входа << 24 | индекс пакета).

const IDX_BITS: int = 24
const IDX_MASK: int = (1 << 24) - 1

var id: int = 0
var a: int = 0
var b: int = 0
var kind: int = Defs.LinkKind.CABLE
var length: int = 0
var latency: int = 2       # тиков
var capacity: int = 10     # размер/сек на направление
var queue_limit: int = 30  # размер очереди выходного порта

var port_q: Array[IntQueue] = [IntQueue.new(), IntQueue.new()]
var port_units: PackedInt32Array = PackedInt32Array([0, 0])
var chan: Array[IntQueue] = [IntQueue.new(), IntQueue.new()]
var credit: PackedInt32Array = PackedInt32Array([0, 0])
var sent_hist: Array[PackedInt32Array] = []   # отправлено за тик, окно в секунду

func _init() -> void:
	for d in 2:
		var arr := PackedInt32Array()
		arr.resize(Defs.LOAD_WINDOW)
		sent_hist.append(arr)

func other(n: int) -> int:
	return b if n == a else a

## Направление, исходящее из узла n.
func dir_from(n: int) -> int:
	return 0 if n == a else 1

func credit_cap() -> int:
	return maxi(capacity * Defs.BURST_TICKS, Defs.CREDIT_FLOOR)

## Загрузка направления 0..100: максимум из занятости канала за секунду и заполнения очереди.
func load_pct(d: int) -> int:
	var total: int = 0
	for v in sent_hist[d]:
		total += v
	var util: int = total * 100 / capacity
	var fill: int = port_units[d] * 100 / queue_limit
	return mini(100, maxi(util, fill))

func in_flight_count() -> int:
	return chan[0].size() + chan[1].size()

func hash_into(h: Hasher) -> void:
	h.add(id)
	h.add(a)
	h.add(b)
	h.add(kind)
	h.add(latency)
	h.add(capacity)
	for d in 2:
		h.add(port_units[d])
		h.add(credit[d])
		port_q[d].hash_into(h)
		chan[d].hash_into(h)
		h.add_array(sent_hist[d])
