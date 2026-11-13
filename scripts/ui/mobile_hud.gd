class_name MobileHUD
extends CanvasLayer
## Touch HUD: joystick bottom-left, action button bottom-right.
##
## * Shown only when GameInput.touch_ui_enabled (Android/iOS, `--touch-ui`, or
##   after a real touch on a touchscreen PC). Hidden on PC by default.
## * Sized by screen density (aims for a ~18 mm joystick on any phone) and laid
##   out inside the display safe area (notches / cutouts / rounded corners).
## * Controls stay in the corners so the centre of the screen remains clear.
##
## Debug: `--fake-safe-area=L,T,R,B` insets the safe area by window pixels to
## preview cutout handling on desktop.

@export var joystick_diameter_mm := 18.0
@export var margin := 8.0  # viewport pixels inside the safe area

@onready var root: Control = $Root
@onready var joystick: TouchJoystick = $Root/Joystick
@onready var action_button: TouchActionButton = $Root/ActionButton

var safe_rect := Rect2()  # in viewport coordinates, for tests/debug
var _fake_insets := Vector4.ZERO


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fake-safe-area="):
			var p := arg.trim_prefix("--fake-safe-area=").split(",")
			if p.size() == 4:
				_fake_insets = Vector4(p[0].to_float(), p[1].to_float(), p[2].to_float(), p[3].to_float())
	get_viewport().size_changed.connect(_layout)
	GameInput.touch_ui_changed.connect(_on_touch_ui_changed)
	_on_touch_ui_changed(GameInput.touch_ui_enabled)


func _on_touch_ui_changed(enabled: bool) -> void:
	visible = enabled
	if enabled:
		_layout.call_deferred()
	else:
		GameInput.reset_virtual()


## Window-pixels-per-viewport-pixel and letterbox offset of the stretched root.
func _stretch() -> Array:
	var win := Vector2(DisplayServer.window_get_size())
	var vp := get_viewport().get_visible_rect().size
	var s := minf(win.x / vp.x, win.y / vp.y)
	if ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer":
		s = maxf(1.0, roundf(s))
	return [s, (win - vp * s) / 2.0]


func _compute_safe_rect() -> Rect2:
	var vp_rect := get_viewport().get_visible_rect()
	var st := _stretch()
	var s: float = st[0]
	var off: Vector2 = st[1]
	var safe := Rect2(DisplayServer.get_display_safe_area())
	safe.position -= Vector2(DisplayServer.window_get_position())
	if _fake_insets != Vector4.ZERO:
		var win := Vector2(DisplayServer.window_get_size())
		safe = Rect2(_fake_insets.x, _fake_insets.y,
			win.x - _fake_insets.x - _fake_insets.z, win.y - _fake_insets.y - _fake_insets.w)
	var r := Rect2((safe.position - off) / s, safe.size / s)
	r = r.intersection(vp_rect)
	return r if r.has_area() else vp_rect


func _layout() -> void:
	if not visible:
		return
	safe_rect = _compute_safe_rect()
	root.position = Vector2.ZERO
	root.size = get_viewport().get_visible_rect().size

	# Density-aware sizing: physical joystick size -> viewport pixels.
	var s: float = _stretch()[0]
	var dpi := float(DisplayServer.screen_get_dpi())
	var radius_px := (joystick_diameter_mm / 25.4) * dpi * 0.5
	var r := clampf(roundf(radius_px / s), 26.0, 48.0)
	joystick.base_radius = r
	joystick.knob_radius = roundf(r * 0.42)
	action_button.radius = roundf(r * 0.62)

	var j_center := Vector2(safe_rect.position.x + margin + r,
		safe_rect.end.y - margin - r)
	joystick.position = (j_center - joystick.size / 2.0).round()

	var b := action_button.radius
	var b_center := Vector2(safe_rect.end.x - margin - b - r * 0.25,
		safe_rect.end.y - margin - b - r * 0.35)
	action_button.position = (b_center - action_button.size / 2.0).round()
