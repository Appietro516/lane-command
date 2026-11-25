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
const ROUTE_HEIGHT := 0.12
const ROUTE_HALF_WIDTH := 0.045
const ROUTE_TIP_RADIUS := 0.18

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
@export_range(0.9, 12.0, 0.1) var unit_aggro_radius := MatchBattle.DEFAULT_AGGRO_RADIUS
@export var unit_target_priority := MatchBattle.TargetPriority.NEAREST

var _battle: MatchBattle
var _layout: TerritoryLayout
var _regions_by_id: Dictionary[StringName, MatchRegion] = {}
var _initial_owners: Dictionary[StringName, MatchRegion.Owner] = {}
var _selected_region_id: StringName = &""
var _unit_views: Dictionary[int, MeshInstance3D] = {}
var _selected_unit_id := MatchBattle.NO_TARGET
var _route_mesh := ImmediateMesh.new()
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
@onready var _unit_selection: MeshInstance3D = $UnitSelection
@onready var _unit_route: MeshInstance3D = $UnitRoute
@onready var _unit_panel: PanelContainer = %UnitInspection
@onready var _unit_name: Label = %UnitName
@onready var _unit_stats: Label = %UnitStats
@onready var _unit_intent: Label = %UnitIntent
@onready var _unit_order_hint: Label = %UnitOrderHint
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
@onready var _camera: StrategyCamera = $Camera
@onready var _player_hp_label: Label = %PlayerHP
@onready var _cpu_hp_label: Label = %CPUHP
@onready var _outcome_label: Label = %Outcome
@onready var _restart_button: Button = %Restart


func _ready() -> void:
	_generate_map()
	_unit_route.mesh = _route_mesh
	_unit_route.global_transform = _regions.global_transform
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
	%Overview.pressed.connect(func() -> void: _camera.reset_view())
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
	_camera.reset_view(true)
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
	_battle = MatchBattle.new(_map_position(_bases[PLAYER].global_position),
		_map_position(_bases[CPU].global_position), unit_aggro_radius)
	_battle.target_priority = unit_target_priority
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
		_select_unit(MatchBattle.NO_TARGET)
		set_process(false)

	for unit in _battle.active_units():
		_update_unit_view(unit, _unit_views[unit.id])
	_update_unit_selection()
	_refresh_hud()


