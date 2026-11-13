class_name SceneFade
extends RefCounted
## Fade-out -> change scene -> fade-in, through a layer on the root viewport
## that survives the scene change. One transition at a time.

static var _busy := false


static func go(tree: SceneTree, path: String, out_time := 0.6, in_time := 0.6, color := Color(0.02, 0.02, 0.03)) -> void:
	if _busy:
		return
	_busy = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(color, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP  # no clicks during the fade
	layer.add_child(rect)
	tree.root.add_child(layer)
	var tw := layer.create_tween()
	tw.tween_property(rect, "color:a", 1.0, out_time)
	await tw.finished
	tree.paused = false
	tree.change_scene_to_file(path)
	await tree.process_frame
	await tree.process_frame
	var tw2 := layer.create_tween()
	tw2.tween_property(rect, "color:a", 0.0, in_time)
	await tw2.finished
	layer.queue_free()
	_busy = false


static func is_busy() -> bool:
	return _busy
