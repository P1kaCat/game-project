extends RefCounted
## NPC / dialogue / shop runtime checks, driven through real input events.
## Used by autotest.gd (shares its check() and helper functions).

var t: Node  # the autotest node
var world: Node
var player: Player
var eldric: Npc
var director: InteractionDirector
var dm: DialogueManager
var ui: DialogueUI
var shop: ShopUI
var completed := false


func _init(autotest: Node) -> void:
	t = autotest
	world = t.world
	player = t.player
	eldric = world.eldric
	director = world.director
	dm = director.dialogue_manager
	ui = director.dialogue_ui
	shop = director.shop_ui


func run() -> void:
	await _test_setup_and_indicator()
	await _test_talk_and_typewriter()
	await _test_branch_who_and_back()
	await _test_open_shop_and_buy()
	await _test_trade_rules()
	await _test_close_shop_restores_control()
	await _test_goodbye_by_touch()
	await _test_escape_cancels()
	await _test_touch_flow_and_scroll()
	completed = true


func run_layout_only() -> void:
	# Open dialogue + shop and check layout at the current resolution.
	_place_near_eldric()
	await t._wait(0.2)
	_key_e()
	await t._wait(0.5)
	ui.finish_typing()
	await t._wait(0.3)
	_check_world_visible("layout: dialogue", ui)
	t._capture("layout_dialogue")
	await _choose_by_keyboard(0)
	await _confirm_until_closed()
	await t._wait(0.5)
	_check_world_visible("layout: shop", shop)
	t._capture("layout_shop")


# ------------------------------------------------------------------- tests
func _test_setup_and_indicator() -> void:
	world.spawn_player(Vector2i(8, 8))
	await t._wait(0.2)
	t.check("npc: Eldric placed near the crossroads", world.terrain.cell_at(eldric.global_position) == Vector2i(10, 7),
		str(world.terrain.cell_at(eldric.global_position)))
	t.check("npc: Eldric uses his PixelLab sprites", eldric.sprite.sprite_frames.has_animation(&"idle_w")
		and String(eldric.sprite.animation) == "idle_w", String(eldric.sprite.animation))
	t.check("npc: indicator hidden when far", not eldric.interactable.highlighted)
	_place_near_eldric()
	await t._wait(0.2)
	t.check("npc: indicator shown in range", eldric.interactable.highlighted and player.interactor.target == eldric.interactable)
	if t._shots_dir != "":
		t._capture("npc_indicator")


func _test_talk_and_typewriter() -> void:
	_key_e()
	await t._wait(0.12)
	t.check("talk: E opens the dialogue", director.busy and ui.is_open and dm.is_active())
	t.check("talk: player locked + touch controls hidden", player.is_controls_locked() and not world.hud.visible)
	t.check("talk: player faces Eldric", player.facing == "e", player.facing)
	t.check("talk: Eldric faces the player", eldric.facing == "w", eldric.facing)
	t.check("talk: first line from data", dm.current_step().get("text", "").begins_with("Alors, tu as besoin"))
	t.check("typewriter: text appears progressively", ui.is_typing and ui._text.visible_characters < ui._text.get_total_character_count(),
		"%d/%d chars" % [ui._text.visible_characters, ui._text.get_total_character_count()])
	t._release([&"move_right"])
	t._press([&"move_right"])
	var p0 := player.global_position
	await t._wait(0.3)
	t._release([&"move_right"])
	t.check("talk: movement blocked during dialogue", player.global_position.distance_to(p0) < 0.01)
	if t._shots_dir != "":
		t._capture("dialogue_typing")
	_action(&"ui_accept")
	await t._wait(0.05)
	t.check("typewriter: confirm completes the line instantly", not ui.is_typing and ui._text.visible_characters == -1)
	t.check("dialogue: 3 choices shown", _choice_texts() == ["Montre-moi tes marchandises.", "Comment vont les affaires ?", "Rien pour l'instant."],
		str(_choice_texts()))
	_action(&"ui_accept")
	_action(&"ui_accept")
	await t._wait(0.05)
	t.check("double confirm: no accidental choice", dm.current_step().get("node", "") == "greet",
		str(dm.current_step().get("node", "")))
	_check_world_visible("dialogue", ui)
	if t._shots_dir != "":
		await t._wait(0.3)
		t._capture("dialogue_choices")


