class_name DialogueUI
extends CanvasLayer
## JRPG dialogue window: framed portrait on the left, gold speaker name, text
## revealed progressively, choices in a panel above the box on the right.
##
## Pure view: it displays DialogueManager steps and forwards the player's
## input (confirm / choose / cancel) back to the manager.
##   Confirm : Enter / Space / E, click or tap on the box. While text is
##             typing it completes the line; otherwise it advances.
##   Choices : arrows + Enter, mouse click, tap (touch-sized rows).
##   Cancel  : Escape (picks the dialogue's "cancel" choice, or closes).
## Double confirmations are filtered (grace period after opening, minimum
## delay between inputs, choices armed shortly after they appear).

signal opened
signal closed

## Typewriter speed (characters per second).
@export var chars_per_second := 45.0
## Extra pause after . ! ? (seconds).
@export var punctuation_pause := 0.12
## Minimum time between two accepted confirm inputs.
@export var input_cooldown := 0.18
## Inputs ignored right after the window opens (the key that opened it).
@export var open_grace := 0.25
## Delay before freshly shown choices accept input.
@export var choice_arm_delay := 0.2

const BOX_HEIGHT := 88
## Portraits are 128 px pixel art shown 1:1 as a bust standing on the box's
## left edge (it rises above the box), never resampled.
const PORTRAIT := 128
const MARGIN := 6

var manager: DialogueManager
var is_open := false
var is_typing := false

var _root: Control
var _box: PanelContainer
var _portrait_holder: Control
var _text_spacer: Control
var _portrait: TextureRect
var _name: Label
var _text: Label
var _arrow: TextureRect
var _choices_panel: PanelContainer
var _choices_box: VBoxContainer
var _cursor: TextureRect
var _shown := 0.0
var _pause := 0.0
var _step := {}
var _last_input_ms := -100000
var _opened_ms := 0
var _choices_armed_ms := 0
var _tween: Tween
var _arrow_t := 0.0


func _init() -> void:
	layer = 30
	visible = false
	_build()


func bind(m: DialogueManager) -> void:
	manager = m
	manager.step_shown.connect(_on_step)
	manager.ended.connect(func(_id: String, _r: String) -> void: close())


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)


# ----------------------------------------------------------------- building
func _build() -> void:
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.gui_input.connect(_on_box_input)
	_root.add_child(_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(row)

	_text_spacer = Control.new()
	_text_spacer.custom_minimum_size = Vector2(PORTRAIT + 6, 0)
	_text_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text_spacer)
	_portrait_holder = Control.new()
	_portrait_holder.size = Vector2(PORTRAIT + 8, PORTRAIT + 8)
	_portrait_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_portrait_holder)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.position = Vector2(4, 4)
	bg.size = Vector2(PORTRAIT, PORTRAIT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_holder.add_child(bg)
	_portrait = TextureRect.new()
	_portrait.position = Vector2(4, 4)
	_portrait.size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_holder.add_child(_portrait)
	var frame := NinePatchRect.new()
	frame.texture = load("res://assets/ui/portrait_frame.png")
	frame.patch_margin_left = 8
	frame.patch_margin_top = 8
	frame.patch_margin_right = 8
	frame.patch_margin_bottom = 8
	frame.size = Vector2(PORTRAIT + 8, PORTRAIT + 8)
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_holder.add_child(frame)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_name = Label.new()
	_name.add_theme_color_override("font_color", UITheme.GOLD)
	_name.add_theme_font_size_override("font_size", 11)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_text)

	_arrow = TextureRect.new()
	_arrow.texture = load("res://assets/ui/next_arrow.png")
	_arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.visible = false
	_root.add_child(_arrow)

	_choices_panel = PanelContainer.new()
	_choices_panel.visible = false
	_root.add_child(_choices_panel)
	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 3)
	_choices_panel.add_child(_choices_box)
	_cursor = TextureRect.new()
	_cursor.texture = load("res://assets/ui/cursor.png")
	_cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	_cursor.z_index = 1
	_root.add_child(_cursor)


