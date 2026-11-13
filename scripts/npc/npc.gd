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


func face_towards(world_pos: Vector2) -> void:
	var d := Iso.screen_to_ground(world_pos - global_position)
	if d.length() > 0.5:
		facing = Direction8.from_vector(d)
		sprite.play_state("idle", facing)


func reset_facing() -> void:
	if definition:
		facing = definition.idle_facing
		sprite.play_state("idle", facing)
