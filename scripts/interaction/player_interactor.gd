class_name PlayerInteractor
extends Node
## Finds the nearest Interactable within range of the player's feet, shows its
## indicator, and triggers it on the "interact" action (E / Space / pad X /
## the touch action button). Disabled while a conversation or shop is open.

signal target_changed(target: Interactable)

var enabled := true:
	set(v):
		enabled = v
		if not v:
			_set_target(null)

var target: Interactable

@onready var player: Node2D = get_parent()


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	var best: Interactable = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(&"interactable"):
		var it := node as Interactable
		if it == null or not it.enabled or not it.is_visible_in_tree():
			continue
		var d := it.ground_distance_to(player.global_position)
		if d <= it.radius and d < best_d:
			best = it
			best_d = d
	_set_target(best)


func _set_target(t: Interactable) -> void:
	if t == target:
		return
	if target and is_instance_valid(target):
		target.highlighted = false
	target = t
	if target:
		target.highlighted = true
	target_changed.emit(target)


## Returns true if something was interacted with.
func try_interact() -> bool:
	if not enabled or target == null:
		return false
	target.interact(player)
	return true
