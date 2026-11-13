class_name ShopUI
extends CanvasLayer
## Merchant shop window (pure view + input). Shows a MerchantStock, the buyer's
## gold and owned counts, and asks the TradeService to perform purchases; it
## never edits gold or inventory itself.
##
## Keyboard: arrows to pick an item, Enter on the selected item (or "Acheter")
## to buy, Escape to cancel the confirmation / close the shop.
## Mouse / touch: tap an item to select it, tap it again or "Acheter" to buy;
## drag the list to scroll (touch), wheel to scroll (mouse).

signal opened
signal closed
signal purchase_finished(result: Dictionary)

const RESULT_TEXT := {
	TradeService.Result.UNKNOWN_ITEM: "Cet objet n'existe pas.",
	TradeService.Result.NOT_SOLD_HERE: "Ce marchand ne vend pas cet objet.",
	TradeService.Result.NOT_PURCHASABLE: "Cet objet ne peut pas être acheté.",
	TradeService.Result.INVALID_QUANTITY: "Quantité invalide.",
	TradeService.Result.NOT_ENOUGH_GOLD: "Tu n'as pas assez d'or.",
	TradeService.Result.INVENTORY_FULL: "Ton inventaire est plein.",
	TradeService.Result.OUT_OF_STOCK: "Il n'y en a plus en stock.",
}
const MARGIN := 6
const COIN := preload("res://assets/items/gold_coin_small.png")

@export var input_cooldown := 0.18
@export var open_grace := 0.25

var is_open := false
var stock: MerchantStock
var buyer: PlayerState
var trade: TradeService
var selected := 0
var busy := false
var confirming := false

var _root: Control
var _panel: PanelContainer
var _title: Label
var _gold: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Array[Button] = []
var _price_labels: Array[Label] = []
var _icon: TextureRect
var _item_name: Label
var _desc: Label
var _owned: Label
var _price: Label
var _message: Label
var _buy: Button
var _close: Button
var _confirm_layer: Control
var _confirm_text: Label
var _yes: Button
var _no: Button
var _opened_ms := 0
var _last_input_ms := -100000
var _drag_index := -1
var _drag_total := 0.0
var _drag_last_y := 0.0
var _suppress_press_until := 0
var _confirm_yes := true  # keyboard selection in the confirmation box


func _init() -> void:
	layer = 31
	visible = false
	_build()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)


# ----------------------------------------------------------------- building
func _build() -> void:
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	_panel.add_child(v)

	var header := HBoxContainer.new()
	v.add_child(header)
	_title = Label.new()
	_title.add_theme_color_override("font_color", UITheme.GOLD)
	_title.add_theme_font_size_override("font_size", 11)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_coin())
	_gold = Label.new()
	_gold.add_theme_color_override("font_color", UITheme.GOLD)
	header.add_child(_gold)
	var sep := ColorRect.new()
	sep.color = Color(0.84, 0.63, 0.28, 0.6)
	sep.custom_minimum_size = Vector2(0, 1)
	v.add_child(sep)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	v.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = 1.5
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)

	# Details scroll on their own so a long description can never push the
	# footer buttons off short screens.
	var details_scroll := ScrollContainer.new()
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(details_scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 3)
	details_scroll.add_child(details)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(64, 64)  # 32 px icon drawn at exactly 2x
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	details.add_child(_icon)
	_item_name = Label.new()
	_item_name.add_theme_color_override("font_color", UITheme.GOLD)
	_item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(_item_name)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_desc)
	var info := HBoxContainer.new()
	details.add_child(info)
	_owned = Label.new()
	_owned.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	_owned.add_theme_color_override("font_color", UITheme.MUTED)
	_owned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_owned)
	info.add_child(_coin())
	_price = Label.new()
	info.add_child(_price)

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", UITheme.SMALL_FONT_SIZE)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(0, 10)
	v.add_child(_message)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	v.add_child(footer)
	_buy = _button("Acheter")
	_buy.pressed.connect(func() -> void: request_buy())
	footer.add_child(_buy)
	_close = _button("Fermer")
	_close.pressed.connect(func() -> void: close())
	footer.add_child(_close)

	# Confirmation box (modal over the shop)
	_confirm_layer = Control.new()
	_confirm_layer.visible = false
	_root.add_child(_confirm_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(center)
	var box := PanelContainer.new()
	center.add_child(box)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	box.add_child(cv)
	_confirm_text = Label.new()
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_confirm_text)
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 10)
	cv.add_child(ch)
	_yes = _button("Oui")
	_yes.pressed.connect(func() -> void: confirm_purchase())
	ch.add_child(_yes)
	_no = _button("Non")
	_no.pressed.connect(func() -> void: cancel_confirm())
	ch.add_child(_no)


func _coin() -> TextureRect:
	var c := TextureRect.new()
	c.texture = COIN
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	c.custom_minimum_size = Vector2(16, 16)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(64, _touch_height())
	return b


