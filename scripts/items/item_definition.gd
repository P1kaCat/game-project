class_name ItemDefinition
extends Resource
## Static description of an item type (one .tres per item in res://data/items/).
## Gameplay code only stores item ids + counts; everything else is looked up
## here, so item data is never duplicated (shops, inventory, UI, future server).

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var category: StringName = &"misc"
@export_range(1, 999) var max_stack := 1
## Whether merchants may sell it at all.
@export var purchasable := true
