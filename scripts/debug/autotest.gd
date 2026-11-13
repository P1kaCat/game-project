extends Node
## Scripted verification of the movement prototype.
##
## Run:  godot --path . -- --autotest [--shots=/abs/dir] [--frames]
## Holds real input actions for each of the 8 directions (walk), a few run
## directions and idle, then prints one RESULT line per step and a final
## SUMMARY. With --shots it saves viewport screenshots; with --frames it also
## saves every 3rd physics tick (20 fps of game time) for building a GIF.

const STEP_TIME := 1.0
const STEPS := [
	{"name": "idle_start", "keys": [], "expect": "s", "state": "idle"},
	{"name": "walk_n", "keys": ["move_up"], "expect": "n", "state": "walk"},
	{"name": "walk_ne", "keys": ["move_up", "move_right"], "expect": "ne", "state": "walk"},
	{"name": "walk_e", "keys": ["move_right"], "expect": "e", "state": "walk"},
	{"name": "walk_se", "keys": ["move_down", "move_right"], "expect": "se", "state": "walk"},
	{"name": "walk_s", "keys": ["move_down"], "expect": "s", "state": "walk"},
	{"name": "walk_sw", "keys": ["move_down", "move_left"], "expect": "sw", "state": "walk"},
	{"name": "walk_w", "keys": ["move_left"], "expect": "w", "state": "walk"},
	{"name": "walk_nw", "keys": ["move_up", "move_left"], "expect": "nw", "state": "walk"},
	{"name": "idle_nw", "keys": [], "expect": "nw", "state": "idle"},
	{"name": "run_e", "keys": ["move_right", "run"], "expect": "e", "state": "run"},
	{"name": "run_se", "keys": ["move_down", "move_right", "run"], "expect": "se", "state": "run"},
	{"name": "run_w", "keys": ["move_left", "run"], "expect": "w", "state": "run"},
	{"name": "idle_end", "keys": [], "expect": "w", "state": "idle"},
	# Long walk toward the map edge: must stop on the last tile, never leave it.
	{"name": "edge_e", "keys": ["move_right", "run"], "expect": "e", "state": "run", "time": 6.0},
]

var _shots_dir := ""
var _frames := false
var _frame_counter := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir + "/frames")
		elif arg == "--frames":
			_frames = true
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	# Physics ticks give a fixed game-time capture rate (60 / 3 = 20 fps).
	if _frames and _shots_dir != "":
		_frame_counter += 1
		if _frame_counter % 3 == 0:
			_capture("%s/frames/f_%05d.png" % [_shots_dir, _frame_counter / 3])


func _run() -> void:
	var world := get_parent()
	var player: Player = world.player
	var terrain: IsoTerrain = world.terrain
	await _wait(0.5)

	var failures := 0
	var start_pos := player.global_position
	var start_cell := terrain.local_to_map(terrain.to_local(start_pos))
	print("START pos=%s cell=%s cell_center=%s" % [start_pos, start_cell, terrain.cell_center(start_cell)])
	if not start_pos.is_equal_approx(terrain.cell_center(start_cell)):
		failures += 1
		print("FAIL player not anchored on cell centre")

	for step: Dictionary in STEPS:
		for k: String in step.keys:
			Input.action_press(k)
		var p0 := player.global_position
		var dur: float = step.get("time", STEP_TIME)
		await _wait(dur * 0.5)
		var ground_speed := player.ground_velocity.length()
		var anim := String(player.sprite.animation)
		var playing := player.sprite.is_playing()
		await _wait(dur * 0.5)
		var delta := player.global_position - p0
		if _shots_dir != "":
			_capture("%s/%s.png" % [_shots_dir, step.name])
		for k: String in step.keys:
			Input.action_release(k)

		var expected_anim := "%s_%s" % [step.state, step.expect]
		var expected_speed := 0.0
		match step.state:
			"walk": expected_speed = player.walk_speed
			"run": expected_speed = player.run_speed
		var ok := anim == expected_anim and playing
		if not step.name.begins_with("edge"):
			ok = ok and absf(ground_speed - expected_speed) < 0.01
		var cell := terrain.local_to_map(terrain.to_local(player.global_position))
		var on_ground := terrain.get_cell_source_id(cell) != -1
		ok = ok and on_ground
		if not ok:
			failures += 1
		print("RESULT %-10s %s anim=%-8s expected=%-8s ground_speed=%6.2f screen_delta=(%6.1f,%6.1f) dir=(%5.2f,%5.2f) cell=%s on_ground=%s" % [
			step.name, "PASS" if ok else "FAIL", anim, expected_anim, ground_speed,
			delta.x, delta.y, delta.normalized().x, delta.normalized().y, cell, on_ground])
		await _wait(0.05)

	print("SUMMARY %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(1 if failures else 0)


func _wait(seconds: float) -> void:
	var frames := int(round(seconds * Engine.physics_ticks_per_second))
	for i in frames:
		await get_tree().physics_frame


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
