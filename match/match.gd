extends Node3D

const Fortifications := preload("res://match/fortification_rules.gd")
const BUILDINGS := {
	&"barracks": {
		"label": "Barracks",
		"cost": MatchEconomy.BARRACKS_COST,
		"scene": preload("res://match/barracks.tscn"),
		"rules": preload("res://match/barracks_rules.gd"),
		"accent_node": ^"RoofMarking",
	},
	&"generator": {
		"label": "Generator", "cost": {MatchEconomy.MATERIALS: 26},
		"scene": preload("res://match/producers/generator.tscn"),
		"hp": 24, "size": Vector2(1.4, 1.4),
		"income": {MatchEconomy.ENERGY: 2.0},
	},
	&"mine": {
		"label": "Mine", "cost": {MatchEconomy.MATERIALS: 24, MatchEconomy.ENERGY: 15},
		"scene": preload("res://match/producers/mine.tscn"),
		"hp": 24, "size": Vector2(1.4, 1.4),
		"income": {MatchEconomy.MATERIALS: 2.0},
	},
	&"farm": {
		"label": "Farm", "cost": {MatchEconomy.MATERIALS: 20},
		"scene": preload("res://match/producers/farm.tscn"),
		"hp": 24, "size": Vector2(1.4, 1.4),
		"income": {MatchEconomy.FOOD: 3.0},
	},
	Fortifications.NEST: {
		"scene": preload("res://match/fortifications/machine_gun_nest.tscn"),
		"icon": preload("res://match/fortifications/machine_gun_nest.svg"),
	},
	Fortifications.MORTAR: {
		"scene": preload("res://match/fortifications/mortar.tscn"),
		"icon": preload("res://match/fortifications/mortar.svg"),
	},
	Fortifications.WALL: {
		"scene": preload("res://match/fortifications/wall.tscn"),
		"icon": preload("res://match/fortifications/wall.svg"),
	},
}
const VALID_PREVIEW := Color(0.37, 1.0, 0.70, 0.55)
const INVALID_PREVIEW := Color(1.0, 0.37, 0.40, 0.55)
const UNIT := preload("res://match/unit.tscn")
const STARTING_BASE := preload("res://match/starting_base.tscn")
const OUTPOST := preload("res://match/outpost.tscn")
const LANDMARK := preload("res://match/legendary_landmark.tscn")
const LEGENDARY_SEED_SALT := 0x4C4547454E444152
const LEGENDARY_OUTPOST_SPACING := 2.0
const INACTIVE_ACCENT := preload("res://match/inactive_accent.tres")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const CPU_DECISION_INTERVAL := 2.0
const CPU_OPENING_SUPPLY_CYCLES := 4.0
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

class PlacedBarracks:
	var production: MatchBattle.ProductionTimer
	var accent: MeshInstance3D


class PlacedFortification:
	var defense: MatchBattle.Fortification
	var view: Node3D
	var regions: Array[StringName]


var faction_stats: FactionStats
var economy: MatchEconomy
@export_group("Map")
@export var map_seed: int = 17
@export var map_width := TerritoryLayout.DEFAULT_SIZE.x
@export var map_height := TerritoryLayout.DEFAULT_SIZE.y
@export_range(TerritoryLayout.MIN_REGIONS, TerritoryLayout.MAX_REGIONS)
var region_count := TerritoryLayout.DEFAULT_REGION_COUNT
@export_range(1, TerritoryLayout.MAX_REGIONS) var player_start_count := 1
@export_range(1, TerritoryLayout.MAX_REGIONS) var cpu_start_count := 1
@export_group("Legendary Landmarks", "legendary_")
## Maximum number of landmarks. Each eligible region also rolls against spawn probability.
@export_range(0, TerritoryLayout.MAX_REGIONS) var legendary_count := 2
@export_range(0.0, 1.0, 0.01) var legendary_spawn_probability := 1.0
@export var legendary_neutral_only := true
@export var legendary_catalog: Array[LegendaryBuff] = [
	LegendaryBuff.new("War Spire", FactionStats.UNIT_DPS),
	LegendaryBuff.new("Sun Vault", FactionStats.ENERGY),
	LegendaryBuff.new("Founder’s Forge", FactionStats.MATERIALS),
	LegendaryBuff.new("Harvest Shrine", FactionStats.FOOD),
	LegendaryBuff.new("Ancient Bastion", FactionStats.BUILDING_MAX_HP, 10.0),
]
@export_group("")
@export_range(0.9, 12.0, 0.1) var unit_aggro_radius := MatchBattle.DEFAULT_AGGRO_RADIUS
@export var unit_target_priority := MatchBattle.TargetPriority.NEAREST
@export_range(1, 80) var outpost_hp := MatchBattle.DEFAULT_OUTPOST_HP

var active_map_seed: int:
	get:
		return _layout.active_seed if _layout != null else map_seed

var _battle: MatchBattle
var _layout: TerritoryLayout
var _regions_by_id: Dictionary[StringName, MatchRegion] = {}
var _initial_owners: Dictionary[StringName, MatchRegion.Owner] = {}
var _landmarks: Dictionary[StringName, LegendaryLandmark] = {}
var _outposts_by_region: Dictionary[StringName, MatchBattle.Outpost] = {}
var _outpost_views: Dictionary[StringName, Node3D] = {}
var _fortifications: Dictionary[int, PlacedFortification] = {}
var _fortification_ids: Dictionary[Node3D, int] = {}
var _selected_fortification := MatchBattle.NO_TARGET
var _range_ring: MeshInstance3D
var _splash_ring: MeshInstance3D
var _tracer_material := StandardMaterial3D.new()
var _wall_start := Vector2.INF
var _wall_release_pending := false
var _barracks_by_region: Dictionary[StringName, Array] = {}
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
@onready var _shot_effects := Node3D.new()
@onready var _regions: Node3D = $Regions
@onready var _units: Node3D = $Units
@onready var _unit_selection: MeshInstance3D = $UnitSelection
@onready var _unit_route: MeshInstance3D = $UnitRoute
@onready var _unit_panel: PanelContainer = %UnitInspection
@onready var _unit_name: Label = %UnitName
@onready var _unit_stats: Label = %UnitStats
@onready var _unit_intent: Label = %UnitIntent
@onready var _unit_order_hint: Label = %UnitOrderHint
@onready var _resource_readouts: HBoxContainer = %Resources
@onready var _barracks_label: Label = %BarracksCount
@onready var _build_button: Button = %Build
@onready var _build_menu: PanelContainer = %BuildMenu
@onready var _build_list: VBoxContainer = %BuildList
@onready var _placement_panel: PanelContainer = %PlacementPanel
@onready var _placement_label: Label = %PlacementStatus
@onready var _upgrade_button: Button = %Upgrade
@onready var _claim_button: Button = %Claim
@onready var _region_label: Label = %SelectedRegion
@onready var _landmark_panel: PanelContainer = %LandmarkInspection
@onready var _landmark_details: Label = %LandmarkDetails
@onready var _legendary_summary: Label = %LegendarySummary
@onready var _camera: StrategyCamera = $Camera
@onready var _player_hp_label: Label = %PlayerHP
@onready var _cpu_hp_label: Label = %CPUHP
@onready var _outcome_label: Label = %Outcome
@onready var _restart_button: Button = %Restart


