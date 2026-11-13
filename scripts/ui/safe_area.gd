class_name SafeArea
extends RefCounted
## Screen-geometry helpers shared by every HUD/UI layer.

## Display safe area (notches, cutouts, rounded corners) in viewport (canvas)
## coordinates, clipped to the visible rect. Honors the debug option
## `--fake-safe-area=L,T,R,B` (window pixels) for testing on desktop.
static func viewport_rect(viewport: Viewport) -> Rect2:
	var vp_rect := viewport.get_visible_rect()
	var s := pixel_scale(viewport)
	var win := Vector2(DisplayServer.window_get_size())
	var off := (win - vp_rect.size * s) / 2.0
	var safe := Rect2(DisplayServer.get_display_safe_area())
	safe.position -= Vector2(DisplayServer.window_get_position())
	var fake := _fake_insets()
	if fake != Vector4.ZERO:
		safe = Rect2(fake.x, fake.y, win.x - fake.x - fake.z, win.y - fake.y - fake.w)
	var r := Rect2((safe.position - off) / s, safe.size / s).intersection(vp_rect)
	return r if r.has_area() else vp_rect


## Window pixels per viewport pixel (integer with the project's scale mode).
static func pixel_scale(viewport: Viewport) -> float:
	var win := Vector2(DisplayServer.window_get_size())
	var vp := viewport.get_visible_rect().size
	var s := minf(win.x / vp.x, win.y / vp.y)
	if ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer":
		s = maxf(1.0, roundf(s))
	return s


## Viewport pixels that measure `mm` millimetres on the physical screen,
## clamped to [lo, hi] (desktop DPI values are unreliable).
static func mm_to_px(viewport: Viewport, mm: float, lo: float, hi: float) -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	return clampf(roundf(mm / 25.4 * dpi / pixel_scale(viewport)), lo, hi)


static func _fake_insets() -> Vector4:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-safe-area="):
			var p := arg.trim_prefix("--fake-safe-area=").split(",")
			if p.size() == 4:
				return Vector4(p[0].to_float(), p[1].to_float(), p[2].to_float(), p[3].to_float())
	return Vector4.ZERO
