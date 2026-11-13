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
var _frame_points: Array[Vector2] = []
var _frame_anchor := Vector2.ZERO


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


## Starts the view displaced by `offset` (it then glides back to the target at
## `follow_speed`), e.g. looking at the sky before settling on the player.
func start_offset(offset: Vector2) -> void:
	_smoothed += offset
	global_position = _smoothed
	reset_physics_interpolation()


## Frames world points (e.g. player + NPC during a conversation) so that their
## midpoint appears at `screen_anchor` (viewport pixels). Smoothly animated.
func frame_points(points: Array[Vector2], screen_anchor: Vector2) -> void:
	_frame_points = points
	_frame_anchor = screen_anchor


func clear_framing() -> void:
	_frame_points = []


func is_framing() -> bool:
	return not _frame_points.is_empty()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position + focus_offset
	if not _frame_points.is_empty():
		var mid := Vector2.ZERO
		for p in _frame_points:
			mid += p
		mid /= _frame_points.size()
		goal = mid + get_viewport_rect().size / 2.0 - _frame_anchor
	_smoothed = _smoothed.lerp(goal, 1.0 - exp(-follow_speed * delta))
	# Keep (target - camera) integral -> stable sprite, smooth world scroll.
	global_position = goal - (goal - _smoothed).round()


## Distance between the camera centre and the focus point (for tests / HUD).
func lag() -> Vector2:
	return (target.global_position + focus_offset) - global_position if target else Vector2.ZERO
