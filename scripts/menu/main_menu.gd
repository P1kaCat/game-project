extends Control
## Asthya main menu: illustrated background with slow parallax, drifting
## dithered fog, rising motes, the ASTHYA logo and the menu column.
##
##   Continuer        latest valid save (disabled when there is none)
##   Nouvelle partie  confirmation if it would replace the current progress,
##                    then the opening cinematic
##   Charger          slot picker
##   Paramètres       SettingsPanel
##   Quitter          desktop only (hidden on Android / iOS)
##
## `-- --autotest` (the movement / NPC regression suites) skips the menu and
## starts a sandbox game with the story already seen.

const WORLD_SCENE := "res://scenes/main.tscn"
const CINEMATIC_SCENE := "res://scenes/cinematic.tscn"
const BG_COLOR := Color(0.055, 0.055, 0.07)

var buttons := {}            # id -> Button (tests)
var _bg: TextureRect
var _fog: Array[Atmosphere.ScrollLayer] = []
var _logo: TextureRect
var _ring: TextureRect
var _subtitle: Label
var _menu: VBoxContainer
var _cursor: TextureRect
var _shade: TextureRect
var _motes: CPUParticles2D
var _t := 0.0
var _overlay_open := false


func _ready() -> void:
	Settings.apply()
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args and not "--flow-test" in args:
		GameState.setup_sandbox()
		get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_intro_animation()
	Audio.ambience("amb_menu", 2.5, -6.0)
	if "--flow-test" in args and not get_tree().root.has_node(^"FlowTest"):
		var t: Node = load("res://scripts/debug/autotest_flow.gd").new()
		t.name = "FlowTest"
		get_tree().root.add_child.call_deferred(t)


func _build() -> void:
	var clear := ColorRect.new()
	clear.color = BG_COLOR
	clear.set_anchors_preset(Control.PRESET_FULL_RECT)
	clear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clear)
	_bg = TextureRect.new()
	_bg.texture = Atmosphere.dither_edges(load("res://assets/ui/menu_bg.png"), 20)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	# Fog bands: far (slow, faint) and near (faster, denser) = parallax depth.
	var fog_far := Atmosphere.ScrollLayer.new(Atmosphere.fog_texture(256, 48, 7, 0.55, Color(0.62, 0.64, 0.70, 0.30)), 3.0)
	fog_far.bob = 2.0
	var fog_near := Atmosphere.ScrollLayer.new(Atmosphere.fog_texture(320, 64, 21, 0.6, Color(0.70, 0.71, 0.76, 0.36)), -7.0)
	fog_near.bob = 3.0
	_fog = [fog_far, fog_near]
	for f in _fog:
		add_child(f)
	# Dark dithered shade behind the menu column (readability), left side.
	_shade = TextureRect.new()
	_shade.texture = Atmosphere.dither_gradient(160, 8, Color(0.03, 0.03, 0.04, 0.55), true)
	_shade.flip_h = true
	_shade.stretch_mode = TextureRect.STRETCH_TILE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_motes = Atmosphere.motes(Rect2(0, 0, 480, 270), 22, Color(0.92, 0.80, 0.55, 0.8))
	add_child(_motes)

	_ring = TextureRect.new()
	_ring.texture = load("res://assets/ui/logo_ring.png")
	_ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring.size = Vector2(70, 70)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/ui/logo_asthya.png")
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.size = _logo.texture.get_size() * 2
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)
	_subtitle = Label.new()
	_subtitle.text = Loc.t("menu.subtitle")  # optional: empty string hides it
	_subtitle.add_theme_color_override("font_color", Color(UITheme.TEXT, 0.8))
	_subtitle.add_theme_font_size_override("font_size", UITheme.small_font_size())
	add_child(_subtitle)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 1)
	add_child(_menu)
	var has_save := SaveSystem.latest_valid_slot() != ""
	_add("continue", "menu.continue", _on_continue).disabled = not has_save
	_add("new_game", "menu.new_game", _on_new_game)
	_add("load", "menu.load", _on_load).disabled = not has_save
	_add("settings", "menu.settings", _on_settings)
	if not Settings.is_mobile():
		_add("quit", "menu.quit", _on_quit)
	_cursor = MenuKit.cursor()
	add_child(_cursor)

	var version := Label.new()
	version.name = "Version"
	version.text = "v" + _version()
	version.add_theme_font_size_override("font_size", 8)
	version.add_theme_color_override("font_color", Color(UITheme.TEXT, 0.35))
	add_child(version)


