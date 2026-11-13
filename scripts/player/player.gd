class_name Player
extends CharacterBody2D
## Player-controlled character: 8-directional isometric movement with automatic
## idle / walk / run animation selection.
##
## Input comes from the GameInput autoload (keyboard WASD == AZERTY ZQSD by
## physical position, arrows, gamepad stick, on-screen joystick).
##
## Movement happens in an undistorted "ground" plane and is projected to the
## screen with the 2:1 isometric camera (Iso.ground_to_screen), so diagonals run
## exactly along the 64x32 tile edges and diagonal speed is normalised.

signal facing_changed(dir_code: String)
signal interacted

## Ground-space speeds in px/s, calibrated against the stride in the generated
## frames so the feet don't slide.
@export var walk_speed := 50.0
@export var run_speed := 90.0
## Ground-space acceleration / braking in px/s². High values feel responsive;
## the short ramp only removes the 1-frame start/stop pop.
@export var acceleration := 1400.0
@export var braking := 1800.0
## Snap analog input (joystick, gamepad) to the 8 sprite directions so movement
## always matches the drawn facing. Keyboard input is already 8-directional.
@export var snap_to_8_directions := true
## Extra angle past a 22.5° sector boundary before the direction changes.
@export_range(0.0, 20.0) var direction_hysteresis_deg := 8.0
## A diagonal facing only turns to an adjacent cardinal after this long, so
## releasing two keys a frame apart does not leave the character facing N/E/S/W.
@export var facing_settle_time := 0.09
## When blocked, a slide must keep at least this fraction of the intended
## forward progress; otherwise the character just stops (no corner jitter).
@export_range(0.0, 1.0) var min_slide_progress := 0.25

@onready var sprite: DirectionalSprite = $Sprite
@onready var emote: Node2D = $Emote

var facing := Direction8.S
## Current ground-space velocity (undistorted), useful for debugging/tests.
var ground_velocity := Vector2.ZERO
var is_running := false

var _move_sector := -1
var _facing_sector := Direction8.sector(Direction8.S)
var _pending_sector := -1
var _pending_time := 0.0


func _physics_process(delta: float) -> void:
	var input := GameInput.get_move_vector()
	var strength := minf(input.length(), 1.0)
	is_running = strength > 0.0 and GameInput.is_run_requested()

	var target := Vector2.ZERO
	if strength > 0.0:
		_move_sector = Direction8.sector_with_hysteresis(
			input, _move_sector, deg_to_rad(direction_hysteresis_deg))
		var dir := Direction8.sector_vector(_move_sector) if snap_to_8_directions else input / strength
		var speed := run_speed if is_running else walk_speed * strength
		target = dir * speed
		_update_facing(_move_sector, delta)
	else:
		_move_sector = -1
		_pending_sector = -1

	var rate := acceleration if target != Vector2.ZERO else braking
	ground_velocity = ground_velocity.move_toward(target, rate * delta)

	velocity = Iso.ground_to_screen(ground_velocity)
	var start := global_position
	move_and_slide()
	if get_slide_collision_count() > 0:
		_resolve_collision(start, delta)

	_update_animation(target)


## After hitting something: keep useful slides along a face, but stop cleanly
## when the move made almost no progress in the intended direction (head-on
## push, or wedged in an inside corner where sliding would jitter between the
## two faces). Measured in ground space so the iso squash doesn't skew angles.
func _resolve_collision(start: Vector2, delta: float) -> void:
	var intended := ground_velocity * delta
	var moved := Iso.screen_to_ground(global_position - start)
	if intended.is_zero_approx() or moved.dot(intended.normalized()) < intended.length() * min_slide_progress:
		global_position = start
		ground_velocity = Vector2.ZERO
	else:
		# Match what actually happened so the walk cycle follows the slide speed.
		ground_velocity = moved / delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		interact()


## Placeholder for future interactions (talk, open, pick up...).
func interact() -> void:
	emote.call(&"pop")
	interacted.emit()


func _update_facing(sector: int, delta: float) -> void:
	if sector == _facing_sector:
		_pending_sector = -1
		return
	var settle := Direction8.is_diagonal(_facing_sector) and not Direction8.is_diagonal(sector) \
		and Direction8.are_adjacent(_facing_sector, sector)
	if not settle:
		_set_facing(sector)
		return
	if sector != _pending_sector:
		_pending_sector = sector
		_pending_time = 0.0
	_pending_time += delta
	if _pending_time >= facing_settle_time:
		_set_facing(sector)


func _set_facing(sector: int) -> void:
	_facing_sector = sector
	_pending_sector = -1
	facing = Direction8.code(sector)
	facing_changed.emit(facing)


func _update_animation(_target: Vector2) -> void:
	var speed := ground_velocity.length()
	# Idle when not actually moving: no input, or pushing against a wall.
	if speed < 2.0:
		sprite.speed_scale = 1.0
		sprite.play_state("idle", facing)
		return
	var state := "run" if is_running and sprite.has_state("run") else "walk"
	var nominal := run_speed if state == "run" else walk_speed
	# Tie the cycle to actual speed (analog input, acceleration, wall sliding).
	sprite.speed_scale = clampf(speed / nominal, 0.35, 1.0)
	sprite.play_state(state, facing)
