extends Node
## End-to-end story / menu / save flow, driven through real input actions
## (ui_accept / ui_cancel / interact) on the real scenes.
##
## Run:  godot --path . -- --autotest --flow-test [--shots=/abs/dir]
## Covers: main menu states, settings persistence, new game -> full cinematic
## (accelerated) -> awakening -> optional first Eldric dialogue (exact lines,
## the three choices) -> merchant + shop, autosave, pause + manual save,
## back to menu, Continue (state restored), corrupted / tampered saves,
## new game over an existing save (confirmation) and hold-to-skip.
## WARNING: deletes user://saves and user://settings.cfg of the test profile.

var _checks := 0
var _failures := 0
var _shots := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots)
	# watchdog (real time, survives pause / time scale)
	get_tree().create_timer(420.0, true, false, true).timeout.connect(func() -> void:
		print("SUMMARY FAIL (timeout after %d checks)" % _checks)
		get_tree().quit(2))
	await _run()
	Engine.time_scale = 1.0
	print("SUMMARY %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(1 if _failures else 0)


func check(name: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("CHECK %-4s %-48s %s" % ["PASS" if ok else "FAIL", name, detail])


# ------------------------------------------------------------------ helpers
func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func seconds(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


## Waits (real time) until cond() is true. Returns whether it became true.
func until(cond: Callable, timeout := 10.0) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func action(a: StringName, hold := 0.0) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = true
	Input.parse_input_event(e)
	if hold > 0.0:
		Input.action_press(a)
		await seconds(hold)
		Input.action_release(a)
	else:
		await frames(2)
	var r := InputEventAction.new()
	r.action = a
	r.pressed = false
	Input.parse_input_event(r)
	await frames(3)


## Focus + Enter, like a keyboard / gamepad user.
func activate(b: Control) -> void:
	b.grab_focus()
	await frames(1)
	await action(&"ui_accept")


func scene() -> Node:
	return get_tree().current_scene


func scene_is(path: String) -> bool:
	return scene() != null and scene().scene_file_path == path and not SceneFade.is_busy()


func shot(name: String) -> void:
	if _shots == "":
		return
	await seconds(0.35)  # let open / fade tweens settle
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


# ------------------------------------------------------------------- flow
func _run() -> void:
	# Clean profile, then a fresh menu.
	for slot in SaveSystem.SLOTS:
		SaveSystem.delete_slot(slot)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	Settings.load_settings()
	Settings.apply()
	get_tree().reload_current_scene()
	await until(func() -> bool: return scene() != null and scene().get("buttons") != null and not scene().buttons.is_empty())
	await seconds(2.6)
	await _test_menu_without_save()
	await _test_settings()
	await _test_new_game_full_cinematic()
	await _test_awakening()
	await _test_first_eldric_dialogue()
	await _test_pause_and_manual_save()
	await _test_back_to_menu_and_continue()
	await _test_corrupted_saves()
	await _test_new_game_over_save_and_skip()


func _test_menu_without_save() -> void:
	var m := scene()
	check("menu: is the main menu", m.scene_file_path == "res://scenes/main_menu.tscn")
	check("menu: Continuer disabled without a save", m.buttons.continue.disabled)
	check("menu: Charger disabled without a save", m.buttons.load.disabled)
	check("menu: Quitter present on desktop", m.buttons.has("quit"))
	var labels: Array = ["continue", "new_game", "load", "settings", "quit"].map(func(k: String) -> String: return m.buttons[k].text)
	check("menu: French entries", labels == ["Continuer", "Nouvelle partie", "Charger une partie", "Paramètres", "Quitter"], str(labels))
	check("menu: subtitle", m._subtitle.text == "Un monde au-delà de l'oubli.")
	check("menu: focus on Nouvelle partie", get_viewport().gui_get_focus_owner() == m.buttons.new_game)
	await shot("menu")


func _test_settings() -> void:
	var m := scene()
	await activate(m.buttons.settings)
	var p = m.get_children().filter(func(n: Node) -> bool: return n is SettingsPanel)
	check("settings: panel opens", p.size() == 1)
	if p.is_empty():
		return
	var panel: SettingsPanel = p[0]
	await frames(3)
	await shot("settings")
	var ts := panel.control_for("gameplay/text_speed") as Button
	check("settings: text speed shows Normale", ts.text.contains("Normale"), ts.text)
	await activate(ts)
	check("settings: Enter cycles text speed -> fast", Settings.get_value("gameplay/text_speed") == "fast" and ts.text.contains("Rapide"), ts.text)
	ts.grab_focus()
	await action(&"ui_left")
	check("settings: left arrow cycles back", Settings.get_value("gameplay/text_speed") == "normal")
	await action(&"ui_right")
	var vol := panel.control_for("audio/music") as HSlider
	vol.grab_focus()
	await action(&"ui_left")
	await action(&"ui_left")
	check("settings: music slider by keyboard", is_equal_approx(float(Settings.get_value("audio/music")), 0.6), str(Settings.get_value("audio/music")))
	check("settings: Music bus volume applied", absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.6)) < 0.05)
	var zoom := panel.control_for("display/zoom") as Button
	await activate(zoom)
	check("settings: pixel scale -> wide changes internal height", PixelScaler.target_height == 320)
	await activate(zoom)
	await activate(zoom)
	check("settings: pixel scale back to normal", PixelScaler.target_height == 270)
	check("settings: fullscreen row on desktop", panel.control_for("display/fullscreen") != null)
	await action(&"ui_cancel")
	check("settings: Escape closes the panel", not is_instance_valid(panel) or panel.is_queued_for_deletion())
	var cfg := ConfigFile.new()
	check("settings: written to user://settings.cfg", cfg.load(Settings.PATH) == OK
		and cfg.get_value("gameplay", "text_speed") == "fast" and is_equal_approx(cfg.get_value("audio", "music"), 0.6))
	Settings.set_value("gameplay/text_speed", "slow")
	Settings.load_settings()
	check("settings: reload restores saved values", Settings.get_value("gameplay/text_speed") == "fast")
	# corrupted settings file -> defaults, no crash
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	f.store_string("[audio]\nmusic=\"loud\"\n[gameplay]\ntext_speed=42\n")
	f.close()
	Settings.load_settings()
	check("settings: invalid values fall back to defaults", Settings.get_value("audio/music") == 0.7 and Settings.get_value("gameplay/text_speed") == "normal")
	Settings.set_value("gameplay/text_speed", "fast")
	Settings.save_settings()
	await frames(3)
	check("settings: focus returns to the menu", get_viewport().gui_get_focus_owner() == m.buttons.settings)


func _test_new_game_full_cinematic() -> void:
	var m := scene()
	await activate(m.buttons.new_game)
	check("new game: no confirmation without a save", not m.get_children().any(func(n: Node) -> bool: return n is ConfirmDialog))
	var ok := await until(func() -> bool: return scene_is("res://scenes/cinematic.tscn"), 5)
	check("new game: opening cinematic starts", ok)
	if not ok:
		return
	var c := scene()
	check("new game: state initialised (250 gold, no flags)", GameState.player.gold == 250 and not GameState.flags.has("eldric_intro_done"))
	await until(func() -> bool: return c.lines_shown >= 1, 10)
	check("cinematic: first line (exact)", c.current_line == "Dans le monde où je suis né, chaque âme portait une inscription.", c.current_line)
	await shot("cinematic_1")
	# a short tap advances to the next line
	await until(func() -> bool: return c._subtitle.modulate.a >= 1.0, 3)
	var n = c.lines_shown
	await action(&"ui_accept")
	await until(func() -> bool: return c.lines_shown > n, 3)
	check("cinematic: tap advances the line", c.current_line == "Un nom que nul ne pouvait effacer.", c.current_line)
	check("cinematic: tap does not skip", not c.skipped and not c.done)
	Engine.time_scale = 12.0
	var seen_voice := [false]
	var seen_last := [false]
	var watcher := func() -> bool:
		if c.current_line == "Une âme sans inscription ne peut appartenir à notre monde.":
			seen_voice[0] = true
		if c.current_line == "Je n'avais plus de monde auquel appartenir.":
			seen_last[0] = true
		if c.current_scene == 2 and _shots != "" and c._portrait.visible and not has_meta("shot3"):
			set_meta("shot3", true)
			shot("cinematic_3")
		return c.done or not is_instance_valid(c)
	await until(watcher, 60)
	Engine.time_scale = 1.0
	check("cinematic: authority voice line shown", seen_voice[0])
	check("cinematic: all 5 scenes played", c.current_scene == 4)
	check("cinematic: last narration line", seen_last[0])
	check("cinematic: title ASTHYA shown", c._title.texture != null and c._title.modulate.a > 0.0)
	check("cinematic: finished without skipping", c.done and not c.skipped)
	check("cinematic: intro flag set", GameState.flags.get("intro_seen", false) == true)


func _test_awakening() -> void:
	var ok := await until(func() -> bool: return scene_is("res://scenes/main.tscn"), 10)
	check("awakening: world loaded", ok)
	if not ok:
		return
	var w := scene()
	await frames(2)
	check("awakening: story sequence running", w.story_running)
	check("awakening: controls locked", w.player.is_controls_locked())
	check("awakening: kneeling (get-up frame 0)", w.player.sprite.current_state == "getup" and w.player.sprite.frame == 0,
		"%s frame %d playing %s" % [w.player.sprite.current_state, w.player.sprite.frame, w.player.sprite.is_playing()])
	check("awakening: dialogue not forced", not w.director.busy)
	var d: float = w.player.global_position.distance_to(w.eldric.global_position)
	check("awakening: Eldric nearby, not adjacent", d > 60.0 and d < 200.0, "%.0f px" % d)
	Input.action_press(&"ui_cancel")
	await frames(2)
	Input.action_release(&"ui_cancel")
	check("awakening: no pause during the sequence", not w.pause_menu.is_open)
	await shot("awakening_start")
	await until(func() -> bool: return w.player.sprite.current_state == "getup" and w.player.sprite.is_playing(), 6)
	check("awakening: get-up animation plays", w.player.sprite.current_state == "getup")
	await until(func() -> bool: return not w.story_running, 10)
	check("awakening: control given back", not w.player.is_controls_locked() and w.player.sprite.current_state == "idle")
	check("awakening: flag set", GameState.flags.get("awakened", false) == true)
	var auto := SaveSystem.load_slot("auto")
	check("awakening: autosave written and valid", auto.ok and auto.data.flags.get("awakened") == true, str(auto.error))
	# the player can move
	var start: Vector2 = w.player.global_position
	Input.action_press(&"move_right")
	await seconds(0.4)
	Input.action_release(&"move_right")
	await seconds(0.2)
	check("awakening: player can move", w.player.global_position.distance_to(start) > 8.0)
	await shot("awakening_end")


func _talk_to_eldric(w: Node) -> void:
	w.player.global_position = w.eldric.global_position + Vector2(-30, 8)
	w.player.reset_physics_interpolation()
	await seconds(0.3)
	await action(&"interact")
	await until(func() -> bool: return w.director.busy and w.director.dialogue_ui.is_open, 3)


## Completes the current line, then waits until it can be confirmed.
func _next(ui: DialogueUI) -> void:
	await seconds(0.25)
	if ui.is_typing:
		ui.finish_typing()
	await seconds(0.25)
	await action(&"ui_accept")
	await seconds(0.1)


func _texts(ui: DialogueUI) -> Array:
	return ui.choice_buttons().map(func(b: Button) -> String: return b.text) if ui._choices_panel.visible else []


func _wait_choices(ui: DialogueUI) -> void:
	await seconds(0.25)
	if ui.is_typing:
		ui.finish_typing()
	await until(func() -> bool: return ui._choices_panel.visible, 3)
	await seconds(0.3)


func _choose(ui: DialogueUI, i: int) -> void:
	ui.choice_buttons()[i].grab_focus()
	await frames(2)
	await action(&"ui_accept")
	await seconds(0.2)


func _test_first_eldric_dialogue() -> void:
	var w := scene()
	if w == null or w.scene_file_path != "res://scenes/main.tscn":
		return
	var dm: DialogueManager = w.director.dialogue_manager
	var ui: DialogueUI = w.director.dialogue_ui
	await _talk_to_eldric(w)
	var step := dm.current_step()
	check("eldric: first meeting line (exact)", step.get("text", "") == "Eh bien... Je commençais à croire que tu ne te réveillerais jamais.", str(step.get("text", "")))
	check("eldric: greet gesture plays", w.eldric.sprite.current_state == "greet")
	check("eldric: 128 px portrait", ui._portrait.texture != null and ui._portrait.texture.get_size() == Vector2(128, 128))
	await shot("eldric_intro")
	var expected := [["player", "Où suis-je ?"], ["eldric", "En Asthya, évidemment."], ["player", "Asthya... ?"],
		["eldric", "Tu n'es vraiment pas d'ici, hein ?"],
		["eldric", "Écoute, je ne sais pas d'où tu viens, mais tu ferais mieux de ne pas rester seul trop longtemps."]]
	var all_ok := true
	var detail := ""
	for e in expected:
		await _next(ui)
		var s := dm.current_step()
		if s.get("speaker") != e[0] or s.get("text") != e[1]:
			all_ok = false
			detail = "%s: %s" % [s.get("speaker"), s.get("text")]
		if e[0] == "player" and s.get("name") != "???":
			all_ok = false
			detail = "player name %s" % s.get("name")
	check("eldric: scripted exchange (exact lines, '???')", all_ok, detail)
	await _wait_choices(ui)
	check("eldric: the three choices", _texts(ui) == ["Tu peux m'aider ?", "Qu'est-ce que cet endroit ?", "Je dois partir."], str(_texts(ui)))
	check("eldric: intro flag set once the exchange is seen", GameState.flags.get("eldric_intro_done", false) == true)
	await shot("eldric_choices")
	await _choose(ui, 1)
	check("eldric: 'Qu'est-ce que cet endroit ?' answered", str(dm.current_step().get("node")) == "place_1")
	await _next(ui)
	await _wait_choices(ui)
	check("eldric: back to the three choices", _texts(ui).size() == 3 and _texts(ui)[0] == "Tu peux m'aider ?")
	await _choose(ui, 0)
	check("eldric: 'Tu peux m'aider ?' answered", str(dm.current_step().get("node")) == "help_1")
	await _next(ui)
	await _wait_choices(ui)
	check("eldric: merchant choices now offered", _texts(ui) == ["Montre-moi tes marchandises.", "Qui es-tu ?", "Non merci."], str(_texts(ui)))
	await _choose(ui, 0)
	await _next(ui)
	var shop: ShopUI = w.director.shop_ui
	await until(func() -> bool: return shop.visible, 3)
	check("shop: opens after the introduction", shop.visible)
	await seconds(0.4)
	var gold_before: int = GameState.player.gold
	await action(&"ui_accept")  # buy the focused (first) item
	await seconds(0.3)
	if shop.has_method("_confirm_input"):
		pass
	await action(&"ui_accept")  # confirm purchase
	await seconds(0.3)
	check("shop: purchase changes the saved state's gold", GameState.player.gold < gold_before, "%d -> %d" % [gold_before, GameState.player.gold])
	await shot("shop")
	for i in 3:  # cancel a pending confirmation box, then the shop itself
		if not w.director.busy:
			break
		await action(&"ui_cancel")
		await seconds(0.3)
	check("pause: not opened by the key that closed the shop", not w.pause_menu.is_open)
	check("shop: closed, control back", not w.director.busy and not w.player.is_controls_locked())
	var auto := SaveSystem.load_slot("auto")
	check("autosave: after the conversation (flag + gold)", auto.ok and auto.data.flags.get("eldric_intro_done") == true
		and int(auto.data.player.gold) == GameState.player.gold)
	# second conversation: regular merchant greeting
	await _talk_to_eldric(w)
	check("eldric: later talks use the merchant greeting", str(dm.current_step().get("text", "")).begins_with("Bienvenue, voyageur"),
		"busy=%s open=%s text=%s" % [w.director.busy, ui.is_open, str(dm.current_step().get("text", "")).left(30)])
	await _wait_choices(ui)
	await action(&"ui_cancel")
	await _next(ui)
	await until(func() -> bool: return not w.director.busy, 3)


func _test_pause_and_manual_save() -> void:
	var w := scene()
	if w == null or w.scene_file_path != "res://scenes/main.tscn":
		return
	await seconds(0.3)
	await action(&"ui_cancel")
	check("pause: Escape opens the pause menu", w.pause_menu.is_open and get_tree().paused)
	await shot("pause")
	await activate(w.pause_menu.buttons.save)
	var panels = w.pause_menu._root.get_children().filter(func(n: Node) -> bool: return n is SaveSlotsPanel)
	check("pause: save slots panel", panels.size() == 1)
	if panels.is_empty():
		return
	var sp: SaveSlotsPanel = panels[0]
	check("pause: automatic slot not offered for manual saves", sp.button_for("auto") == null and sp.button_for("1") != null)
	await activate(sp.button_for("1"))
	await seconds(0.2)
	var r := SaveSystem.load_slot("1")
	check("pause: saved to slot 1", r.ok and int(r.data.player.gold) == GameState.player.gold, r.error)
	check("pause: saved position = player position", r.ok and Vector2(r.data.position[0], r.data.position[1]).distance_to(w.player.global_position) < 1.0)
	set_meta("saved_gold", GameState.player.gold)
	set_meta("saved_pos", w.player.global_position)
	await activate(w.pause_menu.buttons.resume)
	check("pause: Reprendre unpauses", not w.pause_menu.is_open and not get_tree().paused)


func _test_back_to_menu_and_continue() -> void:
	var w := scene()
	if w == null or w.scene_file_path != "res://scenes/main.tscn":
		return
	await action(&"ui_cancel")
	await activate(w.pause_menu.buttons.main_menu)
	var dlg = w.pause_menu._root.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)
	check("pause: main menu asks for confirmation", dlg.size() == 1)
	if dlg.is_empty():
		return
	await activate(dlg[0].yes_button)
	var ok := await until(func() -> bool: return scene_is("res://scenes/main_menu.tscn") and scene().get("buttons") != null and not scene().buttons.is_empty(), 6)
	check("menu: back to the main menu, unpaused", ok and not get_tree().paused)
	if not ok:
		return
	await seconds(2.6)
	var m := scene()
	check("menu: Continuer enabled with a save", not m.buttons.continue.disabled and not m.buttons.load.disabled)
	# wipe the in-memory state to prove it comes from disk
	GameState.new_game()
	GameState.player.gold = 1
	await activate(m.buttons.continue)
	ok = await until(func() -> bool: return scene_is("res://scenes/main.tscn"), 6)
	check("continue: world loaded", ok)
	if not ok:
		return
	var w2 := scene()
	await frames(3)
	check("continue: no awakening replay", not w2.story_running and not w2.player.is_controls_locked())
	check("continue: flags restored", GameState.flags.get("eldric_intro_done", false) == true and GameState.flags.get("intro_seen", false) == true)
	var auto_t := int(SaveSystem.load_slot("auto").saved_at)
	var one_t := int(SaveSystem.load_slot("1").saved_at)
	var src := "auto" if auto_t > one_t else "1"
	var expect := SaveSystem.load_slot(src)
	check("continue: latest save's gold and position", GameState.player.gold == int(expect.data.player.gold)
		and w2.player.global_position.distance_to(Vector2(expect.data.position[0], expect.data.position[1])) < 1.0,
		"slot %s gold %d" % [src, GameState.player.gold])
	var canon := func(v: Variant) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(v)), "", true)
	check("continue: inventory restored", canon.call(GameState.player.inventory.to_dict()) == canon.call(expect.data.player.inventory),
		canon.call(GameState.player.inventory.to_dict()).left(80))
	await _talk_to_eldric(w2)
	check("continue: Eldric remembers (merchant greeting)", str(w2.director.dialogue_manager.current_step().get("text", "")).begins_with("Bienvenue"))
	await _wait_choices(w2.director.dialogue_ui)
	await action(&"ui_cancel")
	await _next(w2.director.dialogue_ui)
	await until(func() -> bool: return not w2.director.busy, 3)
	await action(&"ui_cancel")
	await activate(w2.pause_menu.buttons.main_menu)
	var dlg2 = w2.pause_menu._root.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)
	if not dlg2.is_empty():
		await activate(dlg2[0].yes_button)
	await until(func() -> bool: return scene_is("res://scenes/main_menu.tscn") and scene().get("buttons") != null and not scene().buttons.is_empty(), 6)
	await seconds(2.6)


