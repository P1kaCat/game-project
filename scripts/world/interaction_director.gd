class_name InteractionDirector
extends Node
## Orchestrates conversations: NPC interaction -> dialogue -> optional shop.
## The only place that knows all the pieces; each piece stays independent:
##   Npc (world)  DialogueManager (logic)  DialogueUI / ShopUI (views)
##   TradeService (purchase rules)  PlayerState (gold + inventory data)
## While busy: player movement locked, touch movement controls hidden, both
## characters face each other and the camera frames them in the free area.

signal conversation_started(npc: Npc)
signal conversation_finished(npc: Npc)

@export var player: Player
@export var camera: FollowCamera
@export var hud: MobileHUD
## Portrait shown when the protagonist speaks (speaker id "player").
@export var player_portrait: Texture2D = preload("res://assets/characters/player/portrait.png")

var dialogue_manager := DialogueManager.new()
var dialogue_ui := DialogueUI.new()
var shop_ui := ShopUI.new()
var trade := TradeService.new()
var current_npc: Npc
var busy := false

var _pending_shop: MerchantStock
var _dialogue_cache := {}


func _ready() -> void:
	dialogue_manager.name = "DialogueManager"
	add_child(dialogue_manager)
	dialogue_ui.name = "DialogueUI"
	add_child(dialogue_ui)
	dialogue_ui.bind(dialogue_manager)
	shop_ui.name = "ShopUI"
	add_child(shop_ui)
	dialogue_manager.action_requested.connect(_on_action)
	dialogue_manager.step_shown.connect(_on_step)
	dialogue_manager.ended.connect(_on_dialogue_ended)
	shop_ui.closed.connect(_finish)
	for n in get_tree().get_nodes_in_group(&"npc"):
		register_npc(n as Npc)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is Npc:
			register_npc.call_deferred(n))


func register_npc(npc: Npc) -> void:
	if npc and not npc.interaction_requested.is_connected(_on_npc_interaction):
		npc.interaction_requested.connect(_on_npc_interaction)


func _on_npc_interaction(npc: Npc, _by: Node) -> void:
	if busy or npc.definition == null:
		return
	var data := _load_dialogue(npc.definition.dialogue)
	if data.is_empty():
		return
	busy = true
	current_npc = npc
	player.set_controls_locked(true)
	if hud:
		hud.suppressed = true
	player.face_towards(npc.global_position)
	npc.face_towards(player.global_position)
	conversation_started.emit(npc)
	var speakers := {
		String(npc.definition.id): {"name": npc.definition.display_name, "portrait": npc.definition.portrait},
		"player": {"name": Loc.t("name.player"), "portrait": player_portrait},
	}
	dialogue_manager.flags = GameState.flags  # story flags are saved with the game
	dialogue_manager.start(data, speakers)
	_frame(dialogue_ui.free_rect())


## Lines can ask the speaking NPC for a one-shot gesture ("anim" in the data).
func _on_step(step: Dictionary) -> void:
	var anim := str(step.get("anim", ""))
	if anim != "" and current_npc and step.get("speaker", "") != "player":
		current_npc.play_action(anim)


func _on_action(action: Dictionary) -> void:
	match str(action.get("type", "")):
		"open_shop":
			_pending_shop = current_npc.definition.shop if current_npc else null
		_:
			push_warning("Unhandled dialogue action: %s" % action)


func _on_dialogue_ended(_id: String, _reason: String) -> void:
	if _pending_shop:
		var shop := _pending_shop
		_pending_shop = null
		shop_ui.open(shop, player.state, trade)
		_frame(shop_ui.free_rect())
	else:
		_finish()


func _finish() -> void:
	if not busy:
		return
	busy = false
	player.set_controls_locked(false)
	if hud:
		hud.suppressed = false
	if camera:
		camera.clear_framing()
	var npc := current_npc
	current_npc = null
	conversation_finished.emit(npc)
	if npc:
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if is_instance_valid(npc) and current_npc != npc:
				npc.reset_facing())


## Frame player + NPC in the given free screen rect (above / beside the UI).
func _frame(free: Rect2) -> void:
	if camera == null or current_npc == null:
		return
	var head := Vector2(0, -24)  # frame bodies, not feet
	camera.frame_points([player.global_position + head, current_npc.global_position + head], free.get_center())


func _load_dialogue(path: String) -> Dictionary:
	if not _dialogue_cache.has(path):
		_dialogue_cache[path] = DialogueData.load_file(Loc.localized_path(path))
	return _dialogue_cache[path]
