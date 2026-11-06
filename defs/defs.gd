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
const PLAYER_FLOW_TYPES: Array = [PacketType.FLOOD, PacketType.INIT, PacketType.PAYLOAD, PacketType.PAYLOAD_HIDDEN, PacketType.SCAN]

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

## --- Агенты, доступ и ПО (S3) ---

enum AccessMode { PASSWORD_WEAK, PASSWORD_STRONG, KEYS }

enum SoftType { FIREWALL, ANTIVIRUS, IDS, SNIFFER, STORAGE, RELAY }

const SOFT_NAMES: Dictionary = {
	SoftType.FIREWALL: "Файрвол",
	SoftType.ANTIVIRUS: "Антивирус",
	SoftType.IDS: "IDS",
	SoftType.SNIFFER: "Сниффер",
	SoftType.STORAGE: "Хранилище",
	SoftType.RELAY: "Ретранслятор",
}

## time_s — длительность установки, cost — байты, cpu_per_s — постоянная нагрузка на CPU узла.
const SOFT_DEFS: Dictionary = {
	SoftType.FIREWALL: {"time_s": 10, "cost": 40, "cpu_per_s": 0},
	SoftType.ANTIVIRUS: {"time_s": 15, "cost": 60, "cpu_per_s": 8},
	SoftType.IDS: {"time_s": 12, "cost": 50, "cpu_per_s": 8},
	SoftType.SNIFFER: {"time_s": 15, "cost": 60, "cpu_per_s": 4},
	SoftType.STORAGE: {"time_s": 8, "cost": 20, "cpu_per_s": 2},
	SoftType.RELAY: {"time_s": 12, "cost": 60, "cpu_per_s": 6},
}

## ПО, доступное игроку в текущем спринте (растёт вместе с механиками, которые ПО обслуживает).
const PLAYER_SOFT: Array = [SoftType.FIREWALL, SoftType.ANTIVIRUS, SoftType.IDS, SoftType.SNIFFER, SoftType.STORAGE, SoftType.RELAY]

## Слоты ПО на узле.
const SOFT_SLOTS: Dictionary = {
	NodeType.CORE: 3,
	NodeType.MACHINE: 2,
	NodeType.GATEWAY: 2,
	NodeType.SWITCH: 0,
}
const MAX_SOFT_SLOTS: int = 3

## Файрвол: чужие FLOOD и PAYLOAD проходят не чаще лимита в секунду; каждая проверка стоит CPU.
const FIREWALL_LIMIT_PER_S: int = 8
const FIREWALL_CPU_COST: int = 1
const FIREWALL_BURST_TICKS: int = 4
## Хранилище прибавляет к буферу байт.
const STORAGE_BUFFER_BONUS: int = 100
## Ретранслятор: исходящие потоки с узла в процентах от заданных; собственная выработка DATA — в процентах.
const RELAY_FLOW_PERCENT: int = 200
const RELAY_DATA_PERCENT: int = 50

const AGENTS_PER_PLAYER: int = 3
const AGENT_QUEUE_MAX: int = 3
## Агент, которого выкинули или потеряли в пути, появляется на ядре через 20 секунд.
const AGENT_RETURN_TICKS: int = 400

enum TaskKind { MOVE, CHANGE_PASSWORD, SET_KEYS, INSTALL_SOFT, CLEAN_VIRUS, STEAL_KEY, DRAIN_BUFFER, ENTRENCH, BACKDOOR }

const TASK_NAMES: Dictionary = {
	TaskKind.MOVE: "Перейти",
	TaskKind.CHANGE_PASSWORD: "Сменить пароль",
	TaskKind.SET_KEYS: "Ключи",
	TaskKind.INSTALL_SOFT: "Поставить ПО",
	TaskKind.CLEAN_VIRUS: "Вычистить вирус",
	TaskKind.STEAL_KEY: "Украсть ключ",
	TaskKind.DRAIN_BUFFER: "Выкачать байты",
	TaskKind.ENTRENCH: "Закрепиться",
	TaskKind.BACKDOOR: "Поставить бэкдор",
}

## Время (с) и цена (байты) задач без аргумента. Установка ПО берёт числа из SOFT_DEFS.
const TASK_DEFS: Dictionary = {
	TaskKind.MOVE: {"time_s": 0, "cost": 0},
	TaskKind.CHANGE_PASSWORD: {"time_s": 4, "cost": 5},
	TaskKind.SET_KEYS: {"time_s": 10, "cost": 15},
	TaskKind.STEAL_KEY: {"time_s": 12, "cost": 0},
	TaskKind.DRAIN_BUFFER: {"time_s": 0, "cost": 0},   # идёт, пока стоит агент и есть что качать
	TaskKind.ENTRENCH: {"time_s": 6, "cost": 10},
	TaskKind.BACKDOOR: {"time_s": 10, "cost": 30},
	TaskKind.CLEAN_VIRUS: {"time_s": 6, "cost": 10},   # +до 14 с по степени заражения
}

## --- Атака и захват чужих машин (S4) ---

## Нагрузка CPU (%), при которой машина «ложится», и при которой поднимается обратно.
const LYING_ON_PCT: int = 100
const LYING_OFF_PCT: int = 80

## PAYLOAD: цена одного пакета в байтах и прирост шкалы заражения (тысячные доли пункта, 100000 = 100%).
const PAYLOAD_COST_BYTES: int = 1

