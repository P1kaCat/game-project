class_name Npc
extends StaticBody2D
## A non-player character placed in the world, configured by an NpcDefinition.
## Owns its sprite, collision and Interactable; what happens on interaction
## (dialogue, shop...) is decided by InteractionDirector, not here.

signal interaction_requested(npc: Npc, by: Node)

@export var definition: NpcDefinition

@onready var sprite: DirectionalSprite = $Sprite
@onready var interactable: Interactable = $Interactable

var facing := "s"


func _ready() -> void:
	add_to_group(&"npc")
	if definition:
		sprite.metadata_path = definition.sprite_metadata
		sprite.reload()
		interactable.radius = definition.interaction_radius
		facing = definition.idle_facing
	sprite.play_state("idle", facing)
	interactable.interacted.connect(func(by: Node) -> void: interaction_requested.emit(self, by))


## Plays a one-shot animation (greet, gesture...) in the closest direction it
## was drawn for, then returns to idle. Missing animations are ignored.
func play_action(anim: String) -> void:
	if not sprite.has_state(anim):
		return
	var dirs := sprite.state_directions(anim)
	var dir := facing if facing in dirs else _closest_dir(dirs)
	if dir == "":
		return
	sprite.speed_scale = 1.0
	sprite.play_state(anim, dir)
	if not sprite.animation_finished.is_connected(_on_action_finished):
		sprite.animation_finished.connect(_on_action_finished)


func is_playing_action() -> bool:
	return sprite.current_state not in ["idle", "walk", ""]


func _on_action_finished() -> void:
	if is_playing_action():
		sprite.play_state("idle", facing)


func _closest_dir(dirs: Array) -> String:
	var best := ""
	var best_d := 99
	var i := Direction8.sector(facing)
	for d in dirs:
		var diff := absi(Direction8.sector(d) - i) % 8
		diff = mini(diff, 8 - diff)
		if diff < best_d:
			best_d = diff
			best = d
	return best


func face_towards(world_pos: Vector2) -> void:
	var d := Iso.screen_to_ground(world_pos - global_position)
	if d.length() > 0.5:
		facing = Direction8.from_vector(d)
		if not is_playing_action():
			sprite.play_state("idle", facing)


func reset_facing() -> void:
	if definition:
		facing = definition.idle_facing
		if not is_playing_action():
			sprite.play_state("idle", facing)
