class_name DialogueManager
extends Node
## Runs a dialogue graph (see DialogueData). Knows nothing about the UI: it
## emits `step_shown` for each line (with the choices to offer, if any) and the
## UI calls `confirm()` / `choose(i)` / `cancel()` back.
##
## Gameplay effects are emitted as `action_requested` (e.g. open_shop) and
## handled elsewhere. Flags persist between conversations (future quests).

signal started(dialogue_id: String)
## step = {speaker: id, name: String, portrait: Texture2D, text: String,
##         choices: [{text, index}], cancel_index: int}
signal step_shown(step: Dictionary)
signal action_requested(action: Dictionary)
signal ended(dialogue_id: String, reason: String)

var flags := {}

var _data := {}
var _speakers := {}  # id -> {name, portrait}
var _node_id := ""
var _choice_node := {}   # node whose choices are currently offered
var _step := {}
var _last_text := ""


func is_active() -> bool:
	return not _data.is_empty()


func current_step() -> Dictionary:
	return _step


## `speakers`: {speaker_id: {name: String, portrait: Texture2D}}
func start(data: Dictionary, speakers: Dictionary) -> void:
	if data.is_empty() or is_active():
		return
	_data = data
	_speakers = speakers
	_last_text = ""
	started.emit(str(data.get("id", "")))
	_enter(str(data.start))


## Advance past a line without choices. Returns false if the step waits for a choice.
func confirm() -> bool:
	if not is_active() or not _step.get("choices", []).is_empty():
		return false
	var node := _node(_node_id)
	_run_actions(node.get("actions", []))
	_enter(str(node.get("next", "end")))
	return true


func choose(index: int) -> bool:
	if not is_active():
		return false
	var visible := _visible_choices(_choice_node)
	if index < 0 or index >= visible.size():
		return false
	var choice: Dictionary = visible[index]
	_run_actions(_node(_node_id).get("actions", []))  # leaving the line node
	_run_actions(choice.get("actions", []))
	_enter(str(choice.get("next", "end")))
	return true


## Escape / back: picks the choice marked "cancel" if one is offered,
## otherwise ends the conversation.
func cancel() -> void:
	if not is_active():
		return
	var ci := int(_step.get("cancel_index", -1))
	if ci >= 0:
		choose(ci)
	else:
		_finish("cancel")


func _enter(id: String) -> void:
	if id == "end" or not _data.nodes.has(id):
		_finish("end")
		return
	_node_id = id
	var node := _node(id)
	for f in node.get("set_flags", {}):
		flags[f] = node.set_flags[f]
	_choice_node = {}
	if node.has("choices"):
		_choice_node = node
	elif node.has("next") and _data.nodes.has(str(node.next)):
		var nxt := _node(str(node.next))
		if nxt.has("choices") and not nxt.has("text"):
			_choice_node = nxt  # show the follow-up choices under this line
	var text := str(node.get("text", _last_text))
	_last_text = text
	var speaker_id := str(node.get("speaker", _data.get("speaker", "")))
	var sp: Dictionary = _speakers.get(speaker_id, {})
	var choices := []
	var cancel_index := -1
	var visible := _visible_choices(_choice_node)
	for i in visible.size():
		choices.append({"text": str(visible[i].text), "index": i})
		if visible[i].get("cancel", false):
			cancel_index = i
	_step = {"speaker": speaker_id, "name": str(sp.get("name", speaker_id)), "portrait": sp.get("portrait"),
		"text": text, "choices": choices, "cancel_index": cancel_index, "node": id}
	step_shown.emit(_step)


func _visible_choices(node: Dictionary) -> Array:
	var out := []
	for c in node.get("choices", []):
		var cond: Dictionary = c.get("condition", {})
		if cond.is_empty() or flags.get(cond.get("flag", ""), null) == cond.get("equals", true):
			out.append(c)
	return out


func _run_actions(actions: Array) -> void:
	for a in actions:
		if a.get("type", "") == "set_flag":
			flags[a.flag] = a.get("value", true)
		else:
			action_requested.emit(a)


func _finish(reason: String) -> void:
	var id := str(_data.get("id", ""))
	_data = {}
	_step = {}
	_node_id = ""
	ended.emit(id, reason)


func _node(id: String) -> Dictionary:
	return _data.nodes.get(id, {})
