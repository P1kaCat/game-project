extends Node2D
## Tiny pixel "!" speech bubble shown above the character. Drawn with rects so
## it stays crisp at any integer scale (no font, no texture).

@export var show_time := 0.45

var _timer := 0.0

const OUTLINE := Color(0.08, 0.07, 0.1)
const FILL := Color(1, 0.97, 0.88)
const MARK := Color(0.85, 0.2, 0.15)


func _ready() -> void:
	visible = false


func pop() -> void:
	_timer = show_time
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false


func _draw() -> void:
	# 9x11 bubble with 1px outline and a 2px tail, origin at the tail tip.
	draw_rect(Rect2(-5, -14, 11, 12), OUTLINE)
	draw_rect(Rect2(-4, -13, 9, 10), FILL)
	draw_rect(Rect2(-1, -2, 3, 2), OUTLINE)
	draw_rect(Rect2(0, -2, 1, 1), FILL)
	draw_rect(Rect2(0, -12, 1, 5), MARK)
	draw_rect(Rect2(0, -6, 1, 1), MARK)
