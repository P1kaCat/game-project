class_name Audio
extends RefCounted
## Sound helper: one-shot effects on the "SFX" bus and a looping ambience on
## the "Music" bus (cross-faded). Sounds are optional files in
## res://assets/audio/<name>.wav; a missing file is silently ignored.

const DIR := "res://assets/audio/"

static var _sfx: Array[AudioStreamPlayer] = []
static var _amb: AudioStreamPlayer
static var _amb_name := ""


static func ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


static func _stream(name: String) -> AudioStream:
	var path := DIR + name + ".wav"
	return load(path) if ResourceLoader.exists(path) else null


static func _root() -> Node:
	return Engine.get_main_loop().root if Engine.get_main_loop() else null


static func sfx(name: String, volume_db := 0.0) -> void:
	var s := _stream(name)
	var root := _root()
	if s == null or root == null:
		return
	ensure_buses()
	for q in _sfx:
		if is_instance_valid(q) and q.is_inside_tree() and not q.playing:
			q.stream = s
			q.volume_db = volume_db
			q.play()
			return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.stream = s
	p.volume_db = volume_db
	p.autoplay = true
	root.add_child.call_deferred(p)
	_sfx.append(p)


## Starts (cross-fades to) a looping ambience; "" fades out.
static func ambience(name: String, fade := 1.5, volume_db := 0.0) -> void:
	if name == _amb_name:
		return
	var root := _root()
	if root == null:
		return
	ensure_buses()
	_amb_name = name
	var old := _amb
	if old and is_instance_valid(old) and old.is_inside_tree():
		var tw := old.create_tween()
		tw.tween_property(old, "volume_db", -40.0, fade)
		tw.tween_callback(old.queue_free)
	_amb = null
	var s := _stream(name)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.stream = s
	p.volume_db = -40.0
	p.autoplay = true
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.play)  # loop
	p.ready.connect(func() -> void: p.create_tween().tween_property(p, "volume_db", volume_db, fade))
	root.add_child.call_deferred(p)
	_amb = p


static func current_ambience() -> String:
	return _amb_name
