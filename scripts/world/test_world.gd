extends Node2D
## The starting area of Asthya ("Prairie de l'Éveil"): builds the isometric map
## (ground, edge collision, raised solid blocks), places Eldric and the player
## from GameState (new game: awakening sequence; loaded game: saved position),
## wires the pause menu, autosave and settings. Pass `-- --autotest` to run
## scripted verification (scripts/debug/autotest.gd).

@export var map_size := 16

@onready var terrain: IsoTerrain = $Terrain
@onready var obstacles: IsoObstacles = $Entities/Obstacles
@onready var player: Player = $Entities/Player
@onready var camera: FollowCamera = $Camera
@onready var hud: MobileHUD = $MobileHUD
@onready var eldric: Npc = $Entities/Eldric
@onready var director: InteractionDirector = $InteractionDirector

## Eldric stands on the plaza next to the central crossroads.
const ELDRIC_CELL := Vector2i(10, 7)
## Where the protagonist wakes up: near Eldric, not beside him.
const AWAKEN_CELL := Vector2i(7, 9)
## Seconds between periodic autosaves (also saved after story beats / trades).
const AUTOSAVE_INTERVAL := 120.0

var pause_menu: PauseMenu
var story_running := false
var _autosave_t := 0.0


func _ready() -> void:
	if not GameState.active:
		GameState.setup_sandbox()  # scene started directly (editor / tests)
	Settings.apply()
	terrain.build_test_map(map_size)
	obstacles.build_test_blocks()
	eldric.global_position = terrain.cell_center(ELDRIC_CELL)
	player.state = GameState.player  # gold + inventory live in the saved state
	camera.follow_speed = Settings.camera_follow_speed()
	add_to_group(&"settings_listeners")
	hud.add_to_group(&"settings_listeners")

	if GameState.has_position:
		player.global_position = GameState.player_position
		player.reset_physics_interpolation()
		player.set_facing(GameState.facing)
		camera.snap_to_target()
	elif GameState.awakening_pending:
		spawn_player(AWAKEN_CELL)
	else:
		spawn_player(Vector2i(map_size / 2, map_size / 2))

	_add_version_label()
	_add_pause_menu()
	director.conversation_finished.connect(func(_npc: Npc) -> void: autosave())
	Audio.ambience("amb_meadow", 2.0, -8.0)
	if GameState.awakening_pending:
		_play_awakening()

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
	layer.layer = 5  # under the HUD (10) and the dialogue / shop windows (30+)
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


func _process(delta: float) -> void:
	GameState.play_time += delta
	if story_running or GameState.sandbox:
		return
	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_INTERVAL and not director.busy:
		autosave()


func apply_settings() -> void:
	camera.follow_speed = Settings.camera_follow_speed()


## Copies the live world state into GameState (before any save).
func capture_state() -> void:
	GameState.player_position = player.global_position
	GameState.has_position = true
	GameState.facing = player.facing
	GameState.map_id = GameState.START_MAP


func autosave() -> void:
	_autosave_t = 0.0
	if GameState.sandbox or story_running:
		return
	capture_state()
	if SaveSystem.save_slot("auto", GameState.to_dict()) == OK and pause_menu:
		pause_menu.show_toast(Loc.t("hint.autosave"))


func _add_pause_menu() -> void:
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.can_open = func() -> bool:
		return not story_running and not director.busy and not player.is_controls_locked()
	pause_menu.before_save = capture_state
	add_child(pause_menu)


## New game: the protagonist lies where the cinematic left them, the view
## starts on the sky and settles, they get up, then the player takes over.
func _play_awakening() -> void:
	story_running = true
	player.set_controls_locked(true)
	hud.suppressed = true
	player.animation_override = true
	player.set_facing("se")
	var sprite := player.sprite
	sprite.play_state("getup", "se")
	sprite.pause()
	sprite.frame = 0
	camera.follow_speed = 1.1
	camera.start_offset(Vector2(0, -90))
	await get_tree().create_timer(2.4).timeout
	Audio.sfx("getup", -6.0)
	sprite.play()
	await sprite.animation_finished
	sprite.play_state("idle", "se")
	player.animation_override = false
	await get_tree().create_timer(0.6).timeout
	camera.follow_speed = Settings.camera_follow_speed()
	player.set_controls_locked(false)
	hud.suppressed = false
	GameState.flags["awakened"] = true
	GameState.awakening_pending = false
	story_running = false
	autosave()


func _notification(what: int) -> void:
	MenuKit.forward_back_button(what)
