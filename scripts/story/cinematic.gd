extends Control
## Opening cinematic, built from layered pixel-art illustrations (never a
## video). All content comes from data/story/intro.json (localized as
## intro.<locale>.json); this script only knows how to present it:
##
##   scene: {image, pan: [from, to] (0 = top of the art, 1 = bottom), pan_delay,
##           fade_in, fade_in_color, fade_out_color, fog, motes, ambience, beats}
##   beat:  {line, speaker}   subtitle (speaker styles in "speakers")
##          {wait}            silence (seconds)
##          {sfx} {shake} {flash}
##          {crossfade: {image, time}}         same framing, changed art
##          {runes: {center, radius, count, speed, fade}} / {runes_off: t}
##          {dim: {amount, time}}             slow darkening
##          {fade_out: t}                     to black, mid-scene
##          {title: {image, hold}} {caption: {text, hold}}   on black
##
## Unified framing: every illustration is ART_SIZE pixels, shown 1:1 inside the
## same letterbox on black, whatever the screen. No dialogue portraits here:
## speech is subtitled.
##
## Input: a short press (tap / click / Enter) advances the current line;
## holding HOLD_TO_SKIP seconds skips everything. Watching or skipping leads
## to the same story state.

signal finished(skipped: bool)

const DATA := "res://data/story/intro.json"
const WORLD_SCENE := "res://scenes/main.tscn"
const ART_SIZE := Vector2(480, 254)
const HOLD_TO_SKIP := 1.2
const BAR_TOP := 22.0
const BAR_BOTTOM := 40.0

var skipped := false
var done := false
var current_scene := -1
var current_line := ""
var current_speaker := ""
var lines_shown := 0
var lines_log: Array[String] = []

var _data := {}
var _speakers := {}
var _image: TextureRect
var _image_b: TextureRect
var _runes: RuneRing
var _dim: ColorRect
var _fog_layers: Array[Control] = []
var _motes: CPUParticles2D
var _bars: Array[ColorRect] = []
var _subtitle: Label
var _flash: ColorRect
var _title: TextureRect
var _caption: Label
var _fade: ColorRect
var _skip_hint: SkipHint
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
	_speakers = _data.get("speakers", {})
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
	_image = _art_rect()
	_image_b = _art_rect()
	_image_b.modulate.a = 0.0
	_runes = RuneRing.new()
	add_child(_runes)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
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
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_title = TextureRect.new()
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.modulate.a = 0.0
	add_child(_title)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_color", UITheme.TEXT)
	_caption.add_theme_font_size_override("font_size", UITheme.TITLE_FONT_SIZE)
	_caption.modulate.a = 0.0
	add_child(_caption)
	_skip_hint = SkipHint.new()
	_skip_hint.modulate.a = 0.0
	add_child(_skip_hint)


func _art_rect() -> TextureRect:
	var t := TextureRect.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.size = ART_SIZE
	add_child(t)
	return t


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
	_dim.position = win.position
	_dim.size = win.size
	_subtitle.size = Vector2(minf(440.0, safe.size.x - 24), BAR_BOTTOM - 4)
	_subtitle.position = Vector2((vp.x - _subtitle.size.x) / 2.0, win.end.y + 2).round()
	for f in _fog_layers:
		f.size.x = vp.x
	if _title.texture:
		_title.size = _title.texture.get_size() * 2
		_title.position = ((vp - _title.size) / 2.0).round()
	_caption.size = Vector2(vp.x, 16)
	_caption.position = Vector2(0, roundf(vp.y / 2.0 - 8))
	_skip_hint.position = Vector2(safe.end.x - 104, safe.position.y + 4).round()
	_skip_hint.size = Vector2(100, 16)
	if _motes:
		_motes.position = win.get_center()
		_motes.emission_rect_extents = win.size / 2.0
	_place_art()


## Art origin on screen (top-left of the ART_SIZE illustration).
func _art_origin() -> Vector2:
	var win := _window()
	var travel := maxf(0.0, ART_SIZE.y - win.size.y)
	var shake := Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)) if _shake > 0.0 else Vector2.ZERO
	return (Vector2((win.size.x - ART_SIZE.x) / 2.0, win.position.y - travel * _pan) + shake).round()


func _place_art() -> void:
	var o := _art_origin()
	_image.position = o
	_image_b.position = o
	_runes.position = o
	_runes.size = ART_SIZE


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 6.0)
	_place_art()
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
	_skip_hint.progress = clampf(_hold / HOLD_TO_SKIP, 0.0, 1.0)


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
	_set_art(_image, str(sc.image))
	_image.modulate.a = 1.0
	_image_b.modulate.a = 0.0
	_runes.intensity = 0.0
	_dim.color.a = 0.0
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
	_fade.color = Color.WHITE if sc.get("fade_in_color", "") == "white" else Color.BLACK
	_fade.color.a = 1.0
	await _tween(_fade, "color:a", 0.0, float(sc.get("fade_in", 1.5)))
	for beat: Dictionary in sc.get("beats", []):
		if skipped:
			return
		await _beat(beat)
	if skipped:
		return
	await _hide_subtitle()
	if _fade.color.a < 1.0:
		var white: bool = sc.get("fade_out_color", "") == "white"
		_fade.color = Color(Color.WHITE if white else Color.BLACK, _fade.color.a)
		await _tween(_fade, "color:a", 1.0, 1.6 if white else 1.2)