func _test_branch_who_and_back() -> void:
	await _choose_by_keyboard(1)
	t.check("branch 2: Eldric talks about trade", str(dm.current_step().get("text", "")).begins_with("Les routes sont calmes"),
		str(dm.current_step().get("text", "")).left(30))
	await _finish_line()
	t.check("branch 2: back to the initial choices", _choice_texts().size() == 3 and dm.current_step().node == "trade")
	t.check("dialogue: flag set for future quests", dm.flags.get("asked_trade", false) == true)


func _test_open_shop_and_buy() -> void:
	await t._wait(0.3)
	await _click(ui.choice_buttons()[0])
	t.check("branch 1: 'Avec plaisir.'", str(dm.current_step().get("text", "")).begins_with("Avec plaisir"))
	await _confirm_until_closed()
	await t._wait(0.4)
	t.check("shop: opens after the line", shop.is_open and not ui.is_open and director.busy)
	t.check("shop: merchant name + 250 gold", shop._title.text == "Eldric le marchand" and shop._gold.text == "250",
		"%s / %s" % [shop._title.text, shop._gold.text])
	t.check("shop: 3 items with icons and prices", shop._rows.size() == 3 and shop._price_labels.map(func(l): return l.text) == ["25", "10", "120"])
	t.check("shop: still locked", player.is_controls_locked())
	_check_world_visible("shop", shop)
	if t._shots_dir != "":
		t._capture("shop")
	await _buy(0)
	t.check("buy potion: 250 -> 225 gold", player.state.gold == 225 and shop._gold.text == "225", shop._gold.text)
	t.check("buy potion: in inventory, UI updated", player.state.inventory.count_of(&"healing_potion") == 1
		and shop._owned.text == "Possédé : 1", shop._owned.text)
	t.check("buy potion: confirmation message", shop.message_text().begins_with("Merci"), shop.message_text())
	if t._shots_dir != "":
		t._capture("shop_bought")
	await _buy(2)
	t.check("buy sword: 225 -> 105 gold", player.state.gold == 105 and player.state.inventory.count_of(&"iron_sword") == 1)
	await _buy(2)
	t.check("buy sword again: refused, not enough gold", player.state.gold == 105 and player.state.inventory.count_of(&"iron_sword") == 1
		and shop.message_text() == "Tu n'as pas assez d'or.", shop.message_text())
	t.check("shop: unaffordable price shown in red", shop._price_labels[2].get_theme_color("font_color") == UITheme.BAD)
	if t._shots_dir != "":
		t._capture("shop_not_enough")
	await _buy(1)
	t.check("buy bread: 105 -> 95 gold", player.state.gold == 95 and player.state.inventory.count_of(&"fresh_bread") == 1)


func _test_trade_rules() -> void:
	var stock: MerchantStock = load("res://data/shops/eldric.tres")
	var rich := PlayerState.new(1000, 1)
	rich.inventory.add(&"iron_sword")
	var r := TradeService.validate_and_apply(rich, stock, &"healing_potion")
	t.check("rules: inventory full -> refused, gold kept", r.result == TradeService.Result.INVENTORY_FULL and rich.gold == 1000)
	var stacker := PlayerState.new(1000, 1)
	stacker.inventory.add(&"healing_potion", 9)
	r = TradeService.validate_and_apply(stacker, stock, &"healing_potion")
	t.check("rules: stacks into an existing slot", r.ok and stacker.inventory.count_of(&"healing_potion") == 10 and stacker.gold == 975)
	r = TradeService.validate_and_apply(stacker, stock, &"healing_potion")
	t.check("rules: full stack + no free slot -> refused", r.result == TradeService.Result.INVENTORY_FULL and stacker.gold == 975)
	r = TradeService.validate_and_apply(PlayerState.new(), stock, &"dragon_egg")
	t.check("rules: unknown item -> refused", r.result == TradeService.Result.UNKNOWN_ITEM)
	var other := MerchantStock.new()
	other.entries = [{"item": &"fresh_bread", "price": 10, "stock": 1}]
	r = TradeService.validate_and_apply(PlayerState.new(), other, &"iron_sword")
	t.check("rules: item not sold by this merchant -> refused", r.result == TradeService.Result.NOT_SOLD_HERE)
	var buyer := PlayerState.new()
	TradeService.validate_and_apply(buyer, other, &"fresh_bread")
	r = TradeService.validate_and_apply(buyer, other, &"fresh_bread")
	t.check("rules: limited stock runs out", r.result == TradeService.Result.OUT_OF_STOCK and buyer.gold == 240)
	var restored := PlayerState.new(0, 1)
	restored.apply_dict(player.state.to_dict())
	t.check("state: serializable (server-ready)", restored.gold == player.state.gold
		and restored.inventory.count_of(&"iron_sword") == 1 and restored.inventory.capacity == 20)