func _touch_height() -> float:
	return SafeArea.mm_to_px(get_viewport(), 7.0, 20.0, 30.0) if is_inside_tree() else 22.0


func _layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var safe := SafeArea.viewport_rect(vp)
	_root.size = vp.get_visible_rect().size
	var w := clampf(roundf(safe.size.x * 0.64), 290.0, 380.0)
	var h := safe.size.y - 2 * MARGIN
	_panel.position = Vector2(safe.end.x - MARGIN - w, safe.position.y + MARGIN).round()
	_panel.size = Vector2(w, h).round()
	_confirm_layer.position = _panel.position
	_confirm_layer.size = _panel.size
	# Large 2x icon when there is room, 1x on short screens.
	_icon.custom_minimum_size = Vector2(64, 64) if h >= 250.0 else Vector2(32, 32)
	var th := _touch_height()
	for b in [_buy, _close, _yes, _no]:
		b.custom_minimum_size.y = th
	for r in _rows:
		r.custom_minimum_size.y = maxf(38.0, th)


## Viewport area left free for the game world (left of the shop panel).
func free_rect() -> Rect2:
	var safe := SafeArea.viewport_rect(get_viewport())
	return Rect2(safe.position, Vector2(maxf(60.0, _panel.position.x - safe.position.x - 4), safe.size.y))


func covered_rects() -> Array[Rect2]:
	return [Rect2(_panel.position, _panel.size)]


# ------------------------------------------------------------- open / close
func open(merchant: MerchantStock, player_state: PlayerState, service: TradeService) -> void:
	stock = merchant
	buyer = player_state
	trade = service
	is_open = true
	confirming = false
	busy = false
	visible = true
	_confirm_layer.visible = false
	_opened_ms = Time.get_ticks_msec()
	_title.text = stock.merchant_name
	if not buyer.gold_changed.is_connected(_on_gold_changed):
		buyer.gold_changed.connect(_on_gold_changed)
		buyer.inventory.changed.connect(_refresh)
	_build_rows()
	_layout()
	_on_gold_changed(buyer.gold)
	_message.text = "Que veux-tu acheter ?"
	_message.add_theme_color_override("font_color", UITheme.MUTED)
	select(0)
	if not _rows.is_empty():
		_rows[0].grab_focus()
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(1, 0.96)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.16)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.16)
	opened.emit()


func close() -> void:
	if not is_open or busy:
		return
	is_open = false
	confirming = false
	_confirm_layer.visible = false
	if buyer and buyer.gold_changed.is_connected(_on_gold_changed):
		buyer.gold_changed.disconnect(_on_gold_changed)
		buyer.inventory.changed.disconnect(_refresh)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit())


func _build_rows() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	_price_labels.clear()
	for i in stock.entries.size():
		var e: Dictionary = stock.entries[i]
		var def := ItemDatabase.get_item(StringName(e.item))
		var row := Button.new()
		row.custom_minimum_size = Vector2(0, maxf(38.0, _touch_height()))
		row.toggle_mode = false
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 4
		h.offset_right = -8
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var icon := TextureRect.new()
		icon.texture = def.icon if def else null
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.custom_minimum_size = Vector2(32, 32)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(icon)
		var name := Label.new()
		name.text = def.display_name if def else str(e.item)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.clip_text = true  # long names truncate, the price stays visible
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name.size_flags_vertical = Control.SIZE_FILL
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(name)
		var price := Label.new()
		price.text = str(e.price)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.custom_minimum_size = Vector2(20, 0)
		price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price.size_flags_vertical = Control.SIZE_FILL
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(price)
		var coin := _coin()
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(coin)
		var idx := i
		row.pressed.connect(func() -> void: _on_row_pressed(idx))
		# Keyboard navigation selects on focus; mouse/touch select on a real tap
		# (so a drag that starts on a row doesn't change the selection).
		row.focus_entered.connect(func() -> void:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				select(idx))
		_list.add_child(row)
		_rows.append(row)
		_price_labels.append(price)


func _entry() -> Dictionary:
	return stock.entries[selected] if stock and selected < stock.entries.size() else {}


func select(i: int) -> void:
	if stock == null or stock.entries.is_empty():
		return
	selected = clampi(i, 0, stock.entries.size() - 1)
	_refresh()
	_scroll.ensure_control_visible(_rows[selected])


func _refresh() -> void:
	if stock == null:
		return
	var e := _entry()
	var def := ItemDatabase.get_item(StringName(e.get("item", "")))
	_icon.texture = def.icon if def else null
	_item_name.text = def.display_name if def else "?"
	_desc.text = def.description if def else ""
	_owned.text = "Possédé : %d" % buyer.inventory.count_of(StringName(e.get("item", "")))
	_price.text = str(e.get("price", 0))
	for i in _rows.size():
		var afford := int(stock.entries[i].price) <= buyer.gold
		_price_labels[i].add_theme_color_override("font_color", UITheme.TEXT if afford else UITheme.BAD)
		_rows[i].add_theme_stylebox_override("normal", UITheme.get_theme().get_stylebox("hover" if i == selected else "normal", "Button"))
	_price.add_theme_color_override("font_color", UITheme.TEXT if int(e.get("price", 0)) <= buyer.gold else UITheme.BAD)


