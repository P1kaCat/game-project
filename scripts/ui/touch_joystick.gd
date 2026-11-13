class_name TouchJoystick
extends Control
## On-screen analog joystick for touchscreens.
##
## * Tracks one finger by its touch index, so other fingers (action button,
##   future buttons) work at the same time (multitouch).
## * Continuous 360° output with a radial dead zone; output is rescaled so it
##   starts at 0 just outside the dead zone and reaches 1 slightly before the
##   rim (easy full tilt). Full tilt = run (GameInput.touch_run_threshold).
## * Releases on finger up, touch cancel, focus loss or when hidden; the knob
##   springs back to the centre.
## * Only reacts to InputEventScreenTouch/Drag, never to (emulated) mouse
##   events, so it cannot conflict with mouse or keyboard input.
##
## Writes its value into GameInput.virtual_move; also emits `changed`.

signal changed(value: Vector2)

## Radii in viewport pixels (the HUD rescales them for screen density).
@export var base_radius := 32.0:
	set(v):
		base_radius = v
		_resize()
@export var knob_radius := 13.0
## Touches this far from the centre (in base radii) still grab the stick.
@export var grab_radius_factor := 1.6
@export_range(0.0, 0.6) var dead_zone := 0.2
## Fraction of the radius at which output reaches 1.0.
@export_range(0.5, 1.0) var saturation := 0.9
@export var return_speed := 18.0

@export var base_color := Color(0.05, 0.06, 0.09, 0.35)
@export var ring_color := Color(1, 1, 1, 0.45)
@export var knob_color := Color(1, 1, 1, 0.55)
@export var knob_active_color := Color(1, 0.92, 0.6, 0.8)

## Current output (screen space, length 0..1).
var value := Vector2.ZERO
var _finger := -1
var _knob := Vector2.ZERO  # knob offset from centre, in pixels (visual)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			release())


func _resize() -> void:
	custom_minimum_size = Vector2.ONE * base_radius * grab_radius_factor * 2.0
	size = custom_minimum_size
	queue_redraw()


## Centre of the stick in the same coordinates as touch events (viewport/canvas).
func global_center() -> Vector2:
	return get_global_transform_with_canvas() * (size / 2.0)


func is_active() -> bool:
	return _finger != -1


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _finger == -1:
			if t.position.distance_to(global_center()) <= base_radius * grab_radius_factor:
				_finger = t.index
				_update_from(t.position)
				get_viewport().set_input_as_handled()
		elif t.index == _finger and (not t.pressed or t.canceled):
			release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _finger:
			_update_from(d.position)
			get_viewport().set_input_as_handled()


func _update_from(touch_pos: Vector2) -> void:
	var offset := touch_pos - global_center()
	_knob = offset.limit_length(base_radius)
	var raw := offset.length() / base_radius
	var out := Vector2.ZERO
	if raw > dead_zone:
		var m := clampf((raw - dead_zone) / (saturation - dead_zone), 0.0, 1.0)
		out = offset.normalized() * m
	_set_value(out)
	queue_redraw()


## Lets go of the stick (finger up, cancel, focus loss, hidden).
func release() -> void:
	_finger = -1
	_set_value(Vector2.ZERO)
	queue_redraw()


func _set_value(v: Vector2) -> void:
	if v == value:
		return
	value = v
	GameInput.virtual_move = v
	changed.emit(v)


func _process(delta: float) -> void:
	if _finger == -1 and _knob != Vector2.ZERO:
		_knob = _knob.lerp(Vector2.ZERO, 1.0 - exp(-return_speed * delta))
		if _knob.length() < 0.5:
			_knob = Vector2.ZERO
		queue_redraw()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			release()


func _draw() -> void:
	var c := (size / 2.0).round()
	draw_circle(c, base_radius, base_color, true, -1.0, false)
	draw_arc(c, base_radius, 0.0, TAU, 48, ring_color, 1.0, false)
	draw_arc(c, base_radius * dead_zone, 0.0, TAU, 16, Color(ring_color, ring_color.a * 0.5), 1.0, false)
	var k := c + _knob.round()
	draw_circle(k, knob_radius, knob_active_color if is_active() else knob_color, true, -1.0, false)
	draw_arc(k, knob_radius, 0.0, TAU, 32, Color(0.05, 0.06, 0.09, 0.5), 1.0, false)