func _beat(b: Dictionary) -> void:
	if b.has("sfx"):
		Audio.sfx(str(b.sfx))
	if b.has("shake"):
		_shake = float(b.shake)
	if b.has("flash"):
		_flash.color.a = 0.9
		create_tween().tween_property(_flash, "color:a", 0.0, float(b.flash))
	if b.has("crossfade"):
		var cf: Dictionary = b.crossfade
		_set_art(_image_b, str(cf.image))
		create_tween().tween_property(_image_b, "modulate:a", 1.0, float(cf.get("time", 2.0)))
	if b.has("runes"):
		var r: Dictionary = b.runes
		_runes.center = Vector2(r.center[0], r.center[1])
		_runes.radius = Vector2(r.radius[0], r.radius[1])
		_runes.count = int(r.get("count", 18))
		_runes.speed = float(r.get("speed", 0.05))
		create_tween().tween_property(_runes, "intensity", float(r.get("intensity", 1.0)), float(r.get("fade", 2.0)))
	if b.has("runes_off"):
		create_tween().tween_property(_runes, "intensity", 0.0, float(b.runes_off))
	if b.has("dim"):
		create_tween().tween_property(_dim, "color:a", float(b.dim.amount), float(b.dim.get("time", 4.0)))
	if b.has("line") or b.has("say") or b.has("voice"):
		var speaker := str(b.get("speaker", "authority" if b.has("voice") else "narrator"))
		await _line(str(b.get("line", b.get("say", b.get("voice", "")))), speaker)
	if b.has("fade_out"):
		await _hide_subtitle()
		_fade.color = Color(0, 0, 0, _fade.color.a)
		await _tween(_fade, "color:a", 1.0, float(b.fade_out))
	if b.has("title"):
		await _show_title(load(str(b.title.image)), float(b.title.get("hold", 3.0)))
	if b.has("caption"):
		await _show_caption(str(b.caption.text), float(b.caption.get("hold", 3.0)))
	if b.has("wait"):
		await _wait(float(b.wait), false)


func _line(text: String, speaker: String) -> void:
	await _hide_subtitle()
	if skipped:
		return
	var style: Dictionary = _speakers.get(speaker, {})
	current_line = text
	current_speaker = speaker
	lines_shown += 1
	lines_log.append(text)
	_subtitle.text = ("« %s »" % text) if style.get("quotes", false) else text
	_subtitle.add_theme_color_override("font_color", Color.html(str(style.get("color", "#e8dec4"))))
	_advance = false
	await _tween(_subtitle, "modulate:a", 1.0, 0.4)
	# reading time: ~15 characters / second, never rushed
	await _wait(clampf(1.4 + text.length() * 0.06, 2.4, 6.5), true)


func _hide_subtitle() -> void:
	if _subtitle.modulate.a > 0.0:
		await _tween(_subtitle, "modulate:a", 0.0, 0.3)
		await _wait(0.2, false)


func _show_title(tex: Texture2D, hold: float) -> void:
	await _hide_subtitle()
	_title.texture = tex
	_layout()
	_title.move_to_front()
	await _tween(_title, "modulate:a", 1.0, 1.8)
	await _wait(hold, false)
	await _tween(_title, "modulate:a", 0.0, 1.2)


func _show_caption(text: String, hold: float) -> void:
	_caption.text = text
	_caption.move_to_front()
	current_line = text
	await _tween(_caption, "modulate:a", 1.0, 1.2)
	await _wait(hold, false)
	await _tween(_caption, "modulate:a", 0.0, 1.2)


func _set_art(rect: TextureRect, path: String) -> void:
	var tex: Texture2D = load(path)
	if tex and Vector2(tex.get_size()) != ART_SIZE:
		push_warning("Cinematic art %s is %s, expected %s" % [path, tex.get_size(), ART_SIZE])
	rect.texture = Atmosphere.dither_edges(tex, 10) if tex else null
	rect.size = ART_SIZE


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
		move_child(_motes, _dim.get_index())


func _add_fog(tex: Texture2D, speed: float, y: float) -> void:
	var f := Atmosphere.ScrollLayer.new(tex, speed)
	f.bob = 2.0
	f.position = Vector2(0, roundf(y))
	f.size = Vector2(get_viewport().get_visible_rect().size.x, tex.get_height())
	add_child(f)
	move_child(f, _dim.get_index())
	_fog_layers.append(f)


## Estimated scene length (pans span the whole scene).
func _estimate(sc: Dictionary) -> float:
	var t := float(sc.get("fade_in", 1.5)) + 1.2
	for b: Dictionary in sc.get("beats", []):
		t += float(b.get("wait", 0.0))
		var text := str(b.get("line", b.get("say", b.get("voice", ""))))
		if text != "":
			t += clampf(1.4 + text.length() * 0.06, 2.4, 6.5) + 0.9
	return t


func _tween(node: Object, prop: String, value: float, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, prop, value, t)
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
	GameState.complete_intro()
	finished.emit(was_skipped)
	Audio.ambience("", 1.0)
	SceneFade.go(get_tree(), WORLD_SCENE, 0.8 if was_skipped else 0.01, 1.4)


func _notification(what: int) -> void:
	MenuKit.forward_back_button(what)
