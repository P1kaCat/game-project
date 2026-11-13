class_name MenuKit
extends RefCounted
## Small builders for the Asthya menus (main menu, pause, settings, saves).


## Touch-friendly row height: ~7 mm on phones, compact on desktop.
static func row_height(vp: Viewport) -> float:
	return SafeArea.mm_to_px(vp, 6.5, 17.0, 28.0)


static func menu_button(text: String, vp: Viewport = null) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"MenuEntry"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	if vp:
		b.custom_minimum_size.y = row_height(vp)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", -8.0))
	b.pressed.connect(func() -> void: Audio.sfx("ui_confirm", -4.0))
	return b


static func title(text: String, size := UITheme.TITLE_FONT_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UITheme.GOLD)
	l.add_theme_font_size_override("font_size", size)
	return l


static func dimmer(alpha := 0.6) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.02, 0.03, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## Brass cursor that follows the focused button of `container`.
static func cursor() -> TextureRect:
	var c := TextureRect.new()
	c.texture = load("res://assets/ui/cursor.png")
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.z_index = 2
	return c


static func place_cursor(c: TextureRect, owner: Control) -> void:
	var f := owner.get_viewport().gui_get_focus_owner()
	if f == null or not owner.is_ancestor_of(f) or not f is Button or f.theme_type_variation != &"MenuEntry":
		c.visible = false
		return
	c.visible = true
	c.global_position = (f.global_position + Vector2(6, (f.size.y - 9) / 2.0)).round()


## Android back button -> a regular ui_cancel press, so whichever window is on
## top (dialog, settings, pause...) handles it like Escape. Call from the
## scene root's _notification.
static func forward_back_button(what: int) -> void:
	if what == Node.NOTIFICATION_WM_GO_BACK_REQUEST:
		var e := InputEventAction.new()
		e.action = &"ui_cancel"
		e.pressed = true
		Input.parse_input_event(e)
		var r := InputEventAction.new()
		r.action = &"ui_cancel"
		r.pressed = false
		Input.parse_input_event.call_deferred(r)