func _ready() -> void:
	_generate_map()
	_unit_route.mesh = _route_mesh
	_unit_route.global_transform = _regions.global_transform
	_create_resource_readouts()
	for label in [_unit_stats, _player_hp_label, _cpu_hp_label, _region_label, _legendary_summary]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	for building_id in BUILDINGS:
		var definition: Dictionary = BUILDINGS[building_id]
		var option := Button.new()
		var profile: Dictionary = Fortifications.PROFILES.get(building_id, definition)
		option.text = "%s · %s" % [profile.label, MatchEconomy.cost_text(_minimum_build_cost(building_id))]
		option.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if building_id == Fortifications.WALL:
			option.text += " minimum"
		if definition.has("icon"):
			option.icon = definition.icon
		var effect: String = profile.get("description", "")
		if definition.has("income"):
			effect = _income_text(definition.income)
		elif definition.has("rules"):
			effect = "Auto-spawn · %s per unit" % MatchEconomy.cost_text(MatchEconomy.UNIT_COST)
		if not effect.is_empty():
			option.text += "\n" + effect
		option.pressed.connect(_begin_placement.bind(building_id))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_build_list.add_child(option)
		_build_options[building_id] = option
	%BuildScroll.custom_minimum_size.y = minf(_build_list.get_combined_minimum_size().y, 360.0)
	_build_button.pressed.connect(_toggle_build_menu)
	%CancelPlacement.pressed.connect(_cancel_placement)
	_preview_material = StandardMaterial3D.new()
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_ring = _create_radius_ring(Color("#ffe5a5"), 0.018)
	_splash_ring = _create_radius_ring(Color("#ffa977"), 0.06)
	add_child(_range_ring)
	add_child(_splash_ring)
	add_child(_shot_effects)
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tracer_material.albedo_color = Color("#fff0b8")
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_claim_button.text = "Claim\n%s" % MatchEconomy.cost_text(MatchEconomy.CLAIM_COST)
	_claim_button.pressed.connect(func() -> void: try_claim(PLAYER, _selected_region_id))
	_restart_button.pressed.connect(restart_match)
	%Overview.pressed.connect(func() -> void: _camera.reset_view())
	restart_match()


func _create_layout() -> TerritoryLayout:
	return TerritoryLayout.new(map_seed, region_count, Vector2(map_width, map_height),
		player_start_count, cpu_start_count)


func _generate_map() -> void:
	_layout = _create_layout()
	_camera.set_map_bounds(_layout.bounds)
	%Overview.tooltip_text = "Center the map and zoom out (Home)\nMap seed: %d" % active_map_seed
	for cell in _layout.cells:
		var region := MatchRegion.new(cell)
		region.name = cell.id
		match cell.id:
			TerritoryLayout.PLAYER_START:
				region.name = "PlayerStart"
			TerritoryLayout.CPU_START:
				region.name = "CPUStart"
		if cell.id in _layout.player_start_ids:
			region.region_owner = PLAYER
		elif cell.id in _layout.cpu_start_ids:
			region.region_owner = CPU
		_regions.add_child(region)
		_regions_by_id[cell.id] = region
		_initial_owners[cell.id] = region.region_owner
		if cell.id == TerritoryLayout.PLAYER_START or cell.id == TerritoryLayout.CPU_START:
			_add_starting_base(region)
	_generate_landmarks()


