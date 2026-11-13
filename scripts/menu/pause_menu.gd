class_name PauseMenu
extends CanvasLayer
## In-game pause: Escape / gamepad Start / Android back / the touch pause
## button (top-left, shown with the touch controls). Pauses the tree.
##   Reprendre · Sauvegarder (slots 1-3) · Paramètres · Menu principal
## Not available while a conversation, the shop or a story sequence runs
## (`can_open` callable decides).

signal opened
signal closed

const MAIN_MENU := "res://scenes/main_menu.tscn"

## Returns true when the game may be paused now.
var can_open: Callable = func() -> bool: return true
## Called before saving so the world can copy live state into GameState.
var before_save: Callable = func() -> void: pass

var is_open := false
var buttons := {}
var _root: Control
var _panel: PanelContainer
var _col: VBoxContainer
var _cursor: TextureRect
var _touch_button: Button
var _toast: Label


func _init() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_touch_button = Button.new()
	_touch_button.text = "II"
	_touch_button.focus_mode = Control.FOCUS_NONE
	_touch_button.pressed.connect(open)
	_root.add_child(_touch_button)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 8)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	GameInput.touch_ui_changed.connect(func(_e: bool) -> void: _layout())
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var safe := SafeArea.viewport_rect(get_viewport())
	var s := MenuKit.row_height(get_viewport())
	_touch_button.visible = GameInput.touch_ui_enabled and not is_open
	_touch_button.size = Vector2(s + 4, s)
	_touch_button.position = (safe.position + Vector2(6, 6)).round()
	_toast.reset_size()
	_toast.position = Vector2(safe.end.x - _toast.size.x - 6, safe.end.y - _toast.size.y - 4).round()
	if _panel:
		_panel.reset_size()
		_panel.position = (safe.get_center() - _panel.size / 2.0).round()


func open() -> void:
	if is_open or not can_open.call() or SceneFade.is_busy():
		return
	is_open = true
	get_tree().paused = true
	GameInput.reset_virtual()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := MenuKit.dimmer(0.55)
	dim.name = "Dim"
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_root.add_child(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 1)
	_panel.add_child(_col)
	_col.add_child(MenuKit.title(Loc.t("pause.title")))
	_col.add_child(HSeparator.new())
	_add("resume", "pause.resume", close)
	_add("save", "pause.save", _on_save)
	_add("settings", "pause.settings", _on_settings)
	_add("main_menu", "pause.main_menu", _on_main_menu)
	_cursor = MenuKit.cursor()
	_root.add_child(_cursor)
	_layout()
	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, 0.12)
	buttons.resume.grab_focus.call_deferred()
	Audio.sfx("ui_open", -6.0)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	for n in [_root.get_node_or_null("Dim"), _panel, _cursor]:
		if n:
			n.queue_free()
	_panel = null
	_cursor = null
	buttons.clear()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	_layout()
	closed.emit()


func _add(id: String, key: String, cb: Callable) -> void:
	var b := MenuKit.menu_button(Loc.t(key), get_viewport())
	b.custom_minimum_size.x = 150
	b.pressed.connect(func() -> void:
		if not _has_overlay():
			cb.call())
	_col.add_child(b)
	buttons[id] = b


func _process(_d: float) -> void:
	if _cursor and is_instance_valid(_cursor):
		MenuKit.place_cursor(_cursor, _col)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START):
		if is_open:
			if not _has_overlay():
				get_viewport().set_input_as_handled()
				Audio.sfx("ui_back", -4.0)
				close()
		elif can_open.call():
			get_viewport().set_input_as_handled()
			open()


func _has_overlay() -> bool:
	return _root.get_children().any(func(n: Node) -> bool:
		return (n is ConfirmDialog or n is SettingsPanel or n is SaveSlotsPanel) and not n.is_queued_for_deletion())


func _refocus(id: String) -> void:
	if is_open and buttons.has(id):
		buttons[id].grab_focus()


func _on_save() -> void:
	var p := SaveSlotsPanel.open(_root, SaveSlotsPanel.Mode.SAVE)
	p.slot_chosen.connect(func(slot: String) -> void:
		before_save.call()
		var ok := SaveSystem.save_slot(slot, GameState.to_dict()) == OK
		p.close()
		show_toast(Loc.t("slots.saved" if ok else "slots.save_failed")))
	p.closed.connect(_refocus.bind("save"))


func _on_settings() -> void:
	var p := SettingsPanel.new()
	_root.add_child(p)
	p.closed.connect(func() -> void:
		for id in buttons:
			buttons[id].text = Loc.t("pause." + id)
		_refocus("settings"))


func _on_main_menu() -> void:
	var d := ConfirmDialog.ask(_root, Loc.t("pause.confirm_menu"))
	if await d.answered:
		Audio.ambience("", 0.6)
		SceneFade.go(get_tree(), MAIN_MENU, 0.5, 0.5)
	else:
		_refocus("main_menu")


## Small bottom-right message ("Partie sauvegardée.", "Sauvegarde automatique…").
func show_toast(text: String) -> void:
	_toast.text = text
	_layout()
	var tw := create_tween()
	tw.tween_property(_toast, "modulate:a", 0.85, 0.2)
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
