class_name DialogueData
extends RefCounted
## Loads and validates a dialogue graph (res://data/dialogues/*.json).
##
## Format:
##   {"id", "speaker" (default speaker id), "start" (node id), "nodes": {
##      "<id>": {
##        "speaker"?: id,          who says the text (defaults to dialogue speaker)
##        "text"?: "...",          a line (typewriter)
##        "choices"?: [ {"text", "next", "condition"?: {"flag", "equals"?},
##                       "actions"?: [...], "cancel"?: bool} ],
##        "actions"?: [ {"type": "...", ...} ],   run when the node is left
##        "set_flags"?: {"flag": value},          set when the node is entered
##        "next"?: "<id>" | "end" } } }
## A text node followed by a choices-only node shows the choices under that
## text (classic JRPG prompt). "end" closes the conversation.

static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Dialogue %s: invalid JSON" % path)
		return {}
	var errors := validate(data)
	for e in errors:
		push_error("Dialogue %s: %s" % [path, e])
	return data if errors.is_empty() else {}


static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var nodes: Dictionary = data.get("nodes", {})
	if not nodes.has(str(data.get("start", ""))):
		errors.append("start node '%s' missing" % data.get("start", ""))
	for id in nodes:
		var n: Dictionary = nodes[id]
		var targets := []
		if n.has("next"):
			targets.append(str(n.next))
		for c in n.get("choices", []):
			targets.append(str(c.get("next", "")))
		for t in targets:
			if t != "end" and not nodes.has(t):
				errors.append("node '%s' points to unknown node '%s'" % [id, t])
		if not n.has("text") and not n.has("choices"):
			errors.append("node '%s' has neither text nor choices" % id)
		if not n.has("choices") and not n.has("next"):
			errors.append("node '%s' has no way forward (next or choices)" % id)
	return errors