func _test_close_shop_restores_control() -> void:
	await t._wait(0.3)
	_action(&"ui_cancel")
	await t._wait(0.4)
	t.check("shop: Escape closes it", not shop.is_open and not director.busy)
	t.check("after shop: control restored", not player.is_controls_locked() and not world.camera.is_framing())
	var p0 := player.global_position
	t._press([&"move_left"])
	await t._wait(0.3)
	t._release([&"move_left"])
	t.check("after shop: player moves again", player.global_position.distance_to(p0) > 5.0)


func _test_goodbye_by_touch() -> void:
	_place_near_eldric()
	await t._wait(0.2)
	_key_e()
	await t._wait(0.4)
	await _tap(ui._box.get_global_rect().get_center())  # tap: complete the line
	await t._wait(0.3)
	t.check("touch: tap completes the line", not ui.is_typing and _choice_texts().size() == 3)
	await t._wait(0.3)
	await _tap(ui.choice_buttons()[2].get_global_rect().get_center())
	t.check("branch 3: 'D'accord. Je reste dans le coin.'", str(dm.current_step().get("text", "")) == "D'accord. Je reste dans le coin.",
		str(dm.current_step().get("text", "")))
	await _confirm_until_closed(true)
	await t._wait(0.4)
	t.check("branch 3: dialogue closed, no shop", not ui.is_open and not shop.is_open and not director.busy)


func _test_escape_cancels() -> void:
	_place_near_eldric()
	await t._wait(0.2)
	_key_e()
	await t._wait(0.4)
	_action(&"ui_accept")
	await t._wait(0.35)
	_action(&"ui_cancel")
	await t._wait(0.1)
	t.check("Escape on choices: picks 'Rien pour l'instant.'", str(dm.current_step().get("text", "")) == "D'accord. Je reste dans le coin.")
	await _confirm_until_closed()
	await t._wait(0.4)
	t.check("Escape flow: closed", not director.busy)


func _test_touch_flow_and_scroll() -> void:
	GameInput.touch_ui_enabled = true
	_place_near_eldric()
	await t._wait(0.3)
	t.check("touch: HUD visible before talking", world.hud.visible)
	var b: Vector2 = world.hud.action_button.global_center()
	t._touch(1, b, true)
	await t._wait(0.05)
	t._touch(1, b, false)
	await t._wait(0.15)
	t.check("touch: action button starts the conversation", director.busy and ui.is_open)
	t.check("touch: movement controls hidden", not world.hud.visible)
	await t._wait(0.3)  # past the anti-double-tap grace period
	await _tap(ui._box.get_global_rect().get_center())
	await t._wait(0.35)
	var rows := ui.choice_buttons()
	var row_h := rows[0].size.y
	t.check("touch: choice rows are finger-sized", row_h >= 18.0, "%.0f px" % row_h)
	await _tap(rows[0].get_global_rect().get_center())
	await _confirm_until_closed(true)
	await t._wait(0.4)
	t.check("touch: shop opened by tapping choices", shop.is_open)
	await t._wait(0.3)
	await _tap(shop._rows[1].get_global_rect().get_center())  # select bread
	await t._wait(0.25)
	await _tap(shop._buy.get_global_rect().get_center())
	await t._wait(0.25)
	t.check("touch: confirmation box", shop.confirming)
	t._capture("shop_confirm")
	var gold0: int = player.state.gold
	await _tap(shop._yes.get_global_rect().get_center())
	await t._wait(0.2)
	t.check("touch: purchase by taps", player.state.gold == gold0 - 10, "%d -> %d" % [gold0, player.state.gold])
	# Scrolling: a long catalogue in the same window
	var long := MerchantStock.new()
	long.merchant_name = "Test"
	for i in 12:
		long.entries.append({"item": [&"healing_potion", &"fresh_bread", &"iron_sword"][i % 3], "price": 5, "stock": -1})
	var orig := shop.stock
	shop.stock = long
	shop._build_rows()
	shop._layout()
	await t._wait(0.2)
	var sel := shop.selected
	var c := shop._scroll.get_global_rect().get_center()
	t._touch(3, c, true)
	for i in 8:
		t._drag(3, c - Vector2(0, 8 * (i + 1)))
		await t.get_tree().process_frame
	t._touch(3, c - Vector2(0, 64), false)
	await t._wait(0.2)
	t.check("touch: drag scrolls the catalogue", shop._scroll.scroll_vertical > 20, "scroll %d" % shop._scroll.scroll_vertical)
	t.check("touch: drag does not select/buy", shop.selected == sel and not shop.confirming)
	shop.stock = orig
	shop._build_rows()
	shop.select(0)
	await t._wait(0.3)
	await _tap(shop._close.get_global_rect().get_center())
	await t._wait(0.4)
	t.check("touch: 'Fermer' closes, controls back", not director.busy and world.hud.visible)


