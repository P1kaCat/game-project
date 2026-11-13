class_name SaveSystem
extends RefCounted
## Local save slots in user://saves/<slot>.json.
##
## File: {"format": "asthya-save", "version", "saved_at", "slot",
##        "checksum": sha256 of the canonical JSON of "data", "data": {...}}
## Writes go to a temp file then replace the slot (the previous file is kept as
## <slot>.bak), so a crash mid-save can't destroy the last good save. Loading
## validates format, version, checksum and every field; anything missing,
## truncated, edited or corrupted is reported and never applied.

const DIR := "user://saves"
const FORMAT := "asthya-save"
const VERSION := 1
const SLOTS: Array[String] = ["auto", "1", "2", "3"]
const MAX_GOLD := 1_000_000_000
const DIRECTIONS := ["n", "ne", "e", "se", "s", "sw", "w", "nw"]


static func path_of(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]


static func save_slot(slot: String, data: Dictionary) -> Error:
	if not slot in SLOTS:
		return ERR_INVALID_PARAMETER
	var problem := validate(data)
	if problem != "":
		push_error("Refusing to save invalid data: " + problem)
		return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(DIR)
	var payload := {"format": FORMAT, "version": VERSION, "saved_at": int(Time.get_unix_time_from_system()),
		"slot": slot, "checksum": _checksum(data), "data": data}
	var final := path_of(slot)
	var tmp := final + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final + ".bak")
		DirAccess.rename_absolute(final, final + ".bak")
	return DirAccess.rename_absolute(tmp, final)


## {ok: bool, data: Dictionary, saved_at: int, error: String}
static func load_slot(slot: String) -> Dictionary:
	var res := {"ok": false, "data": {}, "saved_at": 0, "error": ""}
	var path := path_of(slot)
	if not FileAccess.file_exists(path):
		res.error = "missing"
		return res
	var text := FileAccess.get_file_as_string(path)
	var payload = JSON.parse_string(text)
	if not payload is Dictionary:
		res.error = "unreadable"
		return res
	if payload.get("format") != FORMAT:
		res.error = "not a save file"
		return res
	if typeof(payload.get("version")) not in [TYPE_INT, TYPE_FLOAT] or int(payload.version) > VERSION:
		res.error = "unsupported version"
		return res
	var data = payload.get("data")
	if not data is Dictionary:
		res.error = "no data"
		return res
	if payload.get("checksum") != _checksum(data):
		res.error = "checksum mismatch (corrupted)"
		return res
	var problem := validate(data)
	if problem != "":
		res.error = problem
		return res
	res.ok = true
	res.data = data
	res.saved_at = int(payload.get("saved_at", 0))
	return res


## Returns "" if `d` is a complete, sane game-state dictionary, else the problem.
static func validate(d: Dictionary) -> String:
	if typeof(d.get("map_id")) != TYPE_STRING or d.map_id == "":
		return "map_id"
	var pos = d.get("position")
	if not pos is Array or pos.size() != 2:
		return "position"
	for v in pos:
		if typeof(v) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(v)) or is_inf(float(v)) or absf(float(v)) > 1e6:
			return "position"
	if not d.get("facing") in DIRECTIONS:
		return "facing"
	if typeof(d.get("play_time")) not in [TYPE_INT, TYPE_FLOAT] or float(d.play_time) < 0:
		return "play_time"
	if not d.get("flags") is Dictionary:
		return "flags"
	for k in d.flags:
		if typeof(d.flags[k]) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			return "flags"
	var p = d.get("player")
	if not p is Dictionary:
		return "player"
	if typeof(p.get("gold")) not in [TYPE_INT, TYPE_FLOAT] or int(p.gold) < 0 or int(p.gold) > MAX_GOLD:
		return "gold"
	var inv = p.get("inventory")
	if not inv is Dictionary or typeof(inv.get("capacity")) not in [TYPE_INT, TYPE_FLOAT]:
		return "inventory"
	var cap := int(inv.capacity)
	if cap < 1 or cap > 200 or not inv.get("slots") is Array or inv.slots.size() > cap:
		return "inventory"
	for s in inv.slots:
		if not s is Dictionary or typeof(s.get("id")) != TYPE_STRING or typeof(s.get("count")) not in [TYPE_INT, TYPE_FLOAT]:
			return "inventory slot"
		var def := ItemDatabase.get_item(StringName(s.id))
		if def == null or int(s.count) < 1 or int(s.count) > def.max_stack:
			return "inventory item %s" % s.get("id")
	return ""


## Summary for menus: {exists, ok, saved_at, play_time, region, gold, error}
static func slot_info(slot: String) -> Dictionary:
	var r := load_slot(slot)
	var info := {"slot": slot, "exists": r.error != "missing", "ok": r.ok, "saved_at": r.saved_at, "error": r.error}
	if r.ok:
		info.play_time = float(r.data.play_time)
		info.region = Loc.t("region." + str(r.data.map_id))
		info.gold = int(r.data.player.gold)
	return info


## Most recent valid slot, or "".
static func latest_valid_slot() -> String:
	var best := ""
	var best_t := -1
	for slot in SLOTS:
		var r := load_slot(slot)
		if r.ok and r.saved_at > best_t:
			best = slot
			best_t = r.saved_at
	return best


static func delete_slot(slot: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path_of(slot) + suffix):
			DirAccess.remove_absolute(path_of(slot) + suffix)


static func _checksum(data: Dictionary) -> String:
	return JSON.stringify(data, "", true).sha256_text()