func _test_corrupted_saves() -> void:
	# slot 2: garbage; slot 3: valid JSON with an edited gold value
	var f := FileAccess.open(SaveSystem.path_of("2"), FileAccess.WRITE)
	f.store_string("{\"format\": \"asthya-save\", \"data\": {trunc")
	f.close()
	var good := FileAccess.get_file_as_string(SaveSystem.path_of("1"))
	var payload: Dictionary = JSON.parse_string(good)
	payload.data.player.gold = 999999
	f = FileAccess.open(SaveSystem.path_of("3"), FileAccess.WRITE)
	f.store_string(JSON.stringify(payload))
	f.close()
	check("save: truncated file rejected", not SaveSystem.load_slot("2").ok, SaveSystem.load_slot("2").error)
	check("save: edited file rejected (checksum)", SaveSystem.load_slot("3").error.begins_with("checksum"), SaveSystem.load_slot("3").error)
	var bad := GameState.to_dict()
	bad.player.inventory.slots = [{"id": "no_such_item", "count": 1}]
	check("save: unknown item refused on save", SaveSystem.save_slot("3", bad) != OK)
	bad = GameState.to_dict()
	bad.position = [NAN, 0]
	check("save: invalid position refused", SaveSystem.validate(bad) == "position")
	check("save: latest valid slot ignores corrupted ones", SaveSystem.latest_valid_slot() in ["auto", "1"])
	var m := scene()
	await activate(m.buttons.load)
	var panels = m.get_children().filter(func(n: Node) -> bool: return n is SaveSlotsPanel)
	check("load: slots panel opens", panels.size() == 1)
	if panels.is_empty():
		return
	var sp: SaveSlotsPanel = panels[0]
	check("load: corrupted slots disabled and labelled", sp.button_for("2").disabled and sp.button_for("2").text.contains("illisible")
		and sp.button_for("3").disabled)
	check("load: valid slot shows region / time / gold", sp.button_for("1").text.contains("Prairie de l'Éveil") and sp.button_for("1").text.contains(" or"),
		sp.button_for("1").text.replace("\n", " | "))
	await shot("load_slots")
	await action(&"ui_cancel")
	await frames(3)
	# a .bak is kept when a slot is overwritten
	SaveSystem.save_slot("1", GameState.to_dict()) if GameState.active else OK
	check("save: previous version kept as .bak", FileAccess.file_exists(SaveSystem.path_of("1") + ".bak"))


