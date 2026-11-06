class_name Replay
extends RefCounted
## Реплей: сид, карта, длительность и список применённых команд.

var seed_value: int = 1
var map_path: String = ""
var ticks: int = 0
var commands: Array[Command] = []

static func from_world(w: World, path: String) -> Replay:
	var r := Replay.new()
	r.seed_value = w.seed_value
	r.map_path = path
	r.ticks = w.tick
	for c in w.applied_log:
		r.commands.append(c)
	return r

func to_json() -> String:
	var arr: Array = []
	for c in commands:
		arr.append(c.to_array())
	return JSON.stringify({
		"version": 1,
		"seed": seed_value,
		"map": map_path,
		"ticks": ticks,
		"commands": arr,
	})

static func from_json(text: String) -> Replay:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = parsed
	if not (d.has("seed") and d.has("map") and d.has("ticks") and d.has("commands")):
		return null
	var r := Replay.new()
	r.seed_value = int(d["seed"])
	r.map_path = str(d["map"])
	r.ticks = int(d["ticks"])
	for a in (d["commands"] as Array):
		r.commands.append(Command.from_array(a as Array))
	return r

func save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json())
	return true

static func load_file(path: String) -> Replay:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))

## Проиграть реплей на свежем мире; возвращает мир после последнего тика.
func play() -> World:
	var res: Dictionary = MapLoader.load_file(map_path, seed_value)
	if res["world"] == null:
		return null
	var w: World = res["world"]
	for c in commands:
		w.submit(c)
	w.run(ticks)
	return w
