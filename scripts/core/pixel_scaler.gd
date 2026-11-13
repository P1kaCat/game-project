extends Node
## Autoload "PixelScaler": pixel-perfect, full-screen scaling on any display.
##
## The project renders at a low internal resolution ("viewport" stretch mode)
## and upscales by an integer factor, which keeps every art pixel a crisp k x k
## square. Plain integer scaling letterboxes most phones (e.g. 720p, 1440p,
## 1220p screens), so instead we pick the integer factor k that brings the
## internal height closest to `target_height`, then set the internal resolution
## to exactly window / k. Result: the whole screen is used, no black bars, no
## fractional (blurry or uneven) pixels.

## Preferred internal height in pixels (how much of the world is visible).
@export var target_height := 270
@export var min_height := 200

var scale_factor := 1


func _ready() -> void:
	get_tree().root.size_changed.connect(_apply)
	_apply()


func _apply() -> void:
	var root := get_tree().root
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var k := maxi(1, roundi(float(win.y) / target_height))
	while k > 1 and win.y / k < min_height:
		k -= 1
	var size := Vector2i(win.x / k, win.y / k)
	scale_factor = k
	if root.content_scale_size != size:
		root.content_scale_size = size
