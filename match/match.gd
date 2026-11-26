extends Node3D

const Fortifications := preload("res://match/fortification_rules.gd")
const BUILDINGS := {
	&"barracks": {
		"cost": MatchEconomy.BARRACKS_COST,
		"scene": preload("res://match/barracks.tscn"),
		"accent_node": ^"RoofMarking",
		"label": "Barracks", "hp": MatchBattle.BARRACKS_HP,
		"size": MatchBattle.BARRACKS_FOOTPRINT * 2.0,
		"unit_type": UnitCatalog.INFANTRY, "interval": MatchEconomy.PRODUCTION_INTERVAL,
	},
	&"training_range": {
		"label": "Training Range", "cost": {MatchEconomy.ENERGY: 45, MatchEconomy.MATERIALS: 25},
		"scene": preload("res://match/training_range.tscn"),
		"hp": 28, "size": Vector2(2.6, 1.8),
		"unit_type": UnitCatalog.RANGED, "interval": 4.5,
	},
	&"heavy_factory": {
		"label": "Heavy Factory", "cost": {MatchEconomy.ENERGY: 55, MatchEconomy.MATERIALS: 35},
		"scene": preload("res://match/heavy_factory.tscn"),
		"hp": 40, "size": Vector2(2.9, 2.1),
		"unit_type": UnitCatalog.HEAVY, "interval": 6.0,
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
const UnitAttackEffects := preload("res://match/unit_attack_effects.gd")
const UnitCatalog := preload("res://match/unit_catalog.gd")
const DEFAULT_REGION_BUILDING_CAPACITY := 5
const BASE_KIND := &"base"
const OUTPOST_KIND := &"outpost"
const LEGENDARY_KIND := &"legendary"
const FIXED_STRUCTURE_LABELS := {
	BASE_KIND: "Base",
	OUTPOST_KIND: "Outpost",
	LEGENDARY_KIND: "Legendary",
}
const STARTING_BASE := preload("res://match/starting_base.tscn")
const OUTPOST := preload("res://match/outpost.tscn")
const LANDMARK := preload("res://match/legendary_landmark.tscn")
const LEGENDARY_SEED_SALT := 0x4C4547454E444152
const LEGENDARY_OUTPOST_SPACING := 2.0
const INACTIVE_ACCENT := preload("res://match/inactive_accent.tres")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const DifficultyProfile := preload("res://match/difficulty_profile.gd")
const CpuStrategy := preload("res://match/cpu_strategy.gd")
const ScoutExpeditions := preload("res://match/scout_expeditions.gd")
const CLAIM_DISCOVERY := &"claim_completed"

signal claim_completed(faction: MatchRegion.Owner, region: StringName, scout_id: int)
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

class PlacedFortification:
	var defense: MatchBattle.Fortification
	var view: Node3D
	# Ownership requirements for activation. Occupancy tracks the physical footprint separately.
	var regions: Array[StringName]


var faction_stats: FactionStats
var economy: MatchEconomy
var narrative_events: NarrativeEvents

@export var narrative_catalog: NarrativeCatalog
@export_group("Map")
@export var map_seed: int = 17
@export var map_width := TerritoryLayout.DEFAULT_SIZE.x
@export var map_height := TerritoryLayout.DEFAULT_SIZE.y
@export_range(TerritoryLayout.MIN_REGIONS, TerritoryLayout.MAX_REGIONS)
var region_count := TerritoryLayout.DEFAULT_REGION_COUNT
@export_range(1, 128) var region_building_capacity := DEFAULT_REGION_BUILDING_CAPACITY
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
@export_group("Match Setup")
@export var show_match_setup_on_start := false

@export_group("CPU Strategy", "cpu_")
@export_range(0.25, 10.0, 0.25) var cpu_decision_interval := 2.0
@export_range(4.0, 24.0, 0.5) var cpu_threat_radius := 10.0
@export_range(2.0, 60.0, 0.5) var cpu_defense_cooldown := 6.0
@export_range(2.0, 60.0, 0.5) var cpu_placement_retry := 8.0
@export_range(0, 16) var cpu_expansion_limit := 3
@export_range(8.0, 45.0, 0.5) var cpu_investment_horizon := 26.0
@export_range(1, 16) var cpu_production_target := 4
@export_range(1, 16) var cpu_production_limit := 8
@export_range(1.0, 6.0, 0.5) var cpu_food_buffer_cycles := 3.0
@export_range(0.0, 5.0, 0.1) var cpu_diversity_weight := 0.8
@export_range(0.0, 5.0, 0.1) var cpu_counter_weight := 2.8
@export_range(0.0, 1.0, 0.05) var cpu_counter_gap := 0.15
@export_range(0.25, 30.0, 0.25) var cpu_scout_dispatch_interval := 6.0
@export_range(0, 100) var cpu_scout_energy_reserve := 10
@export_range(0.0, 5.0, 0.1) var cpu_scout_travel_weight := 2.0
@export_range(0.0, 5.0, 0.1) var cpu_scout_connection_weight := 1.0
@export_range(0.0, 5.0, 0.1) var cpu_scout_capacity_weight := 1.4
@export_range(0.0, 5.0, 0.1) var cpu_scout_production_weight := 0.5
@export_range(0.0, 5.0, 0.1) var cpu_scout_landmark_weight := 1.2
@export_range(0.0, 5.0, 0.1) var cpu_scout_danger_weight := 4.0
@export_range(0.0, 1.0, 0.05) var cpu_scout_max_danger := 0.8
@export_group("Scout Expeditions")
@export_range(1, 500) var claim_energy: int = MatchEconomy.CLAIM_COST[MatchEconomy.ENERGY]
@export_range(0.1, 120.0, 0.1) var claim_duration := 20.0
@export_range(1, 500) var scout_replacement_energy := 35
@export_range(1.0, 120.0, 0.5) var scout_replacement_delay := 15.0
@export_group("")
@export_range(0.9, 12.0, 0.1) var unit_aggro_radius := MatchBattle.DEFAULT_AGGRO_RADIUS
@export var unit_target_priority := MatchBattle.TargetPriority.NEAREST
@export_range(1, 80) var outpost_hp := MatchBattle.DEFAULT_OUTPOST_HP

var active_map_seed: int:
	get:
		return _layout.active_seed if _layout != null else map_seed

var _battle: MatchBattle
var _expeditions: ScoutExpeditions
var _claim_markers: Dictionary[StringName, PanelContainer] = {}
var _scout_buttons: Array[Button] = []
var _layout: TerritoryLayout
var _regions_by_id: Dictionary[StringName, MatchRegion] = {}
var _initial_owners: Dictionary[StringName, MatchRegion.Owner] = {}
var _landmarks: Dictionary[StringName, LegendaryLandmark] = {}
var _outposts_by_region: Dictionary[StringName, MatchBattle.Outpost] = {}
var _outpost_views: Dictionary[StringName, Node3D] = {}
# Each region indexes its physically present structures by stable source ID.
var _region_structures: Dictionary[StringName, Dictionary] = {}
var _fortifications: Dictionary[int, PlacedFortification] = {}
var _fortification_ids: Dictionary[Node3D, int] = {}
var _selected_fortification := MatchBattle.NO_TARGET
var _range_ring: MeshInstance3D
var _splash_ring: MeshInstance3D
var _tracer_material := StandardMaterial3D.new()
var _wall_start := Vector2.INF
var _wall_release_pending := false
var _selected_resource: StringName
var _income_details: Dictionary[StringName, String] = {}
var _selected_region_id: StringName = &""
var _unit_views: Dictionary[int, MeshInstance3D] = {}
var _unit_materials: Dictionary[StringName, StandardMaterial3D] = {}
var _selected_unit_id := MatchBattle.NO_TARGET
var _route_mesh := ImmediateMesh.new()
var _time_until_cpu_decision: float
var _advancing_battle := false
var _owns_narrative_pause := false

var _bases: Dictionary[MatchRegion.Owner, Node3D] = {}
var _pending_pick := Vector2.INF
var _placement_id: StringName = &""
var _preview: Node3D
var _preview_material: StandardMaterial3D
var _cpu_strategy: CpuStrategy
var cpu_difficulty := DifficultyProfile.DEFAULT_LEVEL
var _process_mode_before_setup: ProcessMode
var _build_options: Dictionary[StringName, Button] = {}

@onready var _buildings: Dictionary[MatchRegion.Owner, Node3D] = {
	PLAYER: $Buildings/Player,
	CPU: $Buildings/CPU,
}
@onready var _unit_attack_effects := UnitAttackEffects.new()
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
@onready var _stat_sources: Button = %StatSources
@onready var _stat_source_scroll: ScrollContainer = %StatSourceScroll
@onready var _stat_source_text: Label = %StatSourceText
@onready var _resource_readouts: HBoxContainer = %Resources
@onready var _income_sources: PanelContainer = %IncomeSources
@onready var _income_source_scroll: ScrollContainer = %IncomeSourceScroll
@onready var _income_source_text: Label = %IncomeSourceText
@onready var _barracks_label: Label = %BarracksCount
@onready var _build_button: Button = %Build
@onready var _build_menu: PanelContainer = %BuildMenu
@onready var _build_list: VBoxContainer = %BuildList
@onready var _placement_panel: PanelContainer = %PlacementPanel
@onready var _placement_label: Label = %PlacementStatus
@onready var _upgrade_button: Button = %Upgrade
@onready var _claim_button: Button = %Claim
@onready var _scout_count: Label = %ScoutCount
@onready var _scout_notice: Label = %ScoutNotice
@onready var _recall_button: Button = %Recall
@onready var _unit_claim_progress: ProgressBar = %UnitClaimProgress
@onready var _region_claim_progress: ProgressBar = %RegionClaimProgress
@onready var _region_label: Label = %SelectedRegion
@onready var _region_slots: Label = %RegionSlots
@onready var _landmark_panel: PanelContainer = %LandmarkInspection
@onready var _landmark_details: Label = %LandmarkDetails
@onready var _legendary_summary: Label = %LegendarySummary
@onready var _camera: StrategyCamera = $Camera
@onready var _player_hp_label: Label = %PlayerHP
@onready var _cpu_hp_label: Label = %CPUHP
@onready var _outcome_label: Label = %Outcome
@onready var _restart_button: Button = %Restart
@onready var _active_difficulty: Label = %ActiveDifficulty
@onready var _match_setup: Control = %MatchSetup
@onready var _difficulty_picker: OptionButton = _match_setup.get_node("%Difficulty")
@onready var _difficulty_description: Label = _match_setup.get_node("%Description")
@onready var _confirm_setup: Button = _match_setup.get_node("%Confirm")
@onready var _cancel_setup: Button = _match_setup.get_node("%Cancel")
@onready var _event_dialogue := $NarrativeOverlay/EventDialogue


func _ready() -> void:
	_generate_map()
	_unit_route.mesh = _route_mesh
	_unit_route.global_transform = _regions.global_transform
	_create_resource_readouts()
	_stat_sources.toggled.connect(func(open: bool) -> void:
		_stat_source_scroll.visible = open
		_stat_source_scroll.scroll_vertical = 0)
	for label in [_unit_stats, _player_hp_label, _cpu_hp_label, _region_label, _region_slots, _legendary_summary,
			_landmark_details]:
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
		if not effect.is_empty():
			option.text += "\n" + effect
		option.pressed.connect(_begin_placement.bind(building_id))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_build_list.add_child(option)
		_build_options[building_id] = option
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
	add_child(_unit_attack_effects)
	_unit_attack_effects.global_transform = _regions.global_transform
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tracer_material.albedo_color = Color("#fff0b8")
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_claim_button.pressed.connect(_dispatch_selected_scout)
	_recall_button.pressed.connect(func() -> void:
		if _expeditions.recall(PLAYER, _selected_unit_id):
			_refresh_hud())
	for index in ScoutExpeditions.CAPACITY:
		var button := Button.new()
		button.pressed.connect(_use_scout_slot.bind(index))
		%ScoutSlots.add_child(button)
		_scout_buttons.append(button)
	$HUD.move_child(%ClaimMarkers, 0)
	for level in range(1, DifficultyProfile.PROFILES.size() + 1):
		var difficulty := DifficultyProfile.get_profile(level)
		_difficulty_picker.add_item(DifficultyProfile.display_name(level), level)
		_difficulty_picker.get_popup().set_item_tooltip(level - 1, difficulty.description)
	_difficulty_picker.item_selected.connect(_describe_difficulty)
	_confirm_setup.pressed.connect(_apply_match_setup)
	_cancel_setup.pressed.connect(_close_match_setup)
	_restart_button.pressed.connect(_open_match_setup.bind(false))
	_event_dialogue.choice_pressed.connect(_resolve_narrative_choice)
	claim_completed.connect(_discover_on_claim)
	%Overview.pressed.connect(func() -> void: _camera.reset_view())
	restart_match()
	if show_match_setup_on_start:
		_open_match_setup(true)


func _open_match_setup(initial: bool) -> void:
	if _match_setup.visible:
		return
	_pending_pick = Vector2.INF
	_clear_wall_drag()
	_camera.end_drag()
	_difficulty_picker.select(_difficulty_picker.get_item_index(cpu_difficulty))
	_describe_difficulty(_difficulty_picker.selected)
	_confirm_setup.text = "Start match" if initial else "Restart match"
	_cancel_setup.visible = not initial
	var next_button := _confirm_setup if initial else _cancel_setup
	var previous_button := _difficulty_picker if initial else _cancel_setup
	_difficulty_picker.focus_previous = _difficulty_picker.get_path_to(_confirm_setup)
	_difficulty_picker.focus_next = _difficulty_picker.get_path_to(next_button)
	_confirm_setup.focus_previous = _confirm_setup.get_path_to(previous_button)
	_confirm_setup.focus_next = _confirm_setup.get_path_to(_difficulty_picker)
	_cancel_setup.focus_previous = _cancel_setup.get_path_to(_difficulty_picker)
	_cancel_setup.focus_next = _cancel_setup.get_path_to(_confirm_setup)
	_process_mode_before_setup = process_mode
	process_mode = Node.PROCESS_MODE_DISABLED
	_match_setup.show()
	_difficulty_picker.grab_focus()


func _describe_difficulty(index: int) -> void:
	var difficulty := DifficultyProfile.get_profile(_difficulty_picker.get_item_id(index))
	_difficulty_description.text = difficulty.description
	_difficulty_picker.tooltip_text = difficulty.description


func _apply_match_setup() -> void:
	cpu_difficulty = _difficulty_picker.get_selected_id()
	restart_match()


func _close_match_setup() -> void:
	if _match_setup.visible:
		_match_setup.hide()
		process_mode = _process_mode_before_setup


func _cpu_decision_period() -> float:
	return cpu_decision_interval * _cpu_strategy.difficulty.cadence


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
		_region_structures[cell.id] = {}
		if cell.id == TerritoryLayout.PLAYER_START or cell.id == TerritoryLayout.CPU_START:
			_add_starting_base(region)
	_register_starting_bases()
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
		if not building_slot_block_reason(LEGENDARY_KIND, [region.region_id]).is_empty():
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
		_register_region_structure(landmark.source_id, LEGENDARY_KIND, [region.region_id])


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


func _register_starting_bases() -> void:
	for side in _bases:
		var center := _map_position(_bases[side].global_position)
		var footprint := Fortifications.footprint(center, MatchBattle.BASE_FOOTPRINT * 2.0)
		_register_region_structure(_base_structure_id(side), BASE_KIND, _footprint_regions(footprint))


func _base_structure_id(side: MatchRegion.Owner) -> StringName:
	return StringName("base/%d" % side)


func restart_match() -> void:
	_close_match_setup()
	_active_difficulty.text = "CPU %s" % DifficultyProfile.display_name(cpu_difficulty)
	_active_difficulty.tooltip_text = DifficultyProfile.get_profile(cpu_difficulty).description
	if narrative_events != null:
		narrative_events.close()
		narrative_events.queue_changed.disconnect(_sync_narrative_dialogue)
	_camera.reset_view(true)
	if _battle != null:
		_battle.step_finished.disconnect(_expeditions._step)
		_battle.step_finished.disconnect(_advance_narrative_time)
		_battle.unit_produced.disconnect(_spawn_unit)
		_battle.unit_removed.disconnect(_remove_unit)
		_battle.attack_resolved.disconnect(_unit_attack_effects.record)
		_battle.base_destroyed.disconnect(_hide_base)
		_battle.outpost_destroyed.disconnect(_lose_region)
		_battle.fortification_destroyed.disconnect(_remove_fortification)
		_battle.fortification_fired.disconnect(_show_fortification_shot)
	_unit_attack_effects.clear()
	for shot in _shot_effects.get_children():
		_shot_effects.remove_child(shot)
		shot.queue_free()
	for view in _outpost_views.values():
		view.get_parent().remove_child(view)
		view.queue_free()
	for structures in _region_structures.values():
		structures.clear()
	_register_starting_bases()
	for landmark in _landmarks.values():
		_register_region_structure(landmark.source_id, LEGENDARY_KIND, [landmark.region_id])
	_outpost_views.clear()
	_outposts_by_region.clear()
	_show_income_sources(&"")
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

	if faction_stats != null:
		faction_stats.stat_changed.disconnect(_invalidate_income_details)
	faction_stats = FactionStats.new()
	_income_details.clear()
	faction_stats.stat_changed.connect(_invalidate_income_details)
	for landmark in _landmarks.values():
		faction_stats.set_modifier(landmark.source_id, _initial_owners[landmark.region_id],
			landmark.stat, landmark.magnitude, &"legendary", landmark.display_name,
			"", true, 0, landmark.region_id)
	economy = MatchEconomy.new(faction_stats)
	narrative_events = NarrativeEvents.new(active_map_seed, economy, narrative_catalog)
	narrative_events.queue_changed.connect(_sync_narrative_dialogue)
	_cpu_strategy = CpuStrategy.new(active_map_seed, cpu_difficulty)
	_time_until_cpu_decision = _cpu_decision_period()
	_battle = MatchBattle.new(_map_position(_bases[PLAYER].global_position),
		_map_position(_bases[CPU].global_position), unit_aggro_radius,
		_layout.bounds, faction_stats)
	for landmark in _landmarks.values():
		_battle.add_landmark_footprint(landmark.footprint)
	_battle.target_priority = unit_target_priority
	_battle.unit_produced.connect(_spawn_unit)
	_battle.unit_removed.connect(_remove_unit)
	_battle.attack_resolved.connect(_unit_attack_effects.record)
	_battle.base_destroyed.connect(_hide_base)
	_battle.outpost_destroyed.connect(_lose_region)
	_battle.fortification_destroyed.connect(_remove_fortification)
	_battle.fortification_fired.connect(_show_fortification_shot)
	_battle.step_finished.connect(_advance_narrative_time)
	_expeditions = ScoutExpeditions.new(_battle, economy, _regions_by_id, {
		"claim_energy": claim_energy,
		"outpost_slot_block_reason": _outpost_slot_block_reason,
		"duration": claim_duration,
		"replacement_energy": scout_replacement_energy,
		"replacement_delay": scout_replacement_delay,
	})
	_expeditions.expedition_completed.connect(_complete_claim)
	_expeditions.expedition_failed.connect(_show_expedition_notice)
	_expeditions.assignment_interrupted.connect(_cpu_strategy.on_assignment_interrupted)
	_claim_button.text = "Claim\n%s" % MatchEconomy.cost_text(_expeditions.claim_cost)
	_scout_notice.hide()
	_refresh_legendary_summary()
	_refresh_hud()
	%BuildScroll.custom_minimum_size.y = minf(_build_list.get_combined_minimum_size().y, 550.0)
	set_process(true)


func _process(delta: float) -> void:
	if _match_setup.visible or _battle.is_finished() or _has_narrative_decision():
		return

	# Apply income and production up to each decision before making its purchase.
	while delta >= _time_until_cpu_decision and not _battle.is_finished():
		var used := _advance_simulation(_time_until_cpu_decision)
		delta -= used
		_time_until_cpu_decision -= used
		if _has_narrative_decision():
			break
		_time_until_cpu_decision = _cpu_decision_period()
		if not _battle.is_finished():
			_try_cpu_purchase()
		if _has_narrative_decision():
			break

	if not _battle.is_finished() and not _has_narrative_decision():
		_time_until_cpu_decision -= _advance_simulation(delta)
	if _battle.is_finished():
		_cancel_placement()
		_select_unit(MatchBattle.NO_TARGET)
		_select_fortification(MatchBattle.NO_TARGET)
		set_process(false)

	_unit_attack_effects.render_at(_battle.elapsed_time())
	for unit in _battle.active_units():
		_update_unit_view(unit, _unit_views[unit.id])
	_refresh_hud()


func try_place_building(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> bool:
	if not BUILDINGS.has(building_id) or building_id == Fortifications.WALL:
		return false

	if not world_position.is_finite():
		return false
	var ground := _map_plane().project(world_position)
	var position := _map_position(ground)
	var definition: Dictionary = BUILDINGS[building_id]
	var profile: Dictionary = Fortifications.PROFILES.get(building_id, definition)
	var polygon := Fortifications.footprint(position, profile.size)
	var covered := _footprint_regions(polygon)
	if not _building_site_block_reason(side, building_id, position, polygon, covered).is_empty():
		return false
	if Fortifications.PROFILES.has(building_id):
		if not economy.try_spend(side, profile.cost):
			return false
		_add_fortification(side, building_id, position, 0.0, covered)
		_refresh_hud()
		return true

	var region_id := region_at_world_position(ground)
	var structure: MatchBattle.Fortification
	var purchased := economy.try_build(side, definition.cost) if building_id == &"barracks" \
		else economy.try_spend(side, definition.cost)
	if not purchased:
		return false
	if definition.has("unit_type"):
		structure = _battle.add_producer(building_id, definition, side, position)
	else:
		structure = _battle.add_structure(building_id, definition, side, position)
	_add_structure_view(structure, [region_id], covered)
	var income: Dictionary = definition.get("income", {})
	for resource_id in income:
		faction_stats.set_modifier(structure.source_id, side, resource_id,
			income[resource_id], &"building",
			"%s #%d" % [definition.label, absi(structure.id)], "", true, structure.id, region_id)
	_refresh_hud()
	return true


func _placement_block_reason(side: MatchRegion.Owner, building_id: StringName,
		world_position: Vector3) -> String:
	if not world_position.is_finite():
		return "Choose a spot in your territory"
	var position := _map_position(world_position)
	var definition: Dictionary = Fortifications.PROFILES.get(building_id, BUILDINGS[building_id])
	var polygon := Fortifications.footprint(position, definition.size)
	return _building_site_block_reason(side, building_id, position, polygon, _footprint_regions(polygon))


func _building_site_block_reason(side: MatchRegion.Owner, building_id: StringName, position: Vector2,
		polygon: PackedVector2Array, covered: Array[StringName]) -> String:
	if not position.is_finite() or not _buildings.has(side) or not owns_region(side, _layout.region_at(position)):
		return "Choose a spot in your territory"
	if Fortifications.PROFILES.has(building_id) and not _owns_footprint(side, polygon, covered):
		return "Keep the footprint in your territory"
	var slot_reason := building_slot_block_reason(building_id, covered)
	if not slot_reason.is_empty():
		return slot_reason
	var definition: Dictionary = BUILDINGS[building_id]
	var clear := _battle.producer_site_clear(position, definition) if definition.has("unit_type") \
		else _battle.fortification_site_clear(polygon)
	if not clear:
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


func _footprint_regions(polygon: PackedVector2Array) -> Array[StringName]:
	var covered: Array[StringName] = []
	for region_id in _regions_by_id:
		if not Geometry2D.intersect_polygons(polygon, get_region(region_id).polygon).is_empty():
			covered.append(region_id)
	return covered


func _owns_footprint(side: MatchRegion.Owner, polygon: PackedVector2Array,
		covered: Array[StringName]) -> bool:
	if not _buildings.has(side) or covered.is_empty():
		return false
	for point in polygon:
		if not _layout.bounds.has_point(point):
			return false
	for region_id in covered:
		if not owns_region(side, region_id):
			return false
	return true


static func _building_slot_cost(kind: StringName) -> int:
	return 0 if kind == Fortifications.WALL else 1


func _register_region_structure(id: StringName, kind: StringName, covered: Array[StringName],
		fort: MatchBattle.Fortification = null) -> void:
	var entry := {"kind": kind, "fort": fort}
	for region_id in covered:
		_region_structures[region_id][id] = entry


func _unregister_region_structure(id: StringName) -> void:
	for structures in _region_structures.values():
		structures.erase(id)


func region_occupancy(region_id: StringName) -> Dictionary:
	var used := 0
	var by_kind := {}
	var inactive := {}
	for entry in _region_structures.get(region_id, {}).values():
		var kind: StringName = entry.kind
		used += _building_slot_cost(kind)
		by_kind[kind] = by_kind.get(kind, 0) + 1
		var fort := entry.fort as MatchBattle.Fortification
		if (fort != null and not fort.active) or (kind == LEGENDARY_KIND
				and owns_region(MatchRegion.Owner.NEUTRAL, region_id)):
			inactive[kind] = inactive.get(kind, 0) + 1
	var capacity := maxi(1, region_building_capacity)
	return {"used": used, "capacity": capacity, "free": maxi(0, capacity - used),
		"by_kind": by_kind, "inactive": inactive}


func building_slot_block_reason(kind: StringName, covered: Array,
		claim_region: StringName = &"") -> String:
	var cost := _building_slot_cost(kind)
	if cost == 0:
		return ""
	for region_id: StringName in covered:
		var occupancy := region_occupancy(region_id)
		var reserve := int(owns_region(MatchRegion.Owner.NEUTRAL, region_id) and region_id != claim_region)
		if occupancy.free < cost + reserve:
			if reserve > 0 and occupancy.free >= cost:
				return "%s needs a slot for its outpost" % str(region_id).capitalize()
			return "%s is full (%d/%d slots)" % [
				str(region_id).capitalize(), occupancy.used, occupancy.capacity]
	return ""


func _outpost_slot_block_reason(region_id: StringName) -> String:
	return building_slot_block_reason(OUTPOST_KIND, [region_id], region_id)


func _has_building_capacity(side: MatchRegion.Owner, kind: StringName) -> bool:
	for region_id in _regions_by_id:
		if owns_region(side, region_id) and building_slot_block_reason(kind, [region_id]).is_empty():
			return true
	return false


func _catalog_block_reason(side: MatchRegion.Owner, kind: StringName) -> String:
	if _building_slot_cost(kind) > 0 and not _has_building_capacity(side, kind):
		return "All owned regions are full"
	return _purchase_block_reason(side, kind)


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
		var regions := _footprint_regions(polygon)
		if not _owns_footprint(side, polygon, regions):
			plan.reason = "Keep the entire wall in your territory"
			return plan
		if not _battle.fortification_site_clear(polygon):
			plan.reason = "Keep structures and spawn exits clear"
			return plan
		plan.reason = building_slot_block_reason(Fortifications.WALL, regions)
		if not plan.reason.is_empty():
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
	_add_structure_view(_battle.add_fortification(kind, side, center, angle), regions, regions)


func _add_structure_view(defense: MatchBattle.Fortification, regions: Array[StringName],
		covered: Array[StringName]) -> void:
	_register_region_structure(defense.source_id, defense.kind, covered, defense)
	var view := BUILDINGS[defense.kind].scene.instantiate() as Node3D
	_buildings[defense.side].add_child(view)
	view.global_position = _world_position(defense.position)
	view.rotation.y = -defense.angle
	_structure_accent(view, defense.kind).material_override = FACTION_ACCENTS[defense.side]
	var placed := PlacedFortification.new()
	placed.defense = defense
	placed.view = view
	placed.regions = regions
	_fortifications[defense.id] = placed
	_fortification_ids[view] = defense.id


func _structure_accent(view: Node3D, kind: StringName) -> MeshInstance3D:
	return view.get_node(BUILDINGS[kind].get("accent_node", ^"Marking")) as MeshInstance3D


func _remove_fortification(defense: MatchBattle.Fortification) -> void:
	var placed: PlacedFortification = _fortifications.get(defense.id)
	if placed == null:
		return
	if defense.kind == &"barracks":
		economy.remove_barracks(defense.side)
	_unregister_region_structure(defense.source_id)
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
	if not _catalog_block_reason(PLAYER, building_id).is_empty():
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
	var reason := _catalog_block_reason(PLAYER, _placement_id)
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


func dispatch_scout(side: MatchRegion.Owner, scout_id: int, region_id: StringName) -> bool:
	return _expeditions.dispatch(side, scout_id, region_id).is_empty()


func _dispatch_selected_scout() -> void:
	var reason := _expeditions.dispatch(PLAYER, _selected_unit_id, _selected_region_id)
	if not reason.is_empty():
		_show_expedition_notice(PLAYER, reason)
	else:
		_scout_notice.hide()
	_refresh_hud()


func _complete_claim(side: MatchRegion.Owner, region_id: StringName, scout_id: int,
		point: Vector2) -> void:
	var outpost := _battle.add_outpost(region_id, side, point, maxi(1, outpost_hp))
	var footprint := Fortifications.footprint(point, MatchBattle.OUTPOST_FOOTPRINT * 2.0)
	_register_region_structure(outpost.source_id, OUTPOST_KIND, _footprint_regions(footprint))
	_outposts_by_region[region_id] = outpost
	var view := OUTPOST.instantiate() as Node3D
	view.get_node("Beacon").material_override = FACTION_ACCENTS[side]
	get_region(region_id).add_child(view)
	view.global_position = _regions.to_global(Vector3(point.x, 0.0, point.y))
	_outpost_views[region_id] = view
	_set_region_owner(region_id, side)
	outpost.hp = outpost.max_hp
	_refresh_claim_control()
	claim_completed.emit(side, region_id, scout_id)


func _discover_on_claim(side: MatchRegion.Owner, region_id: StringName, _scout_id: int) -> void:
	# The first successful claim by this faction owns this occurrence for the match.
	# Replacements and reclamations reuse the ID, even if another Scout completes them.
	var id := StringName("claim/%d/%s" % [side, region_id])
	if narrative_events.submit(id, CLAIM_DISCOVERY, side, region_id) and side == CPU:
		narrative_events.resolve_cpu(id)


func _lose_region(outpost: MatchBattle.Outpost) -> void:
	var region_id := outpost.region_id
	var view := _outpost_views[region_id]
	view.get_parent().remove_child(view)
	view.queue_free()
	_outpost_views.erase(region_id)
	_outposts_by_region.erase(region_id)
	_unregister_region_structure(outpost.source_id)
	_set_region_owner(region_id, MatchRegion.Owner.NEUTRAL)


func _set_region_owner(region_id: StringName, side: MatchRegion.Owner) -> void:
	get_region(region_id).region_owner = side
	faction_stats.set_source_owner(region_source_id(region_id), side)
	var landmark := _landmarks.get(region_id) as LegendaryLandmark
	if landmark != null:
		faction_stats.set_source_owner(landmark.source_id, side)
		_refresh_legendary_summary()
	for placed in _fortifications.values():
		if not placed.regions.has(region_id):
			continue
		var active := true
		for covered in placed.regions:
			if not owns_region(placed.defense.side, covered):
				active = false
				break
		_battle.set_fortification_active(placed.defense, active)
		_structure_accent(placed.view, placed.defense.kind).material_override = FACTION_ACCENTS[placed.defense.side] \
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
		region.region_owner, stat, magnitude, source_type, source_name, description, true, 0, region_id)


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
	if event.is_action_pressed("ui_cancel") and _income_sources.visible:
		_show_income_sources(&"")
		get_viewport().set_input_as_handled()
		return
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
		if unit.type_id != UnitCatalog.SCOUT:
			_select_region(&"")
	else:
		var building := _pick_building(pointer)
		var point: Variant = _ground_point(pointer) if building == null else building.global_position
		var region_id := region_at_world_position(point) if point != null else &""
		var scout := _expeditions.scout_for(_selected_unit_id)
		var fort_id: int = _fortification_ids.get(building, MatchBattle.NO_TARGET)
		if scout == null or scout.side != PLAYER or fort_id != MatchBattle.NO_TARGET \
				or not owns_region(MatchRegion.Owner.NEUTRAL, region_id):
			_select_unit(MatchBattle.NO_TARGET)
		_select_fortification(fort_id)
		_select_region(region_id)
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
	if id != _selected_unit_id:
		_stat_sources.button_pressed = false
	_selected_unit_id = id
	_update_unit_selection()


func _update_unit_selection() -> void:
	var unit := selected_unit() if _placement_id.is_empty() and _battle != null else null
	_unit_selection.visible = unit != null
	_unit_panel.visible = unit != null
	_route_mesh.clear_surfaces()
	_recall_button.hide()
	_unit_claim_progress.hide()
	if unit == null:
		return

	_unit_selection.global_position = _unit_views[unit.id].global_position
	_unit_selection.scale = Vector3.ONE * float(unit.definition.selection_scale)
	_unit_name.text = "%s %s #%d" % [_side_label(unit.side), unit.definition.label, unit.id]
	_unit_name.modulate = FACTION_ACCENTS[unit.side].albedo_color.lightened(0.25)
	var scout := _expeditions.scout_for(unit.id)
	_stat_sources.visible = scout == null
	if scout != null:
		_update_scout_inspection(unit, scout)
		return
	_unit_order_hint.text = "Right-click ground to move"
	var attack := _battle.unit_attack_stat(unit)
	var health := _battle.unit_health_stat(unit)
	var speed := _battle.unit_speed_stat(unit)
	_unit_stats.text = "HP  %s / %s\nAttack  %s · Speed  %s units/s\nRange  %s · Cooldown  %ss" % [
		_stat_number(unit.hp), _stat_number(health.total), _stat_number(attack.total),
		_stat_number(speed.total), _stat_number(unit.definition.range),
		_stat_number(unit.attack_interval),
	]
	var sources := PackedStringArray([
		_breakdown_text("Damage per second", _battle.unit_dps_stat(unit)),
		_breakdown_text("Maximum HP", health),
		_breakdown_text("Damage per attack", attack),
		_breakdown_text("Movement speed", speed, " units/s"),
	])
	if unit.definition.structure_damage_multiplier != 1.0:
		sources.append("Damage per attack against structures  %s" %
			_stat_number(attack.total * unit.definition.structure_damage_multiplier))
	_refresh_stat_sources("\n\n".join(sources))
	_unit_intent.text = "Target  %s\nOrder  %s\nState  %s" % [
		_target_label(unit), MatchBattle.Order.keys()[unit.order].capitalize(), _unit_state_label(unit),
	]
	_unit_order_hint.visible = _selected_unit_can_receive_orders()
	if not unit.waypoints.is_empty():
		_draw_unit_route(unit)


func _select_fortification(id: int) -> void:
	if id != _selected_fortification:
		_stat_sources.button_pressed = false
	_selected_fortification = id
	_update_fortification_inspection()


func _update_fortification_inspection() -> void:
	var placed: PlacedFortification = _fortifications.get(_selected_fortification)
	if placed == null or not _placement_id.is_empty():
		if _placement_id.is_empty():
			_hide_ranges()
		if selected_unit() == null or not _placement_id.is_empty():
			_unit_panel.hide()
		return
	var fort := placed.defense
	_unit_panel.show()
	_stat_sources.show()
	_unit_name.text = "%s %s" % [_side_label(fort.side), fort.profile.label]
	_unit_name.modulate = FACTION_ACCENTS[fort.side].albedo_color.lightened(0.25)
	_unit_stats.text = _health_text(fort)
	var details := _breakdown_text("Maximum HP", fort.health_stat())
	_unit_intent.text = "Active" if fort.active else "Inactive · territory lost"
	if fort is MatchBattle.ProductionTimer:
		var production := _production_stat(fort)
		var unit: Dictionary = UnitCatalog.DEFINITIONS[fort.unit_type]
		_unit_intent.text += "\n%s · %s per unit\nCapacity  %s units/s" % [
			unit.label, MatchEconomy.cost_text({MatchEconomy.FOOD: unit.food}),
			_stat_number(production.total),
		]
		details += "\n\n" + _breakdown_text("Production capacity", production, " units/s")
	for resource_id in fort.profile.get("income", {}):
		var production := faction_stats.inspect_source(resource_id, fort.source_id)
		var label: String = MatchEconomy.RESOURCES[resource_id].label
		_unit_intent.text += "\n%s %s" % [label, _stat_amount(production.total, "/s")]
		details += "\n\n" + _breakdown_text(label + " production", production, "/s", true)
	_refresh_stat_sources(details)
	if fort.profile.get("range", 0.0) > 0.0:
		_unit_intent.text += "\n" + _range_text(fort.profile).replace(" · ", "\n")
	_unit_order_hint.hide()
	_show_ranges(fort.profile, fort.position, true)


func _production_stat(timer: MatchBattle.ProductionTimer) -> Dictionary:
	if timer.kind == &"barracks":
		return economy.production_stat(timer.side, timer.active)
	var rate := 1.0 / timer.interval(economy)
	var breakdown: Array[Dictionary] = [
		{"source_name": "Base", "source_type": FactionStats.BASELINE_TYPE, "magnitude": rate, "active": true},
	]
	if not timer.active:
		breakdown.append({"source_name": "Territory lost", "source_type": &"rule",
			"magnitude": -rate, "active": true})
	return {"total": rate if timer.active else 0.0, "breakdown": breakdown}


func _refresh_stat_sources(details: String) -> void:
	_unit_stats.tooltip_text = details
	_set_breakdown_text(_stat_source_text, _stat_source_scroll, details, 350.0)


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
	return unit != null and unit.side == PLAYER and not unit.scout_committed and not _battle.is_finished()


func _target_label(unit: MatchBattle.Unit) -> String:
	if unit.target == MatchBattle.BASE_TARGET:
		return "CPU base" if unit.side == PLAYER else "Player base"
	var target := _battle.get_unit(unit.target)
	if target != null:
		return "%s %s #%d" % [_side_label(target.side), target.definition.label, target.id]
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


func _advance_simulation(delta: float) -> float:
	if _has_narrative_decision():
		return 0.0
	_advancing_battle = true
	var used := _battle.advance(delta, economy, true, _has_narrative_decision)
	_advancing_battle = false
	if _has_narrative_decision():
		_sync_narrative_dialogue()
	return used


func _has_narrative_decision() -> bool:
	return not narrative_events.pending_player_id().is_empty()


func _advance_narrative_time() -> void:
	narrative_events.advance_time(_battle.elapsed_time())


func _sync_narrative_dialogue() -> void:
	if _advancing_battle and _has_narrative_decision():
		return
	if _has_narrative_decision() and not _event_dialogue.visible:
		_owns_narrative_pause = not get_tree().paused
		get_tree().paused = true
		_pending_pick = Vector2.INF
		_clear_wall_drag()
		_camera.end_drag()
	_event_dialogue.present(narrative_events.player_dialogue())
	if not _has_narrative_decision():
		_release_narrative_pause()


func _resolve_narrative_choice(instance_id: StringName, option_id: StringName) -> void:
	if narrative_events.resolve_player(instance_id, option_id):
		_refresh_hud()


func _release_narrative_pause() -> void:
	if _owns_narrative_pause:
		_owns_narrative_pause = false
		get_tree().paused = false


func _exit_tree() -> void:
	if narrative_events != null:
		narrative_events.queue_changed.disconnect(_sync_narrative_dialogue)
		narrative_events.close()
	_release_narrative_pause()


func _try_cpu_purchase() -> void:
	_cpu_strategy.decide(self)


func _spawn_unit(unit: MatchBattle.Unit) -> void:
	var view := unit.definition.scene.instantiate() as MeshInstance3D
	view.material_override = _unit_material(unit)
	_units.add_child(view)
	_unit_views[unit.id] = view
	_update_unit_view(unit, view)


func _unit_material(unit: MatchBattle.Unit) -> StandardMaterial3D:
	var accent: StandardMaterial3D = FACTION_ACCENTS[unit.side]
	var weight: float = unit.definition.tint_weight
	if weight == 0.0:
		return accent
	var key := StringName("%d/%s" % [unit.side, unit.type_id])
	if not _unit_materials.has(key):
		var material := accent.duplicate() as StandardMaterial3D
		material.albedo_color = accent.albedo_color.lerp(unit.definition.tint, weight)
		_unit_materials[key] = material
	return _unit_materials[key]


func _update_unit_view(unit: MatchBattle.Unit, view: MeshInstance3D) -> void:
	view.global_position = _regions.to_global(Vector3(unit.position.x, 0.14, unit.position.y))
	# Unit meshes face +Z before yaw.
	view.rotation.y = atan2(unit.heading.x, unit.heading.y)


func _remove_unit(unit_id: int) -> void:
	var view := _unit_views[unit_id]
	_units.remove_child(view)
	view.queue_free()
	_unit_views.erase(unit_id)
	if _selected_unit_id == unit_id:
		_select_unit(MatchBattle.NO_TARGET)


func _hide_base(side: MatchRegion.Owner) -> void:
	_unregister_region_structure(_base_structure_id(side))
	_bases[side].hide()
	narrative_events.close()


func _create_resource_readouts() -> void:
	for resource_id in MatchEconomy.RESOURCES:
		var readout := Button.new()
		readout.name = resource_id
		readout.custom_minimum_size = Vector2(124 if resource_id == MatchEconomy.MATERIALS else 112, 52)
		readout.toggle_mode = true
		readout.pressed.connect(func() -> void:
			_show_income_sources(&"" if _selected_resource == resource_id else resource_id))
		_resource_readouts.add_child(readout)

		var stockpile := Label.new()
		stockpile.name = &"Stockpile"
		stockpile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stockpile.anchor_bottom = 0.5
		stockpile.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		stockpile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stockpile.add_theme_font_size_override("font_size", 18)
		stockpile.add_theme_color_override("font_color", Color(0.99, 0.81, 0.49))
		readout.add_child(stockpile)

		var rate := Label.new()
		rate.name = &"Rate"
		rate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rate.anchor_top = 0.5
		rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate.add_theme_color_override("font_color", Color(0.73, 0.84, 0.90))
		readout.add_child(rate)


func _show_income_sources(resource_id: StringName) -> void:
	_selected_resource = resource_id
	_income_sources.visible = not resource_id.is_empty()
	_income_source_scroll.scroll_vertical = 0
	for readout: Button in _resource_readouts.get_children():
		readout.set_pressed_no_signal(readout.name == resource_id)
	if _income_sources.visible:
		_refresh_resource_readouts()


func _refresh_resource_readouts() -> void:
	for readout: Control in _resource_readouts.get_children():
		var resource_id := readout.name
		var resource_label: String = MatchEconomy.RESOURCES[resource_id].label
		var stockpile := readout.get_node(^"Stockpile") as Label
		var rate := readout.get_node(^"Rate") as Label
		stockpile.text = "%s %d" % [resource_label, floori(economy.stockpile(PLAYER, resource_id))]
		if not _income_details.has(resource_id):
			var income := economy.income_stat(PLAYER, resource_id)
			rate.text = _stat_amount(income.total, "/s")
			_income_details[resource_id] = _breakdown_text(resource_label + " income", income, "/s", true)
			readout.tooltip_text = _income_details[resource_id]
		if resource_id == _selected_resource:
			_set_breakdown_text(_income_source_text, _income_source_scroll,
				_income_details[resource_id], 235.0)


func _invalidate_income_details(stat: StringName) -> void:
	_income_details.erase(stat)


func _set_breakdown_text(label: Label, scroll: ScrollContainer, details: String, height_limit: float) -> void:
	if label.text == details:
		return
	label.text = details
	var line_height := label.get_line_height() + label.get_theme_constant("line_spacing")
	scroll.custom_minimum_size.y = minf((details.count("\n") + 1) * line_height + 2, height_limit)


func _stat_number(value: float) -> String:
	var amount := String.num(value, 6)
	if amount.contains("."):
		amount = amount.rstrip("0").rstrip(".")
	return amount


func _stat_amount(value: float, suffix: String) -> String:
	return _format_amount(value, suffix, not suffix.is_empty())


func _format_amount(value: float, suffix: String, signed: bool) -> String:
	return "%s%s%s" % ["+" if value >= 0.0 and signed else "",
		_stat_number(value), suffix]


func _income_text(income: Dictionary) -> String:
	var rates := PackedStringArray()
	for resource_id in income:
		rates.append("%s %s" % [_stat_amount(income[resource_id], "/s"),
			MatchEconomy.RESOURCES[resource_id].label])
	return ", ".join(rates)


func _breakdown_text(title: String, result: Dictionary, suffix := "", income := false) -> String:
	var lines := PackedStringArray([title])
	for source: Dictionary in result.breakdown:
		var baseline: bool = source.source_type == FactionStats.BASELINE_TYPE
		var label: String = "Passive trickle" if baseline and income else source.source_name
		var row := "%s  %s" % [label, _format_amount(source.magnitude, suffix, income or not baseline)]
		if source.has("region_id"):
			row += " · " + str(source.region_id).capitalize()
		if not source.active:
			row += " · Inactive"
		lines.append(row)
	lines.append("Total  " + _format_amount(result.total, suffix, income))
	return "\n".join(lines)


func _legendary_effect(stat: StringName, amount: float) -> String:
	if MatchEconomy.RESOURCES.has(stat):
		return _income_text({stat: amount})
	var label := str(stat).capitalize()
	match stat:
		FactionStats.UNIT_DPS:
			label = "Unit DPS"
		FactionStats.UNIT_MAX_HP:
			label = "Unit max HP"
		FactionStats.UNIT_SPEED:
			label = "unit movement speed (units/s)"
		FactionStats.BUILDING_MAX_HP:
			label = "Building max HP"
		FactionStats.BARRACKS_INTERVAL:
			label = "seconds per barracks cycle"
	return _format_amount(amount, " " + label, true)


func _refresh_legendary_summary() -> void:
	_legendary_summary.get_parent().visible = not _landmarks.is_empty()
	var counts := {PLAYER: 0, CPU: 0}
	var entries := PackedStringArray()
	for landmark in _landmarks.values():
		var contribution := faction_stats.inspect_source(landmark.stat, landmark.source_id)
		if contribution.breakdown.is_empty() or not contribution.breakdown[0].active:
			continue
		var side: MatchRegion.Owner = contribution.breakdown[0].owner
		counts[side] += 1
		entries.append("%s · %s (%s) · %s" % [_side_label(side), landmark.display_name,
			str(landmark.region_id).capitalize(), _legendary_effect(landmark.stat, contribution.total)])
	_legendary_summary.text = "Legendary bonuses · Player %d · CPU %d" % [counts[PLAYER], counts[CPU]]
	_legendary_summary.tooltip_text = "Claim landmark regions to activate their bonuses." \
		if entries.is_empty() else "\n".join(entries)


func _refresh_hud() -> void:
	_player_hp_label.text = "Player base · %s HP" % _stat_number(_battle.base_hp(PLAYER))
	_cpu_hp_label.text = "CPU base · %s HP" % _stat_number(_battle.base_hp(CPU))
	_player_hp_label.tooltip_text = _breakdown_text("Maximum HP", _battle.base_health_stat(PLAYER))
	_cpu_hp_label.tooltip_text = _breakdown_text("Maximum HP", _battle.base_health_stat(CPU))
	_outcome_label.text = OUTCOME_LABELS[_battle.outcome()]
	_outcome_label.visible = _battle.is_finished()
	_refresh_resource_readouts()
	_barracks_label.text = "Barracks %d" % economy.barracks_count(PLAYER)
	for building_id in _build_options:
		var reason := _catalog_block_reason(PLAYER, building_id)
		_build_options[building_id].disabled = not reason.is_empty()
		_build_options[building_id].tooltip_text = reason
		var definition: Dictionary = BUILDINGS[building_id]
		if definition.has("unit_type"):
			var interval: float = economy.production_interval(PLAYER) if building_id == &"barracks" \
				else definition.interval
			var unit: Dictionary = UnitCatalog.DEFINITIONS[definition.unit_type]
			_build_options[building_id].text = "%s · %s\n%s every %ss · %s per unit" % [
				definition.label, MatchEconomy.cost_text(definition.cost), unit.label,
				_stat_number(interval), MatchEconomy.cost_text({MatchEconomy.FOOD: unit.food}),
			]
	_build_button.disabled = _battle.is_finished()
	if selected_unit() != null:
		_update_unit_selection()
	_update_fortification_inspection()
	_upgrade_button.tooltip_text = "Shortens the Barracks production cycle."
	_upgrade_button.disabled = _battle.is_finished() or not economy.can_upgrade(PLAYER)
	_upgrade_button.text = (
		"Upgraded" if economy.has_upgrade(PLAYER)
		else "Upgrade\n%s" % MatchEconomy.cost_text(MatchEconomy.UPGRADE_COST)
	)
	_refresh_claim_control()
	_refresh_scout_roster()
	_refresh_claim_markers()


func _refresh_claim_control() -> void:
	var reason := _expeditions.block_reason(PLAYER, _selected_unit_id, _selected_region_id)
	_claim_button.disabled = not reason.is_empty()
	_claim_button.tooltip_text = reason
	var expedition := _expeditions.assignments.get(_selected_region_id) as ScoutExpeditions.Scout
	_update_claim_progress(_region_claim_progress, expedition)
	if expedition != null:
		reason = _expedition_text(expedition)
	var displayed_region := _selected_region_id if _regions_by_id.has(_selected_region_id) \
		else TerritoryLayout.PLAYER_START
	var occupancy := region_occupancy(displayed_region)
	var slots := "Slots %d/%d · %d free" % [occupancy.used, occupancy.capacity, occupancy.free]
	_region_slots.text = slots if displayed_region == _selected_region_id else "Base " + slots.to_lower()
	_region_slots.tooltip_text = _slot_breakdown(occupancy)
	_region_label.tooltip_text = ""
	if displayed_region == _selected_region_id:
		var title := str(displayed_region).capitalize()
		if owns_region(MatchRegion.Owner.NEUTRAL, displayed_region):
			title += " · Neutral"
		var outpost := _outposts_by_region.get(displayed_region) as MatchBattle.Outpost
		if outpost != null:
			var health := outpost.health_stat()
			reason = "Outpost · %s/%s HP" % [_stat_number(outpost.hp), _stat_number(health.total)]
			_region_label.tooltip_text = _breakdown_text("Maximum HP", health)
		_region_label.text = "%s\n%s" % [title, reason]
	else:
		_region_label.text = reason
	var landmark := _landmarks.get(_selected_region_id) as LegendaryLandmark
	_landmark_panel.visible = landmark != null
	if landmark != null:
		var contribution := faction_stats.inspect_source(landmark.stat, landmark.source_id)
		var side := get_region(landmark.region_id).region_owner
		var active: bool = not contribution.breakdown.is_empty() and contribution.breakdown[0].active
		var owner := "Neutral" if side == MatchRegion.Owner.NEUTRAL else "%s-controlled" % _side_label(side)
		_landmark_details.text = "%s · %s\n%s · %s\n%s" % [landmark.display_name,
			str(landmark.region_id).capitalize(), owner, "Active" if active else "Inactive",
			_legendary_effect(landmark.stat, contribution.total)]
		if not active and not contribution.breakdown.is_empty():
			_landmark_details.text += "\nOn claim · " + _legendary_effect(landmark.stat,
				contribution.breakdown[0].configured_magnitude)
		var is_income := MatchEconomy.RESOURCES.has(landmark.stat)
		_landmark_details.tooltip_text = _breakdown_text("Landmark contribution", contribution,
			"/s" if is_income else "", is_income)



func _slot_breakdown(occupancy: Dictionary) -> String:
	var lines := PackedStringArray()
	if occupancy.free == 0:
		lines.append("Region full")
	for kind: StringName in occupancy.by_kind:
		if _building_slot_cost(kind) == 0:
			continue
		var definition: Dictionary = Fortifications.PROFILES.get(kind, BUILDINGS.get(kind, {}))
		var label: String = FIXED_STRUCTURE_LABELS.get(kind, definition.get("label", str(kind)))
		var count: int = occupancy.by_kind[kind]
		lines.append(_slot_breakdown_line(label, count, occupancy.inactive.get(kind, 0)))
	var wall_count: int = occupancy.by_kind.get(Fortifications.WALL, 0)
	lines.append(_slot_breakdown_line("Wall segments (0 slots)", wall_count,
		occupancy.inactive.get(Fortifications.WALL, 0)))
	return "\n".join(lines)


func _slot_breakdown_line(label: String, count: int, inactive: int) -> String:
	var line := "%s × %d" % [label, count]
	if inactive > 0:
		line += " (%d inactive)" % inactive
	return line


func _use_scout_slot(index: int) -> void:
	var scout: ScoutExpeditions.Scout = _expeditions.slots[PLAYER][index]
	if scout.state == ScoutExpeditions.State.DEAD:
		if not _expeditions.replace(PLAYER, index):
			_show_expedition_notice(PLAYER, "No clear Scout deployment site")
			return
		_scout_notice.hide()
	_select_fortification(MatchBattle.NO_TARGET)
	_select_unit(scout.unit_id)
	if scout.assigned():
		_select_region(scout.region_id)
	_refresh_hud()


func _show_expedition_notice(side: MatchRegion.Owner, message: String) -> void:
	if side == PLAYER:
		_scout_notice.text = message
		_scout_notice.show()


func _refresh_scout_roster() -> void:
	_scout_count.text = "Scouts %d/%d available" % [
		_expeditions.available(PLAYER).size(), ScoutExpeditions.CAPACITY]
	for index in _scout_buttons.size():
		var scout: ScoutExpeditions.Scout = _expeditions.slots[PLAYER][index]
		var button := _scout_buttons[index]
		var state: String = ScoutExpeditions.State.keys()[scout.state].capitalize()
		button.disabled = _battle.is_finished()
		button.tooltip_text = "Select Scout"
		if scout.state == ScoutExpeditions.State.DEAD:
			var reason := _expeditions.replacement_block_reason(scout)
			var price := MatchEconomy.cost_text(_expeditions.replacement_cost)
			var wait := ceili(_expeditions.replacement_wait(scout))
			state = "Dead · %ds" % wait if wait > 0 else "Dead · %s" % price
			button.disabled = not reason.is_empty()
			button.tooltip_text = "Replace Scout · %s" % price if reason.is_empty() else reason
		button.text = "%d · %s" % [index + 1, state]


func _update_scout_inspection(unit: MatchBattle.Unit, scout: ScoutExpeditions.Scout) -> void:
	var health := _battle.unit_health_stat(unit)
	_unit_stats.text = "HP  %s / %s · Noncombat\nSpeed  %s units/s" % [
		_stat_number(unit.hp), _stat_number(health.total), _stat_number(_battle.unit_speed_stat(unit).total)]
	_unit_intent.text = _expedition_text(scout) + " · " + str(scout.region_id).capitalize() \
		if scout.assigned() else ScoutExpeditions.State.keys()[scout.state].capitalize()
	_recall_button.visible = scout.side == PLAYER and scout.assigned() and not _battle.is_finished()
	_unit_order_hint.visible = _selected_unit_can_receive_orders()
	_unit_order_hint.text = "Select a neutral region to claim\nRight-click ground to move"
	_update_claim_progress(_unit_claim_progress, scout)
	if not unit.waypoints.is_empty():
		_draw_unit_route(unit)


func _expedition_text(scout: ScoutExpeditions.Scout) -> String:
	return "◆ %s · %ds" % [ScoutExpeditions.State.keys()[scout.state].capitalize(),
		ceili(_expeditions.eta(scout) - MatchBattle.TIME_EPSILON)]


func _update_claim_progress(bar: ProgressBar, scout: ScoutExpeditions.Scout) -> void:
	bar.visible = scout != null and scout.assigned()
	if bar.visible:
		bar.value = 100.0 * (1.0 - scout.remaining / _expeditions.duration)


func _refresh_claim_markers() -> void:
	for region_id in _claim_markers.keys():
		if not _expeditions.assignments.has(region_id):
			var old_marker := _claim_markers[region_id]
			old_marker.hide()
			old_marker.queue_free()
			_claim_markers.erase(region_id)
	for region_id in _expeditions.assignments:
		var scout := _expeditions.assignments[region_id]
		if not _claim_markers.has(region_id):
			_claim_markers[region_id] = _create_claim_marker()
		var marker := _claim_markers[region_id]
		var label := marker.get_node("Readouts/Status") as Label
		label.modulate = FACTION_ACCENTS[scout.side].albedo_color.lightened(0.35)
		label.text = _expedition_text(scout)
		_update_claim_progress(marker.get_node("Readouts/Progress"), scout)
		var point := _world_position(scout.site) + Vector3.UP * 0.35
		var view := _unit_views.get(scout.unit_id) as MeshInstance3D
		marker.visible = view != null and not _camera.is_position_behind(point)
		if marker.visible:
			marker.position = _camera.unproject_position(point) - Vector2(marker.size.x * 0.5, marker.size.y)
			var scout_screen := _camera.unproject_position(view.global_position)
			if marker.get_rect().grow(16.0).has_point(scout_screen):
				marker.position.y = scout_screen.y + 16.0


func _create_claim_marker() -> PanelContainer:
	var marker := PanelContainer.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_stylebox_override("panel", _unit_panel.get_theme_stylebox("panel"))
	var readouts := VBoxContainer.new()
	readouts.name = "Readouts"
	readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "Status"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(112.0, 8.0)
	marker.add_child(readouts)
	readouts.add_child(label)
	readouts.add_child(bar)
	%ClaimMarkers.add_child(marker)
	return marker
