class_name UITheme
extends RefCounted
## Pixel-art theme (dark fantasy + warm gold) shared by dialogue and shop UIs.
## Frames are 9-slice textures from assets/ui (tools/ui/make_ui_art.py),
## drawn with nearest filtering; the font has antialiasing disabled.

const GOLD := Color(0.96, 0.78, 0.40)
const TEXT := Color(0.96, 0.92, 0.82)
const MUTED := Color(0.70, 0.64, 0.56)
const BAD := Color(0.95, 0.45, 0.38)
const GOOD := Color(0.62, 0.90, 0.50)

const FONT_SIZE := 10
const SMALL_FONT_SIZE := 8

static var _theme: Theme


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
	t.default_font_size = FONT_SIZE
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
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 6)
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("panel", "ScrollContainer", empty)
	t.set_stylebox("focus", "ScrollContainer", empty)
	return t
