class_name Defs
extends RefCounted
## Числа баланса и справочники. Всё, что крутится при балансе, живёт только здесь.

const TICK_HZ: int = 20
const TICK_MS: int = 50

## Типы узлов (значения enum не менять: они попадают в хеш и реплеи).
enum NodeType { CORE, MACHINE, GATEWAY, SWITCH }

const NODE_TYPE_NAMES: Dictionary = {
	"core": NodeType.CORE,
	"machine": NodeType.MACHINE,
	"gateway": NodeType.GATEWAY,
	"switch": NodeType.SWITCH,
}

## Параметры типов узлов.
## cpu — пакетов в секунду, которые узел может обработать;
## ports — максимум линков; can_own — можно ли владеть.
const NODE_DEFS: Dictionary = {
	NodeType.CORE: {"cpu": 60, "ports": 6, "can_own": true},
	NodeType.MACHINE: {"cpu": 40, "ports": 4, "can_own": true},
	NodeType.GATEWAY: {"cpu": 80, "ports": 5, "can_own": true},
	NodeType.SWITCH: {"cpu": 200, "ports": 8, "can_own": false},
}

## Типы линков.
## capacity — единиц размера пакета в секунду (на каждое направление);
## speed — пикселей карты за тик (время пути = длина / speed, округление вверх);
## queue — лимит очереди на выходном порту, в единицах размера.
enum LinkKind { CABLE, OPTIC, WIFI }

const LINK_KIND_NAMES: Dictionary = {
	"cable": LinkKind.CABLE,
	"optic": LinkKind.OPTIC,
	"wifi": LinkKind.WIFI,
}

const LINK_DEFS: Dictionary = {
	LinkKind.CABLE: {"capacity": 10, "speed": 20, "queue": 30},
	LinkKind.OPTIC: {"capacity": 20, "speed": 40, "queue": 60},
	LinkKind.WIFI: {"capacity": 5, "speed": 20, "queue": 15},
}

## Минимальное время пути по линку, тиков.
const LINK_MIN_LATENCY: int = 2

## Игроки: id игрока от 0; нейтрал = -1.
const NEUTRAL: int = -1
const MAX_PLAYERS: int = 4

## Поток: интенсивность в пакетах в секунду.
const FLOW_MIN_RATE: int = 1
const FLOW_MAX_RATE: int = 20
const FLOW_DEFAULT_RATE: int = 4

## Типы пакетов (значения не менять).
enum PacketType { DATA, KEEPALIVE, INIT, SCAN, FLOOD, PAYLOAD, PAYLOAD_HIDDEN, AGENT }

## Размер пакета: сколько места занимает в канале.
const PACKET_SIZE: Dictionary = {
	PacketType.DATA: 1,
	PacketType.KEEPALIVE: 1,
	PacketType.INIT: 1,
	PacketType.SCAN: 1,
	PacketType.FLOOD: 1,
	PacketType.PAYLOAD: 1,
	PacketType.PAYLOAD_HIDDEN: 1,
	PacketType.AGENT: 5,
}

## Какие типы игрок может пускать потоком (остальные идут автоматически).
## Список растёт вместе со спринтами по мере появления механик.
const PLAYER_FLOW_TYPES: Array = [PacketType.FLOOD, PacketType.INIT]

## --- Сеть (S1) ---

## Сколько CPU стоит пакету прибытие в точку назначения (по типу).
const CPU_COST_ARRIVE: Dictionary = {
	PacketType.DATA: 1,
	PacketType.KEEPALIVE: 1,
	PacketType.INIT: 1,
	PacketType.SCAN: 1,
	PacketType.FLOOD: 2,
	PacketType.PAYLOAD: 2,
	PacketType.PAYLOAD_HIDDEN: 2,
	PacketType.AGENT: 1,
}
## Транзит через узел и рождение пакета на узле — по 1 единице CPU.
const CPU_COST_TRANSIT: int = 1
const CPU_COST_EMIT: int = 1
## Накопленный CPU/канал не копится дольше этого числа тиков (ограничение «всплеска»).
const BURST_TICKS: int = 4
## Минимальный запас кредита канала, чтобы мог пройти самый крупный пакет.
const CREDIT_FLOOR: int = TICK_HZ * 5

## Маршруты: пересчёт раз в секунду; цена = задержка*вес + загрузка(0..100)*штраф.
const ROUTE_RECALC_TICKS: int = 20
const ROUTE_LATENCY_WEIGHT: int = 10
const ROUTE_LOAD_PENALTY: int = 3
## Скользящее окно загрузки: ровно одна секунда.
const LOAD_WINDOW: int = TICK_HZ

## --- Экономика и захват (S2) ---

## Контроль хранится в тысячных долях пункта: 0..100000 = 0..100.
const CONTROL_MAX: int = 100000
## Распад контроля в секунду (не у ядра).
const CONTROL_DECAY_PER_S: int = 5000
## Каждая поддерживаемая машина получает KEEPALIVE с этой частотой (пакетов в секунду).
const KEEPALIVE_RATE: int = 1
const KEEPALIVE_BOOST: int = 10000
## Узел может «кормить» KEEPALIVE других, только если его контроль не ниже порога.
const SUPPLY_MIN_CONTROL: int = 30000
## Контроль свежезахваченного узла.
const CAPTURE_START_CONTROL: int = 50000

## Своя машина или ядро рождает DATA с этой частотой, 1 DATA = 1 байт.
const DATA_RATE: int = 2
const DATA_VALUE: int = 1
## Выгрузка накопленного буфера: дополнительные отправки в секунду, пока буфер не пуст.
const BUFFER_UNLOAD_RATE: int = 4
## Лимит локального буфера в байтах.
const BUFFER_LIMIT: Dictionary = {
	NodeType.CORE: 100,
	NodeType.MACHINE: 60,
	NodeType.GATEWAY: 0,
	NodeType.SWITCH: 0,
}
## Потолок шлюза: пакетов DATA в секунду, которые он принимает.
const GATEWAY_CAP_PER_S: int = 10
## Шлюз сглаживает всплески: кредит копится на столько тиков (поток машин приходит пачками).
const GATEWAY_BURST_TICKS: int = 10

## Сколько пакетов INIT сдаёт нейтрала (по типу узла).
const INIT_NEEDED: Dictionary = {
	NodeType.MACHINE: 30,
	NodeType.GATEWAY: 60,
}
## Шкала захвата теряет столько пунктов в секунду, если на узел не идёт INIT.
const CAPTURE_DECAY_PER_S: int = 3
