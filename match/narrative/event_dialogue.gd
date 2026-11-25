extends Control

signal choice_pressed(instance_id: StringName, option_id: StringName)

@onready var _scroll: ScrollContainer = %Scroll
@onready var _title: Label = %Title
@onready var _description: Label = %Description
@onready var _illustration: TextureRect = %Illustration
@onready var _choices: VBoxContainer = %Choices

var _instance_id: StringName


func present(dialogue: Dictionary) -> void:
	if dialogue.is_empty():
		_instance_id = &""
		hide()
		return
	if _instance_id == dialogue.id:
		return
	_instance_id = dialogue.id
	_title.text = dialogue.title
	_description.text = dialogue.text
	_illustration.texture = dialogue.illustration
	_illustration.visible = _illustration.texture != null
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	var enabled: Array[Button] = []
	for option: Dictionary in dialogue.options:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 5)
		_choices.add_child(group)
		var button := Button.new()
		button.text = option.label
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 40
		button.add_theme_font_size_override("font_size", 19)
		button.disabled = not option.blocked.is_empty()
		button.pressed.connect(_choose.bind(_instance_id, option.id))
		group.add_child(button)
		if not button.disabled:
			enabled.append(button)
		var preview := Label.new()
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.add_theme_color_override("font_color", Color("#c4d7e4"))
		preview.text = option.preview
		if button.disabled:
			preview.text += "\n" + option.blocked
		group.add_child(preview)
	for index in enabled.size():
		var button := enabled[index]
		button.focus_previous = button.get_path_to(enabled[posmod(index - 1, enabled.size())])
		button.focus_next = button.get_path_to(enabled[(index + 1) % enabled.size()])
		button.focus_neighbor_left = button.focus_previous
		button.focus_neighbor_top = button.focus_previous
		button.focus_neighbor_right = button.focus_next
		button.focus_neighbor_bottom = button.focus_next
	show()
	if not enabled.is_empty():
		enabled[0].grab_focus()
	_scroll.set_deferred("scroll_vertical", 0)


func _input(event: InputEvent) -> void:
	if visible and (event.is_action("ui_cancel") or (event.is_echo() and event.is_action("ui_accept"))):
		get_viewport().set_input_as_handled()


func _choose(instance_id: StringName, option_id: StringName) -> void:
	if visible and instance_id == _instance_id:
		choice_pressed.emit(instance_id, option_id)
