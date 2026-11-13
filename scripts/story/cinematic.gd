extends Control
## Opening cinematic ("L'Inscriptible"), built from layered pixel-art
## illustrations, never a video. Everything it shows comes from
## data/story/intro.json (localized as intro.<locale>.json): per scene an
## illustration shown 1:1 inside letterbox bars with a slow vertical pan,
## dithered fog / motes for depth, and timed beats (narration, the voice of
## the authority, silences, flash, portrait, sounds, the title).
##
## Input: a short press (tap / click / Enter) advances the current line;
## holding for HOLD_TO_SKIP seconds skips the whole sequence. Either way the
## game state is initialized the same (intro_seen, awakening pending) and the
## game continues in the starting area.

signal finished(skipped: bool)

const DATA := "res://data/story/intro.json"
const WORLD_SCENE := "res://scenes/main.tscn"
const HOLD_TO_SKIP := 1.2
const BAR_TOP := 22.0
const BAR_BOTTOM := 40.0
const VOICE_COLOR := Color(0.72, 0.78, 0.88)

var skipped := false
var done := false
var current_scene := -1
var current_line := ""
var lines_shown := 0

var _data := {}
var _image: TextureRect
var _fog_layers: Array[Control] = []
var _motes: CPUParticles2D
var _portrait: Control
var _bars: Array[ColorRect] = []
var _subtitle: Label
var _fade: ColorRect
var _flash: ColorRect
var _title: TextureRect
var _skip_hint: Control
var _pan := 0.0
var _pan_tween: Tween
var _shake := 0.0
var _hold := 0.0
var _press_t := -1.0
var _pointer_down := false
var _advance := false
var _hint_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	var raw = JSON.parse_string(FileAccess.get_file_as_string(Loc.localized_path(DATA)))
	_data = raw if raw is Dictionary else {}
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	if not GameState.active:
		GameState.new_game()
	_run()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_image = TextureRect.new()
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_portrait = Control.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false
	add_child(_portrait)
	for i in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(b)
		_bars.append(b)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate.a = 0.0
	add_child(_subtitle)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_title = TextureRect.new()
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.modulate.a = 0.0
	add_child(_title)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_skip_hint = SkipHint.new()
	_skip_hint.modulate.a = 0.0
	add_child(_skip_hint)


func _window() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	return Rect2(0, BAR_TOP, vp.x, vp.y - BAR_TOP - BAR_BOTTOM)


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var safe := SafeArea.viewport_rect(get_viewport())
	var win := _window()
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(vp.x, BAR_TOP)
	_bars[1].position = Vector2(0, win.end.y)
	_bars[1].size = Vector2(vp.x, BAR_BOTTOM)
	_subtitle.size = Vector2(minf(440.0, safe.size.x - 24), BAR_BOTTOM - 4)
	_subtitle.position = Vector2((vp.x - _subtitle.size.x) / 2.0, win.end.y + 2).round()
	for f in _fog_layers:
		f.size.x = vp.x
	if _title.texture:
		_title.size = _title.texture.get_size() * 2
		_title.position = ((vp - _title.size) / 2.0).round()
	_skip_hint.position = Vector2(safe.end.x - 104, safe.position.y + 4).round()
	_skip_hint.size = Vector2(100, 16)
	_place_image()
	if _motes:
		_motes.position = win.get_center()
		_motes.emission_rect_extents = win.size / 2.0


