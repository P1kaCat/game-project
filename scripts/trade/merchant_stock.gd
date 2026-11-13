class_name MerchantStock
extends Resource
## What a merchant sells (res://data/shops/<id>.tres). Entries reference items
## by id; names, icons and descriptions come from ItemDefinition.

@export var id: StringName
@export var merchant_name := ""
## [{item: StringName, price: int, stock: int}]  stock -1 = unlimited.
@export var entries: Array[Dictionary] = []


func find_entry(item_id: StringName) -> Dictionary:
	for e in entries:
		if StringName(e.get("item", "")) == item_id:
			return e
	return {}


func price_of(item_id: StringName) -> int:
	return int(find_entry(item_id).get("price", -1))
