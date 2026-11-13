class_name Iso
extends RefCounted
## 2:1 isometric projection helpers.
##
## Gameplay vectors (input, velocity) live in "ground space": an undistorted,
## top-down plane where every direction has the same length. The screen shows
## that plane through a 2:1 isometric camera, which halves vertical distances.
## A ground diagonal (1, 1) therefore projects to screen (1, 0.5): exactly the
## slope of a 64x32 tile edge, so diagonal movement follows the grid lines.

const TILE_SIZE := Vector2i(64, 32)
const Y_SCALE := 0.5  # TILE_SIZE.y / TILE_SIZE.x


static func ground_to_screen(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * Y_SCALE)


static func screen_to_ground(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y / Y_SCALE)


## On-screen movement for a ground-space velocity `v`.
##
## The direction is the true projection (diagonals keep the 2:1 tile-edge
## slope), but the on-screen speed is shaped by an ellipse: full speed
## horizontally, `vertical_speed` x speed vertically, smoothly in between.
## vertical_speed = 0.5 is pure isometric foreshortening (up/down look twice as
## slow), 1.0 is the same screen speed in every direction.
static func move_to_screen(v: Vector2, vertical_speed: float) -> Vector2:
	if v.is_zero_approx():
		return Vector2.ZERO
	var dir := ground_to_screen(v).normalized()
	return dir * v.length() * screen_speed_factor(dir, vertical_speed)


## Inverse of move_to_screen (used to measure what a collision slide did).
static func screen_to_move(s: Vector2, vertical_speed: float) -> Vector2:
	if s.is_zero_approx():
		return Vector2.ZERO
	var dir := s.normalized()
	return screen_to_ground(dir).normalized() * s.length() / screen_speed_factor(dir, vertical_speed)


## Speed multiplier for a unit screen direction: 1 horizontally,
## `vertical_speed` vertically (ellipse in between).
static func screen_speed_factor(screen_dir: Vector2, vertical_speed: float) -> float:
	var y := screen_dir.y / vertical_speed
	return 1.0 / sqrt(screen_dir.x * screen_dir.x + y * y)