func _generate_landmarks() -> void:
	if legendary_count <= 0 or legendary_spawn_probability <= 0.0:
		return
	var catalog: Array[LegendaryBuff] = []
	var weights := PackedFloat32Array()
	for buff in legendary_catalog:
		if buff != null and buff.weight > 0 and not buff.landmark_name.strip_edges().is_empty() \
				and FactionStats.STAT_DEFINITIONS.has(buff.stat) and is_finite(buff.magnitude):
			catalog.append(buff)
			weights.append(buff.weight)
	if catalog.is_empty():
		return

	var eligible: Array[MatchRegion] = []
	for region in _regions_by_id.values():
		if not legendary_neutral_only or region.region_owner == MatchRegion.Owner.NEUTRAL:
			eligible.append(region)
	var occupied: Array[Rect2] = []
	for base in _bases.values():
		var center := _map_position(base.global_position)
		occupied.append(Rect2(center - MatchBattle.BASE_FOOTPRINT, MatchBattle.BASE_FOOTPRINT * 2.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = active_map_seed ^ LEGENDARY_SEED_SALT
	# Draw without replacement in seeded order, and skip cells with no safe site.
	for i in range(eligible.size()):
		if _landmarks.size() == legendary_count:
			break
		var next := rng.randi_range(i, eligible.size() - 1)
		var region := eligible[next]
		eligible[next] = eligible[i]
		if legendary_spawn_probability < 1.0 and rng.randf() >= legendary_spawn_probability:
			continue
		var outpost_site := region.interior_point() if region.region_owner == MatchRegion.Owner.NEUTRAL \
			else Vector2.INF
		var point := region.interior_point(_landmark_site_clear.bind(region, outpost_site, occupied))
		if not point.is_finite():
			continue
		var landmark := LANDMARK.instantiate() as LegendaryLandmark
		landmark.configure(region.region_id, point, catalog[rng.rand_weighted(weights)])
		region.add_child(landmark)
		landmark.global_position = _world_position(point)
		_landmarks[region.region_id] = landmark
		occupied.append(landmark.footprint)


func _landmark_site_clear(point: Vector2, region: MatchRegion, outpost_site: Vector2,
		occupied: Array[Rect2]) -> bool:
	if point.distance_squared_to(outpost_site) < LEGENDARY_OUTPOST_SPACING ** 2:
		return false
	var half_size := LegendaryLandmark.HALF_SIZE
	var footprint := Rect2(point - half_size, half_size * 2.0)
	for obstacle in occupied:
		if footprint.intersects(obstacle):
			return false
	var boundary_clearance := footprint.grow(MatchRegion.EDGE_GAP + MatchRegion.BORDER_WIDTH)
	for corner in BattleNavigation.corners_of(boundary_clearance):
		if not Geometry2D.is_point_in_polygon(corner, region.polygon):
			return false
	return true


func _add_starting_base(region: MatchRegion) -> void:
	var side := region.region_owner
	var base := STARTING_BASE.instantiate() as Node3D
	base.name = "PlayerBase" if side == PLAYER else "CPUBase"
	base.position.y = 0.08
	var offset := Vector2(0.0, 2.0)
	var site := Vector2(region.position.x, region.position.z)
	var footprint := Rect2(site + offset - MatchBattle.BASE_FOOTPRINT,
		MatchBattle.BASE_FOOTPRINT * 2.0)
	for corner in BattleNavigation.corners_of(footprint):
		if not Geometry2D.is_point_in_polygon(corner, region.polygon):
			offset = Vector2.ZERO
			break
	base.position.z = offset.y
	base.get_node("Core").material_override = FACTION_ACCENTS[side]
	region.add_child(base)
	_bases[side] = base


func restart_match() -> void:
	_camera.reset_view(true)
	if _battle != null:
		_battle.unit_produced.disconnect(_spawn_unit)
		_battle.unit_removed.disconnect(_remove_unit)
		_battle.base_destroyed.disconnect(_hide_base)
		_battle.outpost_destroyed.disconnect(_lose_region)
		_battle.fortification_destroyed.disconnect(_remove_fortification)
		_battle.fortification_fired.disconnect(_show_fortification_shot)
	for shot in _shot_effects.get_children():
		_shot_effects.remove_child(shot)
		shot.queue_free()
	for view in _outpost_views.values():
		view.get_parent().remove_child(view)
		view.queue_free()
	_outpost_views.clear()
	_outposts_by_region.clear()
	_barracks_by_region.clear()
	_fortifications.clear()
	_fortification_ids.clear()
	_select_fortification(MatchBattle.NO_TARGET)
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

	faction_stats = FactionStats.new()
	for landmark in _landmarks.values():
		faction_stats.set_modifier(landmark.source_id, _initial_owners[landmark.region_id],
			landmark.stat, landmark.magnitude, &"legendary", landmark.display_name,
			"", true, 0, landmark.region_id)
	economy = MatchEconomy.new(faction_stats)
	_time_until_cpu_decision = CPU_DECISION_INTERVAL
	_cpu_placement_rng.seed = 46
	_battle = MatchBattle.new(_map_position(_bases[PLAYER].global_position),
		_map_position(_bases[CPU].global_position), unit_aggro_radius,
		_layout.bounds, faction_stats)
	for landmark in _landmarks.values():
		_battle.add_landmark_footprint(landmark.footprint)
	_battle.target_priority = unit_target_priority
	_battle.unit_produced.connect(_spawn_unit)
	_battle.unit_removed.connect(_remove_unit)
	_battle.base_destroyed.connect(_hide_base)
	_battle.outpost_destroyed.connect(_lose_region)
	_battle.fortification_destroyed.connect(_remove_fortification)
	_battle.fortification_fired.connect(_show_fortification_shot)
	_refresh_legendary_summary()
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
		_select_fortification(MatchBattle.NO_TARGET)
		set_process(false)

	for unit in _battle.active_units():
		_update_unit_view(unit, _unit_views[unit.id])
	_update_unit_selection()
	_refresh_hud()


func try_place_building(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> bool:
	if not BUILDINGS.has(building_id) or building_id == Fortifications.WALL:
		return false

	var ground := _map_plane().project(world_position)
	var position := _map_position(ground)
	if Fortifications.PROFILES.has(building_id):
		var polygon := Fortifications.footprint(position, Fortifications.PROFILES[building_id].size)
		var regions := _owned_footprint_regions(side, polygon)
		if not _gun_block_reason(side, building_id, polygon, regions).is_empty() \
				or not economy.try_spend(side, _minimum_build_cost(building_id)):
			return false
		_add_fortification(side, building_id, position, 0.0, regions)
		_refresh_hud()
		return true

	if not _placement_block_reason(side, building_id, ground).is_empty():
		return false
	var definition: Dictionary = BUILDINGS[building_id]
	var region_id := region_at_world_position(ground)
	if definition.has("income"):
		if not economy.try_spend(side, definition.cost):
			return false
		var structure := _battle.add_structure(building_id, definition, side, position)
		_add_structure_view(structure, [region_id])
		for resource_id in definition.income:
			faction_stats.set_modifier(structure.source_id, side, resource_id,
				definition.income[resource_id], &"building",
				"%s #%d" % [definition.label, absi(structure.id)], "", true, structure.id, region_id)
		_refresh_hud()
		return true

	var production: MatchBattle.ProductionTimer = definition.rules.purchase(
		economy, _battle, side, position, definition.cost)
	if production == null:
		return false

	var building := definition.scene.instantiate() as Node3D
	var barracks := PlacedBarracks.new()
	barracks.production = production
	barracks.accent = building.get_node(definition.accent_node)
	barracks.accent.material_override = FACTION_ACCENTS[side]
	building.position = _buildings[side].to_local(ground)
	_buildings[side].add_child(building)
	if not _barracks_by_region.has(region_id):
		_barracks_by_region[region_id] = []
	_barracks_by_region[region_id].append(barracks)
	_refresh_hud()
	return true


func _placement_block_reason(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> String:
	if not owns_region(side, region_at_world_position(world_position)):
		return "Choose a spot in your territory"
	var position := _map_position(world_position)
	if Fortifications.PROFILES.has(building_id):
		var polygon := Fortifications.footprint(position, Fortifications.PROFILES[building_id].size)
		return _gun_block_reason(side, building_id, polygon, _owned_footprint_regions(side, polygon))
	var definition: Dictionary = BUILDINGS[building_id]
	if definition.has("income"):
		if not _battle.fortification_site_clear(Fortifications.footprint(position, definition.size)):
			return "Keep structures and spawn exits clear"
		return _purchase_block_reason(side, building_id)
	var clearance := MatchBattle.BARRACKS_FOOTPRINT + MatchBattle.OUTPOST_CLEARANCE
	for outpost: MatchBattle.Outpost in _outposts_by_region.values():
		var offset := (outpost.position - position).abs()
		if offset.x < clearance.x and offset.y < clearance.y:
			return "Keep the outpost clear"
	var spawn_size := MatchBattle.BARRACKS_SPAWN_CLEARANCE * 2.0
	if not _battle.fortification_site_clear(Fortifications.footprint(position, spawn_size), true):
		return "Keep defenses and spawn exits clear"
	return _purchase_block_reason(side, building_id)


func _gun_block_reason(side: MatchRegion.Owner, building_id: StringName,
		polygon: PackedVector2Array, regions: Array[StringName]) -> String:
	if regions.is_empty():
		return "Keep the footprint in your territory"
	if not _battle.fortification_site_clear(polygon):
		return "Keep structures and spawn exits clear"
	return _purchase_block_reason(side, building_id)


func _purchase_block_reason(side: MatchRegion.Owner, building_id: StringName) -> String:
	if _battle.is_finished():
		return "Match ended"
	if not _buildings.has(side) or not BUILDINGS.has(building_id):
		return "Building unavailable"
	return economy.cost_block_reason(side, _minimum_build_cost(building_id))


func _minimum_build_cost(building_id: StringName) -> Dictionary:
	if building_id == Fortifications.WALL:
		return Fortifications.wall_cost(1)
	return Fortifications.PROFILES.get(building_id, BUILDINGS[building_id]).cost


func _owned_footprint_regions(side: MatchRegion.Owner,
		polygon: PackedVector2Array) -> Array[StringName]:
	var covered: Array[StringName] = []
	if not _buildings.has(side):
		return covered
	for point in polygon:
		if not _layout.bounds.has_point(point):
			return []
	for region_id in _regions_by_id:
		var region := get_region(region_id)
		if not Geometry2D.intersect_polygons(polygon, region.polygon).is_empty():
			if region.region_owner != side:
				return []
			covered.append(region_id)
	return covered


func _wall_plan(side: MatchRegion.Owner, start: Vector2, end: Vector2) -> Dictionary:
	var plan := {"reason": "", "length": 0.0, "cost": {}, "angle": 0.0, "segments": []}
	if not start.is_finite() or not end.is_finite() or not _layout.bounds.has_point(start) \
			or not _layout.bounds.has_point(end):
		plan.reason = "Keep both endpoints on the map"
		return plan
	var count := Fortifications.wall_count(start.distance_to(end))
	if count < 1:
		plan.reason = "Minimum length %s unit" % _stat_number(Fortifications.WALL_SEGMENT_LENGTH)
		return plan
	var direction := start.direction_to(end)
	var step := direction * Fortifications.WALL_SEGMENT_LENGTH
	plan.angle = direction.angle()
	plan.length = count * Fortifications.WALL_SEGMENT_LENGTH
	plan.cost = Fortifications.wall_cost(count)
	if _battle.is_finished():
		plan.reason = "Match ended"
		return plan
	for i in range(count):
		var center := start + step * (i + 0.5)
		var polygon := Fortifications.footprint(center, Fortifications.PROFILES[Fortifications.WALL].size,
			plan.angle)
		var regions := _owned_footprint_regions(side, polygon)
		if regions.is_empty():
			plan.reason = "Keep the entire wall in your territory"
			return plan
		if not _battle.fortification_site_clear(polygon):
			plan.reason = "Keep structures and spawn exits clear"
			return plan
		plan.segments.append({"center": center, "regions": regions})
	plan.reason = economy.cost_block_reason(side, plan.cost)
	return plan


func try_place_wall(side: MatchRegion.Owner, world_start: Vector3, world_end: Vector3) -> bool:
	var plan := _wall_plan(side, _map_position(world_start), _map_position(world_end))
	if not plan.reason.is_empty() or not economy.try_spend(side, plan.cost):
		return false
	for segment: Dictionary in plan.segments:
		_add_fortification(side, Fortifications.WALL, segment.center, plan.angle, segment.regions)
	_refresh_hud()
	return true


func _add_fortification(side: MatchRegion.Owner, kind: StringName, center: Vector2, angle: float,
		regions: Array[StringName]) -> void:
	_add_structure_view(_battle.add_fortification(kind, side, center, angle), regions)


func _add_structure_view(defense: MatchBattle.Fortification, regions: Array[StringName]) -> void:
	var view := BUILDINGS[defense.kind].scene.instantiate() as Node3D
	_buildings[defense.side].add_child(view)
	view.global_position = _world_position(defense.position)
	view.rotation.y = -defense.angle
	view.get_node("Marking").material_override = FACTION_ACCENTS[defense.side]
	var placed := PlacedFortification.new()
	placed.defense = defense
	placed.view = view
	placed.regions = regions
	_fortifications[defense.id] = placed
	_fortification_ids[view] = defense.id


func _remove_fortification(defense: MatchBattle.Fortification) -> void:
	var placed := _fortifications[defense.id]
	_fortifications.erase(defense.id)
	_fortification_ids.erase(placed.view)
	placed.view.get_parent().remove_child(placed.view)
	placed.view.queue_free()
	if _selected_fortification == defense.id:
		_select_fortification(MatchBattle.NO_TARGET)


func _show_fortification_shot(fort: MatchBattle.Fortification, impact: Vector2) -> void:
	var effect := MeshInstance3D.new()
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shot_effects.add_child(effect)
	var end := Vector3(impact.x, 0.20, impact.y)
	if fort.profile.splash > 0.0:
		effect.mesh = _splash_ring.mesh
		effect.position = end
		effect.scale = Vector3.ONE * float(fort.profile.splash)
	else:
		var start := Vector3(fort.position.x, 0.46, fort.position.y)
		var perpendicular := fort.position.direction_to(impact).orthogonal() * 0.035
		var width := Vector3(perpendicular.x, 0.0, perpendicular.y)
		var tracer := ImmediateMesh.new()
		tracer.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _tracer_material)
		tracer.surface_add_vertex(start - width)
		tracer.surface_add_vertex(start + width)
		tracer.surface_add_vertex(end - width)
		tracer.surface_add_vertex(end + width)
		tracer.surface_end()
		effect.mesh = tracer
	effect.global_transform = _regions.global_transform * effect.transform
	effect.create_tween().tween_callback(effect.queue_free).set_delay(0.16)


func _world_position(point: Vector2) -> Vector3:
	return _regions.to_global(Vector3(point.x, 0.0, point.y))


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
	_update_unit_selection()
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
	_clear_wall_drag()
	_placement_panel.hide()
	_build_menu.hide()
	_update_unit_selection()
	_update_fortification_inspection()


func _update_placement_preview(pointer: Vector2) -> void:
	if _placement_id == Fortifications.WALL:
		_update_wall_preview(pointer)
		return
	var definition: Dictionary = Fortifications.PROFILES.get(_placement_id, BUILDINGS[_placement_id])
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
	if definition.has("income"):
		_placement_label.text += "\n" + _income_text(definition.income)
	if definition.has("range"):
		_placement_label.text += "\n" + _range_text(definition)
		_show_ranges(definition, _map_position(_preview.global_position), _preview.visible)
	else:
		_hide_ranges()
	_placement_panel.show()


func _update_wall_preview(pointer: Vector2) -> void:
	_hide_ranges()
	_preview.hide()
	var point: Variant = _ground_point(pointer) if pointer != Vector2.INF else null
	var reason := "Drag from a spot in your territory"
	var details := "Whole units, rounded down · %s minimum" % MatchEconomy.cost_text(
		_minimum_build_cost(Fortifications.WALL))
	if _wall_start.is_finite() and point != null:
		var plan := _wall_plan(PLAYER, _wall_start, _map_position(point))
		reason = "Release to build" if plan.reason.is_empty() else plan.reason
		if plan.length > 0.0:
			_preview.global_position = _world_position(_wall_start
				+ Vector2.from_angle(plan.angle) * plan.length * 0.5)
			_preview.rotation.y = -plan.angle
			_preview.scale.x = plan.length / Fortifications.WALL_SEGMENT_LENGTH
			var unit_label := "unit" if is_equal_approx(plan.length, 1.0) else "units"
			details = "%s %s · %s" % [_stat_number(plan.length), unit_label, MatchEconomy.cost_text(plan.cost)]
			_preview_material.albedo_color = VALID_PREVIEW if plan.reason.is_empty() else INVALID_PREVIEW
			_preview.show()
	elif point != null:
		_preview.global_position = point
		_preview.rotation.y = 0.0
		_preview.scale.x = 1.0
		var valid := owns_region(PLAYER, region_at_world_position(point))
		_preview_material.albedo_color = VALID_PREVIEW if valid else INVALID_PREVIEW
		_preview.show()
	_placement_label.text = "Wall · %s\n%s" % [reason, details]
	_placement_panel.show()



func try_upgrade(side: MatchRegion.Owner) -> bool:
	if _battle.is_finished() or not economy.try_upgrade(side):
		return false

	_refresh_hud()
	return true


func try_claim(side: MatchRegion.Owner, region_id: StringName) -> bool:
	if not _claim_block_reason(region_id, side).is_empty():
		return false
	var region := get_region(region_id)
	var point := region.interior_point(_battle.outpost_site_clear)
	if not economy.try_spend(side, MatchEconomy.CLAIM_COST):
		return false

	_set_region_owner(region_id, side)
	var outpost := _battle.add_outpost(region_id, side, point, maxi(1, outpost_hp))
	_outposts_by_region[region_id] = outpost
	var view := OUTPOST.instantiate() as Node3D
	view.get_node("Beacon").material_override = FACTION_ACCENTS[side]
	region.add_child(view)
	view.global_position = _regions.to_global(Vector3(point.x, 0.0, point.y))
	_outpost_views[region_id] = view
	_refresh_claim_control()
	return true


func _lose_region(outpost: MatchBattle.Outpost) -> void:
	var region_id := outpost.region_id
	var view := _outpost_views[region_id]
	view.get_parent().remove_child(view)
	view.queue_free()
	_outpost_views.erase(region_id)
	_outposts_by_region.erase(region_id)
	_set_region_owner(region_id, MatchRegion.Owner.NEUTRAL)
	_update_unit_selection()


func _set_region_owner(region_id: StringName, side: MatchRegion.Owner) -> void:
	get_region(region_id).region_owner = side
	faction_stats.set_source_owner(region_source_id(region_id), side)
	var landmark := _landmarks.get(region_id) as LegendaryLandmark
	if landmark != null:
		faction_stats.set_source_owner(landmark.source_id, side)
		_refresh_legendary_summary()
	for barracks: PlacedBarracks in _barracks_by_region.get(region_id, []):
		var active := barracks.production.side == side
		_battle.set_barracks_active(barracks.production, active)
		barracks.accent.material_override = FACTION_ACCENTS[side] if active else INACTIVE_ACCENT
	for placed in _fortifications.values():
		if not placed.regions.has(region_id):
			continue
		var active := true
		for covered in placed.regions:
			if not owns_region(placed.defense.side, covered):
				active = false
				break
		_battle.set_fortification_active(placed.defense, active)
		placed.view.get_node("Marking").material_override = FACTION_ACCENTS[placed.defense.side] \
			if active else INACTIVE_ACCENT
	_refresh_hud()
	if _preview != null:
		_refresh_placement_preview()


## Use this ID for contributions that follow control of a region.
static func region_source_id(region_id: StringName) -> StringName:
	return StringName("region/" + region_id)


func set_region_modifier(region_id: StringName, stat: StringName, magnitude: float,
		source_name: String, source_type := &"landmark", description := "") -> bool:
	var region := get_region(region_id)
	return region != null and faction_stats.set_modifier(region_source_id(region_id),
		region.region_owner, stat, magnitude, source_type, source_name, description)


func owns_region(side: MatchRegion.Owner, region_id: StringName) -> bool:
	var region := get_region(region_id)
	return region != null and region.region_owner == side


func get_region(region_id: StringName) -> MatchRegion:
	return _regions_by_id.get(region_id)


func region_at_world_position(world_position: Vector3) -> StringName:
	return _layout.region_at(_map_position(world_position))


func selected_unit() -> MatchBattle.Unit:
	return _battle.get_unit(_selected_unit_id) if _battle != null else null


func _map_position(world_position: Vector3) -> Vector2:
	var local := _regions.to_local(world_position)
	return Vector2(local.x, local.z)


func _claim_block_reason(region_id: StringName, side := PLAYER) -> String:
	var region := get_region(region_id)
	if region == null:
		return "Select a region"
	if region.region_owner == PLAYER:
		return "Player-owned"
	if region.region_owner == CPU:
		return "CPU-owned"
	if _battle.is_finished():
		return "Match ended"
	if not _buildings.has(side):
		return "Claim unavailable"
	for neighbor_id in region.neighbor_ids:
		if owns_region(side, neighbor_id):
			var reason := economy.cost_block_reason(side, MatchEconomy.CLAIM_COST)
			if not reason.is_empty():
				return reason
			if not region.interior_point(_battle.outpost_site_clear).is_finite():
				return "No room for an outpost"
			return ""
	return "Not adjacent"


func _input(event: InputEvent) -> void:
	if not _camera.is_dragging() and (_preview != null or _build_menu.visible):
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
	if _wall_start.is_finite() and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		# A release consumed by the HUD must end the drag without building.
		_wall_release_pending = true
		_finish_consumed_wall_release.call_deferred()


func _finish_consumed_wall_release() -> void:
	if _wall_release_pending:
		_clear_wall_drag()


func _clear_wall_drag() -> void:
	_wall_start = Vector2.INF
	_wall_release_pending = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (selected_unit() != null
			or _selected_fortification != MatchBattle.NO_TARGET):
		_select_unit(MatchBattle.NO_TARGET)
		_select_fortification(MatchBattle.NO_TARGET)
		get_viewport().set_input_as_handled()
	elif _placement_id == Fortifications.WALL and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Variant = _ground_point(event.position)
		if event.pressed:
			_wall_release_pending = false
			_wall_start = _map_position(point) if point != null else Vector2.INF
		else:
			if not _camera.is_dragging() and _wall_start.is_finite() and point != null \
					and try_place_wall(PLAYER, _world_position(_wall_start), point):
				_cancel_placement()
			_clear_wall_drag()
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
		_refresh_placement_preview()


func _refresh_placement_preview() -> void:
	var pointer := get_viewport().get_mouse_position()
	if _camera.is_dragging() or get_viewport().gui_get_hovered_control() != null:
		pointer = Vector2.INF
	_update_placement_preview(pointer)


func _pick_map(pointer: Vector2) -> void:
	var id := _pick_unit(pointer)
	var unit := _battle.get_unit(id)
	if unit != null and not _battle.is_finished():
		_select_fortification(MatchBattle.NO_TARGET)
		_select_unit(id)
		_select_region(&"")
	else:
		_select_unit(MatchBattle.NO_TARGET)
		var building := _pick_building(pointer)
		_select_fortification(_fortification_ids.get(building, MatchBattle.NO_TARGET))
		var point: Variant = _ground_point(pointer) if building == null else building.global_position
		_select_region(region_at_world_position(point) if point != null else &"")
	_refresh_claim_control()


func _pick_building(pointer: Vector2) -> Node3D:
	var start := _camera.project_ray_origin(pointer)
	var end := start + _camera.project_ray_normal(pointer) * _camera.far
	var buildings: Array[Node] = [_bases[PLAYER], _bases[CPU]]
	buildings.append_array(_buildings[PLAYER].get_children())
	buildings.append_array(_buildings[CPU].get_children())
	buildings.append_array(_outpost_views.values())
	buildings.append_array(_landmarks.values())
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
	return nearest


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
	var unit := selected_unit() if _placement_id.is_empty() and _battle != null else null
	_unit_selection.visible = unit != null
	_unit_panel.visible = unit != null
	_route_mesh.clear_surfaces()
	if unit == null:
		return

	_unit_selection.global_position = _unit_views[unit.id].global_position
	_unit_name.text = "%s combat unit #%d" % [_side_label(unit.side), unit.id]
	_unit_name.modulate = FACTION_ACCENTS[unit.side].albedo_color.lightened(0.25)
	var attack := _battle.unit_attack_stat(unit)
	_unit_stats.text = "HP  %s / %d\nAttack  %s · Speed  %.1f units/s" % [
		_stat_number(unit.hp), MatchBattle.UNIT_HP, _stat_number(attack.total),
		MatchBattle.MOVEMENT_SPEED,
	]
	_unit_stats.tooltip_text = _stat_tooltip("Damage per attack", attack) + "\n\n" \
		+ _stat_tooltip("Damage per second", _battle.unit_dps_stat(unit))
	_unit_intent.text = "Target  %s\nState  %s" % [_target_label(unit), _unit_state_label(unit)]
	_unit_order_hint.visible = _selected_unit_can_receive_orders()
	if not unit.waypoints.is_empty():
		_draw_unit_route(unit)


func _select_fortification(id: int) -> void:
	_selected_fortification = id
	_update_fortification_inspection()


func _update_fortification_inspection() -> void:
	var placed: PlacedFortification = _fortifications.get(_selected_fortification)
	if placed == null or not _placement_id.is_empty():
		if _placement_id.is_empty():
			_hide_ranges()
		if placed == null and selected_unit() == null:
			_unit_panel.hide()
		return
	var fort := placed.defense
	_unit_panel.show()
	_unit_name.text = "%s %s" % [_side_label(fort.side), fort.profile.label]
	_unit_name.modulate = FACTION_ACCENTS[fort.side].albedo_color.lightened(0.25)
	_unit_stats.text = _health_text(fort)
	_unit_stats.tooltip_text = _stat_tooltip("Maximum HP", fort.health_stat())
	_unit_intent.text = "Active" if fort.active else "Inactive · territory lost"
	if fort.active and fort.profile.has("income"):
		_unit_intent.text += "\n" + _income_text(fort.profile.income)
	if fort.profile.get("range", 0.0) > 0.0:
		_unit_intent.text += "\n" + _range_text(fort.profile).replace(" · ", "\n")
	_unit_order_hint.hide()
	_show_ranges(fort.profile, fort.position, true)


func _health_text(building: MatchBattle.BuildingHealth) -> String:
	return "HP  %s / %s" % [_stat_number(building.hp), _stat_number(building.max_hp)]


func _range_text(profile: Dictionary) -> String:
	var label := "Range %s" % _stat_number(profile.range)
	if profile.splash > 0.0:
		label += " · Splash radius %s" % _stat_number(profile.splash)
	return label


func _create_radius_ring(color: Color, width_fraction: float) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, material)
	for i in range(65):
		var angle := TAU * i / 64.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		mesh.surface_add_vertex(direction)
		mesh.surface_add_vertex(direction * (1.0 - width_fraction))
	mesh.surface_end()
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.hide()
	return ring


func _show_ranges(profile: Dictionary, center: Vector2, visible_at_point: bool) -> void:
	_show_radius_ring(_range_ring, profile.get("range", 0.0),
		Vector3(center.x, 0.15, center.y), visible_at_point)
	_show_radius_ring(_splash_ring, profile.get("splash", 0.0),
		Vector3(center.x, 0.16, center.y), visible_at_point)


func _show_radius_ring(ring: MeshInstance3D, radius: float, center: Vector3, visible_at_point: bool) -> void:
	ring.visible = visible_at_point and radius > 0.0
	if ring.visible:
		var map_transform := Transform3D(Basis.from_scale(Vector3.ONE * radius), center)
		ring.global_transform = _regions.global_transform * map_transform


func _hide_ranges() -> void:
	_range_ring.hide()
	_splash_ring.hide()


func _selected_unit_can_receive_orders() -> bool:
	var unit := selected_unit()
	return unit != null and unit.side == PLAYER and not _battle.is_finished()


func _target_label(unit: MatchBattle.Unit) -> String:
	if unit.target == MatchBattle.BASE_TARGET:
		return "CPU base" if unit.side == PLAYER else "Player base"
	var target := _battle.get_unit(unit.target)
	if target != null:
		return "%s unit #%d" % [_side_label(target.side), target.id]
	var outpost := _battle.get_outpost(unit.target)
	if outpost != null:
		return "%s outpost · %d/%d HP" % [_side_label(outpost.side), outpost.hp, outpost.max_hp]
	var fort := _battle.get_fortification(unit.target)
	if fort != null:
		return "%s · %s" % [fort.profile.label, _health_text(fort)]
	return "None"


func _unit_state_label(unit: MatchBattle.Unit) -> String:
	if unit.can_attack_target:
		return "Engaging"
	if not unit.waypoints.is_empty():
		if unit.target > MatchBattle.NO_TARGET or unit.target < MatchBattle.BASE_TARGET:
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
	_battle.advance(delta, economy, true)


func _try_cpu_purchase() -> void:
	var active_barracks := _battle.active_barracks_count(CPU)
	if active_barracks == 0 and _try_cpu_build(&"barracks"):
		return

	var food_per_unit := float(MatchEconomy.UNIT_COST[MatchEconomy.FOOD])
	var food_income := economy.income_rate(CPU, MatchEconomy.FOOD)
	var interval := economy.production_interval(CPU)
	var demand := food_per_unit * active_barracks / MatchEconomy.UPGRADED_PRODUCTION_INTERVAL
	# Opening stockpiles can fund expansion while the CPU saves for a Farm.
	var opening_cycle_deficit := food_per_unit * (active_barracks + 1) - food_income * interval
	if not economy.has_upgrade(CPU) and food_income < demand \
			and economy.stockpile(CPU, MatchEconomy.FOOD) >= opening_cycle_deficit * CPU_OPENING_SUPPLY_CYCLES:
		if not _purchase_block_reason(CPU, &"barracks").is_empty() or _try_cpu_build(&"barracks"):
			return

	# Secure the income needed to keep all barracks running after the upgrade.
	if food_income < demand:
		_try_cpu_build(&"farm")
		return
	if not economy.has_upgrade(CPU):
		try_upgrade(CPU)
		return

	for building_id in BUILDINGS:
		var income: Dictionary = BUILDINGS[building_id].get("income", {})
		if income.is_empty():
			continue
		var has_active_building := false
		for placed: PlacedFortification in _fortifications.values():
			var structure := placed.defense
			if structure.side == CPU and structure.kind == building_id and structure.active:
				has_active_building = true
				break
		if not has_active_building and _try_cpu_build(building_id):
			return

	# Support the next barracks with recurring income before adding its unit costs.
	if food_income >= demand + food_per_unit / interval:
		_try_cpu_build(&"barracks")
	elif _purchase_block_reason(CPU, &"barracks").is_empty():
		_try_cpu_build(&"farm")


func _try_cpu_build(building_id: StringName) -> bool:
	if not _purchase_block_reason(CPU, building_id).is_empty():
		return false
	for region: MatchRegion in _regions_by_id.values():
		if region.region_owner != CPU:
			continue
		var tile := region.geometry
		var bounds := tile.get_aabb()
		# Sample the territory and let the shared placement check validate its shape.
		for attempt in range(8):
			var point := tile.to_global(Vector3(
				_cpu_placement_rng.randf_range(bounds.position.x, bounds.end.x),
				bounds.end.y,
				_cpu_placement_rng.randf_range(bounds.position.z, bounds.end.z)))
			if try_place_building(CPU, building_id, point):
				return true
	return false


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


func _create_resource_readouts() -> void:
	for resource_id in MatchEconomy.RESOURCES:
		var readout := VBoxContainer.new()
		readout.name = resource_id
		readout.custom_minimum_size.x = 100
		readout.mouse_filter = Control.MOUSE_FILTER_STOP
		readout.alignment = BoxContainer.ALIGNMENT_CENTER
		readout.add_theme_constant_override("separation", 0)
		_resource_readouts.add_child(readout)

		var stockpile := Label.new()
		stockpile.name = &"Stockpile"
		stockpile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stockpile.add_theme_font_size_override("font_size", 18)
		stockpile.add_theme_color_override("font_color", Color(0.99, 0.81, 0.49))
		readout.add_child(stockpile)

		var rate := Label.new()
		rate.name = &"Rate"
		rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate.add_theme_color_override("font_color", Color(0.73, 0.84, 0.90))
		readout.add_child(rate)


func _refresh_resource_readouts() -> void:
	for readout: Control in _resource_readouts.get_children():
		var resource_id := readout.name
		var resource_label: String = MatchEconomy.RESOURCES[resource_id].label
		var stockpile := readout.get_node(^"Stockpile") as Label
		var rate := readout.get_node(^"Rate") as Label
		stockpile.text = "%s %d" % [resource_label, floori(economy.stockpile(PLAYER, resource_id))]
		var income := economy.income_stat(PLAYER, resource_id)
		rate.text = _stat_amount(income.total, "/s")
		readout.tooltip_text = _stat_tooltip(resource_label + " income", income, "/s")


func _stat_number(value: float) -> String:
	var amount := String.num(value, 3)
	if amount.contains("."):
		amount = amount.rstrip("0").rstrip(".")
	return amount


func _stat_amount(value: float, suffix: String) -> String:
	return "%s%s%s" % ["+" if value >= 0.0 and not suffix.is_empty() else "",
		_stat_number(value), suffix]


func _income_text(income: Dictionary) -> String:
	var rates := PackedStringArray()
	for resource_id in income:
		rates.append("%s %s" % [_stat_amount(income[resource_id], "/s"),
			MatchEconomy.RESOURCES[resource_id].label])
	return ", ".join(rates)


func _stat_tooltip(title: String, result: Dictionary, suffix := "") -> String:
	var lines := PackedStringArray([title])
	for source: Dictionary in result.breakdown:
		if source.active:
			lines.append("%s  %s" % [source.source_name, _stat_amount(source.magnitude, suffix)])
	lines.append("Total  " + _stat_amount(result.total, suffix))
	return "\n".join(lines)


func _legendary_effect(landmark: LegendaryLandmark) -> String:
	if MatchEconomy.RESOURCES.has(landmark.stat):
		return _income_text({landmark.stat: landmark.magnitude})
	var label := str(landmark.stat).capitalize()
	match landmark.stat:
		FactionStats.UNIT_DPS:
			label = "Unit DPS"
		FactionStats.BUILDING_MAX_HP:
			label = "Building max HP"
	return "%s%s %s" % ["+" if landmark.magnitude >= 0.0 else "",
		_stat_number(landmark.magnitude), label]


func _refresh_legendary_summary() -> void:
	_legendary_summary.get_parent().visible = not _landmarks.is_empty()
	var counts := {PLAYER: 0, CPU: 0}
	var entries := PackedStringArray()
	for landmark in _landmarks.values():
		var side := get_region(landmark.region_id).region_owner
		if side == MatchRegion.Owner.NEUTRAL:
			continue
		counts[side] += 1
		entries.append("%s · %s (%s) · %s" % [_side_label(side), landmark.display_name,
			str(landmark.region_id).capitalize(), _legendary_effect(landmark)])
	_legendary_summary.text = "Legendary bonuses · Player %d · CPU %d" % [counts[PLAYER], counts[CPU]]
	_legendary_summary.tooltip_text = "Claim landmark regions to activate their bonuses." \
		if entries.is_empty() else "\n".join(entries)


func _refresh_hud() -> void:
	_player_hp_label.text = "Player base · %s HP" % _stat_number(_battle.base_hp(PLAYER))
	_cpu_hp_label.text = "CPU base · %s HP" % _stat_number(_battle.base_hp(CPU))
	_player_hp_label.tooltip_text = _stat_tooltip("Maximum HP", _battle.base_health_stat(PLAYER))
	_cpu_hp_label.tooltip_text = _stat_tooltip("Maximum HP", _battle.base_health_stat(CPU))
	_outcome_label.text = OUTCOME_LABELS[_battle.outcome()]
	_outcome_label.visible = _battle.is_finished()
	_refresh_resource_readouts()
	_barracks_label.text = "Barracks %d" % economy.barracks_count(PLAYER)
	for building_id in _build_options:
		var reason := _purchase_block_reason(PLAYER, building_id)
		_build_options[building_id].disabled = not reason.is_empty()
		_build_options[building_id].tooltip_text = reason
	_build_button.disabled = _battle.is_finished()
	_update_fortification_inspection()
	_upgrade_button.disabled = _battle.is_finished() or not economy.can_upgrade(PLAYER)
	_upgrade_button.text = (
		"Upgraded" if economy.has_upgrade(PLAYER)
		else "Upgrade\n%s" % MatchEconomy.cost_text(MatchEconomy.UPGRADE_COST)
	)
	_refresh_claim_control()


func _refresh_claim_control() -> void:
	var reason := _claim_block_reason(_selected_region_id)
	_claim_button.disabled = not reason.is_empty()
	var tooltip := ""
	if _regions_by_id.has(_selected_region_id):
		var region := get_region(_selected_region_id)
		var title := str(_selected_region_id).capitalize()
		if region.region_owner == MatchRegion.Owner.NEUTRAL:
			title += " · Neutral"
		var outpost := _outposts_by_region.get(_selected_region_id) as MatchBattle.Outpost
		if outpost != null:
			var health := outpost.health_stat()
			reason += "\nOutpost · %s/%s HP" % [_stat_number(outpost.hp), _stat_number(health.total)]
			tooltip = _stat_tooltip("Maximum HP", health)
		_region_label.text = "%s\n%s" % [
			title, reason,
		]
	else:
		_region_label.text = reason
	_region_label.tooltip_text = tooltip
	var landmark := _landmarks.get(_selected_region_id) as LegendaryLandmark
	_landmark_panel.visible = landmark != null
	if landmark != null:
		var side := get_region(landmark.region_id).region_owner
		var status := "Neutral · Inactive" if side == MatchRegion.Owner.NEUTRAL \
			else "%s-controlled · Active" % _side_label(side)
		_landmark_details.text = "%s · %s\n%s\n%s" % [landmark.display_name,
			str(landmark.region_id).capitalize(), _legendary_effect(landmark), status]
