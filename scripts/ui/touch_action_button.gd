class_name TouchActionButton
extends Control
## Round on-screen button for touchscreens.
##
## Tracks its own finger index (works while another finger holds the joystick)
## and drives an InputMap action, so gameplay code handles touch and keyboard
## the same way (`interact` is also bound to E / Space / pad X). Placeholder for
## future interactions; no gameplay logic lives here.

signal pressed
signal released

@export var action := &"interact"
@export var radius := 22.0:
	set(v):
		radius = v
		custom_minimum_size = Vector2.ONE * radius * 2.0
		size = custom_minimum_size
		queue_redraw()
@export var label := "A"
@export var fill_color := Color(0.05, 0.06, 0.09, 0.35)
@export var pressed_color := Color(1, 0.92, 0.6, 0.55)
@export var ring_color := Color(1, 1, 1, 0.5)

var is_pressed := false
var press_count := 0
var _finger := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	radius = radius
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_release())


func global_center() -> Vector2:
	return get_global_transform_with_canvas() * (size / 2.0)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventScreenTouch:
		return
	var t := event as InputEventScreenTouch
	if t.pressed and _finger == -1:
		# Slightly generous hit area for thumbs.
		if t.position.distance_to(global_center()) <= radius * 1.25:
			_finger = t.index
			is_pressed = true
			press_count += 1
			_send_action(true)
			pressed.emit()
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif t.index == _finger and (not t.pressed or t.canceled):
		_release()
		get_viewport().set_input_as_handled()


func _release() -> void:
	if _finger == -1:
		return
	_finger = -1
	is_pressed = false
	_send_action(false)
	released.emit()
	queue_redraw()


func _send_action(down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	ev.strength = 1.0 if down else 0.0
	Input.parse_input_event(ev)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_release()


func _draw() -> void:
	var c := (size / 2.0).round()
	draw_circle(c, radius, pressed_color if is_pressed else fill_color, true, -1.0, false)
	draw_arc(c, radius, 0.0, TAU, 40, ring_color, 1.0, false)
	var font := get_theme_default_font()
	var fs := int(clampf(radius * 0.8, 8.0, 32.0))
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := c + Vector2(-text_size.x / 2.0, font.get_ascent(fs) - text_size.y / 2.0)
	draw_string(font, pos.round(), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85))
