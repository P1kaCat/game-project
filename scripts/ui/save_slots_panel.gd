class_name SaveSlotsPanel
extends Control
## Save / load slot picker: automatic save + 3 manual slots. Each slot shows
## its region, play time and gold; unreadable (corrupted) saves are shown as
## such and cannot be loaded. In save mode the automatic slot is not offered
## and overwriting asks for confirmation.

signal slot_chosen(slot: String)
signal closed

enum Mode { LOAD, SAVE }

var mode := Mode.LOAD
var _buttons := {}
var _cursor: TextureRect
var _col: VBoxContainer
var _panel: PanelContainer


static func open(parent: Node, m: Mode) -> SaveSlotsPanel:
	var p := SaveSlotsPanel.new()
	p.mode = m
	parent.add_child(p)
	return p


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	add_child(MenuKit.dimmer(0.65))
	_panel = PanelContainer.new()
	add_child(_panel)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 3)
	_panel.add_child(_col)
	_col.add_child(MenuKit.title(Loc.t("slots.title_load" if mode == Mode.LOAD else "slots.title_save")))
	_col.add_child(HSeparator.new())
	var first: Button
	for slot in SaveSystem.SLOTS:
		if mode == Mode.SAVE and slot == "auto":
			continue
		var b := _slot_button(slot)
		_col.add_child(b)
		_buttons[slot] = b
		if first == null and not b.disabled:
			first = b
	_col.add_child(HSeparator.new())
	var back := MenuKit.menu_button(Loc.t("menu.back"), get_viewport())
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(close)
	_col.add_child(back)
	_cursor = MenuKit.cursor()
	add_child(_cursor)
	get_viewport().size_changed.connect(_layout)
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	(first if first else back).grab_focus.call_deferred()


func _slot_button(slot: String) -> Button:
	var info := SaveSystem.slot_info(slot)
	var name := Loc.t("slots.auto") if slot == "auto" else Loc.t("slots.slot", {"n": slot})
	var detail := Loc.t("slots.empty")
	if info.ok:
		detail = Loc.t("slots.info", {"region": info.region, "time": GameState.format_play_time(info.play_time), "gold": info.gold})
		detail += "  ·  " + Time.get_datetime_string_from_unix_time(int(info.saved_at) + _utc_offset(), true).left(16)
	elif info.exists:
		detail = Loc.t("slots.corrupted")
	var b := MenuKit.menu_button("%s\n%s" % [name, detail], get_viewport())
	b.custom_minimum_size.y = maxf(30.0, MenuKit.row_height(get_viewport()) + 10)
	b.disabled = mode == Mode.LOAD and not info.ok
	b.pressed.connect(_on_slot.bind(slot, info))
	return b


func _on_slot(slot: String, info: Dictionary) -> void:
	if mode == Mode.SAVE and info.exists:
		var d := ConfirmDialog.ask(self, Loc.t("slots.overwrite"))
		if not await d.answered:
			_buttons[slot].grab_focus()
			return
	slot_chosen.emit(slot)


func refresh() -> void:
	for slot in _buttons:
		var old: Button = _buttons[slot]
		var b := _slot_button(slot)
		old.text = b.text
		old.disabled = b.disabled
		b.free()


func _layout() -> void:
	var safe := SafeArea.viewport_rect(get_viewport())
	_panel.size = Vector2(minf(300.0, safe.size.x - 16), 0)
	_panel.reset_size()
	_panel.size.x = minf(300.0, safe.size.x - 16)
	_panel.position = (safe.get_center() - _panel.size / 2.0).round()


func _process(_d: float) -> void:
	MenuKit.place_cursor(_cursor, self)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx("ui_back", -4.0)
		close()


func button_for(slot: String) -> Button:
	return _buttons.get(slot)


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
