class_name FollowCamera
extends Camera2D
## Smooth, pixel-stable camera that keeps a target approximately centred.
##
## Smoothing is exponential (frame-rate independent). The camera is then placed
## at a whole-pixel offset from the target: the target's on-screen position only
## ever changes by whole pixels, so the pixel-art sprite never jitters against
## the screen while the world scrolls smoothly underneath. Runs in the physics
## step so it shares physics interpolation with the target on high-refresh
## displays.

@export var target: Node2D
## Higher = tighter follow. ~8 gives a few pixels of lag at walking speed.
@export var follow_speed := 10.0
## Offset from the target's foot point to the point kept centred (the
## character's torso, so the body sits in the middle of the screen).
@export var focus_offset := Vector2(0, -20)

var _smoothed := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = false
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	snap_to_target()


## Jump straight to the target (spawn, teleport).
func snap_to_target() -> void:
	if target == null:
		return
	_smoothed = target.global_position + focus_offset
	global_position = _smoothed
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position + focus_offset
	_smoothed = _smoothed.lerp(goal, 1.0 - exp(-follow_speed * delta))
	# Keep (target - camera) integral -> stable sprite, smooth world scroll.
	global_position = goal - (goal - _smoothed).round()


## Distance between the camera centre and the focus point (for tests / HUD).
func lag() -> Vector2:
	return (target.global_position + focus_offset) - global_position if target else Vector2.ZERO