func _layout() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var safe := SafeArea.viewport_rect(vp)
	_root.size = vp.get_visible_rect().size
	_box.position = Vector2(safe.position.x + MARGIN, safe.end.y - MARGIN - BOX_HEIGHT).round()
	_box.size = Vector2(safe.size.x - 2 * MARGIN, BOX_HEIGHT).round()
	_arrow.position = _box.position + _box.size - Vector2(18, 14)
	# Bust: bottom of the frame sits on the box's bottom border, left-aligned.
	_portrait_holder.position = Vector2(_box.position.x + 2, _box.position.y + _box.size.y - PORTRAIT - 8 - 2).round()
	if _choices_panel.visible:
		_layout_choices()


func _choice_row_height() -> float:
	# ~7 mm on a phone, never tiny on desktop.
	return SafeArea.mm_to_px(get_viewport(), 7.0, 18.0, 30.0)


func _layout_choices() -> void:
	var w := 0.0
	var font := UITheme.get_theme().default_font if UITheme.get_theme().default_font else ThemeDB.fallback_font
	for b in _choices_box.get_children():
		w = maxf(w, font.get_string_size((b as Button).text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.font_size()).x)
	w = clampf(w + 40, 120, _box.size.x * 0.6)
	var h := _choices_box.get_child_count() * (_choice_row_height() + 3) - 3 + 16
	_choices_panel.size = Vector2(w, h).round()
	_choices_panel.position = Vector2(_box.position.x + _box.size.x - w, _box.position.y - 4 - h).round()
	_update_cursor()


## Viewport area left free for the game world while the window is open
## (above the box, left of the choices column). Used to frame the camera.
func free_rect() -> Rect2:
	var safe := SafeArea.viewport_rect(get_viewport())
	var right := _box.position.x + _box.size.x - 200.0
	var left := safe.position.x
	if _portrait_holder.visible:
		left = _portrait_holder.position.x + _portrait_holder.size.x
	return Rect2(left, safe.position.y,
		maxf(80.0, right - left), maxf(60.0, _box.position.y - safe.position.y - 4))


## Screen rects covered by the window (for tests / overlap checks).
func covered_rects() -> Array[Rect2]:
	var out: Array[Rect2] = [Rect2(_box.position, _box.size)]
	if _portrait_holder.visible:
		out.append(Rect2(_portrait_holder.position, _portrait_holder.size))
	if _choices_panel.visible:
		out.append(Rect2(_choices_panel.position, _choices_panel.size))
	return out


# ------------------------------------------------------------- open / close
func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_layout()
	_opened_ms = Time.get_ticks_msec()
	if _tween:
		_tween.kill()
	_box.modulate.a = 0.0
	var target_y := _box.position.y
	_box.position.y += 12
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_box, "modulate:a", 1.0, 0.18)
	_portrait_holder.modulate.a = 0.0
	_tween.tween_property(_portrait_holder, "modulate:a", 1.0, 0.25)
	_tween.tween_property(_box, "position:y", target_y, 0.18)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	is_typing = false
	_choices_panel.visible = false
	_cursor.visible = false
	_arrow.visible = false
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(_box, "modulate:a", 0.0, 0.14)
	_tween.tween_property(_portrait_holder, "modulate:a", 0.0, 0.14)
	_tween.tween_property(_box, "position:y", _box.position.y + 12, 0.14)
	_tween.chain().tween_callback(func() -> void:
		visible = false
		closed.emit())


# -------------------------------------------------------------------- steps
func _on_step(step: Dictionary) -> void:
	open()
	_step = step
	_name.text = str(step.get("name", ""))
	_name.add_theme_color_override("font_color", UITheme.SILVER if step.get("speaker", "") == "player" else UITheme.GOLD)
	var tex: Texture2D = step.get("portrait")
	_portrait.texture = tex
	_portrait_holder.visible = tex != null
	_text_spacer.visible = tex != null
	chars_per_second = Settings.text_cps()
	_text.text = str(step.get("text", ""))
	_shown = 0.0
	_pause = float(step.get("pause", 0.0))
	_text.visible_characters = 0
	is_typing = _text.get_total_character_count() > 0
	_arrow.visible = false
	_hide_choices()
	if not is_typing:
		_on_typing_done()


