extends Node
## Scripted runtime verification of movement, animation, camera, collision and
## touch controls. Drives the real game through InputMap actions (keyboard path)
## and injected InputEventScreenTouch / InputEventScreenDrag events (touch path,
## in window coordinates, exactly like the OS delivers them).
##
## Run:  godot --path . -- --autotest [--shots=/abs/dir] [--frames] [--layout-only]
##       godot ... -- --autotest --launcher-only --expect-launcher=STATUS
##             [--expect-content-version=X.Y.Z] [--check-updates --update-api-base=URL ...]
## Prints one CHECK line per assertion and a final SUMMARY; exit code 0 = pass.

var world: Node
var player: Player
var camera: FollowCamera
var hud: MobileHUD
var terrain: IsoTerrain
var obstacles: IsoObstacles

var _shots_dir := ""
var _frames := false
var _frame_counter := 0
var _failures := 0
var _checks := 0
var _anim_changes := 0
var _interacts := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir + "/frames")
		elif arg == "--frames":
			_frames = true
	world = get_parent()
	player = world.player
	camera = world.camera
	hud = world.hud
	terrain = world.terrain
	obstacles = world.obstacles
	player.sprite.animation_changed.connect(func() -> void: _anim_changes += 1)
	player.interacted.connect(func() -> void: _interacts += 1)
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	if _frames and _shots_dir != "":
		_frame_counter += 1
		if _frame_counter % 3 == 0:
			_capture("frames/f_%05d" % (_frame_counter / 3))


