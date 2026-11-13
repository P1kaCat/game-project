class_name TradeService
extends RefCounted
## Purchase API used by the shop UI. The UI only *requests* a purchase and
## displays the returned result; it never edits gold or inventory itself.
##
## This local implementation validates and applies the purchase on the client.
## A networked version keeps the same `request_purchase` signature: it sends
## the request to the server, the server runs the same checks against its
## authoritative PlayerState and returns the result + new state, which the
## client applies with PlayerState.apply_dict(). The UI does not change.

enum Result { OK, UNKNOWN_ITEM, NOT_SOLD_HERE, NOT_PURCHASABLE, INVALID_QUANTITY, NOT_ENOUGH_GOLD, INVENTORY_FULL, OUT_OF_STOCK }

signal purchase_completed(result: Dictionary)


## Returns {result: Result, ok: bool, item: StringName, quantity: int,
## cost: int, gold: int}. Coroutine, so a network round-trip fits later.
func request_purchase(buyer: PlayerState, shop: MerchantStock, item_id: StringName, quantity := 1) -> Dictionary:
	await Engine.get_main_loop().process_frame  # same timing model as a remote call
	var res := validate_and_apply(buyer, shop, item_id, quantity)
	purchase_completed.emit(res)
	return res


## The authoritative rules (would run on the server).
static func validate_and_apply(buyer: PlayerState, shop: MerchantStock, item_id: StringName, quantity := 1) -> Dictionary:
	var res := {"result": Result.OK, "ok": false, "item": item_id, "quantity": quantity, "cost": 0, "gold": buyer.gold}
	if quantity <= 0:
		res.result = Result.INVALID_QUANTITY
		return res
	var def := ItemDatabase.get_item(item_id)
	if def == null:
		res.result = Result.UNKNOWN_ITEM
		return res
	if not def.purchasable:
		res.result = Result.NOT_PURCHASABLE
		return res
	var entry := shop.find_entry(item_id)
	if entry.is_empty() or int(entry.get("price", -1)) < 0:
		res.result = Result.NOT_SOLD_HERE
		return res
	var stock := int(entry.get("stock", -1))
	if stock != -1 and stock < quantity:
		res.result = Result.OUT_OF_STOCK
		return res
	var cost := int(entry.price) * quantity
	res.cost = cost
	if buyer.gold < cost:
		res.result = Result.NOT_ENOUGH_GOLD
		return res
	if not buyer.inventory.can_add(item_id, quantity):
		res.result = Result.INVENTORY_FULL
		return res
	# All checks passed: apply atomically.
	buyer.gold -= cost
	buyer.inventory.add(item_id, quantity)
	if stock != -1:
		entry.stock = stock - quantity
	res.ok = true
	res.gold = buyer.gold
	return res
