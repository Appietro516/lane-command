class_name MatchSetup
extends Control

const DifficultyProfile := preload("res://match/difficulty_profile.gd")
const MAX_INT_TEXT := "9223372036854775807"
const MIN_INT_MAGNITUDE_TEXT := "9223372036854775808"

signal start_requested(selected_settings: MatchSettings, layout: TerritoryLayout)

var settings: MatchSettings

var _difficulty_pickers: Array[OptionButton] = []
var _difficulty_descriptions: Array[Label] = []
var _cpu_rows: Array[VBoxContainer] = []
var _layout: TerritoryLayout
var _seed_rng := RandomNumberGenerator.new()

@onready var _shape_picker: OptionButton = %MapShape
@onready var _region_field: LineEdit = %MapRegions
@onready var _seed_field: LineEdit = %MapSeed
@onready var _opponent_picker: OptionButton = %OpponentCount
@onready var _capacity: Label = %Capacity
@onready var _error: Label = %ValidationError
@onready var _start: Button = %Start


func _ready() -> void:
	if settings == null:
		settings = MatchSettings.defaults()
	_seed_rng.randomize()
	for shape in MapSettings.SHAPE_NAMES:
		_shape_picker.add_item(MapSettings.SHAPE_NAMES[shape], shape)
	for count in range(1, TerritoryLayout.MAX_CPU_OPPONENTS + 1):
		_opponent_picker.add_item(str(count), count)
		var level := settings.cpu_difficulties[count - 1] if count <= settings.cpu_difficulties.size() \
			else DifficultyProfile.DEFAULT_LEVEL
		_add_cpu_row(count, level)
	_shape_picker.select(_shape_picker.get_item_index(settings.map.shape))
	_opponent_picker.select(_opponent_picker.get_item_index(settings.cpu_difficulties.size()))
	_region_field.text = str(settings.map.region_count)
	_seed_field.text = str(settings.map.seed)

	_shape_picker.item_selected.connect(_validate.unbind(1))
	_opponent_picker.item_selected.connect(func(_index: int) -> void:
		_update_cpu_rows()
		_validate())
	_region_field.text_changed.connect(_validate.unbind(1))
	_seed_field.text_changed.connect(_validate.unbind(1))
	%Randomize.pressed.connect(_randomize_seed)
	_start.pressed.connect(_start_match)
	_update_cpu_rows()
	_validate()
	_opponent_picker.grab_focus()


func _add_cpu_row(count: int, level: int) -> void:
	var row := VBoxContainer.new()
	var fields := HBoxContainer.new()
	var label := Label.new()
	label.text = "CPU %d difficulty" % count
	var side := (MatchRegion.Owner.CPU + count - 1) as MatchRegion.Owner
	label.add_theme_color_override("font_color", MatchRegion.accent_color(side).lightened(0.3))
	fields.add_child(label)

	var picker := OptionButton.new()
	picker.accessibility_name = label.text
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for available_level in range(1, DifficultyProfile.PROFILES.size() + 1):
		picker.add_item(DifficultyProfile.display_name(available_level), available_level)
	picker.select(picker.get_item_index(level))
	fields.add_child(picker)
	row.add_child(fields)

	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 14)
	description.modulate = Color(0.79, 0.86, 0.92)
	row.add_child(description)
	%CPURows.add_child(row)
	_cpu_rows.append(row)
	_difficulty_pickers.append(picker)
	_difficulty_descriptions.append(description)
	picker.item_selected.connect(_describe_cpu.bind(count - 1))
	_describe_cpu(picker.selected, count - 1)


func _describe_cpu(index: int, cpu_index: int) -> void:
	var picker := _difficulty_pickers[cpu_index]
	var description: String = DifficultyProfile.get_profile(picker.get_item_id(index)).description
	_difficulty_descriptions[cpu_index].text = description
	picker.accessibility_description = description


func _update_cpu_rows() -> void:
	var count := _opponent_picker.get_selected_id()
	for i in _cpu_rows.size():
		_cpu_rows[i].visible = i < count


func _validate() -> void:
	var shape := _shape_picker.get_selected_id() as MapSettings.Shape
	var opponents := _opponent_picker.get_selected_id()
	var minimum := opponents + 2
	var regions := _region_field.text.strip_edges()
	var seed := _seed_field.text.strip_edges()
	var count: Variant = _parse_integer(regions)
	_capacity.text = "%d–%d regions · terrain scales automatically" % [minimum, MapSettings.MAX_REGIONS]
	if count == null or count < MapSettings.MIN_REGIONS or count > MapSettings.MAX_REGIONS:
		_show_error("Enter a whole number of regions from 2 to 128.")
	elif count < minimum:
		_show_error("Use at least %d regions so each faction has a start and one region stays neutral." % minimum)
	else:
		var selected_seed: Variant = _parse_integer(seed)
		if selected_seed == null:
			_show_error("Enter a whole-number seed from -%s to %s." % [MIN_INT_MAGNITUDE_TEXT, MAX_INT_TEXT])
			return
		_layout = TerritoryLayout.new(selected_seed, count, MapSettings.scaled_dimensions(shape, count),
			1, 1, opponents, shape)
		_show_error(_layout.configuration_error)


func _show_error(message: String) -> void:
	_error.text = message
	_error.visible = not message.is_empty()
	_start.disabled = _error.visible
	if _start.disabled:
		_layout = null


func _randomize_seed() -> void:
	var value := str(_seed_rng.randi())
	if _parse_integer(value) == _parse_integer(_seed_field.text.strip_edges()):
		value = str(value.to_int() + 1)
	_seed_field.text = value
	_validate()


func _start_match() -> void:
	if _start.disabled or _layout == null:
		return
	var levels: Array[int] = []
	for i in _opponent_picker.get_selected_id():
		levels.append(_difficulty_pickers[i].get_selected_id())
	var selected := MatchSettings.new(_layout.settings, levels)
	_start.disabled = true
	start_requested.emit(selected, _layout)


static func _parse_integer(value: String) -> Variant:
	if not value.is_valid_int():
		return null
	var negative := value.begins_with("-")
	var digits := value.trim_prefix("-").trim_prefix("+").lstrip("0")
	if digits.is_empty():
		return 0
	var limit := MIN_INT_MAGNITUDE_TEXT if negative else MAX_INT_TEXT
	if digits.length() > limit.length() or (digits.length() == limit.length() and digits > limit):
		return null
	return (("-" if negative else "") + digits).to_int()
