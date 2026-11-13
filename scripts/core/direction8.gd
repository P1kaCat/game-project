class_name Direction8
extends RefCounted
## Eight screen-space facing directions shared by sprites, input and metadata.
##
## Codes match the sprite-sheet row order in
## res://assets/characters/player/player_animations.json ("directions").
## Sectors are numbered from +X (east) turning clockwise on screen (Godot's +Y
## points down): 0=E 1=SE 2=S 3=SW 4=W 5=NW 6=N 7=NE. Odd sectors are diagonals.

const N := "n"
const NE := "ne"
const E := "e"
const SE := "se"
const S := "s"
const SW := "sw"
const W := "w"
const NW := "nw"

const SECTOR_ANGLE := PI / 4.0
const _BY_SECTOR: Array[String] = [E, SE, S, SW, W, NW, N, NE]


## Nearest sector (0-7) for a non-zero vector.
static func sector_of_vector(v: Vector2) -> int:
	return wrapi(roundi(v.angle() / SECTOR_ANGLE), 0, 8)


## Nearest sector, but stays on `current` until the vector is more than
## `hysteresis` radians past the shared boundary. Prevents flicker when an
## analog stick hovers around a 22.5° boundary.
static func sector_with_hysteresis(v: Vector2, current: int, hysteresis: float) -> int:
	if current < 0:
		return sector_of_vector(v)
	var diff := absf(angle_difference(current * SECTOR_ANGLE, v.angle()))
	if diff <= SECTOR_ANGLE * 0.5 + hysteresis:
		return current
	return sector_of_vector(v)


static func is_diagonal(sector: int) -> bool:
	return sector % 2 == 1


## True when the two sectors are neighbours (45° apart).
static func are_adjacent(a: int, b: int) -> bool:
	return absi(wrapi(a - b + 4, 0, 8) - 4) == 1


static func code(sector: int) -> String:
	return _BY_SECTOR[wrapi(sector, 0, 8)]


static func sector(dir_code: String) -> int:
	return _BY_SECTOR.find(dir_code)


## Unit vector (ground / input space) of a sector.
static func sector_vector(s: int) -> Vector2:
	return Vector2.RIGHT.rotated(s * SECTOR_ANGLE)


## Direction code closest to `v` (any length > 0).
static func from_vector(v: Vector2) -> String:
	return code(sector_of_vector(v))


## Unit vector (ground / input space) for a direction code.
static func to_vector(dir_code: String) -> Vector2:
	return sector_vector(sector(dir_code))