func _on_gold_changed(g: int) -> void:
	_gold.text = str(g)
	_refresh()


# ---------------------------------------------------------------- purchase
func _on_row_pressed(i: int) -> void:
	if Time.get_ticks_msec() < _suppress_press_until:
		return  # end of a touch drag-scroll, not a tap
	if i == selected and _accept():
		request_buy()
	else:
		select(i)


## Opens the confirmation box for the selected item.
func request_buy() -> void:
	if not is_open or busy or confirming or stock == null:
		return
	var e := _entry()
	var def := ItemDatabase.get_item(StringName(e.get("item", "")))
	_confirm_text.text = "Acheter %s\npour %d or ?" % [def.display_name if def else "?", int(e.get("price", 0))]
	confirming = true
	_confirm_layer.visible = true
	_last_input_ms = Time.get_ticks_msec()
	# The box handles its keys itself (see _input), independent of GUI focus.
	_set_confirm_choice(true)


func _set_confirm_choice(yes: bool) -> void:
	_confirm_yes = yes
	var theme := UITheme.get_theme()
	_yes.add_theme_stylebox_override("normal", theme.get_stylebox("hover" if yes else "normal", "Button"))
	_no.add_theme_stylebox_override("normal", theme.get_stylebox("normal" if yes else "hover", "Button"))


func cancel_confirm() -> void:
	confirming = false
	_confirm_layer.visible = false
	if selected < _rows.size():
		_rows[selected].grab_focus.call_deferred()


## "Oui" in the confirmation box: asks the TradeService.
func confirm_purchase() -> void:
	if not confirming or busy or not _accept():
		return
	confirming = false
	_confirm_layer.visible = false
	busy = true
	for b in [_buy, _close]:
		b.disabled = true
	var e := _entry()
	var res: Dictionary = await trade.request_purchase(buyer, stock, StringName(e.get("item", "")), 1)
	busy = false
	for b in [_buy, _close]:
		b.disabled = false
	if res.ok:
		var def := ItemDatabase.get_item(res.item)
		_show_message("Merci ! %s ajouté à ton sac (-%d or)." % [def.display_name, res.cost], UITheme.GOOD)
		_flash_gold()
	else:
		_show_message(RESULT_TEXT.get(res.result, "Achat impossible."), UITheme.BAD)
	_refresh()
	if selected < _rows.size():
		_rows[selected].grab_focus.call_deferred()
	purchase_finished.emit(res)


func _show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)


func _flash_gold() -> void:
	_gold.modulate = Color(1.6, 1.4, 0.8)
	create_tween().tween_property(_gold, "modulate", Color.WHITE, 0.4)


func message_text() -> String:
	return _message.text


# -------------------------------------------------------------------- input
func _accept() -> bool:
	var now := Time.get_ticks_msec()
	if now - _opened_ms < int(open_grace * 1000) or now - _last_input_ms < int(input_cooldown * 1000):
		return false
	_last_input_ms = now
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if confirming:
			cancel_confirm()
		elif _accept():
			close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"interact") and not confirming:
		# E on PC: buy the selected item (Enter is handled by the focused button).
		if _accept():
			request_buy()
		get_viewport().set_input_as_handled()


## Keyboard in the confirmation box: Left/Right pick Oui/Non, Enter/E
## validates, Escape cancels. Consumed before the GUI so focus can't interfere.
func _confirm_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right") \
			or event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"ui_down"):
		_set_confirm_choice(not _confirm_yes)
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		if _confirm_yes:
			confirm_purchase()
		else:
			cancel_confirm()
	elif event.is_action_pressed(&"ui_cancel"):
		cancel_confirm()
	else:
		return
	get_viewport().set_input_as_handled()


## Touch drag-scrolling of the item list (works on every device, independent
## of ScrollContainer's touchscreen detection).
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if confirming:
		_confirm_input(event)
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _drag_index == -1 and _scroll.get_global_rect().has_point(t.position):
			_drag_index = t.index
			_drag_total = 0.0
			_drag_last_y = t.position.y
		elif not t.pressed and t.index == _drag_index:
			_drag_index = -1
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _drag_index:
		var d := event as InputEventScreenDrag
		# Delta from the previous position (doesn't rely on `relative`).
		var dy := d.position.y - _drag_last_y
		_drag_last_y = d.position.y
		_drag_total += absf(dy)
		_scroll.scroll_vertical -= int(roundf(dy))
		if _drag_total > 6.0:
			# It's a scroll, not a tap: ignore the row "press" the lift will emit
			# (Godot delivers the emulated mouse release before this touch event).
			_suppress_press_until = Time.get_ticks_msec() + 250