func _test_new_game_over_save_and_skip() -> void:
	var m := scene()
	await activate(m.buttons.new_game)
	var dlg = m.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)
	check("new game over a save: confirmation", dlg.size() == 1)
	if dlg.is_empty():
		return
	check("new game over a save: 'Non' focused by default", get_viewport().gui_get_focus_owner() == dlg[0].no_button)
	await shot("confirm_new_game")
	await action(&"ui_accept")
	await seconds(0.3)
	check("new game over a save: 'Non' keeps the menu", scene_is("res://scenes/main_menu.tscn") and SaveSystem.load_slot("auto").ok)
	await activate(m.buttons.new_game)
	dlg = m.get_children().filter(func(n: Node) -> bool: return n is ConfirmDialog)
	await activate(dlg[0].yes_button)
	var ok := await until(func() -> bool: return scene_is("res://scenes/cinematic.tscn"), 5)
	check("new game over a save: 'Oui' starts the cinematic", ok)
	if not ok:
		return
	check("new game: fresh state (flags cleared)", not GameState.flags.has("eldric_intro_done") and GameState.player.gold == 250)
	var c := scene()
	await until(func() -> bool: return c.lines_shown >= 1, 10)
	await action(&"ui_accept", 0.5)
	check("skip: a 0.5 s press does not skip", not c.skipped)
	await action(&"ui_accept", 1.5)
	check("skip: holding 1.2 s skips the cinematic", c.skipped)
	check("skip: state initialised like a full viewing", GameState.flags.get("intro_seen", false) == true and GameState.awakening_pending)
	ok = await until(func() -> bool: return scene_is("res://scenes/main.tscn"), 8)
	check("skip: continues into the awakening", ok and scene().story_running)
	if ok:
		await until(func() -> bool: return not scene().story_running, 10)
		check("skip: then the player gets control", not scene().player.is_controls_locked())
		var w := scene()
		await _talk_to_eldric(w)
		check("skip: Eldric introduction available again (new game)", str(w.director.dialogue_manager.current_step().get("text", "")).begins_with("Eh bien"))
