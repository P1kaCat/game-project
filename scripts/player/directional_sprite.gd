class_name DirectionalSprite
extends AnimatedSprite2D
## 8-direction animated sprite driven by a metadata JSON exported from PixelLab
## (see tools/pixellab/export_assets.py).
##
## Every animation listed in the metadata becomes SpriteFrames animations named
## "<anim>_<dir>" (e.g. "walk_se"), sliced from the sprite sheet. The node origin
## is the character's foot contact point, so placing the parent node on a ground
## position anchors the feet exactly there.

@export_file("*.json") var metadata_path := "res://assets/characters/player/player_animations.json"

var current_state := ""
var current_dir := Direction8.S
var _meta: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	_load_metadata()
	play_state("idle", Direction8.S)


func _load_metadata() -> void:
	var text := FileAccess.get_file_as_string(metadata_path)
	_meta = JSON.parse_string(text)
	assert(_meta != null, "Cannot parse %s" % metadata_path)

	var fw: int = _meta.frame_width
	var fh: int = _meta.frame_height
	# Put the foot pivot on the node origin.
	offset = -Vector2(_meta.pivot.x, _meta.pivot.y)

	var base_dir := metadata_path.get_base_dir()
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var dirs: Array = _meta.directions
	for anim_name: String in _meta.animations:
		var anim: Dictionary = _meta.animations[anim_name]
		var sheet: Texture2D = load(base_dir.path_join(anim.sheet))
		var rows: Array = anim.rows
		for dir_code: String in dirs:
			var row := rows.find(dir_code)
			var sf_name := StringName("%s_%s" % [anim_name, dir_code])
			frames.add_animation(sf_name)
			frames.set_animation_loop(sf_name, anim.loop)
			frames.set_animation_speed(sf_name, 1000.0 / float(anim.frame_duration_ms))
			for i in int(anim.frames):
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(i * fw, row * fh, fw, fh)
				frames.add_frame(sf_name, atlas)
	sprite_frames = frames


func has_state(state: String) -> bool:
	return _meta.animations.has(state)


## Plays `state` facing `dir`. Turning while staying in the same state keeps the
## current frame and progress, so the walk cycle does not restart on every turn.
func play_state(state: String, dir: String) -> void:
	if state == current_state and dir == current_dir:
		return
	var anim := StringName("%s_%s" % [state, dir])
	if state == current_state:
		var f := frame
		var p := frame_progress
		play(anim)
		set_frame_and_progress(f, p)
	else:
		play(anim)
	current_state = state
	current_dir = dir
