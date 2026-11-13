class_name Direction8
extends RefCounted
## Eight screen-space facing directions shared by sprites, input and metadata.
##
## Codes match the sprite-sheet row order in
## res://assets/characters/player/player_animations.json ("directions").

const N := "n"
const NE := "ne"
const E := "e"
const SE := "se"
const S := "s"
const SW := "sw"
const W := "w"
const NW := "nw"

## Order of the 45° sectors starting at +X (east) and turning clockwise
## (Godot's +Y points down, so increasing angle = clockwise on screen).
const _BY_SECTOR: Array[String] = [E, SE, S, SW, W, NW, N, NE]


## Returns the direction code closest to `v` (any length > 0).
static func from_vector(v: Vector2) -> String:
	var sector := wrapi(roundi(v.angle() / (PI / 4.0)), 0, 8)
	return _BY_SECTOR[sector]


## Unit vector (in ground / input space) for a direction code.
static func to_vector(code: String) -> Vector2:
	var sector := _BY_SECTOR.find(code)
	return Vector2.RIGHT.rotated(sector * PI / 4.0)