func _process(delta: float) -> void:
	if not is_open:
		return
	if is_typing:
		if _pause > 0.0:
			_pause -= delta
		else:
			var before := int(_shown)
			_shown += chars_per_second * delta
			var total := _text.get_total_character_count()
			var n := mini(int(_shown), total)
			_text.visible_characters = n
			if n > before and n < total and _text.text[n - 1] in ".!?…":
				_pause = punctuation_pause
			if n >= total:
				finish_typing()
	elif _arrow.visible:
		_arrow_t += delta
		_arrow.position = _box.position + _box.size - Vector2(18, 14) + Vector2(0, roundf(absf(sin(_arrow_t * 5.0)) * 2.0))


## Shows the whole current line at once.
func finish_typing() -> void:
	if not is_typing:
		return
	is_typing = false
	_text.visible_characters = -1
	_on_typing_done()


func _on_typing_done() -> void:
	var choices: Array = _step.get("choices", [])
	if choices.is_empty():
		_arrow.visible = true
		_arrow_t = 0.0
	else:
		_show_choices(choices)


func _show_choices(choices: Array) -> void:
	for c in _choices_box.get_children():
		c.queue_free()
		_choices_box.remove_child(c)
	var h := _choice_row_height()
	for c in choices:
		var b := Button.new()
		b.text = str(c.text)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = &"ChoiceButton"  # wider left margin for the cursor
		b.custom_minimum_size = Vector2(0, h)
		var idx := int(c.index)
		b.pressed.connect(func() -> void: _on_choice(idx))
		b.focus_entered.connect(_update_cursor)
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		_choices_box.add_child(b)
	_choices_panel.visible = true
	_choices_panel.modulate.a = 0.0
	_layout_choices()
	create_tween().tween_property(_choices_panel, "modulate:a", 1.0, 0.12)
	_choices_armed_ms = Time.get_ticks_msec() + int(choice_arm_delay * 1000)
	# Deferred: steps can arrive from inside a choice button's press handler.
	(_choices_box.get_child(0) as Button).grab_focus.call_deferred()
	_update_cursor.call_deferred()


func _hide_choices() -> void:
	_choices_panel.visible = false
	_cursor.visible = false
	for c in _choices_box.get_children():
		c.queue_free()
		_choices_box.remove_child(c)


func _update_cursor() -> void:
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() else null
	if not _choices_panel.visible or focused == null or focused.get_parent() != _choices_box:
		_cursor.visible = false
		return
	_cursor.visible = true
	_cursor.position = (focused.global_position + Vector2(5, (focused.size.y - 9) / 2.0)).round()


func choice_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for b in _choices_box.get_children():
		out.append(b as Button)
	return out


# -------------------------------------------------------------------- input
func _accepting_input() -> bool:
	var now := Time.get_ticks_msec()
	if now - _opened_ms < int(open_grace * 1000) or now - _last_input_ms < int(input_cooldown * 1000):
		return false
	_last_input_ms = now
	return true


## Confirm button / tap on the box.
func confirm() -> void:
	if not is_open or not _accepting_input():
		return
	if is_typing:
		finish_typing()
	elif _choices_panel.visible:
		var focused := get_viewport().gui_get_focus_owner()
		if focused and focused.get_parent() == _choices_box and Time.get_ticks_msec() >= _choices_armed_ms:
			_choose_button(focused as Button)
	elif manager:
		manager.confirm()


func _on_choice(index: int) -> void:
	if Time.get_ticks_msec() < _choices_armed_ms:
		return
	var now := Time.get_ticks_msec()
	if now - _last_input_ms < int(input_cooldown * 1000) and _last_input_ms > _choices_armed_ms:
		return
	_last_input_ms = now
	_hide_choices()
	manager.choose(index)


func _choose_button(b: Button) -> void:
	var i := choice_buttons().find(b)
	if i >= 0:
		_last_input_ms = 0  # allow _on_choice through
		_choices_armed_ms = 0
		_on_choice(i)


func _on_box_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"ui_cancel"):
		if _accepting_input() and manager:
			_hide_choices()
			manager.cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		confirm()
		get_viewport().set_input_as_handled()
