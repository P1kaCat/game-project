class_name UITheme
extends RefCounted
## Asthya pixel-art design system shared by every UI (menus, dialogue, shop,
## settings, saves): dark charcoal panels, aged ivory text, tarnished silver
## borders, muted brass highlights. Frames are 9-slice textures from assets/ui
## (tools/ui/make_ui_art.py), drawn with nearest filtering; the font has
## antialiasing disabled.

const GOLD := Color(0.86, 0.72, 0.45)     # muted brass (titles, prices, highlights)
const BRASS := GOLD
const TEXT := Color(0.91, 0.87, 0.77)     # aged ivory
const MUTED := Color(0.60, 0.58, 0.55)    # faded ink
const SILVER := Color(0.76, 0.77, 0.80)
const BAD := Color(0.86, 0.42, 0.36)
const GOOD := Color(0.60, 0.80, 0.52)
const SHADOW := Color(0.02, 0.02, 0.04, 0.85)

const FONT_SIZE := 10
const SMALL_FONT_SIZE := 8
const TITLE_FONT_SIZE := 12

## 1.0 normal, 1.25 large (Settings > Affichage > Taille de l'interface).
static var ui_scale := 1.0
static var _theme: Theme


static func font_size() -> int:
	return roundi(FONT_SIZE * ui_scale)


static func small_font_size() -> int:
	return roundi(SMALL_FONT_SIZE * ui_scale)


## Changes text size everywhere the shared theme is used (live).
static func set_ui_scale(s: float) -> void:
	ui_scale = s
	if _theme:
		_theme.default_font_size = font_size()


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func frame(path: String, margin: int, content: Vector4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(path)
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content.x
	sb.content_margin_top = content.y
	sb.content_margin_right = content.z
	sb.content_margin_bottom = content.w
	return sb


static func panel_style() -> StyleBoxTexture:
	return frame("res://assets/ui/panel.png", 8, Vector4(10, 8, 10, 8))


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = font_size()
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var pad := Vector4(8, 3, 8, 3)
	t.set_stylebox("normal", "Button", frame("res://assets/ui/button.png", 5, pad))
	t.set_stylebox("hover", "Button", frame("res://assets/ui/button_hover.png", 5, pad))
	t.set_stylebox("focus", "Button", frame("res://assets/ui/button_hover.png", 5, pad))
	t.set_stylebox("pressed", "Button", frame("res://assets/ui/button_pressed.png", 5, pad))
	t.set_stylebox("hover_pressed", "Button", frame("res://assets/ui/button_pressed.png", 5, pad))
	t.set_stylebox("disabled", "Button", frame("res://assets/ui/button_disabled.png", 5, pad))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED)
	# Dialogue choices: same look, room on the left for the gold cursor.
	t.set_type_variation(&"ChoiceButton", &"Button")
	var cpad := Vector4(16, 3, 8, 3)
	t.set_stylebox("normal", "ChoiceButton", frame("res://assets/ui/button.png", 5, cpad))
	t.set_stylebox("hover", "ChoiceButton", frame("res://assets/ui/button_hover.png", 5, cpad))
	t.set_stylebox("focus", "ChoiceButton", frame("res://assets/ui/button_hover.png", 5, cpad))
	t.set_stylebox("pressed", "ChoiceButton", frame("res://assets/ui/button_pressed.png", 5, cpad))
	t.set_stylebox("hover_pressed", "ChoiceButton", frame("res://assets/ui/button_pressed.png", 5, cpad))
	t.set_color("font_color", "Label", TEXT)
	# Menu buttons: wider padding, text left-aligned next to the brass cursor.
	t.set_type_variation(&"MenuEntry", &"Button")
	var mpad := Vector4(18, 4, 12, 4)
	t.set_stylebox("normal", "MenuEntry", StyleBoxEmpty.new())
	t.set_stylebox("hover", "MenuEntry", frame("res://assets/ui/button_hover.png", 5, mpad))
	t.set_stylebox("focus", "MenuEntry", frame("res://assets/ui/button_hover.png", 5, mpad))
	t.set_stylebox("pressed", "MenuEntry", frame("res://assets/ui/button_pressed.png", 5, mpad))
	t.set_stylebox("hover_pressed", "MenuEntry", frame("res://assets/ui/button_pressed.png", 5, mpad))
	t.set_stylebox("disabled", "MenuEntry", StyleBoxEmpty.new())
	for st in ["normal", "disabled"]:
		var sb: StyleBox = t.get_stylebox(st, "MenuEntry")
		sb.content_margin_left = mpad.x
		sb.content_margin_top = mpad.y
		sb.content_margin_right = mpad.z
		sb.content_margin_bottom = mpad.w
	t.set_color("font_color", "MenuEntry", TEXT)
	t.set_color("font_hover_color", "MenuEntry", GOLD)
	t.set_color("font_focus_color", "MenuEntry", GOLD)
	t.set_color("font_disabled_color", "MenuEntry", Color(MUTED, 0.55))
	t.set_color("font_outline_color", "MenuEntry", SHADOW)
	t.set_constant("outline_size", "MenuEntry", 2)
	t.set_color("font_outline_color", "Label", SHADOW)
	# Small icon buttons (arrows of selector rows): no frame, brass when focused.
	t.set_type_variation(&"IconButton", &"Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 2
		e.content_margin_right = 2
		t.set_stylebox(st, "IconButton", e)
	t.set_stylebox("focus", "IconButton", StyleBoxEmpty.new())
	# Volume / size sliders.
	t.set_icon("grabber", "HSlider", _slider_grabber(false))
	t.set_icon("grabber_highlight", "HSlider", _slider_grabber(true))
	var track := frame("res://assets/ui/bar_bg.png", 2, Vector4(0, 2, 0, 2))
	t.set_stylebox("slider", "HSlider", track)
	var fill := frame("res://assets/ui/bar_fill.png", 2, Vector4(0, 2, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	# Section dividers.
	var sep := StyleBoxTexture.new()
	sep.texture = load("res://assets/ui/divider.png")
	sep.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sep.content_margin_top = 1
	sep.content_margin_bottom = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 5)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", empty)
	t.set_stylebox("focus", "ScrollContainer", empty)
	return t


## 5x9 silver (or brass when focused) grabber, drawn pixel by pixel.
static func _slider_grabber(hot: bool) -> Texture2D:
	var img := Image.create(5, 9, false, Image.FORMAT_RGBA8)
	var ink := Color(0.04, 0.04, 0.05)
	var hi := Color(0.89, 0.77, 0.50) if hot else Color(0.78, 0.78, 0.80)
	var mid := Color(0.69, 0.56, 0.31) if hot else Color(0.56, 0.56, 0.59)
	for y in 9:
		for x in 5:
			var edge := x == 0 or x == 4 or y == 0 or y == 8
			img.set_pixel(x, y, ink if edge else (hi if x == 1 or y == 1 else mid))
	img.set_pixel(0, 0, Color(0, 0, 0, 0))
	img.set_pixel(4, 0, Color(0, 0, 0, 0))
	img.set_pixel(0, 8, Color(0, 0, 0, 0))
	img.set_pixel(4, 8, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