# --------------------------------------------------------------------- runner
func _run() -> void:
	await _wait(0.4)
	if "--launcher-only" in OS.get_cmdline_user_args():
		await _run_launcher_checks()
		print("SUMMARY %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
		get_tree().quit(1 if _failures else 0)
		return
	if "--layout-only" in OS.get_cmdline_user_args():
		# Touch HUD layout check for the current window size / fake safe area.
		GameInput.touch_ui_enabled = true
		await _wait(0.3)
		print("LAYOUT window=%s viewport=%s safe=%s joystick_r=%.0f" % [DisplayServer.window_get_size(),
			get_viewport().get_visible_rect().size, hud.safe_rect, hud.joystick.base_radius])
		await _test_hud_layout()
		print("SUMMARY %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
		get_tree().quit(1 if _failures else 0)
		return
	await _test_spawn_and_anchor()
	await _test_keyboard_directions()
	await _test_idle_and_no_resets()
	await _test_release_stagger()
	await _test_run()
	await _test_sprint_key_mid_walk()
	await _test_frame_rate_independence()
	await _test_camera_follow()
	await _test_collision_blocks()
	await _test_map_edge()
	await _test_keyboard_interact()
	await _test_pc_hides_touch_ui()
	# ---- touch controls (HUD forced on, like on Android)
	GameInput.touch_ui_enabled = true
	await _wait(0.2)
	await _test_hud_layout()
	await _test_joystick_directions()
	await _test_joystick_analog_and_deadzone()
	await _test_joystick_release_and_cancel()
	await _test_multitouch_action_button()
	await _test_touch_sprint_button()
	await _test_touch_outside_ignored()
	await _test_flicker_resistance()
	await _test_keyboard_and_touch_coexist()
	await _test_assets_preserved()

	print("SUMMARY %s (%d checks, %d failures)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	get_tree().quit(1 if _failures else 0)


func check(name: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("CHECK %-4s %-44s %s" % ["PASS" if ok else "FAIL", name, detail])


# ---------------------------------------------------------------- keyboard
func _test_spawn_and_anchor() -> void:
	var cell := Vector2i(8, 8)
	check("spawn: feet on cell centre",
		player.global_position.is_equal_approx(terrain.cell_center(cell)),
		"pos=%s centre=%s" % [player.global_position, terrain.cell_center(cell)])
	check("spawn: idle facing south", String(player.sprite.animation) == "idle_s",
		String(player.sprite.animation))
	var pivot: Vector2 = -player.sprite.offset
	check("sprite: foot pivot on node origin", pivot == Vector2(34, 57), str(pivot))
	check("no input: no movement", player.velocity == Vector2.ZERO and player.ground_velocity == Vector2.ZERO)


const KEY_DIRS := {
	"n": [&"move_up"], "ne": [&"move_up", &"move_right"], "e": [&"move_right"],
	"se": [&"move_down", &"move_right"], "s": [&"move_down"], "sw": [&"move_down", &"move_left"],
	"w": [&"move_left"], "nw": [&"move_up", &"move_left"],
}


func _test_keyboard_directions() -> void:
	for dir: String in KEY_DIRS:
		world.spawn_player(Vector2i(8, 8))
		await _wait(0.05)
		_press(KEY_DIRS[dir])
		await _wait(0.3)
		var p0 := player.global_position
		await _wait(0.5)
		var delta := player.global_position - p0
		var speed := player.ground_velocity.length()
		var anim := String(player.sprite.animation)
		var expect_dir := Iso.ground_to_screen(Direction8.to_vector(dir)).normalized()
		if _shots_dir != "":
			_capture("walk_" + dir)
		_release(KEY_DIRS[dir])
		check("keyboard %s: sprite + walk anim" % dir, anim == "walk_" + dir and player.sprite.is_playing(), anim)
		check("keyboard %s: ground speed normalised" % dir, absf(speed - player.walk_speed) < 0.01, "%.3f px/s" % speed)
		check("keyboard %s: screen direction (iso)" % dir, delta.normalized().dot(expect_dir) > 0.9999,
			"delta=(%.2f,%.2f) expected=(%.3f,%.3f)" % [delta.x, delta.y, expect_dir.x, expect_dir.y])
		await _wait(0.2)


func _test_idle_and_no_resets() -> void:
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.1)
	_anim_changes = 0
	_press([&"move_right"])
	var frames_seen := {}
	for i in 60:
		await get_tree().physics_frame
		frames_seen[player.sprite.frame] = true
	var changes_while_walking := _anim_changes
	_release([&"move_right"])
	await _wait(0.25)
	check("walk: animation set once (no per-frame reset)", changes_while_walking == 1, "changes=%d" % changes_while_walking)
	check("walk: cycle advances through frames", frames_seen.size() >= 7, "distinct frames=%d" % frames_seen.size())
	check("stop: idle anim, last facing kept", String(player.sprite.animation) == "idle_e", String(player.sprite.animation))
	check("stop: velocity returns to zero", player.ground_velocity == Vector2.ZERO, str(player.ground_velocity))


func _test_release_stagger() -> void:
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	_press([&"move_up", &"move_right"])
	await _wait(0.4)
	_release([&"move_right"])   # fingers lift one or two frames apart
	await get_tree().physics_frame
	await get_tree().physics_frame
	_release([&"move_up"])
	await _wait(0.2)
	check("staggered key release keeps diagonal facing", String(player.sprite.animation) == "idle_ne",
		String(player.sprite.animation))


func _test_run() -> void:
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	_press([&"move_left", &"run"])
	await _wait(0.4)
	var anim := String(player.sprite.animation)
	var speed := player.ground_velocity.length()
	var run_scale := player.sprite.speed_scale
	if _shots_dir != "":
		_capture("run_w")
	_release([&"move_left", &"run"])
	check("run: run anim + run speed", anim == "run_w" and absf(speed - player.run_speed) < 0.01,
		"%s %.2f px/s" % [anim, speed])
	var expect_run_scale := player.run_speed / player.run_anim_reference_speed
	check("run: cycle sped up to match speed (no foot sliding)", absf(run_scale - expect_run_scale) < 0.01,
		"speed_scale %.2f (expected %.2f)" % [run_scale, expect_run_scale])
	_press([&"move_left"])
	await _wait(0.4)
	var walk_scale := player.sprite.speed_scale
	_release([&"move_left"])
	var expect_walk_scale := player.walk_speed / player.walk_anim_reference_speed
	check("walk: cycle sped up to match speed (no foot sliding)", absf(walk_scale - expect_walk_scale) < 0.01,
		"speed_scale %.2f (expected %.2f)" % [walk_scale, expect_walk_scale])
	await _wait(0.3)


func _test_frame_rate_independence() -> void:
	var dists := {}
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		world.spawn_player(Vector2i(8, 8))
		await _wait(0.1)
		var p0 := player.global_position
		_press([&"move_right"])
		await _wait(1.0)
		_release([&"move_right"])
		await _wait(0.3)
		dists[hz] = player.global_position.x - p0.x
	Engine.physics_ticks_per_second = 60
	var spread: float = absf(dists[30] - dists[120])
	check("frame-rate independent (30/60/120 Hz)", spread < 1.5,
		"1s walk: %.2f / %.2f / %.2f px" % [dists[30], dists[60], dists[120]])


func _test_camera_follow() -> void:
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.1)
	var c0 := camera.global_position
	_press([&"move_down", &"move_left"])
	await _wait(1.0)
	var moving_lag := camera.lag().length()
	_release([&"move_down", &"move_left"])
	await _wait(1.0)
	var settled_lag := camera.lag().length()
	var moved := camera.global_position.distance_to(c0)
	check("camera follows player", moved > 20.0, "camera moved %.1f px" % moved)
	check("camera keeps player near centre while moving", moving_lag < 12.0, "lag %.2f px" % moving_lag)
	check("camera re-centres when idle", settled_lag < 1.0, "lag %.2f px" % settled_lag)
	var offset := player.global_position - camera.global_position
	check("player offset from camera is whole pixels", offset == offset.round(), str(offset))


func _test_collision_blocks() -> void:
	# Blocks at (4,4) (5,4) (4,5). On screen, "north" from (7,7) crosses
	# (6,6) -> (5,5) and runs into the notch between the three blocks.
	world.spawn_player(Vector2i(7, 7))
	await _wait(0.1)
	var entered := false
	_press([&"move_up"])
	for i in 240:
		await get_tree().physics_frame
		if obstacles.is_blocked(terrain.cell_at(player.global_position)):
			entered = true
	var vel := player.ground_velocity.length()
	var anim := String(player.sprite.animation)
	if _shots_dir != "":
		_capture("collision_block")
	_release([&"move_up"])
	check("collision: never enters a solid block", not entered, "stopped at cell %s" % terrain.cell_at(player.global_position))
	check("collision: stops against the block", vel < 1.0, "ground speed %.2f" % vel)
	check("collision: idles facing the wall (no running in place)", anim == "idle_n", anim)
	# Diagonal push along a block face slides instead of sticking.
	world.spawn_player(Vector2i(6, 4))
	await _wait(0.1)
	var p0 := player.global_position
	_press([&"move_left"])
	await _wait(1.5)
	_release([&"move_left"])
	var cell := terrain.cell_at(player.global_position)
	check("collision: slides along block faces", player.global_position.distance_to(p0) > 10.0 and not obstacles.is_blocked(cell),
		"moved %.1f px, cell %s" % [player.global_position.distance_to(p0), cell])
	await _wait(0.3)


func _test_map_edge() -> void:
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.1)
	var off_ground := false
	_press([&"move_right", &"run"])
	for i in 360:
		await get_tree().physics_frame
		if not terrain.is_ground(terrain.cell_at(player.global_position)):
			off_ground = true
	_press([&"move_up"])  # push diagonally into the edge: must slide, not escape
	for i in 120:
		await get_tree().physics_frame
		if not terrain.is_ground(terrain.cell_at(player.global_position)):
			off_ground = true
	_release([&"move_right", &"move_up", &"run"])
	check("map edge: player stays on the ground", not off_ground, "cell %s" % terrain.cell_at(player.global_position))
	await _wait(0.3)


func _test_keyboard_interact() -> void:
	var before := _interacts
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().physics_frame
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(0.1)
	check("PC: E key triggers interact", _interacts == before + 1, "interacts=%d" % (_interacts - before))


func _test_pc_hides_touch_ui() -> void:
	check("PC: touch HUD hidden by default", not hud.visible)


# -------------------------------------------------------------------- touch
func _test_hud_layout() -> void:
	var vp := get_viewport().get_visible_rect()
	var j := hud.joystick.global_center()
	var b := hud.action_button.global_center()
	check("HUD visible with touch UI", hud.visible)
	check("joystick bottom-left", j.x < vp.size.x * 0.3 and j.y > vp.size.y * 0.6, str(j))
	check("action button bottom-right", b.x > vp.size.x * 0.7 and b.y > vp.size.y * 0.6, str(b))
	var j_rect := Rect2(j - Vector2.ONE * hud.joystick.base_radius, Vector2.ONE * hud.joystick.base_radius * 2)
	check("joystick inside safe area", hud.safe_rect.encloses(j_rect), "%s in %s" % [j_rect, hud.safe_rect])
	var sp := hud.sprint_button.global_center()
	var sr := hud.sprint_button.radius
	var sp_rect := Rect2(sp - Vector2.ONE * sr, Vector2.ONE * sr * 2)
	check("sprint button bottom-right, inside safe area", sp.x > vp.size.x * 0.6 and sp.y > vp.size.y * 0.55
		and hud.safe_rect.encloses(sp_rect), str(sp))
	check("sprint and A buttons don't overlap", sp.distance_to(b) > sr + hud.action_button.radius,
		"distance %.1f" % sp.distance_to(b))
	var centre := Rect2(vp.size * 0.3, vp.size * 0.4)
	check("centre of screen unobstructed", not centre.intersects(j_rect) and not centre.has_point(b)
		and not centre.intersects(sp_rect))
	if _shots_dir != "":
		_capture("hud")


func _test_joystick_directions() -> void:
	var r := hud.joystick.base_radius
	for dir: String in KEY_DIRS:
		world.spawn_player(Vector2i(8, 8))
		await _wait(0.05)
		var v := Direction8.to_vector(dir)  # screen-space stick direction
		await _touch_drag_to(0, hud.joystick.global_center(), hud.joystick.global_center() + v * r * 0.8)
		await _wait(0.4)
		var anim := String(player.sprite.animation)
		var speed := player.ground_velocity.length()
		var expected := player.walk_speed * (0.8 - 0.2) / (0.9 - 0.2)
		if _shots_dir != "" and dir == "ne":
			_capture("joystick_ne")
		await _touch_up(0, hud.joystick.global_center() + v * r * 0.8)
		check("joystick %s: sprite + walk anim" % dir, anim == "walk_" + dir, anim)
		check("joystick %s: analog speed" % dir, absf(speed - expected) < 0.5, "%.2f (expected %.2f)" % [speed, expected])
		await _wait(0.2)


func _test_joystick_analog_and_deadzone() -> void:
	var c := hud.joystick.global_center()
	var r := hud.joystick.base_radius
	# Dead zone: tiny deflection must not move.
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	await _touch_drag_to(0, c, c + Vector2(r * 0.12, 0))
	await _wait(0.3)
	check("dead zone: no movement", player.ground_velocity == Vector2.ZERO and String(player.sprite.animation).begins_with("idle"),
		"v=%s anim=%s" % [player.ground_velocity, player.sprite.animation])
	# Full tilt runs.
	await _touch_drag_to(0, c + Vector2(r * 0.12, 0), c + Vector2(r * 1.2, 0))
	await _wait(0.4)
	check("full tilt: run", String(player.sprite.animation) == "run_e" and absf(player.ground_velocity.length() - player.run_speed) < 0.01,
		"%s %.2f" % [player.sprite.animation, player.ground_velocity.length()])
	# Arbitrary 360° angles snap to the nearest of the 8 directions.
	for deg in [10.0, 100.0, 200.0, 290.0, 330.0]:
		var v := Vector2.RIGHT.rotated(deg_to_rad(deg))
		await _touch_drag_to(0, c, c + v * r * 0.7, false)
		await _wait(0.25)
		var expect := Direction8.from_vector(v)
		var mv := player.ground_velocity.normalized()
		check("360° input %d°: snapped to %s" % [deg, expect],
			player.facing == expect and mv.is_equal_approx(Direction8.to_vector(expect)),
			"facing=%s move=(%.2f,%.2f)" % [player.facing, mv.x, mv.y])
	await _touch_up(0, c)
	await _wait(0.3)


func _test_joystick_release_and_cancel() -> void:
	var c := hud.joystick.global_center()
	var r := hud.joystick.base_radius
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	await _touch_drag_to(0, c, c + Vector2(0, r * 0.8))
	await _wait(0.3)
	await _touch_up(0, c + Vector2(0, r * 0.8))
	await _wait(0.4)
	check("release: stick returns to centre", hud.joystick.value == Vector2.ZERO and not hud.joystick.is_active()
		and hud.joystick._knob == Vector2.ZERO, "value=%s knob=%s" % [hud.joystick.value, hud.joystick._knob])
	check("release: player idles facing s", String(player.sprite.animation) == "idle_s" and player.ground_velocity == Vector2.ZERO,
		String(player.sprite.animation))
	# Touch cancelled by the OS (e.g. notification shade, gesture).
	await _touch_drag_to(0, c, c + Vector2(-r * 0.8, 0))
	await _wait(0.3)
	var cancel := InputEventScreenTouch.new()
	cancel.index = 0
	cancel.position = _to_window(c + Vector2(-r * 0.8, 0))
	cancel.pressed = false
	cancel.canceled = true
	Input.parse_input_event(cancel)
	await _wait(0.3)
	check("cancel: stick released, player stops", hud.joystick.value == Vector2.ZERO and GameInput.virtual_move == Vector2.ZERO
		and player.ground_velocity == Vector2.ZERO, "value=%s" % hud.joystick.value)
	# Focus loss must release too.
	await _touch_drag_to(0, c, c + Vector2(r * 0.8, 0))
	await _wait(0.1)
	hud.joystick.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	GameInput.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait(0.3)
	check("focus loss: stick released", hud.joystick.value == Vector2.ZERO and player.ground_velocity == Vector2.ZERO)
	await _touch_up(0, c)  # stale finger-up after focus loss must be harmless
	await _wait(0.1)


func _test_multitouch_action_button() -> void:
	var c := hud.joystick.global_center()
	var r := hud.joystick.base_radius
	var b := hud.action_button.global_center()
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	var presses := hud.action_button.press_count
	var interacts := _interacts
	await _touch_drag_to(0, c, c + Vector2(r * 0.8, 0))       # finger 0: walk east
	await _wait(0.3)
	_touch(1, b, true)                                         # finger 1: press button
	await _wait(0.1)
	var held_action := Input.is_action_pressed(&"interact")
	var still_moving := String(player.sprite.animation) == "walk_e"
	if _shots_dir != "":
		_capture("multitouch")
	_touch(1, b, false)
	await _wait(0.1)
	check("action button responds to touch", hud.action_button.press_count == presses + 1 and held_action,
		"presses=%d action_held=%s" % [hud.action_button.press_count - presses, held_action])
	check("action button triggers interact", _interacts == interacts + 1, "interacts=%d" % (_interacts - interacts))
	check("multitouch: joystick keeps working during press", still_moving and not Input.is_action_pressed(&"interact"))
	# finger 0 is still down and still steers
	await _touch_drag_to(0, c + Vector2(r * 0.8, 0), c + Vector2(0, -r * 0.8), false)
	await _wait(0.3)
	check("multitouch: joystick finger still tracked", String(player.sprite.animation) == "walk_n", String(player.sprite.animation))
	await _touch_up(0, c + Vector2(0, -r * 0.8))
	await _wait(0.3)


func _test_sprint_key_mid_walk() -> void:
	# Walk, hold Shift while moving, let go: walk -> run -> walk without stopping.
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	_press([&"move_down"])
	await _wait(0.4)
	var a1 := String(player.sprite.animation)
	var v1 := player.ground_velocity.length()
	_press([&"run"])
	await _wait(0.4)
	var a2 := String(player.sprite.animation)
	var v2 := player.ground_velocity.length()
	if _shots_dir != "":
		_capture("sprint_key")
	_release([&"run"])
	await _wait(0.4)
	var a3 := String(player.sprite.animation)
	var v3 := player.ground_velocity.length()
	_release([&"move_down"])
	await _wait(0.3)
	check("sprint key: walk -> run anim + speed", a1 == "walk_s" and a2 == "run_s"
		and absf(v1 - player.walk_speed) < 0.01 and absf(v2 - player.run_speed) < 0.01,
		"%s %.0f -> %s %.0f" % [a1, v1, a2, v2])
	check("sprint key released: back to walk", a3 == "walk_s" and absf(v3 - player.walk_speed) < 0.01,
		"%s %.0f" % [a3, v3])
	check("sprint key alone (no direction): stays idle", await _shift_alone_is_idle())


func _shift_alone_is_idle() -> bool:
	_press([&"run"])
	await _wait(0.3)
	var ok := String(player.sprite.animation).begins_with("idle") and player.ground_velocity == Vector2.ZERO
	_release([&"run"])
	return ok


func _test_touch_sprint_button() -> void:
	var c := hud.joystick.global_center()
	var r := hud.joystick.base_radius
	var sp := hud.sprint_button.global_center()
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	await _touch_drag_to(0, c, c + Vector2(r * 0.8, 0))   # finger 0: walk east (not full tilt)
	await _wait(0.3)
	var a1 := String(player.sprite.animation)
	_touch(1, sp, true)                                    # finger 1: hold sprint
	await _wait(0.4)
	var a2 := String(player.sprite.animation)
	var v2 := player.ground_velocity.length()
	if _shots_dir != "":
		_capture("sprint_touch")
	_touch(1, sp, false)
	await _wait(0.4)
	var a3 := String(player.sprite.animation)
	await _touch_up(0, c + Vector2(r * 0.8, 0))
	await _wait(0.3)
	check("touch sprint button: run anim at run speed", a1 == "walk_e" and a2 == "run_e"
		and absf(v2 - player.run_speed) < 0.01, "%s -> %s %.0f" % [a1, a2, v2])
	check("touch sprint released: back to walk", a3 == "walk_e", a3)
	check("touch sprint: no interact triggered", not Input.is_action_pressed(&"run"))


func _test_touch_outside_ignored() -> void:
	var vp := get_viewport().get_visible_rect().size
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	await _touch_drag_to(2, vp / 2.0, vp / 2.0 + Vector2(40, 0))
	await _wait(0.3)
	check("touch outside controls: no movement", player.ground_velocity == Vector2.ZERO and not hud.joystick.is_active())
	await _touch_up(2, vp / 2.0 + Vector2(40, 0))


func _test_flicker_resistance() -> void:
	var c := hud.joystick.global_center()
	var r := hud.joystick.base_radius
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	await _touch_drag_to(0, c, c + Vector2.RIGHT.rotated(deg_to_rad(18.0)) * r * 0.8)
	await _wait(0.2)
	var changes := 0
	player.facing_changed.connect(func(_d: String) -> void: changes += 1, CONNECT_REFERENCE_COUNTED)
	var conn: Dictionary = player.facing_changed.get_connections().back()
	# Jitter ±5° around the E/SE boundary (22.5°) every frame for one second.
	for i in 60:
		var deg := 22.5 + (5.0 if i % 2 == 0 else -5.0)
		_drag(0, c + Vector2.RIGHT.rotated(deg_to_rad(deg)) * r * 0.8)
		await get_tree().physics_frame
	player.facing_changed.disconnect(conn.callable)
	await _touch_up(0, c)
	check("no direction flicker near sector boundary", changes <= 1, "facing changes=%d over 60 jittered frames" % changes)
	await _wait(0.3)


func _test_keyboard_and_touch_coexist() -> void:
	var c := hud.joystick.global_center()
	var r := hud.joystick.base_radius
	world.spawn_player(Vector2i(8, 8))
	await _wait(0.05)
	_press([&"move_left"])
	await _wait(0.2)
	await _touch_drag_to(0, c, c + Vector2(0, r * 0.5))  # weaker stick input
	await _wait(0.2)
	await _touch_up(0, c + Vector2(0, r * 0.5))
	await _wait(0.3)
	var anim := String(player.sprite.animation)
	_release([&"move_left"])
	check("PC keys keep working with touch HUD active", anim == "walk_w" and Input.is_action_pressed(&"move_left") == false,
		"after touch release: %s" % anim)
	await _wait(0.2)


func _test_assets_preserved() -> void:
	var frames := player.sprite.sprite_frames
	var ok := true
	for st in ["idle", "walk", "run"]:
		for d in ["n", "ne", "e", "se", "s", "sw", "w", "nw"]:
			var name := StringName("%s_%s" % [st, d])
			var expect := 4 if st == "idle" else 8
			if not frames.has_animation(name) or frames.get_frame_count(name) != expect:
				ok = false
	var tex := frames.get_frame_texture(&"walk_s", 0) as AtlasTexture
	check("PixelLab animations loaded (3 x 8 dirs)", ok)
	check("sprite frames 68x68, nearest filtering", tex.region.size == Vector2(68, 68)
		and player.sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, str(tex.region.size))


# ------------------------------------------------------------ launcher test
func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


## Checks what the launcher did before this scene started (see launcher.gd).
func _run_launcher_checks() -> void:
	var res: Dictionary = Engine.get_meta(&"launcher_result", {})
	var expect := _arg("--expect-launcher=")
	check("launcher: result '%s'" % expect, str(res.get("status", "")) == expect, str(res))
	var ev := _arg("--expect-content-version=")
	if ev != "":
		var running := str(Engine.get_meta(&"content_version", ""))
		var info = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
		check("launcher: game runs content v%s" % ev, running == ev and info.version == ev,
			"meta=%s build_info=%s" % [running, info.version])
	var ws := _arg("--expect-walk-speed=")
	if ws != "":
		check("launcher: updated gameplay code active (walk_speed)", is_equal_approx(player.walk_speed, ws.to_float()),
			"walk_speed=%.1f" % player.walk_speed)
	var label: Label = world.find_child("VersionLabel", true, false)
	check("in-game version label", label != null and label.text == "v" + str(Engine.get_meta(&"content_version", "")),
		label.text if label else "missing")
	if _shots_dir != "":
		_capture("game_after_launcher")

# ------------------------------------------------------------------ helpers
func _press(actions: Array) -> void:
	for a: StringName in actions:
		Input.action_press(a)


func _release(actions: Array) -> void:
	for a: StringName in actions:
		Input.action_release(a)


func _wait(seconds: float) -> void:
	var frames := int(round(seconds * Engine.physics_ticks_per_second))
	for i in frames:
		await get_tree().physics_frame


## Viewport (canvas) coordinates -> window pixels, like real OS touch events.
func _to_window(p: Vector2) -> Vector2:
	var st: Array = hud._stretch()
	return p * float(st[0]) + st[1]


func _touch(index: int, vp_pos: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = _to_window(vp_pos)
	t.pressed = down
	Input.parse_input_event(t)


func _drag(index: int, vp_pos: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = index
	d.position = _to_window(vp_pos)
	Input.parse_input_event(d)


## Finger down at `from` (optional), then drag in a few steps to `to`.
func _touch_drag_to(index: int, from: Vector2, to: Vector2, press := true) -> void:
	if press:
		_touch(index, from, true)
		await get_tree().physics_frame
	for i in range(1, 5):
		_drag(index, from.lerp(to, i / 4.0))
		await get_tree().physics_frame


func _touch_up(index: int, vp_pos: Vector2) -> void:
	_touch(index, vp_pos, false)
	await get_tree().physics_frame


func _capture(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shots_dir, name])
