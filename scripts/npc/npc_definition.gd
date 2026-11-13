class_name NpcDefinition
extends Resource
## Data for one NPC (res://data/npcs/<id>.tres): who it is, how it looks, what
## it says and sells. New characters = new .tres, no code.

@export var id: StringName
@export var display_name := ""
@export var portrait: Texture2D
@export_file("*.json") var sprite_metadata := ""
@export_file("*.json") var dialogue := ""
## Optional shop, opened by the dialogue action {"type": "open_shop"}.
@export var shop: MerchantStock
## Facing when nobody is talking to it.
@export_enum("n", "ne", "e", "se", "s", "sw", "w", "nw") var idle_facing := "s"
## Ground-space distance (px) from which the player can interact.
@export var interaction_radius := 40.0
