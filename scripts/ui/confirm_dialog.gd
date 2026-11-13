class_name ConfirmDialog
extends Control
## Modal yes/no question in the Asthya style. "No" is focused by default (the
## safe answer); Escape / back answers no.
##   var d := ConfirmDialog.ask(self, Loc.t("..."))
##   if await d.answered: ...

signal answered(yes: bool)

var _done := false
var yes_button: Button
var no_button: Button


static func ask(parent: Node, text: String, yes_text := "", no_text := "", single := false) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d._build(text, yes_text if yes_text != "" else Loc.t("common.yes"),
		no_text if no_text != "" else Loc.t("common.no"), single)
	parent.add_child(d)
	return d


func _build(text: String, yes_text: String, no_text: String, single: bool) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(MenuKit.dimmer(0.55))
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 220
	col.add_child(label)
	col.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	no_button = Button.new()
	no_button.text = no_text
	yes_button = Button.new()
	yes_button.text = yes_text
	for b in [no_button, yes_button]:
		b.custom_minimum_size = Vector2(70, 18)
		b.mouse_entered.connect(b.grab_focus)
		row.add_child(b)
	no_button.pressed.connect(_answer.bind(false))
	yes_button.pressed.connect(_answer.bind(true))
	if single:
		no_button.visible = false
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	(yes_button if single else no_button).grab_focus.call_deferred()


func _answer(yes: bool) -> void:
	if _done:
		return
	_done = true
	Audio.sfx("ui_confirm" if yes else "ui_back", -4.0)
	answered.emit(yes)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_answer(false)

