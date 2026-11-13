class_name GameState
extends RefCounted
## The current play session (static so menus, cinematic and world share it).
## Serialized by SaveSystem; ready to be mirrored from a server later.

const START_MAP := "asthya_meadow"
const SAVE_FLAGS_VERSION := 1

static var player := PlayerState.new(250, 20)
static var flags := {}               # story / dialogue flags (DialogueManager uses this dict)
static var map_id := START_MAP
static var has_position := false     # false = use the map's start point
static var player_position := Vector2.ZERO
static var facing := "se"
static var awakening_pending := false
static var play_time := 0.0
static var sandbox := false          # automated tests: skip story, merchant ready
static var active := false           # a session was started (menu / load / sandbox)


static func new_game() -> void:
	player = PlayerState.new(250, 20)
	flags = {}
	map_id = START_MAP
	has_position = false
	facing = "se"
	awakening_pending = true
	play_time = 0.0
	sandbox = false
	active = true


## Story already seen: used by automated tests and debugging.
static func setup_sandbox() -> void:
	new_game()
	flags = {"intro_seen": true, "awakened": true, "eldric_intro_done": true}
	awakening_pending = false
	sandbox = true


static func to_dict() -> Dictionary:
	return {
		"map_id": map_id,
		"position": [player_position.x, player_position.y],
		"facing": facing,
		"player": player.to_dict(),
		"flags": flags.duplicate(true),
		"play_time": play_time,
	}


## Applies validated save data (see SaveSystem.validate).
static func apply_dict(d: Dictionary) -> void:
	map_id = str(d.map_id)
	player_position = Vector2(float(d.position[0]), float(d.position[1]))
	has_position = true
	facing = str(d.facing)
	player = PlayerState.new(0, 20)
	player.apply_dict(d.player)
	flags = (d.flags as Dictionary).duplicate(true)
	play_time = float(d.play_time)
	awakening_pending = false
	sandbox = false
	active = true


static func format_play_time(seconds: float) -> String:
	var m := int(seconds) / 60
	return "%dh%02d" % [m / 60, m % 60]