# ----------------------------------------------------------------- helpers
func _place_near_eldric() -> void:
	player.global_position = eldric.global_position + Vector2(-30, 4)
	player.ground_velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	world.camera.snap_to_target()


func _key_e() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _action(a: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _choice_texts() -> Array:
	return ui.choice_buttons().map(func(b: Button) -> String: return b.text) if ui._choices_panel.visible else []


func _finish_line() -> void:
	await t._wait(0.25)
	if ui.is_typing:
		_action(&"ui_accept")
	await t._wait(0.3)


## Keyboard: move the focus down `index` times, then Enter.
func _choose_by_keyboard(index: int) -> void:
	await t._wait(0.3)
	for i in index:
		_action(&"ui_down")
		await t.get_tree().process_frame
	_action(&"ui_accept")
	await t._wait(0.1)


func _confirm_until_closed(by_tap := false) -> void:
	for i in 6:
		if not ui.is_open:
			return
		await t._wait(0.25)
		if by_tap:
			await _tap(ui._box.get_global_rect().get_center())
		else:
			_action(&"ui_accept")
		await t._wait(0.05)  # let the input be processed before checking again


func _buy(row: int) -> void:
	await t._wait(0.25)
	shop.select(row)
	shop._rows[row].grab_focus()
	await t._wait(0.2)
	_action(&"ui_accept")  # Enter on the selected item -> confirmation box
	await t._wait(0.25)
	if not shop.confirming:
		shop.request_buy()
		await t._wait(0.25)
	_action(&"ui_accept")  # "Oui" is focused
	await shop.purchase_finished
	await t._wait(0.05)


## Mouse click at a control (window coordinates, like the OS).
func _click(c: Control) -> void:
	var p: Vector2 = t._to_window(c.get_global_rect().get_center())
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p
		ev.global_position = p
		Input.parse_input_event(ev)
		await t.get_tree().process_frame
	await t._wait(0.1)


## Finger tap (InputEventScreenTouch; Godot emulates the mouse for the GUI).
func _tap(vp_pos: Vector2) -> void:
	t._touch(0, vp_pos, true)
	await t.get_tree().process_frame
	t._touch(0, vp_pos, false)
	await t._wait(0.1)


func _screen(world_pos: Vector2) -> Vector2:
	return t.get_viewport().get_canvas_transform() * world_pos


func _check_world_visible(label: String, view) -> void:
	var free: Rect2 = view.free_rect()
	var ok := true
	var detail := ""
	for who in [player, eldric]:
		var feet := _screen(who.global_position)
		var head := _screen(who.global_position + Vector2(0, -46))
		var body := Rect2(head - Vector2(10, 0), Vector2(20, feet.y - head.y))
		for r: Rect2 in view.covered_rects():
			if r.intersects(body):
				ok = false
		if not t.get_viewport().get_visible_rect().encloses(body):
			ok = false
		detail += "%s feet %s; " % [who.name, feet.round()]
	t.check("%s: player and Eldric visible, not covered" % label, ok, detail + "free %s" % free)
	var safe := SafeArea.viewport_rect(t.get_viewport())
	var inside := true
	for r: Rect2 in view.covered_rects():
		inside = inside and safe.grow(0.5).encloses(r)
	t.check("%s: window inside the safe area" % label, inside)
