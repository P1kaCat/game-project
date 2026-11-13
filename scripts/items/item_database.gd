class_name ItemDatabase
extends RefCounted
## Item definitions by id, loaded on demand from res://data/items/<id>.tres.

const DIR := "res://data/items/"

static var _cache := {}


static func get_item(id: StringName) -> ItemDefinition:
	if _cache.has(id):
		return _cache[id]
	var path := DIR + String(id) + ".tres"
	var def: ItemDefinition = load(path) if ResourceLoader.exists(path) else null
	if def and def.id != id:
		push_error("Item %s declares id %s" % [path, def.id])
		def = null
	_cache[id] = def
	return def


static func exists(id: StringName) -> bool:
	return get_item(id) != null
