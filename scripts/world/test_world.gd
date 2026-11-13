extends Node2D
## Movement test scene: builds the isometric test map (ground, edge collision,
## raised solid blocks), spawns the player on the central tile and attaches the
## follow camera. Pass `-- --autotest` to run scripted verification
## (scripts/debug/autotest.gd).

@export var map_size := 16

@onready var terrain: IsoTerrain = $Terrain
@onready var obstacles: IsoObstacles = $Entities/Obstacles
@onready var player: Player = $Entities/Player
@onready var camera: FollowCamera = $Camera
@onready var hud: MobileHUD = $MobileHUD


func _ready() -> void:
	terrain.build_test_map(map_size)
	obstacles.build_test_blocks()
	spawn_player(Vector2i(map_size / 2, map_size / 2))

	if "--autotest" in OS.get_cmdline_user_args():
		var test := preload("res://scripts/debug/autotest.gd").new()
		test.name = "Autotest"
		add_child(test)


func spawn_player(cell: Vector2i) -> void:
	player.global_position = terrain.cell_center(cell)
	player.ground_velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	camera.snap_to_target()
