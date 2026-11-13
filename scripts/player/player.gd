class_name Player
extends CharacterBody2D
## Player-controlled character: 8-directional isometric movement with automatic
## idle / walk / run animation selection.
##
## Controls (physical key positions, so they work on QWERTY *and* AZERTY):
##   WASD on QWERTY == ZQSD on AZERTY, arrow keys, left stick. Shift / pad A = run.

## Ground-space speeds in pixels per second, calibrated against the stride
## length in the generated frames so the feet do not slide.
@export var walk_speed := 50.0
@export var run_speed := 90.0
## Optional: restricts movement to cells that have a tile on this layer.
@export var walkable_layer: TileMapLayer

@onready var sprite: DirectionalSprite = $Sprite

var facing := Direction8.S
## Last ground-space velocity (undistorted), useful for debugging/tests.
var ground_velocity := Vector2.ZERO


func _physics_process(delta: float) -> void:
	# get_vector() clamps to length 1: diagonals are normalised, analog sticks
	# keep partial magnitudes.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var running := Input.is_action_pressed(&"run")
	var speed := run_speed if running else walk_speed

	ground_velocity = input * speed
	velocity = Iso.ground_to_screen(ground_velocity)
	_constrain_to_ground(delta)
	move_and_slide()
	_update_animation(input, running)


func _update_animation(input: Vector2, running: bool) -> void:
	if input.is_zero_approx():
		sprite.speed_scale = 1.0
		sprite.play_state("idle", facing)
		return
	facing = Direction8.from_vector(input)
	var state := "run" if running and sprite.has_state("run") else "walk"
	# Analog input moves slower; slow the cycle accordingly to keep feet planted.
	sprite.speed_scale = clampf(input.length(), 0.35, 1.0)
	sprite.play_state(state, facing)


## Stops movement components that would leave the tiled ground.
func _constrain_to_ground(delta: float) -> void:
	if walkable_layer == null or velocity.is_zero_approx():
		return
	if _is_walkable(global_position + velocity * delta):
		return
	var slide_x := Vector2(velocity.x, 0.0)
	var slide_y := Vector2(0.0, velocity.y)
	if _is_walkable(global_position + slide_x * delta):
		velocity = slide_x
	elif _is_walkable(global_position + slide_y * delta):
		velocity = slide_y
	else:
		velocity = Vector2.ZERO


func _is_walkable(world_pos: Vector2) -> bool:
	var cell := walkable_layer.local_to_map(walkable_layer.to_local(world_pos))
	return walkable_layer.get_cell_source_id(cell) != -1