## Байты за один пакет потока (0 — бесплатный тип).
static func flow_byte_cost(ptype: int) -> int:
	if ptype == PacketType.PAYLOAD:
		return PAYLOAD_COST_BYTES
	if ptype == PacketType.PAYLOAD_HIDDEN:
		return PAYLOAD_HIDDEN_COST_BYTES
	return 0
const INFECT_MAX: int = 100000
const INFECT_GAIN: int = 1500
## Шкала заражения тает сама; антивирус сбивает её быстрее и режет прирост.
const INFECT_DECAY_PER_S: int = 1000
const ANTIVIRUS_GAIN_PERCENT: int = 60
const ANTIVIRUS_DECAY_PER_S: int = 3000
## Контроль машины сразу после смены владельца.
const TAKEOVER_CONTROL: int = 50000

## Подбор пароля потоком INIT: прирост шкалы за пакет по силе защиты (ключи не подбираются).
const BRUTE_MAX: int = 100000
const BRUTE_GAIN: Dictionary = {
	AccessMode.PASSWORD_WEAK: 10000,
	AccessMode.PASSWORD_STRONG: 1000,
	AccessMode.KEYS: 0,
}
const BRUTE_DECAY_PER_S: int = 2000

## «Выкачать байты»: сколько байт в секунду агент забирает из буфера чужой машины.
const DRAIN_PER_S: int = 5
## «Вычистить вирус»: к базовым 6 с добавляется до этого числа секунд по степени заражения.
const CLEAN_EXTRA_S: int = 14

## --- Туман и разведка (S5) ---

## SCAN: узел-цель не дальше стольких линков от узла, откуда идёт скан. Поток сам заканчивается, когда скан дошёл.
const SCAN_MAX_HOPS: int = 3
const SCAN_FLOW_RATE: int = 4
## IDS пишет в лог чужие пакеты этих типов; от одного атакующего на один узел — не чаще раза в несколько секунд.
const IDS_WATCHED: Array = [PacketType.FLOOD, PacketType.PAYLOAD, PacketType.INIT, PacketType.SCAN]
const IDS_COOLDOWN_TICKS: int = 60
## Данные снимка бледнеют за столько секунд (только вид).
const SNAPSHOT_FADE_S: int = 90

## --- Скрытность (S6) ---

enum HiddenKind { VIRUS, BACKDOOR, SNIFFER }
const HIDDEN_KIND_COUNT: int = 3
const HIDDEN_NAMES: Dictionary = {
	HiddenKind.VIRUS: "скрытый вирус",
	HiddenKind.BACKDOOR: "бэкдор",
	HiddenKind.SNIFFER: "сниффер",
}

## Скрытый PAYLOAD: дороже обычного и растёт медленнее; владелец шкалу не видит.
const PAYLOAD_HIDDEN_COST_BYTES: int = 2
const INFECT_HIDDEN_GAIN: int = 800

## Сколько секунд IDS или антивирус должны «смотреть» на машину, чтобы найти скрытое.
const HIDDEN_DETECT_S: Dictionary = {
	HiddenKind.VIRUS: 40,
	HiddenKind.BACKDOOR: 60,
	HiddenKind.SNIFFER: 30,
}
## Заражённая тайным вирусом машина отдаёт вору этот процент своих DATA, сниффер ворует столько же из транзита.
const VIRUS_SKIM_PERCENT: int = 25
const SNIFFER_STEAL_PERCENT: int = 25
## Активация вируса: «отключить ПО» выводит ПО машины из строя на это число тиков.
const ACTIVATE_DISABLE_SOFT_TICKS: int = 400
enum ActivateMode { TAKEOVER, DISABLE_SOFT }

## --- Бот (S7) ---

## Характер бота: числа поведения. Один уровень сложности.
const BOT_PROFILE: Dictionary = {
	"think_ticks": 10,          # раз в полсекунды
	"reserve": 5,               # байт, которые не тратит на задачи агентов
	"max_init_flows": 2,        # одновременных захватов нейтралов
	"base_nodes": 4,            # сколько узлов держит без шлюзов
	"nodes_per_gateway": 4,     # и сколько прибавляет на каждый шлюз
	"expand_hops": 2,           # насколько далеко от своих узлов тянется захват
	"toward_enemy": 6,          # тяга расширения к чужому ядру (за хоп до него)
	"scan_interval_s": 15,      # пауза между сканами
	"rescan_s": 45,             # когда снимок считается старым
	"attack_start_s": 480,      # когда начинает атаковать
	"attack_min_nodes": 5,      # и сколько узлов для этого нужно
	"max_attack_targets": 1,    # целей под атакой одновременно
	"flood_hold_rate": 10,      # флуд на лежащую цель, которую уже заражают
	"payload_hold_rate": 12,    # вирус на лежащую цель
	"floods_per_target": 2,     # потоков флуда на одну защищённую цель
	"attack_hops": 2,           # цель не дальше стольких хопов от своего узла
	"hidden_percent": 25,       # как часто против защищённой цели берёт скрытый вирус вместо флуда
	"core_pull": 6,             # тяга атаки к чужому ядру
	"payload_rich_bank": 200,   # с какого банка бьёт вирусом напором и против защищённой цели
	"threat_memory_s": 60,      # сколько помнит атаку по логу IDS
}
