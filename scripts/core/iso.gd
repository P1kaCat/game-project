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
