extends Node3D

const BUILDINGS := {
	&"barracks": {
		"label": "Barracks",
		"cost": MatchEconomy.BARRACKS_COST,
		"scene": preload("res://match/barracks.tscn"),
		"rules": preload("res://match/barracks_rules.gd"),
		"accent_node": ^"RoofMarking",
	},
}
const VALID_PREVIEW := Color(0.37, 1.0, 0.70, 0.55)
const INVALID_PREVIEW := Color(1.0, 0.37, 0.40, 0.55)
const UNIT := preload("res://match/unit.tscn")
const STARTING_BASE := preload("res://match/starting_base.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const CPU_DECISION_INTERVAL := 2.0

const FACTION_ACCENTS := {
	PLAYER: preload("res://match/player_accent.tres"),
	CPU: preload("res://match/cpu_accent.tres"),
}

const OUTCOME_LABELS := {
	MatchBattle.Outcome.IN_PROGRESS: "",
	MatchBattle.Outcome.VICTORY: "Victory",
	MatchBattle.Outcome.DEFEAT: "Defeat",
}

var economy: MatchEconomy
@export var map_seed: int = 17
@export_range(5, 7) var region_count: int = 6

var _battle: MatchBattle
var _layout: TerritoryLayout
var _regions_by_id: Dictionary[StringName, MatchRegion] = {}
var _initial_owners: Dictionary[StringName, MatchRegion.Owner] = {}
var _selected_region_id: StringName = &""
var _unit_views: Dictionary[int, MeshInstance3D] = {}
var _corridor_start: Vector3
var _corridor_direction: Vector3
var _time_until_cpu_decision: float

var _bases: Dictionary[MatchRegion.Owner, Node3D] = {}
var _pending_pick := Vector2.INF
var _placement_id: StringName = &""
var _preview: Node3D
var _preview_material: StandardMaterial3D
var _cpu_placement_rng := RandomNumberGenerator.new()
var _build_options: Dictionary[StringName, Button] = {}

@onready var _buildings: Dictionary[MatchRegion.Owner, Node3D] = {
	PLAYER: $Buildings/Player,
	CPU: $Buildings/CPU,
}
@onready var _regions: Node3D = $Regions
@onready var _units: Node3D = $Units
@onready var _energy_label: Label = %Energy
@onready var _income_label: Label = %Income
@onready var _barracks_label: Label = %BarracksCount
@onready var _build_button: Button = %Build
@onready var _build_menu: PanelContainer = %BuildMenu
@onready var _build_list: VBoxContainer = %BuildList
@onready var _placement_panel: PanelContainer = %PlacementPanel
@onready var _placement_label: Label = %PlacementStatus
@onready var _upgrade_button: Button = %Upgrade
@onready var _claim_button: Button = %Claim
@onready var _region_label: Label = %SelectedRegion
@onready var _camera: Camera3D = $Camera
@onready var _player_hp_label: Label = %PlayerHP
@onready var _cpu_hp_label: Label = %CPUHP
@onready var _outcome_label: Label = %Outcome
@onready var _restart_button: Button = %Restart


func _ready() -> void:
	_generate_map()
	_income_label.text = "Income +%d/s" % MatchEconomy.INCOME_PER_SECOND
	for building_id in BUILDINGS:
		var definition: Dictionary = BUILDINGS[building_id]
		var option := Button.new()
		option.text = "%s · %d energy" % [definition.label, definition.cost]
		option.pressed.connect(_begin_placement.bind(building_id))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_build_list.add_child(option)
		_build_options[building_id] = option
	%BuildScroll.custom_minimum_size.y = minf(_build_list.get_combined_minimum_size().y, 240.0)
	_build_button.pressed.connect(_toggle_build_menu)
	%CancelPlacement.pressed.connect(_cancel_placement)
	_preview_material = StandardMaterial3D.new()
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_claim_button.text = "Claim · %d" % MatchEconomy.CLAIM_COST
	_claim_button.pressed.connect(func() -> void: try_claim(PLAYER, _selected_region_id))
	_restart_button.pressed.connect(restart_match)
	restart_match()


func _generate_map() -> void:
	_layout = TerritoryLayout.new(map_seed, region_count)
	for cell in _layout.cells:
		var region := MatchRegion.new(cell)
		region.name = cell.id
		match cell.id:
			TerritoryLayout.PLAYER_START:
				region.name = "PlayerStart"
				region.region_owner = PLAYER
			TerritoryLayout.CPU_START:
				region.name = "CPUStart"
				region.region_owner = CPU
		_regions.add_child(region)
		_regions_by_id[cell.id] = region
		_initial_owners[cell.id] = region.region_owner
		if region.region_owner != MatchRegion.Owner.NEUTRAL:
			_add_starting_base(region)


func _add_starting_base(region: MatchRegion) -> void:
	var side := region.region_owner
	var base := STARTING_BASE.instantiate() as Node3D
	base.name = "PlayerBase" if side == PLAYER else "CPUBase"
	base.position = Vector3(0, 0.08, 2)
	base.get_node("Core").material_override = FACTION_ACCENTS[side]
	region.add_child(base)
	_bases[side] = base


func restart_match() -> void:
	if _battle != null:
		_battle.unit_produced.disconnect(_spawn_unit)
		_battle.unit_removed.disconnect(_remove_unit)
		_battle.base_destroyed.disconnect(_hide_base)
	for unit_id in _unit_views.keys():
		_remove_unit(unit_id)
	_cancel_placement()
	for side in _buildings:
		for building in _buildings[side].get_children():
			_buildings[side].remove_child(building)
			building.queue_free()
		_bases[side].show()
	for region_id in _initial_owners:
		_regions_by_id[region_id].region_owner = _initial_owners[region_id]
	_select_region(&"")

	economy = MatchEconomy.new()
	_time_until_cpu_decision = CPU_DECISION_INTERVAL
	_cpu_placement_rng.seed = 46
	_corridor_start = _units.to_local(_bases[PLAYER].global_position)
	var corridor := _units.to_local(_bases[CPU].global_position) - _corridor_start
	_corridor_direction = corridor.normalized()
	_battle = MatchBattle.new(corridor.length())
	_battle.unit_produced.connect(_spawn_unit)
	_battle.unit_removed.connect(_remove_unit)
	_battle.base_destroyed.connect(_hide_base)
	_refresh_hud()
	set_process(true)


func _process(delta: float) -> void:
	if _battle.is_finished():
		return

	# Apply income and production up to each decision before making its purchase.
	while delta >= _time_until_cpu_decision and not _battle.is_finished():
		_advance_simulation(_time_until_cpu_decision)
		delta -= _time_until_cpu_decision
		_time_until_cpu_decision = CPU_DECISION_INTERVAL
		if not _battle.is_finished():
			_try_cpu_purchase()

	if not _battle.is_finished():
		_advance_simulation(delta)
		_time_until_cpu_decision -= delta
	if _battle.is_finished():
		_cancel_placement()
		set_process(false)

	for unit in _battle.active_units():
		_unit_views[unit.id].position = _corridor_start + _corridor_direction * unit.position
	_refresh_hud()


func try_place_building(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> bool:
	if not _placement_block_reason(side, building_id, world_position).is_empty():
		return false

	var definition: Dictionary = BUILDINGS[building_id]
	if not definition.rules.purchase(economy, _battle, side):
		return false

	var building := definition.scene.instantiate() as Node3D
	if definition.has("accent_node"):
		building.get_node(definition.accent_node).material_override = FACTION_ACCENTS[side]
	var ground := _map_plane().project(world_position)
	building.position = _buildings[side].to_local(ground)
	_buildings[side].add_child(building)
	_refresh_hud()
	return true


func _placement_block_reason(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> String:
	if not owns_region(side, region_at_world_position(world_position)):
		return "Choose a spot in your territory"
	return _purchase_block_reason(side, building_id)


func _purchase_block_reason(side: MatchRegion.Owner, building_id: StringName) -> String:
	if _battle.is_finished():
		return "Match ended"
	if not _buildings.has(side) or not BUILDINGS.has(building_id):
		return "Building unavailable"
	var definition: Dictionary = BUILDINGS[building_id]
	return definition.rules.block_reason(economy, side)


func _toggle_build_menu() -> void:
	var opening := not _build_menu.visible
	_cancel_placement()
	_build_menu.visible = opening
	if opening:
		for option in _build_options.values():
			if not option.disabled:
				option.grab_focus()
				break


func _begin_placement(building_id: StringName) -> void:
	if not _purchase_block_reason(PLAYER, building_id).is_empty():
		return
	_cancel_placement()
	_placement_id = building_id
	var definition: Dictionary = BUILDINGS[building_id]
	_preview = definition.scene.instantiate() as Node3D
	_preview.process_mode = Node.PROCESS_MODE_DISABLED
	_preview.hide()
	if _preview is MeshInstance3D:
		_preview.material_override = _preview_material
	for mesh: MeshInstance3D in _preview.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _preview_material
	add_child(_preview)
	_update_placement_preview(Vector2.INF)


func _cancel_placement() -> void:
	if _preview != null:
		remove_child(_preview)
		_preview.queue_free()
		_preview = null
	_placement_id = &""
	_pending_pick = Vector2.INF
	_placement_panel.hide()
	_build_menu.hide()


func _update_placement_preview(pointer: Vector2) -> void:
	var definition: Dictionary = BUILDINGS[_placement_id]
	var reason := _purchase_block_reason(PLAYER, _placement_id)
	_preview.hide()
	if pointer != Vector2.INF:
		var point: Variant = _ground_point(pointer)
		if point != null:
			reason = _placement_block_reason(PLAYER, _placement_id, point)
			_preview.global_position = point
			_preview_material.albedo_color = VALID_PREVIEW if reason.is_empty() else INVALID_PREVIEW
			_preview.show()
	if reason.is_empty():
		reason = "Click to place" if _preview.visible else "Choose a spot in your territory"
	_placement_label.text = "%s · %s" % [definition.label, reason]
	_placement_panel.show()


func try_upgrade(side: MatchRegion.Owner) -> bool:
	if _battle.is_finished() or not economy.try_upgrade(side):
		return false

	_refresh_hud()
	return true


func try_claim(side: MatchRegion.Owner, region_id: StringName) -> bool:
	if side != PLAYER or not _claim_block_reason(region_id).is_empty():
		return false
	if not economy.try_spend_energy(side, MatchEconomy.CLAIM_COST):
		return false

	_regions_by_id[region_id].region_owner = side
	_refresh_hud()
	return true


func owns_region(side: MatchRegion.Owner, region_id: StringName) -> bool:
	var region := get_region(region_id)
	return region != null and region.region_owner == side


func get_region(region_id: StringName) -> MatchRegion:
	return _regions_by_id.get(region_id)


func region_at_world_position(world_position: Vector3) -> StringName:
	var point := _regions.to_local(world_position)
	return _layout.region_at(Vector2(point.x, point.z))


func _claim_block_reason(region_id: StringName) -> String:
	var region := get_region(region_id)
	if region == null:
		return "Select a region"
	if region.region_owner == PLAYER:
		return "Player-owned"
	if region.region_owner == CPU:
		return "CPU-owned"
	if _battle.is_finished():
		return "Match ended"
	for neighbor_id in region.neighbor_ids:
		if owns_region(PLAYER, neighbor_id):
			return "Need more energy" if economy.energy(PLAYER) < MatchEconomy.CLAIM_COST else ""
	return "Not adjacent"


func _unhandled_input(event: InputEvent) -> void:
	if (_preview != null or _build_menu.visible) and (event.is_action_pressed("ui_cancel") or (
			event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT
			and event.pressed)):
		_cancel_placement()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _build_menu.visible:
			_build_menu.hide()
		else:
			_pending_pick = event.position
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var click := _pending_pick
	_pending_pick = Vector2.INF
	if _preview != null:
		if click != Vector2.INF:
			var point: Variant = _ground_point(click)
			if point != null and try_place_building(PLAYER, _placement_id, point):
				_cancel_placement()
				return
		var pointer := get_viewport().get_mouse_position()
		if get_viewport().gui_get_hovered_control() != null:
			pointer = Vector2.INF
		_update_placement_preview(pointer)
	elif click != Vector2.INF:
		var point: Variant = _ground_point(click)
		_select_region(region_at_world_position(point) if point != null else &"")
		_refresh_claim_control()


func _ground_point(pointer: Vector2) -> Variant:
	var start := _camera.project_ray_origin(pointer)
	var end := start + _camera.project_ray_normal(pointer) * _camera.far
	return _map_plane().intersects_segment(start, end)


func _map_plane() -> Plane:
	return Plane(_regions.global_basis.y.normalized(), _regions.global_position)


func _select_region(region_id: StringName) -> void:
	if _regions_by_id.has(_selected_region_id):
		_regions_by_id[_selected_region_id].set_selected(false)
	_selected_region_id = region_id
	if _regions_by_id.has(_selected_region_id):
		_regions_by_id[_selected_region_id].set_selected(true)


func _advance_simulation(delta: float) -> void:
	economy.advance(delta)
	_battle.advance(delta, economy)


func _try_cpu_purchase() -> void:
	if economy.barracks_count(CPU) < MatchEconomy.BARRACKS_CAPACITY:
		if not economy.can_build(CPU):
			return
		var region: MatchRegion = get_region(TerritoryLayout.CPU_START)
		var tile := region.geometry
		var bounds := tile.get_aabb()
		# Sample the territory and let the shared placement check validate its shape.
		for attempt in range(8):
			var point := tile.to_global(Vector3(
				_cpu_placement_rng.randf_range(bounds.position.x, bounds.end.x),
				bounds.end.y,
				_cpu_placement_rng.randf_range(bounds.position.z, bounds.end.z)))
			if try_place_building(CPU, &"barracks", point):
				break
	elif not economy.has_upgrade(CPU):
		try_upgrade(CPU)


func _spawn_unit(unit: MatchBattle.Unit) -> void:
	var view := UNIT.instantiate() as MeshInstance3D
	view.material_override = FACTION_ACCENTS[unit.side]
	# The prism is laid flat with its tip pointing along +Z before yaw.
	var heading := _corridor_direction if unit.side == PLAYER else -_corridor_direction
	view.rotation.y = atan2(heading.x, heading.z)
	view.position = _corridor_start + _corridor_direction * unit.position
	_units.add_child(view)
	_unit_views[unit.id] = view


func _remove_unit(unit_id: int) -> void:
	var view := _unit_views[unit_id]
	_units.remove_child(view)
	view.queue_free()
	_unit_views.erase(unit_id)


func _hide_base(side: MatchRegion.Owner) -> void:
	_bases[side].hide()


func _refresh_hud() -> void:
	_player_hp_label.text = "Player base · %d HP" % _battle.base_hp(PLAYER)
	_cpu_hp_label.text = "CPU base · %d HP" % _battle.base_hp(CPU)
	_outcome_label.text = OUTCOME_LABELS[_battle.outcome()]
	_outcome_label.visible = _battle.is_finished()
	_energy_label.text = "Energy %d" % floori(economy.energy(PLAYER))
	_barracks_label.text = "Barracks %d/%d" % [
		economy.barracks_count(PLAYER), MatchEconomy.BARRACKS_CAPACITY,
	]
	var has_available_building := false
	for building_id in _build_options:
		var available := _purchase_block_reason(PLAYER, building_id).is_empty()
		_build_options[building_id].disabled = not available
		has_available_building = has_available_building or available
	_build_button.disabled = not has_available_building
	if not has_available_building:
		_build_menu.hide()
	_upgrade_button.disabled = _battle.is_finished() or not economy.can_upgrade(PLAYER)
	_upgrade_button.text = (
		"Upgraded" if economy.has_upgrade(PLAYER) else "Upgrade · %d" % MatchEconomy.UPGRADE_COST
	)
	_refresh_claim_control()


func _refresh_claim_control() -> void:
	var reason := _claim_block_reason(_selected_region_id)
	_claim_button.disabled = not reason.is_empty()
	if _regions_by_id.has(_selected_region_id):
		_region_label.text = "%s\n%s" % [
			str(_selected_region_id).capitalize(), "Neutral" if reason.is_empty() else reason,
		]
	else:
		_region_label.text = reason
