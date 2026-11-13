class_name Interactable
extends Node2D
## Something the player can interact with (NPC, chest, door...). Lives in the
## "interactable" group; PlayerInteractor picks the nearest one in range and
## calls interact(). Draws a small bobbing indicator while highlighted.

signal interacted(by: Node)

## Ground-space distance (px) from the player's feet.
@export var radius := 40.0
@export var enabled := true
## Indicator position above the owner's feet.
@export var indicator_offset := Vector2(0, -56)

var highlighted := false:
	set(v):
		if v != highlighted:
			highlighted = v
			_indicator.visible = v

var _indicator: Node2D
var _t := 0.0


func _ready() -> void:
	add_to_group(&"interactable")
	_indicator = _Indicator.new()
	_indicator.position = indicator_offset
	_indicator.visible = false
	_indicator.z_index = 50
	add_child(_indicator)


func _process(delta: float) -> void:
	if _indicator.visible:
		_t += delta
		_indicator.position = indicator_offset + Vector2(0, -roundf(absf(sin(_t * 4.0)) * 2.0))


func ground_distance_to(world_pos: Vector2) -> float:
	return Iso.screen_to_ground(world_pos - global_position).length()


func interact(by: Node) -> void:
	if enabled:
		interacted.emit(by)


## Pixel speech bubble with three dots, gold-framed (no font, crisp at any scale).
class _Indicator extends Node2D:
	const INK := Color(0.04, 0.035, 0.06)
	const GOLD := Color(0.84, 0.63, 0.28)
	const FILL := Color(1.0, 0.95, 0.82)

	func _draw() -> void:
		draw_rect(Rect2(-7, -10, 15, 10), INK)
		draw_rect(Rect2(-6, -9, 13, 8), GOLD)
		draw_rect(Rect2(-5, -8, 11, 6), FILL)
		for x in [-3, 0, 3]:
			draw_rect(Rect2(x, -6, 2, 2), INK)
		draw_rect(Rect2(-1, 0, 3, 1), INK)
		draw_rect(Rect2(0, 0, 1, 1), GOLD)
		draw_rect(Rect2(0, 1, 1, 1), INK)