func _place_image() -> void:
	if _image.texture == null:
		return
	var win := _window()
	var s := _image.texture.get_size()
	_image.size = s
	var travel := maxf(0.0, s.y - win.size.y)
	var shake := Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)) if _shake > 0.0 else Vector2.ZERO
	_image.position = (Vector2((win.size.x - s.x) / 2.0, win.position.y - travel * _pan) + shake).round()
	if _portrait.visible:
		_portrait.position = Vector2(roundf(win.position.x + win.size.x / 2.0 + 60), roundf(win.position.y + (win.size.y - 136) / 2.0))


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 6.0)
	_place_image()
	# hold-to-skip / tap-to-advance
	var held := _pointer_down or Input.is_action_pressed(&"ui_accept") or Input.is_action_pressed(&"interact") \
		or Input.is_action_pressed(&"ui_cancel")
	if held and not done:
		if _press_t < 0.0:
			_press_t = 0.0
		_press_t += delta
		_hold = _press_t
		_hint_t = 2.0
		if _hold >= HOLD_TO_SKIP:
			skip()
	else:
		if _press_t >= 0.0 and _press_t < 0.35:
			_advance = true
		_press_t = -1.0
		_hold = 0.0
		_hint_t = maxf(0.0, _hint_t - delta)
	_skip_hint.modulate.a = move_toward(_skip_hint.modulate.a, 1.0 if _hint_t > 0.0 and not done else 0.0, delta * 4.0)
	(_skip_hint as SkipHint).progress = clampf(_hold / HOLD_TO_SKIP, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer_down = event.pressed
		_hint_t = 2.0
	elif event is InputEventScreenTouch:
		_pointer_down = event.pressed
		_hint_t = 2.0
	elif event is InputEventKey and event.pressed:
		_hint_t = 2.0


# ------------------------------------------------------------------ sequence
func _run() -> void:
	var scenes: Array = _data.get("scenes", [])
	for i in scenes.size():
		if skipped:
			return
		current_scene = i
		await _play_scene(scenes[i])
	if not skipped:
		_finish(false)


func _play_scene(sc: Dictionary) -> void:
	var tex: Texture2D = load(str(sc.image))
	_image.texture = Atmosphere.dither_edges(tex, 10)
	_portrait.visible = false
	for c in _portrait.get_children():
		c.queue_free()
	_set_atmosphere(str(sc.get("fog", "none")), str(sc.get("motes", "")))
	if sc.has("ambience"):
		Audio.ambience(str(sc.ambience), 2.0, -6.0)
	var pan: Array = sc.get("pan", [0.0, 0.0])
	_pan = float(pan[0])
	_layout()
	if _pan_tween:
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.tween_interval(float(sc.get("pan_delay", 0.0)))
	_pan_tween.tween_property(self, "_pan", float(pan[1]), maxf(4.0, _estimate(sc) - float(sc.get("pan_delay", 0.0)))) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# fade in from black / white
	_fade.color = Color.WHITE if sc.get("fade_in_color", "") == "white" else Color.BLACK
	_fade.color.a = 1.0
	await _tween_alpha(_fade, 0.0, float(sc.get("fade_in", 1.5)))
	for beat: Dictionary in sc.get("beats", []):
		if skipped:
			return
		await _beat(beat)
	if skipped:
		return
	await _hide_subtitle()
	_fade.color = Color.WHITE if sc.get("fade_out_color", "") == "white" else Color.BLACK
	_fade.color.a = 0.0
	await _tween_alpha(_fade, 1.0, 1.6 if sc.get("fade_out_color", "") == "white" else 1.2)


func _beat(b: Dictionary) -> void:
	if b.has("sfx"):
		Audio.sfx(str(b.sfx))
	if b.has("shake"):
		_shake = float(b.shake)
	if b.has("flash"):
		_flash.color.a = 0.9
		create_tween().tween_property(_flash, "color:a", 0.0, float(b.flash))
	if b.has("portrait"):
		_show_portrait(load(str(b.portrait)))
	if b.has("say"):
		await _line(str(b.say), false)
	elif b.has("voice"):
		await _line(str(b.voice), true)
	elif b.has("title"):
		await _show_title(load(str(b.title)), float(b.get("hold", 3.0)))
	if b.has("wait"):
		await _wait(float(b.wait), false)


func _line(text: String, voice: bool) -> void:
	await _hide_subtitle()
	if skipped:
		return
	current_line = text
	lines_shown += 1
	_subtitle.text = ("« %s »" % text) if voice else text
	_subtitle.add_theme_color_override("font_color", VOICE_COLOR if voice else UITheme.TEXT)
	_advance = false
	await _tween_alpha(_subtitle, 1.0, 0.4)
	# reading time: ~15 characters / second, never rushed
	await _wait(clampf(1.4 + text.length() * 0.06, 2.4, 6.5), true)


func _hide_subtitle() -> void:
	if _subtitle.modulate.a > 0.0:
		await _tween_alpha(_subtitle, 0.0, 0.3)
		await _wait(0.2, false)


func _show_portrait(tex: Texture2D) -> void:
	var frame := NinePatchRect.new()
	frame.texture = load("res://assets/ui/portrait_frame.png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_patch_margin(side, 8)
	frame.size = Vector2(136, 136)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.position = Vector2(4, 4)
	pic.size = Vector2(128, 128)
	_portrait.add_child(pic)
	_portrait.add_child(frame)
	_portrait.visible = true
	_portrait.modulate.a = 0.0
	_place_image()
	create_tween().tween_property(_portrait, "modulate:a", 1.0, 1.4)


func _show_title(tex: Texture2D, hold: float) -> void:
	await _hide_subtitle()
	_title.texture = tex
	_layout()
	var tw := create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)
	await tw.finished
	await _wait(hold, false)
	_fade.color = Color(0, 0, 0, 0)
	_fade.move_to_front()
	await _tween_alpha(_fade, 1.0, 1.6)


func _set_atmosphere(fog: String, motes: String) -> void:
	for f in _fog_layers:
		f.queue_free()
	_fog_layers.clear()
	if _motes:
		_motes.queue_free()
		_motes = null
	var win := _window()
	match fog:
		"low":
			_add_fog(Atmosphere.fog_texture(256, 56, 3, 0.55, Color(0.66, 0.67, 0.72, 0.30)), 4.0, win.end.y - 56)
		"void":
			_add_fog(Atmosphere.fog_texture(256, 80, 11, 0.5, Color(0.55, 0.50, 0.72, 0.28)), -10.0, win.position.y + 10)
			_add_fog(Atmosphere.fog_texture(320, 80, 12, 0.5, Color(0.45, 0.42, 0.60, 0.32)), 16.0, win.end.y - 80)
	var col := {"dust": Color(0.9, 0.86, 0.74, 0.55), "sparks": Color(0.92, 0.94, 1.0, 0.9), "void": Color(0.75, 0.70, 0.95, 0.7)}
	if col.has(motes):
		_motes = Atmosphere.motes(win, 40 if motes == "sparks" else 24, col[motes])
		if motes != "dust":
			_motes.initial_velocity_min = 10.0
			_motes.initial_velocity_max = 26.0
		add_child(_motes)
		move_child(_motes, _image.get_index() + 1)


func _add_fog(tex: Texture2D, speed: float, y: float) -> void:
	var f := Atmosphere.ScrollLayer.new(tex, speed)
	f.bob = 2.0
	f.position = Vector2(0, roundf(y))
	f.size = Vector2(get_viewport().get_visible_rect().size.x, tex.get_height())
	add_child(f)
	move_child(f, _image.get_index() + 1)
	_fog_layers.append(f)


## Estimated scene length (pans span the whole scene).
func _estimate(sc: Dictionary) -> float:
	var t := float(sc.get("fade_in", 1.5)) + 1.2
	for b: Dictionary in sc.get("beats", []):
		t += float(b.get("wait", 0.0)) + float(b.get("hold", 0.0))
		var text := str(b.get("say", b.get("voice", "")))
		if text != "":
			t += clampf(1.4 + text.length() * 0.06, 2.4, 6.5) + 0.9
	return t


func _tween_alpha(node: CanvasItem, a: float, t: float) -> void:
	var tw := create_tween()
	if node is ColorRect:
		tw.tween_property(node, "color:a", a, t)
	else:
		tw.tween_property(node, "modulate:a", a, t)
	while tw.is_running() and not skipped:
		await get_tree().process_frame


## Waits `t` seconds; a tap ends a reading pause early (skippable lines).
func _wait(t: float, can_advance: bool) -> void:
	var left := t
	while left > 0.0 and not skipped:
		await get_tree().process_frame
		left -= get_process_delta_time()
		if can_advance and _advance:
			_advance = false
			return


# ---------------------------------------------------------------- ending
func skip() -> void:
	if done:
		return
	skipped = true
	Audio.sfx("ui_confirm", -6.0)
	_finish(true)


func _finish(was_skipped: bool) -> void:
	if done:
		return
	done = true
	if _pan_tween:
		_pan_tween.kill()
	GameState.flags["intro_seen"] = true
	GameState.awakening_pending = true
	GameState.has_position = false
	finished.emit(was_skipped)
	Audio.ambience("", 1.0)
	SceneFade.go(get_tree(), WORLD_SCENE, 0.8 if was_skipped else 0.01, 1.4)


func _notification(what: int) -> void:
	MenuKit.forward_back_button(what)


## "Maintenir pour passer" with a pixel ring that fills while held.
class SkipHint extends Control:
	var progress := 0.0:
		set(v):
			if v != progress:
				progress = v
				queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := get_theme_default_font()
		var text := Loc.t("cinematic.hold_to_skip")
		var fs := UITheme.small_font_size()
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c := Vector2(size.x - 7, 8)
		draw_string(font, Vector2(size.x - 16 - w, 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.TEXT, 0.8))
		# 24-segment ring, radius 5: silver track, brass fill
		for i in 24:
			var a := -PI / 2.0 + TAU * i / 24.0
			var p := (c + Vector2(cos(a), sin(a)) * 5.0).round()
			var on := float(i) / 24.0 < progress
			draw_rect(Rect2(p, Vector2.ONE), UITheme.GOLD if on else Color(UITheme.SILVER, 0.35))