func try_place_building(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> bool:
	if not _placement_block_reason(side, building_id, world_position).is_empty():
		return false

	var definition: Dictionary = BUILDINGS[building_id]
	var ground := _map_plane().project(world_position)
	if not definition.rules.purchase(economy, _battle, side, _map_position(ground)):
		return false

	var building := definition.scene.instantiate() as Node3D
	if definition.has("accent_node"):
		building.get_node(definition.accent_node).material_override = FACTION_ACCENTS[side]
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
	_select_unit(MatchBattle.NO_TARGET)
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
	return _layout.region_at(_map_position(world_position))


func selected_unit() -> MatchBattle.Unit:
	return _battle.get_unit(_selected_unit_id)


func _map_position(world_position: Vector3) -> Vector2:
	var local := _regions.to_local(world_position)
	return Vector2(local.x, local.z)


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
	elif event.is_action_pressed("ui_cancel") and selected_unit() != null:
		_select_unit(MatchBattle.NO_TARGET)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _build_menu.visible:
				_build_menu.hide()
			elif _preview != null:
				# The camera may move before the next physics tick commits the placement.
				var point: Variant = _ground_point(event.position)
				_pending_pick = _map_position(point) if point != null else Vector2.INF
			else:
				_pick_map(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and _selected_unit_can_receive_orders():
			var point: Variant = _ground_point(event.position)
			if point != null and _pick_unit(event.position) == MatchBattle.NO_TARGET \
					and _battle.issue_move(_selected_unit_id, _map_position(point)):
				_update_unit_selection()
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var click := _pending_pick
	_pending_pick = Vector2.INF
	if _preview != null:
		if click != Vector2.INF:
			var point := _regions.to_global(Vector3(click.x, 0.0, click.y))
			if try_place_building(PLAYER, _placement_id, point):
				_cancel_placement()
				return
		var pointer := get_viewport().get_mouse_position()
		if _camera.is_dragging() or get_viewport().gui_get_hovered_control() != null:
			pointer = Vector2.INF
		_update_placement_preview(pointer)


func _pick_map(pointer: Vector2) -> void:
	var id := _pick_unit(pointer)
	var unit := _battle.get_unit(id)
	if unit != null and not _battle.is_finished():
		_select_unit(id)
		_select_region(&"")
	else:
		_select_unit(MatchBattle.NO_TARGET)
		_select_region(_pick_region(pointer))
	_refresh_claim_control()


func _pick_region(pointer: Vector2) -> StringName:
	var start := _camera.project_ray_origin(pointer)
	var end := start + _camera.project_ray_normal(pointer) * _camera.far
	var buildings: Array[Node] = [_bases[PLAYER], _bases[CPU]]
	buildings.append_array(_buildings[PLAYER].get_children())
	buildings.append_array(_buildings[CPU].get_children())
	var nearest: Node3D
	var depth := INF
	for building: Node3D in buildings:
		if not building.is_visible_in_tree():
			continue
		for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
			var local_start := mesh.to_local(start)
			var local_end := mesh.to_local(end)
			if not mesh.is_visible_in_tree() or not mesh.get_aabb().intersects_segment(local_start, local_end):
				continue
			var faces := mesh.mesh.get_faces()
			for i in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(
					local_start, local_end, faces[i], faces[i + 1], faces[i + 2])
				if hit != null:
					var distance := start.distance_squared_to(mesh.to_global(hit))
					if distance < depth:
						nearest = building
						depth = distance
	if nearest != null:
		return region_at_world_position(nearest.global_position)
	var point: Variant = _map_plane().intersects_segment(start, end)
	return region_at_world_position(point) if point != null else &""


func _pick_unit(pointer: Vector2) -> int:
	var start := _camera.project_ray_origin(pointer)
	var end := start + _camera.project_ray_normal(pointer) * _camera.far
	var nearest := MatchBattle.NO_TARGET
	var depth := INF
	for id in _unit_views:
		var view := _unit_views[id]
		var outline := view.get_node("Outline") as MeshInstance3D
		var hit: Variant = outline.get_aabb().grow(0.08).intersects_segment(
			outline.to_local(start), outline.to_local(end))
		if hit != null:
			var distance := start.distance_squared_to(outline.to_global(hit))
			if distance < depth:
				nearest = id
				depth = distance
	return nearest


func _select_unit(id: int) -> void:
	_selected_unit_id = id
	_update_unit_selection()


func _update_unit_selection() -> void:
	var unit := selected_unit()
	_unit_selection.visible = unit != null
	_unit_panel.visible = unit != null
	_route_mesh.clear_surfaces()
	if unit == null:
		return

	_unit_selection.global_position = _unit_views[unit.id].global_position
	_unit_name.text = "%s combat unit #%d" % [_side_label(unit.side), unit.id]
	_unit_name.modulate = FACTION_ACCENTS[unit.side].albedo_color.lightened(0.25)
	_unit_stats.text = "HP  %d / %d\nAttack  %d · Speed  %.1f units/s" % [
		unit.hp, MatchBattle.UNIT_HP, MatchBattle.ATTACK_DAMAGE, MatchBattle.MOVEMENT_SPEED,
	]
	_unit_intent.text = "Target  %s\nState  %s" % [_target_label(unit), _unit_state_label(unit)]
	_unit_order_hint.visible = _selected_unit_can_receive_orders()
	if not unit.waypoints.is_empty():
		_draw_unit_route(unit)


func _selected_unit_can_receive_orders() -> bool:
	var unit := selected_unit()
	return unit != null and unit.side == PLAYER and not _battle.is_finished()


func _target_label(unit: MatchBattle.Unit) -> String:
	if unit.target == MatchBattle.BASE_TARGET:
		return "CPU base" if unit.side == PLAYER else "Player base"
	var target := _battle.get_unit(unit.target)
	if target != null:
		return "%s unit #%d" % [_side_label(target.side), target.id]
	return "None"


func _unit_state_label(unit: MatchBattle.Unit) -> String:
	if unit.can_attack_target:
		return "Engaging"
	if not unit.waypoints.is_empty():
		if unit.target > MatchBattle.NO_TARGET:
			return "Pursuing"
		match unit.order:
			MatchBattle.Order.MOVE: return "Moving to order"
			MatchBattle.Order.HOLD: return "Returning to hold point"
		return "Advancing"
	if unit.order == MatchBattle.Order.HOLD and unit.position == unit.ordered_destination:
		return "Holding"
	if unit.order != MatchBattle.Order.AUTONOMOUS or unit.target != MatchBattle.NO_TARGET:
		return "Waiting for route"
	return "Idle"


func _draw_unit_route(unit: MatchBattle.Unit) -> void:
	_route_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := unit.position
	for waypoint in unit.waypoints:
		var edge := previous.direction_to(waypoint).orthogonal() * ROUTE_HALF_WIDTH
		_add_route_triangle(previous + edge, previous - edge, waypoint + edge)
		_add_route_triangle(waypoint + edge, previous - edge, waypoint - edge)
		previous = waypoint

	var right := Vector2.RIGHT * ROUTE_TIP_RADIUS
	var down := Vector2.DOWN * ROUTE_TIP_RADIUS
	_add_route_triangle(previous - right, previous - down, previous + right)
	_add_route_triangle(previous - right, previous + right, previous + down)
	_route_mesh.surface_end()


func _add_route_triangle(a: Vector2, b: Vector2, c: Vector2) -> void:
	for point: Vector2 in [a, b, c]:
		_route_mesh.surface_add_vertex(Vector3(point.x, ROUTE_HEIGHT, point.y))


func _side_label(side: MatchRegion.Owner) -> String:
	return "Player" if side == PLAYER else "CPU"


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
	_units.add_child(view)
	_unit_views[unit.id] = view
	_update_unit_view(unit, view)


func _update_unit_view(unit: MatchBattle.Unit, view: MeshInstance3D) -> void:
	view.global_position = _regions.to_global(Vector3(unit.position.x, 0.14, unit.position.y))
	# The prism is laid flat with its tip pointing along +Z before yaw.
	view.rotation.y = atan2(unit.heading.x, unit.heading.y)


func _remove_unit(unit_id: int) -> void:
	var view := _unit_views[unit_id]
	_units.remove_child(view)
	view.queue_free()
	_unit_views.erase(unit_id)
	if _selected_unit_id == unit_id:
		_select_unit(MatchBattle.NO_TARGET)


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
