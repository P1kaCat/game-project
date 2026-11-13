class_name PlayerState
extends RefCounted
## The player's economy data: gold + inventory. Today it lives on the client;
## with a multiplayer server the server owns the authoritative copy and the
## client keeps a mirror updated from server responses (see TradeService).

signal gold_changed(gold: int)

var gold := 0:
	set(v):
		gold = maxi(0, v)
		gold_changed.emit(gold)
var inventory: Inventory


func _init(start_gold := 250, inventory_slots := 20) -> void:
	gold = start_gold
	inventory = Inventory.new(inventory_slots)


func to_dict() -> Dictionary:
	return {"gold": gold, "inventory": inventory.to_dict()}


## Replace this mirror with authoritative data (e.g. from a server).
func apply_dict(d: Dictionary) -> void:
	inventory = Inventory.from_dict(d.get("inventory", {}))
	gold = int(d.get("gold", 0))
