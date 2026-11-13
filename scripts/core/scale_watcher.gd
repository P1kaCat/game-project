class_name ScaleWatcher
extends Node
## Keeps the pixel-perfect scaling in sync with the real window, whatever the
## platform does with its resize events.
##
## The PixelScaler autoload re-applies the scaling on the root's size_changed
## signal and reads DisplayServer.window_get_size(). On some systems (seen on
## Windows when leaving fullscreen or maximizing) that signal is missed or the
## reported size is stale, so the picture kept its old scale: drawn too big
## (cropped) or too small, and clicks landed beside the buttons.
##
## This node checks every frame that the internal resolution matches the rule
## below for the size the engine actually stretches to (root.size), and fixes
## it if not (only a comparison when nothing changed).
## Content-side on purpose, so it ships as a hot update.

## Adds the watcher under the root once (survives scene changes).
static func ensure(tree: SceneTree) -> void:
	if tree == null or tree.root.has_node(^"ScaleWatcher"):
		return
	var w := ScaleWatcher.new()
	w.name = "ScaleWatcher"
	w.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(w)


func _process(_delta: float) -> void:
	apply_now()


## Same rule as PixelScaler: integer factor k whose internal height is closest
## to the target, internal size = window / k (no bars, no fractional pixels).
func apply_now() -> void:
	var root := get_tree().root
	var win := Vector2i(root.size)
	if win.x <= 0 or win.y <= 0:
		return
	var scaler := root.get_node_or_null(^"PixelScaler")
	var target := int(scaler.get(&"target_height")) if scaler else 270
	var min_h := int(scaler.get(&"min_height")) if scaler else 200
	var k := maxi(1, roundi(float(win.y) / target))
	while k > 1 and win.y / k < min_h:
		k -= 1
	var size := Vector2i(win.x / k, win.y / k)
	if scaler:
		scaler.set(&"scale_factor", k)
	if root.content_scale_size != size:
		root.content_scale_size = size
