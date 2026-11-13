class_name SettingsPanel
extends Control
## "Paramètres" window (main menu and pause menu). Every change applies live
## (Settings.apply) and is written to user://settings.cfg when the window closes.
## Desktop-only options (fullscreen) are not shown on Android / iOS.
##
## Rows: sliders (left/right or drag) and selectors (a button that cycles its
## value: tap/click/Enter = next, left/right = previous/next).

signal closed

var _rows := {}           # key -> Control (for tests)
var _list: VBoxContainer
var _scroll: ScrollContainer
var _back: Button
var _cursor: TextureRect


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_child(MenuKit.dimmer(0.65))
	var panel := PanelContainer.new()
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(MenuKit.title(Loc.t("settings.title")))
	col.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)

	_section("settings.audio")
	_slider("audio/master", "settings.master", 0.0, 1.0, 0.05, _percent)
	_slider("audio/music", "settings.music", 0.0, 1.0, 0.05, _percent)
	_slider("audio/sfx", "settings.sfx", 0.0, 1.0, 0.05, _percent)
	_section("settings.display")
	if not Settings.is_mobile():
		_toggle("display/fullscreen", "settings.fullscreen")
	_selector("display/zoom", "settings.zoom")
	_selector("display/ui_scale", "settings.ui_scale")
	_section("settings.gameplay")
	_selector("gameplay/text_speed", "settings.text_speed")
	_selector("gameplay/camera_smoothing", "settings.camera")
	_section("settings.touch")
	_slider("touch/joystick_size", "settings.joystick_size", 14.0, 26.0, 1.0, func(v: float) -> String: return "%d mm" % v)
	_slider("touch/joystick_opacity", "settings.joystick_opacity", 0.25, 1.0, 0.05, _percent)
	_section("settings.language")
	_language_row()

	col.add_child(HSeparator.new())
	_back = MenuKit.menu_button(Loc.t("menu.back"), get_viewport())
	_back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back.pressed.connect(close)
	col.add_child(_back)
	_cursor = MenuKit.cursor()
	add_child(_cursor)

	get_viewport().size_changed.connect(_layout)
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	_first_focusable().grab_focus.call_deferred()


func _layout() -> void:
	var safe := SafeArea.viewport_rect(get_viewport())
	var panel := get_child(1) as PanelContainer
	var w := minf(330.0, safe.size.x - 16)
	var h := minf(250.0, safe.size.y - 12)
	panel.size = Vector2(w, h)
	panel.position = (safe.get_center() - panel.size / 2.0).round()


func _process(_d: float) -> void:
	if _cursor:
		MenuKit.place_cursor(_cursor, self)


func close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx("ui_back", -4.0)
		close()


# ------------------------------------------------------------------ rows
func _section(key: String) -> void:
	var l := Label.new()
	l.text = Loc.t(key)
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.add_theme_font_size_override("font_size", UITheme.small_font_size())
	if _list.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 3
		_list.add_child(gap)
	_list.add_child(l)


func _row(label_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = MenuKit.row_height(get_viewport())
	var l := Label.new()
	l.text = Loc.t(label_key)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	row.add_child(l)
	_list.add_child(row)
	return row


func _slider(key: String, label_key: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := _row(label_key)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(96, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var val := Label.new()
	val.custom_minimum_size.x = 36
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		_apply_value(key, v))
	s.focus_entered.connect(func() -> void: row.modulate = Color(1.15, 1.08, 0.9))
	s.focus_exited.connect(func() -> void: row.modulate = Color.WHITE)
	row.add_child(s)
	row.add_child(val)
	_rows[key] = s


func _selector(key: String, label_key: String) -> void:
	var options: Array = Settings.CHOICES[key]
	var b := _cycle_button(_row(label_key), options, func(v: String) -> String:
		return Loc.t("%s.%s" % [label_key, v]), str(Settings.get_value(key)), func(v: String) -> void: _apply_value(key, v))
	_rows[key] = b


func _toggle(key: String, label_key: String) -> void:
	var b := _cycle_button(_row(label_key), [false, true], func(v: bool) -> String:
		return Loc.t("settings.on" if v else "settings.off"), Settings.get_value(key), func(v: bool) -> void: _apply_value(key, v))
	_rows[key] = b


func _language_row() -> void:
	var codes := Loc.available_locales()
	var b := _cycle_button(_row("settings.language"), codes, func(v: String) -> String:
		return Loc.t_in(v, "lang.name"), str(Settings.get_value("lang/locale")), func(v: String) -> void: _apply_value("lang/locale", v))
	_rows["lang/locale"] = b


## A selector: "‹ value ›". Click / tap / Enter -> next value; left/right keys cycle.
func _cycle_button(row: HBoxContainer, options: Array, label: Callable, current: Variant, on_change: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(132, 0)
	b.focus_mode = Control.FOCUS_ALL
	var idx := [maxi(0, options.find(current))]
	var refresh := func() -> void:
		b.text = "‹  %s  ›" % label.call(options[idx[0]])
	refresh.call()
	var step := func(d: int) -> void:
		idx[0] = posmod(idx[0] + d, options.size())
		refresh.call()
		Audio.sfx("ui_move", -6.0)
		on_change.call(options[idx[0]])
	b.pressed.connect(step.bind(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed(&"ui_left", true):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed(&"ui_right", true):
			step.call(1)
			b.accept_event())
	b.mouse_entered.connect(b.grab_focus)
	row.add_child(b)
	return b


func _apply_value(key: String, v: Variant) -> void:
	Settings.set_value(key, v)
	Settings.apply()
	get_tree().call_group(&"settings_listeners", &"apply_settings")


func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func _first_focusable() -> Control:
	for row in _list.get_children():
		if row is HBoxContainer:
			return row.get_child(1)
	return _back


## Test helper: the live control of a settings key.
func control_for(key: String) -> Control:
	return _rows.get(key)
