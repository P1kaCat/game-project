class_name MobileHUD
extends CanvasLayer
## Touch HUD: joystick bottom-left, action (A) and sprint (>>) buttons bottom-right.
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
## Hold to sprint (drives the "run" action, same as Shift on PC).
@onready var sprint_button: TouchActionButton = $Root/SprintButton

var safe_rect := Rect2()  # in viewport coordinates, for tests/debug


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	GameInput.touch_ui_changed.connect(_on_touch_ui_changed)
	_on_touch_ui_changed(GameInput.touch_ui_enabled)


## Hidden while dialogue / shop windows are open (movement is locked anyway).
var suppressed := false:
	set(v):
		suppressed = v
		_on_touch_ui_changed(GameInput.touch_ui_enabled)


func _on_touch_ui_changed(enabled: bool) -> void:
	visible = enabled and not suppressed
	if enabled:
		_layout.call_deferred()
	else:
		GameInput.reset_virtual()


## Window-pixels-per-viewport-pixel and letterbox offset of the stretched root.
func _stretch() -> Array:
	var s := SafeArea.pixel_scale(get_viewport())
	var win := Vector2(DisplayServer.window_get_size())
	return [s, (win - get_viewport().get_visible_rect().size * s) / 2.0]


func _compute_safe_rect() -> Rect2:
	return SafeArea.viewport_rect(get_viewport())


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

	# Sprint: up-left of A, on the arc a right thumb sweeps naturally.
	sprint_button.radius = action_button.radius
	var s_center := b_center + Vector2(-b * 2.3, -b * 0.9)
	sprint_button.position = (s_center - sprint_button.size / 2.0).round()
