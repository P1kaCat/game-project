extends Node
## Autoload "GameInput": the single place gameplay code reads player intent from.
##
## Keyboard / gamepad come through the InputMap actions (move_*, run, interact).
## Touch controls do NOT fake those actions (that would release a key the player
## is still holding); they write `virtual_move` / `virtual_run` here instead, and
## the two sources are merged per frame. Adding another source later (remapping,
## replays, network input) only touches this file.

## Joystick deflection (after dead zone) at or above which the player runs.
@export_range(0.5, 1.0) var touch_run_threshold := 0.95

## Analog move vector from the on-screen joystick, length 0..1 (dead zone already
## applied). Screen space: up is -Y, same as the move_up action.
var virtual_move := Vector2.ZERO
## Set by touch UI elements that request running.
var virtual_run := false

## True when the on-screen controls should be shown (mobile, forced, or a real
## touch happened on a touchscreen PC).
var touch_ui_enabled := false:
	set(value):
		if value != touch_ui_enabled:
			touch_ui_enabled = value
			touch_ui_changed.emit(value)

signal touch_ui_changed(enabled: bool)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_ui_enabled = OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios") or "--touch-ui" in OS.get_cmdline_user_args()


func _input(event: InputEvent) -> void:
	# Touchscreen laptops: reveal the touch HUD on the first real touch.
	if not touch_ui_enabled and event is InputEventScreenTouch and event.pressed:
		touch_ui_enabled = true


## Combined movement intent, length 0..1. Keyboard diagonals are normalised by
## Input.get_vector(); the strongest source wins so sources never add up to >1.
func get_move_vector() -> Vector2:
	var keys := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	return virtual_move if virtual_move.length_squared() > keys.length_squared() else keys


func is_run_requested() -> bool:
	return Input.is_action_pressed(&"run") or virtual_run \
		or virtual_move.length() >= touch_run_threshold


## Clears every virtual input (used on focus loss / HUD hidden).
func reset_virtual() -> void:
	virtual_move = Vector2.ZERO
	virtual_run = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			reset_virtual()