func _add(id: String, key: String, cb: Callable) -> Button:
	var b := MenuKit.menu_button(Loc.t(key), get_viewport())
	b.custom_minimum_size.x = 150
	b.pressed.connect(func() -> void:
		if not _overlay_open and not SceneFade.is_busy():
			cb.call())
	_menu.add_child(b)
	buttons[id] = b
	return b


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var safe := SafeArea.viewport_rect(get_viewport())

	var bg_size := _bg.texture.get_size()
	_bg.size = bg_size
	_bg.position = ((vp - bg_size) / 2.0).round()
	_fog[0].position = Vector2(0, roundf(vp.y * 0.36))
	_fog[0].size = Vector2(vp.x, 48)
	_fog[1].position = Vector2(0, roundf(vp.y - 70))
	_fog[1].size = Vector2(vp.x, 64)
	_shade.position = Vector2(0, 0)
	_shade.size = Vector2(minf(vp.x * 0.5, 230), vp.y)
	_motes.position = vp / 2.0
	_motes.emission_rect_extents = vp / 2.0
	var left := safe.position.x + 22.0
	var top := safe.position.y + maxf(12.0, vp.y * 0.07)
	_logo.position = Vector2(left, top).round()
	_ring.position = (_logo.position + _logo.size / 2.0 - _ring.size / 2.0).round()
	_subtitle.position = Vector2(left + 2, _logo.position.y + _logo.size.y + 3).round()
	_menu.reset_size()
	_menu.position = Vector2(left - 6, maxf(_subtitle.position.y + 22, safe.end.y - _menu.size.y - 18)).round()
	var version := get_node("Version") as Label
	version.reset_size()
	version.position = Vector2(safe.end.x - version.size.x - 4, safe.end.y - version.size.y - 2).round()


func _intro_animation() -> void:
	for n in [_logo, _ring, _subtitle, _menu]:
		n.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(_logo, "modulate:a", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_ring, "modulate:a", 0.45, 2.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.8)
	tw.tween_property(_menu, "modulate:a", 1.0, 0.5)
	tw.tween_callback(_focus_first)
	# Keyboard / gamepad users can act immediately; the fade is only visual.
	_focus_first.call_deferred()


func _focus_first() -> void:
	if _overlay_open:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f and is_ancestor_of(f):
		return
	for b in _menu.get_children():
		if not b.disabled and b.visible:
			b.grab_focus()
			return


func _process(delta: float) -> void:
	_t += delta
	# Slow parallax: the illustration drifts a few pixels, the fog faster.
	var vp := get_viewport().get_visible_rect().size
	var base := ((vp - _bg.size) / 2.0).round()
	_bg.position = base + Vector2(roundf(sin(_t * 0.11) * 4.0), roundf(sin(_t * 0.07) * 1.0))
	if _ring.modulate.a > 0.0 and _logo.modulate.a >= 1.0:
		_ring.modulate.a = 0.35 + 0.12 * sin(_t * 0.8)
	if _cursor:
		MenuKit.place_cursor(_cursor, _menu)


# ----------------------------------------------------------------- actions
func _on_continue() -> void:
	var slot := SaveSystem.latest_valid_slot()
	if slot != "":
		_load_and_play(slot)


func _on_new_game() -> void:
	if SaveSystem.load_slot("auto").error != "missing":
		var d: ConfirmDialog = _open(ConfirmDialog.ask(self, Loc.t("menu.confirm_new.text")))
		if not await d.answered:
			return
	GameState.new_game()
	Audio.ambience("", 1.0)
	SceneFade.go(get_tree(), CINEMATIC_SCENE, 0.9, 0.2)


func _on_load() -> void:
	var p: SaveSlotsPanel = _open(SaveSlotsPanel.open(self, SaveSlotsPanel.Mode.LOAD))
	p.slot_chosen.connect(func(slot: String) -> void:
		p.close()
		_load_and_play(slot))


func _on_settings() -> void:
	_open(_add_overlay(SettingsPanel.new()))


func _on_quit() -> void:
	var d: ConfirmDialog = _open(ConfirmDialog.ask(self, Loc.t("menu.confirm_quit.text")))
	if await d.answered:
		get_tree().quit()


func _load_and_play(slot: String) -> void:
	var r := SaveSystem.load_slot(slot)
	if not r.ok:
		_open(ConfirmDialog.ask(self, Loc.t("slots.load_failed", {"error": r.error}), Loc.t("common.ok"), "", true))
		return
	GameState.apply_dict(r.data)
	Audio.ambience("", 0.8)
	SceneFade.go(get_tree(), WORLD_SCENE, 0.6, 0.6)


func _add_overlay(c: Control) -> Control:
	add_child(c)
	return c


## Tracks an overlay (dialog / panel) so the menu ignores clicks underneath and
## gets focus back when it closes.
func _open(c: Control) -> Control:
	_overlay_open = true
	var back_to := get_viewport().gui_get_focus_owner()
	c.tree_exited.connect(func() -> void:
		_overlay_open = get_children().any(func(n: Node) -> bool:
			return (n is ConfirmDialog or n is SettingsPanel or n is SaveSlotsPanel) and not n.is_queued_for_deletion())
		if not _overlay_open and is_inside_tree():
			_refresh_buttons()
			if is_instance_valid(back_to) and back_to is Button and not back_to.disabled:
				back_to.grab_focus.call_deferred()
			else:
				_focus_first.call_deferred())
	return c


func _refresh_buttons() -> void:
	var has_save := SaveSystem.latest_valid_slot() != ""
	buttons.continue.disabled = not has_save
	buttons.load.disabled = not has_save
	for id in buttons:
		buttons[id].text = Loc.t("menu." + id)


func _notification(what: int) -> void:
	MenuKit.forward_back_button(what)


## Escape / Android back on the bare menu: offer to leave the game (the
## reliable way out on Android, where there is no "Quitter" entry).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _overlay_open and not SceneFade.is_busy():
		get_viewport().set_input_as_handled()
		_on_quit()


func _version() -> String:
	var v := str(Engine.get_meta(&"content_version", ""))
	if v == "":
		var info = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
		v = str(info.get("version", "?")) if info is Dictionary else "?"
	return v
