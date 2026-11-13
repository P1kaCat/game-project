class_name Inventory
extends RefCounted
## Minimal slot inventory: `capacity` slots, each {id, count} with stacking up
## to the item's max_stack. Pure data (no UI); serializable for a future server.

signal changed

var capacity: int
var slots: Array[Dictionary] = []  # [{id: StringName, count: int}]


func _init(slot_capacity := 20) -> void:
	capacity = slot_capacity


func count_of(id: StringName) -> int:
	var n := 0
	for s in slots:
		if s.id == id:
			n += s.count
	return n


func used_slots() -> int:
	return slots.size()


## True if `qty` of `id` fit (existing stacks first, then free slots).
func can_add(id: StringName, qty := 1) -> bool:
	var def := ItemDatabase.get_item(id)
	if def == null or qty <= 0:
		return false
	var room := 0
	for s in slots:
		if s.id == id:
			room += def.max_stack - s.count
	room += (capacity - slots.size()) * def.max_stack
	return room >= qty


func add(id: StringName, qty := 1) -> bool:
	if not can_add(id, qty):
		return false
	var def := ItemDatabase.get_item(id)
	var left := qty
	for s in slots:
		if s.id == id and s.count < def.max_stack:
			var put := mini(left, def.max_stack - s.count)
			s.count += put
			left -= put
	while left > 0:
		var put := mini(left, def.max_stack)
		slots.append({"id": id, "count": put})
		left -= put
	changed.emit()
	return true


func remove(id: StringName, qty := 1) -> bool:
	if count_of(id) < qty:
		return false
	var left := qty
	for i in range(slots.size() - 1, -1, -1):
		if slots[i].id == id and left > 0:
			var take := mini(left, slots[i].count)
			slots[i].count -= take
			left -= take
			if slots[i].count == 0:
				slots.remove_at(i)
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {"capacity": capacity, "slots": slots.map(func(s): return {"id": String(s.id), "count": s.count})}


static func from_dict(d: Dictionary) -> Inventory:
	var inv := Inventory.new(int(d.get("capacity", 20)))
	for s in d.get("slots", []):
		inv.slots.append({"id": StringName(s.id), "count": int(s.count)})
	return inv
