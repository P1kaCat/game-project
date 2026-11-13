extends Node2D
## Movement test scene: builds the isometric test map and spawns the player on
## the central tile. Pass `-- --autotest` on the command line to run the scripted
## verification (see scripts/debug/autotest.gd).

@export var map_size := 16

@onready var terrain: IsoTerrain = $Terrain
@onready var player: Player = $Entities/Player


func _ready() -> void:
	terrain.build_test_map(map_size)
	player.walkable_layer = terrain
	player.global_position = terrain.cell_center(Vector2i(map_size / 2, map_size / 2))

	if "--autotest" in OS.get_cmdline_user_args():
		var test := preload("res://scripts/debug/autotest.gd").new()
		test.name = "Autotest"
		add_child(test)
