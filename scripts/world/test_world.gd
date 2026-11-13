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

	_add_version_label()

	if "--autotest" in OS.get_cmdline_user_args():
		var test := preload("res://scripts/debug/autotest.gd").new()
		test.name = "Autotest"
		add_child(test)


func spawn_player(cell: Vector2i) -> void:
	player.global_position = terrain.cell_center(cell)
	player.ground_velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	camera.snap_to_target()


## Small "vX.Y.Z" in the top-right corner: the content version actually running
## (set by the launcher after a hot update), or the built-in one.
func _add_version_label() -> void:
	var v := str(Engine.get_meta(&"content_version", ""))
	if v == "":
		var info = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
		v = str(info.get("version", "?")) if info is Dictionary else "?"
	var layer := CanvasLayer.new()
	layer.layer = 40
	var label := Label.new()
	label.name = "VersionLabel"
	label.text = "v" + v
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.position += Vector2(-4, 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	add_child(layer)
