class_name SkipHint
extends Control
## "Maintenir pour passer" with a pixel ring that fills while held.

var progress := 0.0:
	set(v):
		if v != progress:
			progress = v
			queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_default_font()
	var text := Loc.t("cinematic.hold_to_skip")
	var fs := UITheme.small_font_size()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := Vector2(size.x - 7, 8)
	draw_string(font, Vector2(size.x - 16 - w, 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.TEXT, 0.8))
	for i in 24:
		var a := -PI / 2.0 + TAU * i / 24.0
		var p := (c + Vector2(cos(a), sin(a)) * 5.0).round()
		var on := float(i) / 24.0 < progress
		draw_rect(Rect2(p, Vector2.ONE), UITheme.GOLD if on else Color(UITheme.SILVER, 0.35))
