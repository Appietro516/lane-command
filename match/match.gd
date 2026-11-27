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
		"unit_type": UnitCatalog.RANGED, "interval": 5.0,
	},
	&"heavy_factory": {
		"label": "Heavy Factory", "cost": {MatchEconomy.ENERGY: 55, MatchEconomy.MATERIALS: 35},
		"scene": preload("res://match/heavy_factory.tscn"),
		"hp": 40, "size": Vector2(2.9, 2.1),
		"unit_type": UnitCatalog.HEAVY, "interval": 6.5,
	},
	&"aid_station": {
		"label": "Aid Station", "cost": {MatchEconomy.ENERGY: 52, MatchEconomy.MATERIALS: 28},
		"scene": preload("res://match/producers/aid_station.tscn"),
		"hp": 30, "size": Vector2(2.6, 1.8),
		"unit_type": UnitCatalog.MEDIC, "interval": 6.5,
	},
	&"raider_camp": {
		"label": "Raider Camp", "cost": {MatchEconomy.ENERGY: 48, MatchEconomy.MATERIALS: 25},
		"scene": preload("res://match/producers/raider_camp.tscn"),
		"hp": 29, "size": Vector2(2.65, 1.8),
		"unit_type": UnitCatalog.RAIDER, "interval": 5.2,
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
	BattleRadar.WATCHTOWER: {
		"label": "Watchtower", "description": "Persistent local sight",
		"cost": {MatchEconomy.ENERGY: 22, MatchEconomy.MATERIALS: 18},
		"scene": preload("res://match/recon/watchtower.tscn"),
		"hp": 22, "size": Vector2(1.15, 1.15), "vision": 11.0,
	},
	BattleRadar.RADAR: {
		"label": "Radar Station", "description": "Map-wide contact snapshot every 8 seconds",
		"cost": {MatchEconomy.ENERGY: 110, MatchEconomy.MATERIALS: 75},
		"scene": preload("res://match/recon/radar.tscn"),
		"hp": 28, "size": Vector2(1.65, 1.65),
	},
	BattleRadar.COUNTERINTELLIGENCE: {
		"label": "Counterintelligence Station", "description": "Deploy a false army to enemy radar",
		"cost": {MatchEconomy.ENERGY: 75, MatchEconomy.MATERIALS: 52},
		"scene": preload("res://match/recon/counterintelligence.tscn"),
		"hp": 26, "size": Vector2(1.55, 1.55),
	},
	Fortifications.NEST: {
		"scene": preload("res://match/fortifications/machine_gun_nest.tscn"),
		"icon": preload("res://match/fortifications/machine_gun_nest.svg"),
	},
	Fortifications.MORTAR: {
		"scene": preload("res://match/fortifications/mortar.tscn"),
		"icon": preload("res://match/fortifications/mortar.svg"),
	},
	Fortifications.ANTI_TANK: {
		"scene": preload("res://match/fortifications/anti_tank_gun.tscn"),
		"accent_node": ^"Turret/Marking",
	},
	Fortifications.SILO: {
		"scene": preload("res://match/fortifications/missile_silo.tscn"),
	},
	Fortifications.WALL: {
		"scene": preload("res://match/fortifications/wall.tscn"),
		"icon": preload("res://match/fortifications/wall.svg"),
	},
}
# Order within each section is part of the menu layout.
const BUILD_SECTIONS := [
	{ "id": &"economy", "label": "Economy", "entries": [&"generator", &"mine", &"farm"] },
	{ "id": &"military", "label": "Military", "entries": [&"barracks", &"training_range", &"heavy_factory",
		&"aid_station", &"raider_camp"] },
	{ "id": &"fortifications", "label": "Fortifications", "entries": [
		Fortifications.NEST, Fortifications.MORTAR, Fortifications.ANTI_TANK, Fortifications.WALL,
	] },
	{ "id": &"strategic", "label": "Strategic", "entries": [BattleRadar.WATCHTOWER, BattleRadar.RADAR, BattleRadar.COUNTERINTELLIGENCE, Fortifications.SILO] },
]
const HUD_MARGIN := 16.0
const HUD_GAP := 8.0
const HUD_DOCK_WIDTH := 408.0

const VALID_PREVIEW := Color(0.37, 1.0, 0.70, 0.55)
const INVALID_PREVIEW := Color(1.0, 0.37, 0.40, 0.55)
const FogOverlay := preload("res://match/fog_overlay.gd")
const RadarContactsView := preload("res://match/radar_contacts_view.gd")
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

signal return_to_setup_requested
signal claim_completed(faction: MatchRegion.Owner, region: StringName, scout_id: int)
enum GroundTarget { NONE, RALLY, MISSILE, DECOY }

const SELECTION_DRAG_THRESHOLD := 7.0
const CONTROL_GROUP_COUNT := 9
const GROUP_DOUBLE_TAP_MSEC := 330
const ROUTE_HEIGHT := 0.12
const ROUTE_HALF_WIDTH := 0.045
const ROUTE_TIP_RADIUS := 0.18

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
@export var map_shape := MapSettings.Shape.RECTANGLE
@export var map_seed := MatchSettings.DEFAULT_SEED
@export var map_width := TerritoryLayout.DEFAULT_SIZE.x
@export var map_height := TerritoryLayout.DEFAULT_SIZE.y
@export_range(TerritoryLayout.MIN_REGIONS, TerritoryLayout.MAX_REGIONS)
var region_count := TerritoryLayout.DEFAULT_REGION_COUNT
@export_range(1, 128) var region_building_capacity := DEFAULT_REGION_BUILDING_CAPACITY
@export_range(1, TerritoryLayout.MAX_REGIONS) var player_start_count := 1
@export_range(1, TerritoryLayout.MAX_REGIONS) var cpu_start_count := 1
@export_group("Legendary Landmarks", "legendary_")
## Maximum number of landmarks. Each eligible region also rolls against spawn probability.
@export_range(0, TerritoryLayout.MAX_REGIONS) var legendary_count := 4
@export_range(0.0, 1.0, 0.01) var legendary_spawn_probability := 1.0
@export var legendary_neutral_only := true
@export var legendary_catalog: Array[LegendaryBuff] = [
	LegendaryBuff.new("War Spire", FactionStats.UNIT_DPS, 1.25),
	LegendaryBuff.new("Sun Vault", FactionStats.ENERGY, 3.0),
	LegendaryBuff.new("Founder’s Forge", FactionStats.MATERIALS, 2.5),
	LegendaryBuff.new("Harvest Shrine", FactionStats.FOOD, 2.75),
	LegendaryBuff.new("Ancient Bastion", FactionStats.BUILDING_MAX_HP, 16.0),
]
@export_group("Match Setup")
@export_range(1, TerritoryLayout.MAX_CPU_OPPONENTS) var cpu_opponent_count := 1
@export_range(1, 5) var cpu_difficulty := DifficultyProfile.DEFAULT_LEVEL
@export var additional_cpu_difficulties: Array[int] = []

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
## Shot selection among enemies in range of a unit on Hold.
@export var unit_target_priority := MatchBattle.TargetPriority.NEAREST
@export var unit_threat_weights := MatchBattle.DEFAULT_THREAT_WEIGHTS
@export_range(1, 80) var outpost_hp := MatchBattle.DEFAULT_OUTPOST_HP

var active_map_seed: int:
	get:
		return _layout.active_seed if _layout != null else map_seed

@export var fog_enabled := true
@export var neutral_objectives_enabled := true
@export_range(0.1, 1.0, 0.05) var fog_update_interval := BattleVisibility.UPDATE_INTERVAL

var _battle: MatchBattle
var _intelligence: Dictionary[MatchRegion.Owner, FactionIntelligence] = {}
var _next_intel_observation := 0.0
var _strength: FactionStrength
var _displayed_score_revision := -1
@onready var _score_panel := PanelContainer.new()
@onready var _score_list := VBoxContainer.new()
@onready var _boon_status := Label.new()
@onready var _decoy_button := Button.new()
var _intel_markers: Dictionary[StringName, Label3D] = {}
@onready var _fog_overlay := FogOverlay.new()
@onready var _intel_root := Node3D.new()
@onready var _radar_contacts_view := RadarContactsView.new()
var _inspected_radar: BattleRadar.Contact
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
var _selected_units: Dictionary[int, bool] = {}
var _control_groups: Array[Dictionary] = []
var _group_buttons: Array[Button] = []
var _last_group_recall := -1
var _last_group_recall_at := -1000
@onready var _group_bar := HBoxContainer.new()
var _group_rings: Array[MeshInstance3D] = []
var _selection_origin := Vector2.INF
var _selection_dragged := false
var _selection_gesture := 0
@onready var _selection_box := Panel.new()
var _ground_target := GroundTarget.NONE
var _ground_target_hint := ""
var _rally_ring: MeshInstance3D
var _missile_ring: MeshInstance3D
var _missile_notice := ""
var _missile_notice_until := 0.0
var _missile_arrows: Dictionary[int, Label] = {}
var _missile_models: Dictionary[MatchBattle.MissileFlight, MeshInstance3D] = {}
var _missile_mesh := CylinderMesh.new()
var _ruin_material := StandardMaterial3D.new()
@onready var _ruins := Node3D.new()
var _pending_unit_order := MatchBattle.Order.AUTONOMOUS
var _order_hint := ""
var _route_mesh := ImmediateMesh.new()
var _advancing_battle := false
var _owns_narrative_pause := false

var _bases: Dictionary[MatchRegion.Owner, Node3D] = {}
var _pending_pick := Vector2.INF
var _placement_id: StringName = &""
var _preview: Node3D
var _preview_material: StandardMaterial3D
var _cpu_strategies: Dictionary[MatchRegion.Owner, CpuStrategy] = {}
var _cpu_strategy: CpuStrategy:
	get:
		return _cpu_strategies.get(CPU)
var _time_until_cpu_decision: float:
	get:
		return _cpu_strategy.time_until_decision
	set(value):
		_cpu_strategy.time_until_decision = value
var _cpu_hp_labels: Dictionary[MatchRegion.Owner, Label] = {}
var _extra_accents: Dictionary[MatchRegion.Owner, StandardMaterial3D] = {}
var _configured_layout: TerritoryLayout
var _build_options: Dictionary[StringName, Button] = {}
var _build_descriptions: Dictionary[StringName, String] = {}
var _barracks_menu_interval := -1.0

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
@onready var _stance_label: Label = %StanceLabel
@onready var _stance_picker: OptionButton = %StancePicker
@onready var _producer_stance: HBoxContainer = %ProducerStance
@onready var _producer_stance_label: Label = %ProducerStanceLabel
@onready var _producer_stance_picker: OptionButton = %ProducerStancePicker
@onready var _tactical_orders: VBoxContainer = %TacticalOrders
@onready var _resume_stance_toggle: CheckBox = %ResumeStance
@onready var _stat_sources: Button = %StatSources
@onready var _stat_source_scroll: ScrollContainer = %StatSourceScroll
@onready var _stat_source_text: Label = %StatSourceText
@onready var _resource_readouts: HBoxContainer = %Resources
@onready var _income_sources: PanelContainer = %IncomeSources
@onready var _income_source_scroll: ScrollContainer = %IncomeSourceScroll
@onready var _income_source_text: Label = %IncomeSourceText
@onready var _build_button: Button = %Build
@onready var _build_menu: PanelContainer = %BuildMenu
@onready var _build_list: VBoxContainer = %BuildList
@onready var _build_scroll: ScrollContainer = %BuildScroll
@onready var _context_scroll: ScrollContainer = %ContextScroll
@onready var _context_cards: VBoxContainer = %Cards
@onready var _top_bar: BoxContainer = %TopBar
@onready var _economy_panel: PanelContainer = %EconomyPanel
@onready var _economy_row: BoxContainer = _economy_panel.get_node(^"ReadoutsAndControls")
@onready var _placement_panel: PanelContainer = %PlacementPanel
@onready var _placement_label: Label = %PlacementStatus
@onready var _upgrade_button: Button = %ProductionUpgrade
@onready var _claim_button: Button = %Claim
@onready var _scout_count: Label = %ScoutCount
@onready var _scout_notice: Label = %ScoutNotice
@onready var _recall_button: Button = %Recall
@onready var _unit_claim_progress: ProgressBar = %UnitClaimProgress
@onready var _region_claim_progress: ProgressBar = %RegionClaimProgress
@onready var _region_label: Label = %SelectedRegion
@onready var _region_slots: Label = %RegionSlots
@onready var _region_panel: PanelContainer = %RegionInspection
@onready var _region_status: Label = %RegionStatus
@onready var _landmark_details: Label = %LandmarkDetails
@onready var _camera: StrategyCamera = $Camera
@onready var _player_hp_label: Label = %PlayerHP
@onready var _cpu_hp_label: Label = %CPUHP
@onready var _outcome_label: Label = %Outcome
@onready var _restart_button: Button = %Restart
@onready var _active_difficulty: Label = %ActiveDifficulty
@onready var _event_dialogue := $NarrativeOverlay/EventDialogue


func configure_match(settings: MatchSettings, layout: TerritoryLayout) -> void:
	assert(not is_inside_tree())
	map_shape = settings.map.shape
	map_width = settings.map.size.x
	map_height = settings.map.size.y
	region_count = settings.map.region_count
	map_seed = settings.map.seed
	cpu_opponent_count = settings.cpu_difficulties.size()
	cpu_difficulty = settings.cpu_difficulties[0]
	additional_cpu_difficulties.assign(settings.cpu_difficulties.slice(1))
	_configured_layout = layout


func _ready() -> void:
	add_child(_fog_overlay)
	add_child(_intel_root)
	add_child(_radar_contacts_view)
	_decoy_button.text = "Deploy radar decoy"
	_decoy_button.pressed.connect(_begin_ground_target.bind(GroundTarget.DECOY))
	%TargetMissile.get_parent().add_child(_decoy_button)
	_decoy_button.hide()
	_unit_route.mesh = _route_mesh
	var selection_style := StyleBoxFlat.new()
	selection_style.bg_color = Color(0.29, 0.76, 1.0, 0.15)
	selection_style.border_color = Color(0.59, 0.85, 1.0, 0.95)
	selection_style.set_border_width_all(1)
	_selection_box.add_theme_stylebox_override("panel", selection_style)
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_box.hide()
	$HUD.add_child(_selection_box)
	get_window().focus_exited.connect(_cancel_selection_drag)
	get_window().mouse_exited.connect(_cancel_selection_drag)
	%TargetMissile.pressed.connect(_begin_ground_target.bind(GroundTarget.MISSILE))
	%SetRally.pressed.connect(_begin_ground_target.bind(GroundTarget.RALLY))
	%ClearRally.pressed.connect(_clear_rally)
	_unit_route.global_transform = _regions.global_transform
	_create_resource_readouts()
	_create_score_panel()
	_create_control_group_bar()
	_stat_sources.toggled.connect(func(open: bool) -> void:
		_stat_source_scroll.visible = open
		_stat_source_scroll.scroll_vertical = 0)
	for label in [_unit_stats, _player_hp_label, _cpu_hp_label, _region_label, _region_slots,
			_landmark_details]:
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	_create_build_options()
	_build_button.pressed.connect(_toggle_build_menu)
	%CloseBuild.pressed.connect(_dismiss_build)
	%CloseIncome.pressed.connect(_close_income_sources)
	%CloseRegion.pressed.connect(_clear_region_selection)
	%CloseInspection.pressed.connect(_clear_inspection)
	%CancelPlacement.pressed.connect(_dismiss_build)
	_preview_material = StandardMaterial3D.new()
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_range_ring = _create_radius_ring(Color("#ffe5a5"), 0.018)
	_splash_ring = _create_radius_ring(Color("#ffa977"), 0.06)
	add_child(_range_ring)
	add_child(_splash_ring)
	_rally_ring = _create_radius_ring(Color("#9de8ff"), 0.12)
	add_child(_rally_ring)
	_missile_ring = _create_radius_ring(Color("#ff674f"), 0.035)
	add_child(_missile_ring)
	_missile_mesh.top_radius = 0.035
	_missile_mesh.bottom_radius = 0.19
	_missile_mesh.height = 1.3
	_missile_mesh.radial_segments = 8
	_missile_mesh.rings = 0
	_missile_mesh.material = _tracer_material
	add_child(_shot_effects)
	add_child(_ruins)
	_ruin_material.albedo_color = Color("#4d484c")
	add_child(_unit_attack_effects)
	_unit_attack_effects.global_transform = _regions.global_transform
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tracer_material.albedo_color = Color("#fff0b8")
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER, _selected_fortification))
	_claim_button.pressed.connect(_claim_selected_region)
	_recall_button.pressed.connect(func() -> void:
		if _expeditions.recall(PLAYER, _selected_unit_id):
			_refresh_hud())
	for index in ScoutExpeditions.CAPACITY:
		var button := Button.new()
		button.pressed.connect(_use_scout_slot.bind(index))
		%ScoutSlots.add_child(button)
		_scout_buttons.append(button)
	$HUD.move_child(%ClaimMarkers, 0)
	_restart_button.pressed.connect(func() -> void: restart_match())
	%ReturnToSetup.visible = _configured_layout != null
	%ReturnToSetup.pressed.connect(return_to_setup_requested.emit)
	_event_dialogue.choice_pressed.connect(_resolve_narrative_choice)
	claim_completed.connect(_discover_on_claim)
	%Overview.pressed.connect(func() -> void: _camera.reset_view())
	for stance in MatchBattle.Stance.values():
		for picker in [_stance_picker, _producer_stance_picker]:
			picker.add_item(_stance_name(stance), stance)
			picker.get_popup().set_item_tooltip(picker.item_count - 1, _stance_tooltip(stance))
	_stance_picker.item_selected.connect(_apply_selected_stance)
	_producer_stance_picker.item_selected.connect(_apply_producer_stance)
	%MoveOrder.pressed.connect(_begin_unit_order.bind(MatchBattle.Order.MOVE))
	%HoldOrder.pressed.connect(_begin_unit_order.bind(MatchBattle.Order.HOLD))
	%HoldHere.pressed.connect(_hold_selected_unit)
	get_viewport().size_changed.connect(_queue_hud_layout)
	_top_bar.resized.connect(_queue_hud_layout)
	_economy_panel.resized.connect(_queue_hud_layout)
	_economy_panel.minimum_size_changed.connect(_queue_hud_layout)
	_context_cards.minimum_size_changed.connect(_queue_hud_layout)
	_context_cards.resized.connect(_queue_hud_layout)
	_build_list.minimum_size_changed.connect(_queue_hud_layout)
	_income_sources.minimum_size_changed.connect(_queue_hud_layout)
	_placement_panel.minimum_size_changed.connect(_queue_hud_layout)
	var layout := _configured_layout if _configured_layout != null else _create_layout()
	_configured_layout = null
	restart_match(layout)


func _cpu_level(index: int) -> int:
	var level := cpu_difficulty if index == 0 else (
		additional_cpu_difficulties[index - 1] if index <= additional_cpu_difficulties.size()
		else DifficultyProfile.DEFAULT_LEVEL)
	return clampi(level, 1, DifficultyProfile.PROFILES.size())


func _map_settings() -> MapSettings:
	return MapSettings.new(map_shape, Vector2(map_width, map_height), region_count, map_seed)


func _matches_layout(settings: MapSettings, opponents: int) -> bool:
	return _layout != null and settings.configuration_error.is_empty() \
		and _layout.settings.shape == settings.shape and _layout.settings.size == settings.size \
		and _layout.settings.region_count == settings.region_count and _layout.active_seed == settings.seed \
		and _layout.starting_counts == Vector3i(player_start_count, cpu_start_count, opponents)


func _create_layout() -> TerritoryLayout:
	return _create_layout_for(cpu_opponent_count, _map_settings())


func _create_layout_for(count: int, settings: MapSettings) -> TerritoryLayout:
	return TerritoryLayout.new(settings.seed, settings.region_count, settings.size,
		player_start_count, cpu_start_count, count, settings.shape)


func _generate_map(layout: TerritoryLayout) -> void:
	_layout = layout
	_camera.set_map_bounds(_layout.bounds, _navigation_boundary())
	%Overview.tooltip_text = "Center the map and zoom out (Home)\nMap seed: %d" % active_map_seed
	var owners: Dictionary[StringName, MatchRegion.Owner] = {}
	var base_regions: Dictionary[StringName, bool] = {}
	for i in _layout.starting_territories.size():
		var territory := _layout.starting_territories[i]
		var side := (PLAYER + i) as MatchRegion.Owner
		base_regions[territory[0]] = true
		for id: StringName in territory:
			owners[id] = side
	for cell in _layout.cells:
		var region := MatchRegion.new(cell)
		region.name = cell.id
		match cell.id:
			TerritoryLayout.PLAYER_START:
				region.name = "PlayerStart"
			TerritoryLayout.CPU_START:
				region.name = "CPUStart"
		region.region_owner = owners.get(cell.id, MatchRegion.Owner.NEUTRAL)
		_regions.add_child(region)
		_regions_by_id[cell.id] = region
		_initial_owners[cell.id] = region.region_owner
		_region_structures[cell.id] = {}
		if base_regions.has(cell.id):
			_add_starting_base(region)
	_register_starting_bases()
	_generate_landmarks()
	_generate_specialties()


func _replace_map(layout: TerritoryLayout) -> void:
	for region in _regions.get_children():
		_regions.remove_child(region)
		region.queue_free()
	for side in _buildings.keys():
		if side > CPU:
			var container := _buildings[side]
			_buildings.erase(side)
			container.get_parent().remove_child(container)
			container.queue_free()
	_bases.clear()
	_regions_by_id.clear()
	_initial_owners.clear()
	_region_structures.clear()
	_landmarks.clear()
	_generate_map(layout)


func _faction_accent(side: MatchRegion.Owner) -> StandardMaterial3D:
	match side:
		PLAYER:
			return MatchRegion.PLAYER_ACCENT
		CPU:
			return MatchRegion.CPU_ACCENT
		_:
			if not _extra_accents.has(side):
				var material := MatchRegion.CPU_ACCENT.duplicate() as StandardMaterial3D
				material.albedo_color = MatchRegion.accent_color(side)
				_extra_accents[side] = material
			return _extra_accents[side]


func _generate_specialties() -> void:
	var eligible: Array[MatchRegion] = []
	for region in _regions_by_id.values():
		if region.region_owner == MatchRegion.Owner.NEUTRAL:
			eligible.append(region)
	var rng := RandomNumberGenerator.new()
	rng.seed = active_map_seed ^ 0x5350454349414C
	var count := ceili(eligible.size() * 0.8)
	var traits := RegionSpecialty.TRAITS.keys()
	var offset := rng.randi_range(0, traits.size() - 1)
	for index in count:
		var choice := rng.randi_range(index, eligible.size() - 1)
		var region := eligible[choice]
		eligible[choice] = eligible[index]
		region.configure_specialty(traits[(index + offset) % traits.size()])


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
	base.name = "PlayerBase" if side == PLAYER else ("CPUBase" if side == CPU else "CPUBase%d" % (side - PLAYER))
	if not _buildings.has(side):
		var container := Node3D.new()
		container.name = "CPU%d" % (side - PLAYER)
		$Buildings.add_child(container)
		_buildings[side] = container
	base.position.y = 0.08
	var offset := _layout.base_positions[region.region_id] - Vector2(region.position.x, region.position.z)
	base.position.x = offset.x
	base.position.z = offset.y
	base.get_node("Core").material_override = _faction_accent(side)
	region.add_child(base)
	_bases[side] = base


func _register_starting_bases() -> void:
	for side in _bases:
		var center := _map_position(_bases[side].global_position)
		var footprint := Fortifications.footprint(center, MatchBattle.BASE_FOOTPRINT * 2.0)
		_register_region_structure(_base_structure_id(side), BASE_KIND, _footprint_regions(footprint))


func _base_structure_id(side: MatchRegion.Owner) -> StringName:
	return StringName("base/%d" % side)


func _navigation_boundary() -> PackedVector2Array:
	# Axis-aligned maps use the rectangular route fast path.
	return _layout.boundary if _layout.settings.shape in [MapSettings.Shape.TRIANGLE,
		MapSettings.Shape.CIRCLE] else PackedVector2Array()


func restart_match(layout: TerritoryLayout = null) -> void:
	if layout == null and not _matches_layout(_map_settings(), cpu_opponent_count):
		layout = _create_layout()
	if layout != null and not layout.configuration_error.is_empty():
		push_error(layout.configuration_error)
		if _battle == null:
			process_mode = Node.PROCESS_MODE_DISABLED
			_outcome_label.text = layout.configuration_error
			_outcome_label.show()
		return
	if narrative_events != null:
		narrative_events.close()
		narrative_events.queue_changed.disconnect(_sync_narrative_dialogue)
	if _battle != null:
		_expeditions.assignment_interrupted.disconnect(_on_assignment_interrupted)
		_battle.step_finished.disconnect(_expeditions._step)
		_battle.step_finished.disconnect(_advance_narrative_time)
		_battle.unit_produced.disconnect(_spawn_unit)
		_battle.unit_removed.disconnect(_remove_unit)
		_battle.attack_resolved.disconnect(_show_unit_effect)
		_battle.healing_resolved.disconnect(_show_unit_effect)
		_battle.base_destroyed.disconnect(_hide_base)
		_battle.outpost_destroyed.disconnect(_lose_region)
		_battle.fortification_destroyed.disconnect(_remove_fortification)
		_battle.fortification_fired.disconnect(_show_fortification_shot)
		_battle.missile_launched.disconnect(_show_missile_launch)
		_battle.missile_cancelled.disconnect(_show_missile_cancelled)
		_battle.missile_impact.disconnect(_ruin_strike_regions)
	_unit_attack_effects.clear()
	_missile_models.clear()
	_reset_control_groups()
	for arrow in _missile_arrows.values():
		arrow.queue_free()
	_missile_arrows.clear()
	_missile_notice = ""
	_missile_notice_until = 0.0
	for rubble in _ruins.get_children():
		_ruins.remove_child(rubble)
		rubble.queue_free()
	for shot in _shot_effects.get_children():
		_shot_effects.remove_child(shot)
		shot.queue_free()
	for view in _outpost_views.values():
		view.get_parent().remove_child(view)
		view.queue_free()
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
	if layout != null:
		_replace_map(layout)
	else:
		for structures in _region_structures.values():
			structures.clear()
		_register_starting_bases()
		for landmark in _landmarks.values():
			_register_region_structure(landmark.source_id, LEGENDARY_KIND, [landmark.region_id])
	for base in _bases.values():
		base.show()
	_camera.reset_view(true)
	_refresh_cpu_status_controls()
	for region_id in _initial_owners:
		_regions_by_id[region_id].ruined = false
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
	economy = MatchEconomy.new(faction_stats, _bases.keys())
	narrative_events = NarrativeEvents.new(active_map_seed, economy, narrative_catalog)
	narrative_events.queue_changed.connect(_sync_narrative_dialogue)
	_cpu_strategies.clear()
	var positions: Dictionary[MatchRegion.Owner, Vector2] = {}
	for side in _bases:
		var position := _map_position(_bases[side].global_position)
		positions[side] = position
		if side == PLAYER:
			continue
		var strategy := CpuStrategy.new(active_map_seed, _cpu_level(side - CPU), side)
		# Stagger the first decisions in larger matches to spread work across frames.
		strategy.time_until_decision = _decision_period(strategy) + 0.12 * (side - CPU)
		_cpu_strategies[side] = strategy
	_battle = MatchBattle.new(positions[PLAYER], positions[CPU], unit_aggro_radius,
		_layout.bounds, faction_stats, positions, _navigation_boundary())
	for landmark in _landmarks.values():
		landmark.show()
		_battle.add_landmark_footprint(landmark.footprint)
	for region_id in _initial_owners:
		if _initial_owners[region_id] != MatchRegion.Owner.NEUTRAL:
			_battle.protected_starting_regions.append(_regions_by_id[region_id].polygon)
	if fog_enabled:
		_battle.enable_visibility(_layout.bounds, fog_update_interval)
	_battle.target_priority = unit_target_priority
	_battle.threat_weights = unit_threat_weights
	_battle.unit_produced.connect(_spawn_unit)
	_battle.unit_removed.connect(_remove_unit)
	_battle.attack_resolved.connect(_show_unit_effect)
	_battle.healing_resolved.connect(_show_unit_effect)
	_battle.base_destroyed.connect(_hide_base)
	_battle.outpost_destroyed.connect(_lose_region)
	_battle.fortification_destroyed.connect(_remove_fortification)
	_battle.fortification_fired.connect(_show_fortification_shot)
	_battle.missile_launched.connect(_show_missile_launch)
	_battle.missile_cancelled.connect(_show_missile_cancelled)
	_battle.missile_impact.connect(_ruin_strike_regions)
	_battle.step_finished.connect(_advance_narrative_time)
	_strength = FactionStrength.new()
	_displayed_score_revision = -1
	_battle.objectives.boon_collected.connect(_award_camp_bounty)
	_expeditions = ScoutExpeditions.new(_battle, economy, _regions_by_id, {
		"claim_energy": claim_energy,
		"outpost_slot_block_reason": _outpost_slot_block_reason,
		"duration": claim_duration,
		"replacement_energy": scout_replacement_energy,
		"replacement_delay": scout_replacement_delay,
	})
	if neutral_objectives_enabled:
		_place_neutral_objectives()
	_expeditions.expedition_completed.connect(_complete_claim)
	_expeditions.expedition_failed.connect(_show_expedition_notice)
	_expeditions.assignment_interrupted.connect(_on_assignment_interrupted)
	_claim_button.text = "Claim · %s" % MatchEconomy.cost_text(_expeditions.claim_price(PLAYER))
	_scout_notice.hide()
	_reset_intelligence()
	_strength.advance(self)
	_refresh_hud()
	set_process(true)


func _place_neutral_objectives() -> void:
	var candidates: Array[Vector2] = []
	for region in _regions_by_id.values():
		if _initial_owners[region.region_id] != MatchRegion.Owner.NEUTRAL:
			continue
		var anchor: Vector2 = region.interior_point()
		var point: Vector2 = region.interior_point(func(candidate: Vector2) -> bool:
			if candidate.distance_squared_to(anchor) < 5.4 ** 2:
				return false
			return _battle.navigation.is_passable(candidate))
		if point.is_finite():
			candidates.append(point)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.length_squared() < b.length_squared())
	_battle.objectives.add_camp(candidates.pop_front(), true)
	var rng := RandomNumberGenerator.new()
	rng.seed = active_map_seed ^ 0x4A554E474C45
	for index in mini(4, candidates.size()):
		var chosen := rng.randi_range(index, candidates.size() - 1)
		var point := candidates[chosen]
		candidates[chosen] = candidates[index]
		_battle.objectives.add_camp(point, false)
	_battle.objectives.advance(_battle, economy, 0.0)



func _process(delta: float) -> void:
	if _battle.is_finished() or _has_narrative_decision():
		return

	# Apply income and production up to the next planner's decision.
	while delta > 0.0 and not _battle.is_finished() and not _has_narrative_decision():
		var next := delta
		for strategy in _cpu_strategies.values():
			next = minf(next, strategy.time_until_decision)
		var used := _advance_simulation(next)
		delta -= used
		for strategy in _cpu_strategies.values():
			strategy.time_until_decision = maxf(0.0, strategy.time_until_decision - used)
		if _battle.is_finished() or _has_narrative_decision():
			break
		for side in _cpu_strategies:
			var strategy := _cpu_strategies[side]
			if strategy.time_until_decision > MatchBattle.TIME_EPSILON:
				continue
			strategy.time_until_decision = _decision_period(strategy)
			if side == CPU:
				_try_cpu_purchase()
			else:
				strategy.decide(self)
	if _battle.is_finished():
		_cancel_placement()
		_select_unit(MatchBattle.NO_TARGET)
		_select_fortification(MatchBattle.NO_TARGET)
		set_process(false)

	_strength.advance(self)
	_refresh_intelligence()
	_unit_attack_effects.render_at(_battle.elapsed_time())
	_update_missile_models()
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
	if definition.has("income"):
		_refresh_producer_income(side, building_id)
	_refresh_hud()
	return true


func _refresh_producer_income(side: MatchRegion.Owner, kind: StringName) -> void:
	var index := 0
	for placed in _fortifications.values():
		var fort: MatchBattle.Fortification = placed.defense
		if fort.side != side or fort.kind != kind:
			continue
		index += int(fort.active)
		var efficiency := MatchEconomy.producer_efficiency(index)
		var region := get_region(placed.regions[0])
		var factor := RegionSpecialty.income_factor(region.specialty, kind)
		for resource_id in fort.profile.income:
			faction_stats.set_modifier(fort.source_id, side, resource_id,
				fort.profile.income[resource_id] * efficiency * factor, &"building",
				"%s #%d" % [fort.profile.label, absi(fort.id)],
				"%d%% producer efficiency · %d%% regional output" % [roundi(efficiency * 100), roundi(factor * 100)],
				fort.active, fort.id, region.region_id)


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
	if not _battle.navigation.contains_footprint(polygon):
		return "Keep the entire footprint on the map"
	if _battle.objectives.reserves_footprint(polygon):
		return "Keep the objective site clear"
	for region_id in covered:
		if get_region(region_id).ruined:
			return "Permanently ruined terrain"
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
	if not _battle.is_side_active(side) or not BUILDINGS.has(building_id):
		return "Building unavailable"
	return economy.cost_block_reason(side, _minimum_build_cost(building_id))


func _minimum_build_cost(building_id: StringName) -> Dictionary:
	if building_id == Fortifications.WALL:
		return Fortifications.wall_cost(1)
	return Fortifications.PROFILES.get(building_id, BUILDINGS[building_id]).cost


func _footprint_regions(polygon: PackedVector2Array) -> Array[StringName]:
	var covered: Array[StringName] = []
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	for region_id in _regions_by_id:
		var region := get_region(region_id)
		if bounds.intersects(region.map_bounds) and not Geometry2D.intersect_polygons(polygon, region.polygon).is_empty():
			covered.append(region_id)
	return covered


func _owns_footprint(side: MatchRegion.Owner, polygon: PackedVector2Array,
		covered: Array[StringName]) -> bool:
	if not _buildings.has(side) or covered.is_empty():
		return false
	for point in polygon:
		if not _layout.contains(point):
			return false
	for region_id in covered:
		if not owns_region(side, region_id):
			return false
	return true


static func _building_slot_cost(kind: StringName) -> int:
	return 0 if kind == Fortifications.WALL else Fortifications.PROFILES.get(kind, {}).get("slots", 1)


func _register_region_structure(id: StringName, kind: StringName, covered: Array[StringName],
		fort: MatchBattle.Fortification = null) -> void:
	var entry := {"kind": kind, "fort": fort}
	for region_id in covered:
		_region_structures[region_id][id] = entry


func _unregister_region_structure(id: StringName) -> void:
	for structures in _region_structures.values():
		structures.erase(id)


func region_occupancy(region_id: StringName, observer := MatchRegion.Owner.NEUTRAL) -> Dictionary:
	var used := 0
	var by_kind := {}
	var inactive := {}
	for entry in _region_structures.get(region_id, {}).values():
		var kind: StringName = entry.kind
		var fort := entry.fort as MatchBattle.Fortification
		if observer != MatchRegion.Owner.NEUTRAL and _battle.visibility != null:
			if fort != null and fort.side != observer and not _battle.can_see(observer, fort.position):
				continue
			if kind == LEGENDARY_KIND and not landmark_known(observer, _landmarks[region_id]):
				continue
			if kind == OUTPOST_KIND:
				var outpost := _outposts_by_region.get(region_id) as MatchBattle.Outpost
				if outpost == null or (outpost.side != observer and not _battle.can_see(observer, outpost.position)):
					continue
		used += _building_slot_cost(kind)
		by_kind[kind] = by_kind.get(kind, 0) + 1
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
		if get_region(region_id).ruined:
			return "Permanently ruined terrain"
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
	if not _layout.contains(start) or not _layout.contains(end):
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
	var region := get_region(_layout.region_at(defense.position))
	if region != null and (defense.profile.has("range") or defense.kind == BattleRadar.WATCHTOWER):
		defense.local_health_factor = RegionSpecialty.defense_factor(region.specialty)
		defense.hp = defense.max_hp
	_register_region_structure(defense.source_id, defense.kind, covered, defense)
	var view := BUILDINGS[defense.kind].scene.instantiate() as Node3D
	_buildings[defense.side].add_child(view)
	view.global_position = _world_position(defense.position)
	view.rotation.y = -defense.angle
	_structure_accent(view, defense.kind).material_override = _faction_accent(defense.side)
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
	if defense.profile.has("income"):
		_refresh_producer_income(defense.side, defense.kind)
	if defense.destroyed_by_missile:
		_leave_ruined_model(placed.view)
	else:
		placed.view.get_parent().remove_child(placed.view)
		placed.view.queue_free()
	if _selected_fortification == defense.id:
		_select_fortification(MatchBattle.NO_TARGET)


func _show_unit_effect(attack: MatchBattle.AttackResolved) -> void:
	if _battle.can_see(PLAYER, attack.attack_position) and _battle.can_see(PLAYER, attack.impact_position):
		_unit_attack_effects.record(attack)


func _show_fortification_shot(fort: MatchBattle.Fortification, impact: Vector2) -> void:
	if not _battle.can_see(PLAYER, fort.position) or not _battle.can_see(PLAYER, impact):
		return
	if fort.kind == Fortifications.ANTI_TANK:
		var placed := _fortifications.get(fort.id) as PlacedFortification
		if placed != null:
			var turret := placed.view.get_node(^"Turret") as Node3D
			var direction := fort.position.direction_to(impact)
			turret.rotation.y = atan2(direction.x, direction.y) + fort.angle
			var barrel := turret.get_node(^"Barrel") as MeshInstance3D
			barrel.position.z = 0.37
			barrel.create_tween().tween_property(barrel, "position:z", 0.64, 0.22)
		var flash := MeshInstance3D.new()
		flash.mesh = _splash_ring.mesh
		_shot_effects.add_child(flash)
		flash.global_position = _world_position(impact) + Vector3.UP * 0.5
		flash.scale = Vector3.ONE * 0.38
		flash.create_tween().tween_callback(flash.queue_free).set_delay(0.20)
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
		var shot_width := 0.08 if fort.kind == Fortifications.ANTI_TANK else 0.035
		var perpendicular := fort.position.direction_to(impact).orthogonal() * shot_width
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


func _refresh_structure_accent(placed: PlacedFortification) -> void:
	var fort: MatchBattle.Fortification = placed.defense
	var silo := fort as MatchBattle.MissileSilo
	var exhausted := silo != null and silo.missile_state == MatchBattle.MissileState.EXHAUSTED
	_structure_accent(placed.view, fort.kind).material_override = _faction_accent(fort.side) \
		if fort.active and not exhausted else INACTIVE_ACCENT


func _preview_missile_at(pointer: Vector2) -> void:
	_missile_ring.hide()
	if _camera.is_dragging() or get_viewport().gui_get_hovered_control() != null:
		return
	var point: Variant = _ground_point(pointer)
	if point != null:
		var target := _map_position(point)
		_show_radius_ring(_missile_ring, Fortifications.MISSILE_RADIUS,
			Vector3(target.x, 0.18, target.y), _layout.contains(target))


func _show_missile_launch(silo: MatchBattle.MissileSilo, flight: MatchBattle.MissileFlight) -> void:
	var placed := _fortifications.get(silo.id) as PlacedFortification
	if placed != null:
		_refresh_structure_accent(placed)
		var hatch := placed.view.get_node(^"Hatch") as MeshInstance3D
		hatch.position.x = 1.15
	if flight.side == PLAYER:
		var model := MeshInstance3D.new()
		model.mesh = _missile_mesh
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shot_effects.add_child(model)
		_missile_models[flight] = model
	_missile_flash(flight.source, 2.4, 0.35)
	_missile_notice = "%s missile in flight" % _side_label(flight.side)
	_missile_notice_until = flight.impact_at
	_update_missile_models()


func _show_missile_cancelled(side: MatchRegion.Owner) -> void:
	var label := _side_label(side)
	_missile_notice = "%s missile launch cancelled" % label
	_missile_notice_until = _battle.elapsed_time() + 2.5


func _update_missile_models() -> void:
	for flight in _missile_models.keys():
		var model := _missile_models[flight]
		var fraction := clampf((_battle.elapsed_time() - flight.started_at) / Fortifications.MISSILE_FLIGHT, 0.0, 1.0)
		if fraction >= 1.0 - MatchBattle.TIME_EPSILON:
			_missile_models.erase(flight)
			model.hide()
			model.queue_free()
			continue
		var next := _missile_flight_position(flight, minf(1.0, fraction + 0.01))
		model.global_position = _missile_flight_position(flight, fraction)
		var heading := model.global_position.direction_to(next)
		if not heading.is_zero_approx():
			model.quaternion = Quaternion(Vector3.UP, heading)


func _missile_flight_position(flight: MatchBattle.MissileFlight, fraction: float) -> Vector3:
	var ground := _world_position(flight.source.lerp(flight.target, smoothstep(0.12, 0.92, fraction)))
	return ground + Vector3.UP * (0.75 + sin(PI * fraction) * 10.0)


func _missile_flash(point: Vector2, radius: float, duration: float) -> void:
	var flash := MeshInstance3D.new()
	flash.mesh = _missile_ring.mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shot_effects.add_child(flash)
	flash.global_position = _world_position(point) + Vector3.UP * 0.22
	flash.scale = Vector3.ONE * minf(0.8, radius)
	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * radius, duration * 0.55)
	tween.tween_callback(flash.queue_free).set_delay(duration * 0.45)


func _update_missile_warning() -> void:
	var warning := %MissileWarning as Label
	var lines := PackedStringArray()
	var launches := _battle.public_missile_launches()
	var screen := get_viewport().get_visible_rect().grow(-38.0)
	for id in _missile_arrows.keys():
		if not launches.has(id):
			_missile_arrows[id].queue_free()
			_missile_arrows.erase(id)
	for id in launches:
		var announcement: Dictionary = launches[id]
		var left := maxf(0.0, announcement.launches_at - _battle.elapsed_time())
		lines.append("%s missile preparing · %.0fs" % [_side_label(announcement.side), ceilf(left)])
		var pointer := _camera.unproject_position(_world_position(announcement.point) + Vector3.UP)
		var offscreen := not screen.has_point(pointer)
		var arrow := _missile_arrows.get(id) as Label
		if arrow == null and offscreen:
			arrow = Label.new()
			arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			arrow.add_theme_color_override("font_color", Color("#ff856d"))
			arrow.add_theme_color_override("font_outline_color", Color("#10151d"))
			arrow.add_theme_constant_override("outline_size", 7)
			arrow.add_theme_font_size_override("font_size", 17)
			$HUD.add_child(arrow)
			_missile_arrows[id] = arrow
		if arrow != null:
			arrow.visible = offscreen
			if offscreen:
				var direction := screen.get_center().direction_to(pointer)
				var octant := posmod(roundi(direction.angle() / (PI / 4.0)), 8)
				arrow.text = "%s %.0fs" % [["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"][octant], ceilf(left)]
				var inset := screen.grow(-24.0)
				arrow.position = pointer.clamp(inset.position, inset.end) - arrow.size * 0.5
	if lines.is_empty() and _missile_notice_until > _battle.elapsed_time():
		lines.append(_missile_notice)
	warning.visible = not lines.is_empty()
	warning.text = "\n".join(lines)


func _ruin_strike_regions(flight: MatchBattle.MissileFlight) -> void:
	var target := flight.target
	var area_squared := Fortifications.MISSILE_RADIUS ** 2
	for cell in _layout.cells:
		if _initial_owners[cell.id] != MatchRegion.Owner.NEUTRAL:
			continue
		var region := get_region(cell.id)
		var hub := cell.site
		if _layout.base_positions.has(cell.id):
			hub = _layout.base_positions[cell.id]
		var outpost := _outposts_by_region.get(cell.id) as MatchBattle.Outpost
		if outpost != null:
			hub = outpost.position
		if not region.ruined and hub.distance_squared_to(target) <= area_squared:
			region.ruined = true
			_set_region_owner(cell.id, MatchRegion.Owner.NEUTRAL, false)
		var landmark := _landmarks.get(cell.id) as LegendaryLandmark
		if landmark != null and (region.ruined or Fortifications.blast_hits(target,
				landmark.footprint.get_center(), landmark.footprint.size)):
			if _battle.remove_landmark_footprint(landmark.footprint):
				_unregister_region_structure(landmark.source_id)
				faction_stats.remove_source(landmark.source_id)
				var remains := landmark.duplicate() as Node3D
				landmark.get_parent().add_child(remains)
				_leave_ruined_model(remains)
				landmark.hide()
	if flight.side == PLAYER or _battle.can_see(PLAYER, target):
		_missile_flash(target, Fortifications.MISSILE_RADIUS, 1.1)
		_missile_flash(target, Fortifications.MISSILE_RADIUS * 0.65, 0.7)
	_missile_notice = "Strategic missile impact"
	_missile_notice_until = _battle.elapsed_time() + 2.5


func _leave_ruined_model(model: Node3D) -> void:
	model.reparent(_ruins, true)
	model.scale.y *= 0.55
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = _ruin_material


func _world_position(point: Vector2) -> Vector3:
	return _regions.to_global(Vector3(point.x, 0.0, point.y))


func _create_build_options() -> void:
	for section: Dictionary in BUILD_SECTIONS:
		if section.entries.is_empty():
			continue
		var group := VBoxContainer.new()
		group.name = section.id
		group.add_theme_constant_override("separation", 3)
		_build_list.add_child(group)
		var heading := Label.new()
		heading.text = section.label
		heading.add_theme_color_override("font_color", Color("#f3ce89"))
		heading.add_theme_font_size_override("font_size", 16)
		group.add_child(heading)
		for building_id: StringName in section.entries:
			var option := Button.new()
			option.name = building_id
			option.alignment = HORIZONTAL_ALIGNMENT_LEFT
			option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			option.add_theme_font_size_override("font_size", 14)
			option.icon = BUILDINGS[building_id].get("icon")
			option.pressed.connect(_begin_placement.bind(building_id))
			group.add_child(option)
			_build_options[building_id] = option
			_build_descriptions[building_id] = _build_description(building_id)


func _build_description(building_id: StringName, barracks_interval := -1.0) -> String:
	var definition: Dictionary = BUILDINGS[building_id]
	var profile: Dictionary = Fortifications.PROFILES.get(building_id, definition)
	var price := MatchEconomy.cost_text(_minimum_build_cost(building_id))
	if building_id == Fortifications.WALL:
		price += " per segment"
	var effect: String = profile.get("description", "")
	if definition.has("income"):
		effect = _income_text(definition.income)
	elif definition.has("unit_type"):
		var interval: float = barracks_interval if barracks_interval >= 0.0 else definition.interval
		var unit: Dictionary = UnitCatalog.DEFINITIONS[definition.unit_type]
		effect = "%s every %ss · %s per unit" % [
			unit.label, _stat_number(interval), MatchEconomy.cost_text({MatchEconomy.FOOD: unit.food}),
		]
	return "%s · %s\n%s" % [profile.label, price, effect]


func _refresh_build_options() -> void:
	var interval := economy.production_interval(PLAYER)
	if _barracks_menu_interval != interval:
		_barracks_menu_interval = interval
		_build_descriptions[&"barracks"] = _build_description(&"barracks", interval)

	var focus_owner := get_viewport().gui_get_focus_owner()
	var needs_focus := false
	var availability_changed := false
	for building_id: StringName in _build_options:
		var option := _build_options[building_id]
		var reason := _catalog_block_reason(PLAYER, building_id)
		var disabled := not reason.is_empty()
		var description := _build_descriptions[building_id]
		if disabled:
			description += "\n" + reason
		if option.text != description:
			option.text = description
		if option.disabled != disabled:
			option.disabled = disabled
			option.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
			needs_focus = needs_focus or (option == focus_owner and disabled)
			availability_changed = true
		option.tooltip_text = reason

	if _build_menu.visible:
		if availability_changed:
			_link_build_focus()
		if needs_focus:
			_focus_build_menu()


func _link_build_focus() -> void:
	var stops: Array[Button] = [%CloseBuild]
	for section: Dictionary in BUILD_SECTIONS:
		for id: StringName in section.entries:
			if not _build_options[id].disabled:
				stops.append(_build_options[id])
	for index in stops.size():
		var option := stops[index]
		option.focus_previous = option.get_path_to(stops[posmod(index - 1, stops.size())])
		option.focus_next = option.get_path_to(stops[(index + 1) % stops.size()])
		option.focus_neighbor_top = option.focus_previous
		option.focus_neighbor_bottom = option.focus_next
		option.focus_neighbor_left = ^"."
		option.focus_neighbor_right = ^"."


func _focus_build_menu() -> void:
	var close := %CloseBuild as Button
	var option := close.get_node(close.focus_next) as Button
	option.grab_focus()
	if option != close:
		_reveal_focused_build_option(option)


func _reveal_focused_build_option(option: Button) -> void:
	# Containers sort after the menu becomes visible. Read the row's final bounds.
	await get_tree().process_frame
	await get_tree().process_frame
	if _build_menu.visible and option.has_focus():
		_build_scroll.ensure_control_visible(option)


func _toggle_build_menu() -> void:
	if _build_menu.visible:
		_dismiss_build()
		return
	_cancel_placement()
	_show_income_sources(&"")
	_build_menu.show()
	_camera.menu_navigation = true
	_layout_hud()
	_update_context_visibility()
	_queue_hud_layout()
	_link_build_focus()
	_focus_build_menu()
	_build_scroll.scroll_vertical = 0


func _dismiss_build() -> void:
	_cancel_placement()
	_build_button.grab_focus()


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
	_cancel_selection_drag()
	_clear_ground_target()
	_clear_pending_unit_order()
	if _preview != null:
		remove_child(_preview)
		_preview.queue_free()
		_preview = null
	_placement_id = &""
	_pending_pick = Vector2.INF
	_clear_wall_drag()
	_placement_panel.hide()
	_build_menu.hide()
	_camera.menu_navigation = false
	_update_unit_selection()
	_update_fortification_inspection()
	_update_context_visibility()


func _update_placement_preview(pointer: Vector2) -> void:
	if _preview == null:
		return
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
	if definition.has("range"):
		_placement_label.text += "\n" + _range_text(definition)
		_show_ranges(definition, _map_position(_preview.global_position), _preview.visible)
	else:
		_hide_ranges()
	if not _placement_panel.visible:
		_placement_panel.show()
		_update_context_visibility()
		_queue_hud_layout()


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
	if not _placement_panel.visible:
		_placement_panel.show()
		_update_context_visibility()
		_queue_hud_layout()



func try_upgrade(side: MatchRegion.Owner, building_id: int) -> bool:
	if not _battle.upgrade_producer(side, building_id, economy):
		return false

	_refresh_hud()
	return true


func dispatch_scout(side: MatchRegion.Owner, region_id: StringName, rank_route := Callable()) -> String:
	return _expeditions.dispatch(side, region_id, rank_route)


func _claim_selected_region() -> void:
	var reason := dispatch_scout(PLAYER, _selected_region_id)
	if not reason.is_empty():
		_show_expedition_notice(PLAYER, reason)
	else:
		_scout_notice.hide()
	_refresh_hud()


func _complete_claim(side: MatchRegion.Owner, region_id: StringName, scout_id: int,
		point: Vector2) -> void:
	if get_region(region_id).ruined:
		return
	var outpost := _battle.add_outpost(region_id, side, point, maxi(1, outpost_hp))
	outpost.local_health_factor = RegionSpecialty.defense_factor(get_region(region_id).specialty)
	var footprint := Fortifications.footprint(point, MatchBattle.OUTPOST_FOOTPRINT * 2.0)
	_register_region_structure(outpost.source_id, OUTPOST_KIND, _footprint_regions(footprint))
	_outposts_by_region[region_id] = outpost
	var view := OUTPOST.instantiate() as Node3D
	view.get_node("Beacon").material_override = _faction_accent(side)
	get_region(region_id).add_child(view)
	view.global_position = _regions.to_global(Vector3(point.x, 0.0, point.y))
	_outpost_views[region_id] = view
	_set_region_owner(region_id, side)
	outpost.hp = outpost.max_hp
	_refresh_claim_control()
	_strength.award(economy, side, StringName("region/" + region_id), _battle.elapsed_time(), _landmarks.has(region_id))
	claim_completed.emit(side, region_id, scout_id)


func _discover_on_claim(side: MatchRegion.Owner, region_id: StringName, _scout_id: int) -> void:
	# The first successful claim by this faction owns this occurrence for the match.
	# Replacements and reclamations reuse the ID, even if another Scout completes them.
	var id := StringName("claim/%d/%s" % [side, region_id])
	if narrative_events.submit(id, CLAIM_DISCOVERY, side, region_id) and side != PLAYER:
		narrative_events.resolve_cpu(id)


func _lose_region(outpost: MatchBattle.Outpost) -> void:
	var region_id := outpost.region_id
	var view := _outpost_views[region_id]
	if outpost.destroyed_by_missile:
		_leave_ruined_model(view)
	else:
		view.get_parent().remove_child(view)
		view.queue_free()
	_outpost_views.erase(region_id)
	_outposts_by_region.erase(region_id)
	_unregister_region_structure(outpost.source_id)
	_set_region_owner(region_id, MatchRegion.Owner.NEUTRAL)


func _set_region_owner(region_id: StringName, side: MatchRegion.Owner, refresh := true) -> void:
	var region := get_region(region_id)
	if region.ruined and side != MatchRegion.Owner.NEUTRAL:
		return
	region.region_owner = side
	faction_stats.set_source_owner(region_source_id(region_id), side)
	var landmark := _landmarks.get(region_id) as LegendaryLandmark
	if landmark != null:
		faction_stats.set_source_owner(landmark.source_id, side)
	for placed in _fortifications.values():
		if not placed.regions.has(region_id):
			continue
		var active := true
		for covered in placed.regions:
			if not owns_region(placed.defense.side, covered):
				active = false
				break
		_battle.set_fortification_active(placed.defense, active)
		_refresh_structure_accent(placed)
		if placed.defense.profile.has("income"):
			_refresh_producer_income(placed.defense.side, placed.defense.kind)
	if refresh:
		_refresh_hud()
		if _preview != null:
			_refresh_placement_preview()


## Use this ID for contributions that follow control of a region.
static func region_source_id(region_id: StringName) -> StringName:
	return StringName("region/" + region_id)


func set_region_modifier(region_id: StringName, stat: StringName, magnitude: float,
		source_name: String, source_type := &"landmark", description := "") -> bool:
	var region := get_region(region_id)
	return region != null and not region.ruined and faction_stats.set_modifier(region_source_id(region_id),
		region.region_owner, stat, magnitude, source_type, source_name, description, true, 0, region_id)


func owns_region(side: MatchRegion.Owner, region_id: StringName) -> bool:
	var region := get_region(region_id)
	return region != null and region.region_owner == side


func get_region(region_id: StringName) -> MatchRegion:
	return _regions_by_id.get(region_id)


func region_at_world_position(world_position: Vector3) -> StringName:
	return _layout.region_at(_map_position(world_position)) if _layout != null else &""


func selected_unit() -> MatchBattle.Unit:
	return _battle.get_unit(_selected_unit_id) if _battle != null else null


func _map_position(world_position: Vector3) -> Vector2:
	var local := _regions.to_local(world_position)
	return Vector2(local.x, local.z)


func _input(event: InputEvent) -> void:
	if _selection_origin.is_finite():
		if event is InputEventMouseMotion:
			_update_selection_drag(event.position)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
				_cancel_selection_drag()
			elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
				# If the HUD consumes the release, cancel rather than issue an order.
				_finish_consumed_selection_release.call_deferred(_selection_gesture)
	if _ground_target != GroundTarget.NONE and (event.is_action_pressed("ui_cancel")
			or event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		_clear_ground_target()
		_update_fortification_inspection()
		get_viewport().set_input_as_handled()
		return
	if not _camera.is_dragging() and (_preview != null or _build_menu.visible):
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
			_dismiss_build()
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
	if _control_group_shortcut(event):
		get_viewport().set_input_as_handled()
		return
	if _camera.is_dragging():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT \
			and not _battle.is_finished() and _placement_id.is_empty():
		if event.pressed:
			_selection_origin = event.position
			_selection_gesture += 1
			_selection_dragged = false
		elif _selection_origin.is_finite():
			_update_selection_drag(event.position)
			if _selection_dragged:
				_select_in_rectangle(Rect2(_selection_origin, event.position - _selection_origin).abs(),
					event.shift_pressed, event.ctrl_pressed)
			elif _selected_unit_can_receive_orders():
				_clear_pending_unit_order()
				_issue_unit_order_at(event.position, MatchBattle.Order.MOVE)
			_cancel_selection_drag()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and _income_sources.visible:
		_close_income_sources()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and _pending_unit_order != MatchBattle.Order.AUTONOMOUS:
		_clear_pending_unit_order()
		_update_unit_selection()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and (not _selected_units.is_empty()
			or _selected_fortification != MatchBattle.NO_TARGET):
		_clear_inspection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not _selected_region_id.is_empty():
		_clear_region_selection()
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
				_dismiss_build()
			elif _income_sources.visible:
				_close_income_sources()
			elif _preview != null:
				# The camera may move before the next physics tick commits the placement.
				var point: Variant = _ground_point(event.position)
				_pending_pick = _map_position(point) if point != null else Vector2.INF
			elif _ground_target != GroundTarget.NONE:
				_commit_ground_target(event.position)
			elif _pending_unit_order != MatchBattle.Order.AUTONOMOUS:
				_issue_unit_order_at(event.position, _pending_unit_order)
			else:
				_pick_map(event.position)
			get_viewport().set_input_as_handled()


func _update_selection_drag(pointer: Vector2) -> void:
	if pointer.distance_squared_to(_selection_origin) >= SELECTION_DRAG_THRESHOLD ** 2:
		_selection_dragged = true
	if _selection_dragged:
		var rectangle := Rect2(_selection_origin, pointer - _selection_origin).abs()
		_selection_box.position = rectangle.position
		_selection_box.size = rectangle.size.max(Vector2.ONE)
		_selection_box.show()


func _finish_consumed_selection_release(gesture: int) -> void:
	if gesture == _selection_gesture:
		_cancel_selection_drag()


func _cancel_selection_drag() -> void:
	_selection_origin = Vector2.INF
	_selection_dragged = false
	_selection_box.hide()


func _select_in_rectangle(rectangle: Rect2, extend: bool, subtract: bool) -> void:
	if not extend and not subtract:
		_selected_units.clear()
	else:
		# A single enemy may be inspected, but can never enter the command group.
		var inspected := selected_unit()
		if inspected != null and inspected.side != PLAYER:
			_selected_units.clear()
	for id in _unit_views:
		var unit := _battle.get_unit(id)
		if unit == null or unit.side != PLAYER or unit.hp <= 0.0:
			continue
		var point := _unit_views[id].global_position
		if _camera.is_position_behind(point) or not rectangle.has_point(_camera.unproject_position(point)):
			continue
		if subtract:
			_selected_units.erase(id)
		else:
			_selected_units[id] = true
	_select_fortification(MatchBattle.NO_TARGET)
	_select_region(&"")
	_refresh_unit_selection()


func _begin_ground_target(mode: GroundTarget) -> void:
	_clear_pending_unit_order()
	_ground_target = mode
	match mode:
		GroundTarget.RALLY:
			_ground_target_hint = "Click ground to set rally point · Esc to cancel"
		GroundTarget.MISSILE:
			_ground_target_hint = "Click to commit the strike · Esc to cancel"
		GroundTarget.DECOY:
			_ground_target_hint = "Click ground to place a radar decoy · Esc to cancel"
	_update_fortification_inspection()


func _clear_ground_target() -> void:
	_ground_target = GroundTarget.NONE
	_ground_target_hint = ""
	_missile_ring.hide()


func _commit_ground_target(pointer: Vector2) -> void:
	var ground: Variant = _ground_point(pointer)
	if _ground_target == GroundTarget.RALLY:
		if ground != null and _battle.set_producer_rally(PLAYER, _selected_fortification, _map_position(ground)):
			_clear_ground_target()
		else:
			_ground_target_hint = "Choose reachable ground · Esc to cancel"
	elif _ground_target == GroundTarget.MISSILE:
		if ground != null and _battle.prepare_missile(PLAYER, _selected_fortification, _map_position(ground)):
			_clear_ground_target()
		else:
			_ground_target_hint = "Choose a point inside the battlefield · Esc to cancel"
	elif _ground_target == GroundTarget.DECOY:
		if ground != null and _battle.deploy_decoy(PLAYER, _selected_fortification, _map_position(ground)):
			_clear_ground_target()
		else:
			_ground_target_hint = "Choose a point inside the battlefield · Esc to cancel"
	_update_fortification_inspection()
	_update_missile_warning()


func _clear_rally() -> void:
	if _battle.set_producer_rally(PLAYER, _selected_fortification, Vector2.INF):
		_clear_ground_target()
		_update_fortification_inspection()


func _physics_process(_delta: float) -> void:
	if _ground_target == GroundTarget.MISSILE:
		_preview_missile_at(get_viewport().get_mouse_position())
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
		if unit.type_id != UnitCatalog.SCOUT and not owns_region(MatchRegion.Owner.NEUTRAL, _selected_region_id):
			_select_region(&"")
	else:
		var building := _pick_building(pointer)
		var point: Variant = _ground_point(pointer) if building == null else building.global_position
		var region_id := region_at_world_position(point) if point != null else &""
		var scout := _expeditions.scout_for(_selected_unit_id)
		var fort_id: int = _fortification_ids.get(building, MatchBattle.NO_TARGET)
		var contact := _radar_contacts_view.contact_at(_camera, pointer, _battle, PLAYER)
		if scout == null or scout.side != PLAYER or fort_id != MatchBattle.NO_TARGET \
				or not owns_region(MatchRegion.Owner.NEUTRAL, region_id):
			_select_unit(MatchBattle.NO_TARGET)
		_select_fortification(fort_id)
		_select_region(region_id)
		_inspected_radar = contact
	_refresh_claim_control()


func _pick_building(pointer: Vector2) -> Node3D:
	var start := _camera.project_ray_origin(pointer)
	var end := start + _camera.project_ray_normal(pointer) * _camera.far
	var buildings: Array[Node] = []
	buildings.append_array(_bases.values())
	for container in _buildings.values():
		buildings.append_array(container.get_children())
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
		if not _battle.can_observe_unit(PLAYER, _battle.get_unit(id)):
			continue
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
	var unit := _battle.get_unit(id) if _battle != null else null
	if unit != null and not _battle.can_observe_unit(PLAYER, unit):
		id = MatchBattle.NO_TARGET
	if _selected_units.size() <= 1 and id == _selected_unit_id:
		_update_unit_selection()
		return
	_selected_units.clear()
	if id != MatchBattle.NO_TARGET:
		_selected_units[id] = true
	_refresh_unit_selection()


func _refresh_unit_selection() -> void:
	_stat_sources.button_pressed = false
	_clear_pending_unit_order()
	_selected_unit_id = _selected_units.keys()[0] if _selected_units.size() == 1 else MatchBattle.NO_TARGET
	_update_unit_selection()
	_update_context_visibility()


func _update_unit_selection() -> void:
	var group := _placement_id.is_empty() and _selected_units.size() > 1
	if group:
		_update_group_rings()
		_update_group_inspection()
		return
	_hide_group_rings()
	var unit := selected_unit() if _placement_id.is_empty() and _battle != null else null
	_unit_selection.visible = unit != null
	_unit_panel.visible = unit != null
	_route_mesh.clear_surfaces()
	var combat_unit := unit != null and unit.type_id != UnitCatalog.SCOUT
	var can_command := combat_unit and _selected_unit_can_receive_orders()
	_stance_label.visible = combat_unit
	_stance_picker.visible = can_command
	_tactical_orders.visible = can_command
	if unit == null:
		_recall_button.hide()
		_unit_claim_progress.hide()
		return

	_unit_selection.global_position = _unit_views[unit.id].global_position
	_unit_selection.scale = Vector3.ONE * float(unit.definition.selection_scale)
	_unit_name.text = "%s %s #%d" % [_side_label(unit.side), unit.definition.label, unit.id]
	_unit_name.modulate = _faction_accent(unit.side).albedo_color.lightened(0.25)
	var scout := _expeditions.scout_for(unit.id)
	_stat_sources.visible = scout == null
	if scout != null:
		_update_scout_inspection(unit, scout)
		return
	_recall_button.hide()
	_unit_claim_progress.hide()
	_stance_label.text = "Stance" if can_command else "Stance  " + _stance_name(unit.stance)
	if _stance_picker.get_selected_id() != unit.stance:
		_stance_picker.select(_stance_picker.get_item_index(unit.stance))
	_unit_order_hint.text = "Right-click ground to move" if _order_hint.is_empty() else _order_hint
	var attack := _battle.unit_attack_stat(unit)
	var health := _battle.unit_health_stat(unit)
	var speed := _battle.unit_speed_stat(unit)
	_unit_stats.text = "HP  %s / %s\nAttack  %s · Speed  %s units/s\nRange  %s · Cooldown  %ss" % [
		_stat_number(unit.hp), _stat_number(health.total), _stat_number(attack.total),
		_stat_number(speed.total), _stat_number(unit.definition.range),
		_stat_number(unit.attack_interval),
	]
	if unit.definition.has("support"):
		var support: Dictionary = unit.definition.support
		_unit_stats.text = "HP  %s / %s · Speed  %s units/s\nHeal  %s every %ss · Radius  %s" % [
			_stat_number(unit.hp), _stat_number(health.total), _stat_number(speed.total),
			_stat_number(support.heal), _stat_number(unit.attack_interval), _stat_number(support.radius)]
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
	if not unit.waypoints.is_empty() and (unit.side == PLAYER or _battle.visibility == null) \
			and (unit.target == MatchBattle.NO_TARGET or _target_label(unit) != "None"):
		_draw_unit_route(unit)


func _hide_group_rings() -> void:
	for ring in _group_rings:
		ring.hide()


func _update_group_rings() -> void:
	var index := 0
	for id in _selected_units:
		var unit := _battle.get_unit(id)
		if unit == null or not _unit_views.has(id):
			continue
		if index == _group_rings.size():
			var marker := _unit_selection.duplicate() as MeshInstance3D
			add_child(marker)
			_group_rings.append(marker)
		var ring := _group_rings[index]
		ring.global_position = _unit_views[id].global_position
		ring.scale = Vector3.ONE * float(unit.definition.selection_scale)
		ring.show()
		index += 1
	for remaining in range(index, _group_rings.size()):
		_group_rings[remaining].hide()


func _update_group_inspection() -> void:
	_unit_selection.hide()
	_unit_panel.show()
	_stat_sources.hide()
	_unit_stats.tooltip_text = ""
	_route_mesh.clear_surfaces()
	_recall_button.hide()
	_unit_claim_progress.hide()
	var counts := {}
	var current_hp := 0.0
	var maximum_hp := 0.0
	var stance_id := -1
	var mixed_stances := false
	var military := false
	for id in _selected_units:
		var unit := _battle.get_unit(id)
		if unit == null:
			continue
		counts[unit.type_id] = counts.get(unit.type_id, 0) + 1
		current_hp += unit.hp
		maximum_hp += _battle.stats.value(unit.side, FactionStats.UNIT_MAX_HP, unit.definition.hp)
		if unit.type_id != UnitCatalog.SCOUT:
			military = true
			mixed_stances = mixed_stances or (stance_id >= 0 and stance_id != unit.stance)
			stance_id = unit.stance
	var types := PackedStringArray()
	for type in UnitCatalog.DEFINITIONS:
		if counts.has(type):
			types.append("%s × %d" % [UnitCatalog.DEFINITIONS[type].label, counts[type]])
	_unit_name.text = "Player selection · %d units" % _selected_units.size()
	_unit_name.modulate = _faction_accent(PLAYER).albedo_color.lightened(0.25)
	_unit_stats.text = "Combined HP  %s / %s" % [_stat_number(current_hp), _stat_number(maximum_hp)]
	_unit_intent.text = " · ".join(types)
	_stance_label.visible = military
	_stance_label.text = "Mixed stances" if mixed_stances else "Stance"
	_stance_picker.visible = military
	_stance_picker.select(-1 if mixed_stances else _stance_picker.get_item_index(stance_id))
	_tactical_orders.visible = military
	_unit_order_hint.show()
	_unit_order_hint.text = "Right-click ground to move" if _order_hint.is_empty() else _order_hint


func _select_fortification(id: int) -> void:
	if id != _selected_fortification:
		_clear_ground_target()
		_stat_sources.button_pressed = false
	_selected_fortification = id
	_update_fortification_inspection()
	_update_context_visibility()
	_queue_hud_layout()


func _update_fortification_inspection() -> void:
	var placed: PlacedFortification = _fortifications.get(_selected_fortification)
	if placed == null or not _placement_id.is_empty():
		_producer_stance.hide()
		_upgrade_button.hide()
		_upgrade_button.disabled = true
		%TargetMissile.hide()
		_decoy_button.hide()
		%RallyControls.hide()
		_rally_ring.hide()
		if _placement_id.is_empty():
			_hide_ranges()
		if _selected_units.is_empty() or not _placement_id.is_empty():
			_unit_panel.hide()
		return
	var fort: MatchBattle.Fortification = placed.defense
	if fort.side != PLAYER and not _battle.can_see(PLAYER, fort.position):
		_select_fortification(MatchBattle.NO_TARGET)
		return
	_decoy_button.visible = fort.kind == BattleRadar.COUNTERINTELLIGENCE and fort.side == PLAYER
	_decoy_button.disabled = not fort.active or _battle.is_finished() or (		_decoy_button.visible and not _battle.radar.can_deploy(PLAYER, fort.id, _battle.elapsed_time()))
	var military := fort is MatchBattle.ProductionTimer
	var silo := fort as MatchBattle.MissileSilo
	%TargetMissile.visible = silo != null and silo.side == PLAYER and silo.hp > 0.0 \
		and silo.active and silo.missile_state == MatchBattle.MissileState.READY and not _battle.is_finished()
	_producer_stance.visible = military
	if not military:
		_upgrade_button.hide()
		%RallyControls.hide()
		_rally_ring.hide()
	_unit_panel.show()
	_tactical_orders.hide()
	_stance_label.hide()
	_stance_picker.hide()
	_stat_sources.show()
	_unit_name.text = "%s %s" % [_side_label(fort.side), fort.profile.label]
	_unit_name.modulate = _faction_accent(fort.side).albedo_color.lightened(0.25)
	_unit_stats.text = _health_text(fort)
	var details := _breakdown_text("Maximum HP", fort.health_stat())
	if fort.local_health_factor > 1.0:
		details += "\nDefensible region  +20% base HP"
	_unit_intent.text = "Active" if fort.active else "Inactive · territory lost"
	if silo != null:
		match silo.missile_state:
			MatchBattle.MissileState.READY:
				_unit_intent.text += "\nMissile ready · Blast radius %s" % _stat_number(Fortifications.MISSILE_RADIUS)
			MatchBattle.MissileState.CHARGING:
				_unit_intent.text += "\nPreparing launch · %.1fs" % maxf(0.0, silo.launches_at - _battle.elapsed_time())
			MatchBattle.MissileState.EXHAUSTED:
				_unit_intent.text += "\nExhausted · Missile expended"
	if fort is MatchBattle.ProductionTimer:
		var production: Dictionary = fort.production_stat(economy)
		var unit: Dictionary = UnitCatalog.DEFINITIONS[fort.unit_type]
		_unit_intent.text += "\nNext unit  %s · %s per unit\nCapacity  %s units/s" % [
			unit.label, MatchEconomy.cost_text({MatchEconomy.FOOD: unit.food}),
			_stat_number(production.total),
		]
		var remaining: float = fort.interval(economy) - fort.elapsed
		_unit_intent.text += "\nProduction  " + ("%.1fs remaining" % remaining
			if remaining > MatchBattle.TIME_EPSILON else "Cycle complete")
		_unit_intent.text += "\nLevel %d / 2 · %ss per cycle" % [fort.level, _stat_number(fort.interval(economy))]
		var can_configure := fort.side == PLAYER and not _battle.is_finished() and fort.hp > 0.0
		_upgrade_button.visible = can_configure
		if can_configure:
			var reason := economy.cost_block_reason(PLAYER, MatchEconomy.UPGRADE_COST)
			_upgrade_button.disabled = fort.level == 2 or not reason.is_empty()
			_upgrade_button.text = "Production upgrade installed" if fort.level == 2 else \
				"Upgrade to level 2 · %s\nCycle %ss → %ss" % [
					MatchEconomy.cost_text(MatchEconomy.UPGRADE_COST), _stat_number(fort.interval(economy)),
					_stat_number(fort.cycle_interval(economy, 2))]
			_upgrade_button.tooltip_text = reason
		%RallyControls.visible = can_configure
		%ClearRally.disabled = not fort.rally_point.is_finite()
		_show_radius_ring(_rally_ring, 0.42, Vector3(fort.rally_point.x, 0.17, fort.rally_point.y),
			fort.rally_point.is_finite())
		_producer_stance_picker.visible = can_configure
		_producer_stance_label.text = "Default behavior" if can_configure \
			else "Default behavior  " + _stance_name(fort.default_stance)
		if _producer_stance_picker.get_selected_id() != fort.default_stance:
			_producer_stance_picker.select(_producer_stance_picker.get_item_index(fort.default_stance))
		details += "\n\n" + _breakdown_text("Production capacity", production, " units/s")
	for resource_id in fort.profile.get("income", {}):
		var production := faction_stats.inspect_source(resource_id, fort.source_id)
		var label: String = MatchEconomy.RESOURCES[resource_id].label
		_unit_intent.text += "\n%s %s" % [label, _stat_amount(production.total, "/s")]
		details += "\n\n" + _breakdown_text(label + " production", production, "/s", true)
	_refresh_stat_sources(details)
	if fort.profile.get("range", 0.0) > 0.0:
		_unit_intent.text += "\n" + _range_text(fort.profile).replace(" · ", "\n")
	_unit_order_hint.visible = not _ground_target_hint.is_empty()
	_unit_order_hint.text = _ground_target_hint
	_show_ranges(fort.profile, fort.position, true)
	if fort.kind == BattleRadar.WATCHTOWER:
		_unit_intent.text += "\nVision radius %s" % _stat_number(fort.profile.vision)
		_show_radius_ring(_range_ring, fort.profile.vision, _world_position(fort.position) + Vector3.UP * 0.15, true)
	elif fort.kind == BattleRadar.RADAR and fort.side == PLAYER:
		_unit_intent.text += "\nRadar contact lifetime %.0fs" % BattleRadar.CONTACT_LIFETIME


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
	for id in _selected_units:
		if _battle._commandable_unit(PLAYER, id) != null:
			return true
	return false


func _selected_combat_unit_can_receive_orders() -> bool:
	if not _placement_id.is_empty() or _build_menu.visible:
		return false
	for id in _selected_units:
		var unit := _battle._commandable_unit(PLAYER, id)
		if unit != null and unit.type_id != UnitCatalog.SCOUT:
			return true
	return false


func _clear_pending_unit_order() -> void:
	_pending_unit_order = MatchBattle.Order.AUTONOMOUS
	_order_hint = ""


func _apply_selected_stance(index: int) -> void:
	if not _selected_combat_unit_can_receive_orders():
		return
	for id in _selected_units:
		_battle.set_unit_stance(PLAYER, id, _stance_picker.get_item_id(index), true)
	_clear_pending_unit_order()
	_update_unit_selection()


func _apply_producer_stance(index: int) -> void:
	_battle.set_producer_stance(PLAYER, _selected_fortification, _producer_stance_picker.get_item_id(index))
	_update_fortification_inspection()


func _begin_unit_order(order: MatchBattle.Order) -> void:
	if not _selected_combat_unit_can_receive_orders():
		return
	_pending_unit_order = order
	_order_hint = "Click ground to move · Esc to cancel" if order == MatchBattle.Order.MOVE \
		else "Click ground to set post · Esc to cancel"
	_update_unit_selection()


func _hold_selected_unit() -> void:
	if _selected_combat_unit_can_receive_orders():
		for id in _selected_units:
			_battle.order_hold(PLAYER, id)
		_clear_pending_unit_order()
		_update_unit_selection()


func _issue_unit_order_at(pointer: Vector2, order: MatchBattle.Order) -> void:
	if order == MatchBattle.Order.MOVE and _attack_at(pointer):
		_clear_pending_unit_order()
		_update_unit_selection()
		return
	var point: Variant = _ground_point(pointer)
	var accepted := false
	if point != null and _pick_unit(pointer) == MatchBattle.NO_TARGET:
		var destination := _map_position(point)
		if _selected_units.size() > 1:
			accepted = _battle.order_formation(PLAYER, _selected_units.keys(), destination,
				order, _resume_stance_toggle.button_pressed) > 0
		elif order == MatchBattle.Order.HOLD:
			accepted = _battle.order_hold(PLAYER, _selected_unit_id, destination)
		else:
			accepted = _battle.issue_move(_selected_unit_id, destination,
				_resume_stance_toggle.button_pressed)
	if accepted:
		_clear_pending_unit_order()
	else:
		_order_hint = "Choose reachable ground"
		if _pending_unit_order != MatchBattle.Order.AUTONOMOUS:
			_order_hint += " · Esc to cancel"
	_update_unit_selection()


func _attack_at(pointer: Vector2) -> bool:
	var id := _pick_unit(pointer)
	var base_side := MatchRegion.Owner.NEUTRAL
	if id == MatchBattle.NO_TARGET:
		var view := _pick_building(pointer)
		if view == null:
			return false
		id = _fortification_ids.get(view, MatchBattle.NO_TARGET)
		if id == MatchBattle.NO_TARGET:
			for side in _bases:
				if _bases[side] == view:
					id = MatchBattle.BASE_TARGET
					base_side = side
			for region_id in _outpost_views:
				if _outpost_views[region_id] == view:
					id = _outposts_by_region[region_id].id
	var accepted := false
	if id != MatchBattle.NO_TARGET:
		for unit_id in _selected_units:
			if _battle.order_attack(PLAYER, unit_id, id, base_side):
				accepted = true
	return accepted


static func _stance_name(stance: MatchBattle.Stance) -> String:
	return MatchBattle.Stance.keys()[stance].capitalize()


static func _stance_tooltip(stance: MatchBattle.Stance) -> String:
	match stance:
		MatchBattle.Stance.SEEK_NEAREST:
			return "Pursue the closest reachable enemy in detection range, or advance on enemy structures."
		MatchBattle.Stance.SEEK_STRONGEST:
			return "Pursue the most threatening reachable enemy in detection range, or advance on enemy structures."
		MatchBattle.Stance.IDLE:
			return "Hold position and fire at enemies in weapon range."
	return ""


func _target_label(unit: MatchBattle.Unit) -> String:
	if unit.side != PLAYER and _battle.visibility != null:
		return "—"
	if unit.target == MatchBattle.BASE_TARGET:
		return "%s base" % _side_label(unit.target_base) if _battle.can_see(PLAYER, _battle._bases[unit.target_base]) else "None"
	var target := _battle.get_unit(unit.target)
	if target != null and _battle.can_observe_unit(PLAYER, target):
		return "%s %s #%d" % [_side_label(target.side), target.definition.label, target.id]
	var outpost := _battle.get_outpost(unit.target)
	if outpost != null and _battle.can_see(PLAYER, outpost.position):
		return "%s outpost · %d/%d HP" % [_side_label(outpost.side), outpost.hp, outpost.max_hp]
	var fort := _battle.get_fortification(unit.target)
	if fort != null and _battle.can_see(PLAYER, fort.position):
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
			MatchBattle.Order.HOLD: return "Moving to hold point"
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
	return MatchRegion.side_label(side, cpu_opponent_count > 1)


func _ground_point(pointer: Vector2) -> Variant:
	var start := _camera.project_ray_origin(pointer)
	var end := start + _camera.project_ray_normal(pointer) * _camera.far
	return _map_plane().intersects_segment(start, end)


func _map_plane() -> Plane:
	return Plane(_regions.global_basis.y.normalized(), _regions.global_position)


func _select_region(region_id: StringName) -> void:
	_inspected_radar = null
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
	_observe_intelligence()
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
		_cancel_placement()
		_show_income_sources(&"")
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


func _decision_period(strategy: CpuStrategy) -> float:
	return cpu_decision_interval * strategy.difficulty.cadence


func _on_assignment_interrupted(side: MatchRegion.Owner, region_id: StringName, elapsed: float) -> void:
	var strategy := _cpu_strategies.get(side) as CpuStrategy
	if strategy != null:
		strategy.on_assignment_interrupted(side, region_id, elapsed)


func _try_cpu_purchase() -> void:
	if _cpu_strategy != null:
		_cpu_strategy.decide(self)


func _spawn_unit(unit: MatchBattle.Unit) -> void:
	var view := unit.definition.scene.instantiate() as MeshInstance3D
	view.material_override = _unit_material(unit)
	_units.add_child(view)
	_unit_views[unit.id] = view
	_update_unit_view(unit, view)


func _unit_material(unit: MatchBattle.Unit) -> StandardMaterial3D:
	var accent: StandardMaterial3D = _faction_accent(unit.side)
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
	if unit.side == MatchRegion.Owner.NEUTRAL:
		view.scale = Vector3.ONE * (1.65 if unit.type_id == UnitCatalog.STRONGHOLD_GUARD else 1.25)
	view.visible = _battle.can_observe_unit(PLAYER, unit)


func _remove_unit(unit_id: int) -> void:
	var view := _unit_views[unit_id]
	_units.remove_child(view)
	view.queue_free()
	_unit_views.erase(unit_id)
	for group in _control_groups:
		group.erase(unit_id)
	if _selected_units.erase(unit_id):
		_refresh_unit_selection()
	_refresh_control_group_bar()


func _hide_base(side: MatchRegion.Owner) -> void:
	_unregister_region_structure(_base_structure_id(side))
	var base := _bases[side]
	if _battle._base_health[side].destroyed_by_missile:
		var remains := base.duplicate() as Node3D
		base.get_parent().add_child(remains)
		_leave_ruined_model(remains)
	base.hide()
	_cpu_strategies.erase(side)
	for region_id in _regions_by_id:
		if owns_region(side, region_id):
			_set_region_owner(region_id, MatchRegion.Owner.NEUTRAL)
	if _battle.is_finished():
		narrative_events.close()


func _award_camp_bounty(side: MatchRegion.Owner, camp_id: int, _cycle: int) -> void:
	_strength.award(economy, side, StringName("camp/%d" % camp_id), _battle.elapsed_time())


func _create_control_group_bar() -> void:
	_group_bar.name = "ControlGroups"
	_group_bar.add_theme_constant_override("separation", 3)
	for index in CONTROL_GROUP_COUNT:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.custom_minimum_size.x = 36.0
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = "%d recall · Ctrl+%d assign · Shift+%d add · Double tap to center" % [
			index + 1, index + 1, index + 1]
		button.pressed.connect(_recall_control_group.bind(index))
		_group_bar.add_child(button)
		_group_buttons.append(button)
	$HUD.add_child(_group_bar)


func _reset_control_groups() -> void:
	_control_groups.clear()
	for index in CONTROL_GROUP_COUNT:
		_control_groups.append({})
	_last_group_recall = -1
	_last_group_recall_at = -1000
	_refresh_control_group_bar()


func _control_group_shortcut(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or event.alt_pressed \
			or event.meta_pressed or _battle.is_finished() or _has_narrative_decision():
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return false
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key < KEY_1 or key > KEY_9:
		return false
	var index := key - KEY_1
	if event.ctrl_pressed or event.shift_pressed:
		_assign_control_group(index, not event.ctrl_pressed)
	else:
		_recall_control_group(index)
	return true


func _assign_control_group(index: int, extend: bool) -> void:
	var members := _control_groups[index]
	if not extend:
		members.clear()
	for id in _selected_units:
		var unit := _battle.get_unit(id)
		if unit == null or unit.side != PLAYER or unit.hp <= 0.0:
			continue
		for group in _control_groups:
			group.erase(id)
		members[id] = true
	_refresh_control_group_bar()


func _recall_control_group(index: int) -> void:
	if _battle.is_finished() or _has_narrative_decision():
		return
	var ids := _control_groups[index]
	if ids.is_empty():
		return
	var now := Time.get_ticks_msec()
	var center := _last_group_recall == index and now - _last_group_recall_at <= GROUP_DOUBLE_TAP_MSEC
	_last_group_recall = index
	_last_group_recall_at = now
	_cancel_placement()
	_select_fortification(MatchBattle.NO_TARGET)
	_select_region(&"")
	_selected_units.clear()
	var minimum := Vector2.INF
	var maximum := -Vector2.INF
	for id in ids:
		var unit := _battle.get_unit(id)
		if unit != null and unit.hp > 0.0:
			_selected_units[id] = true
			minimum = minimum.min(unit.position)
			maximum = maximum.max(unit.position)
	if center and minimum.is_finite():
		_camera.focus_on((minimum + maximum) * 0.5)
	_refresh_unit_selection()
	_refresh_control_group_bar()


func _refresh_control_group_bar() -> void:
	for index in _control_groups.size():
		var members := _control_groups[index]
		var button := _group_buttons[index]
		button.disabled = members.is_empty()
		button.text = "%d·%d" % [index + 1, members.size()] if not members.is_empty() else str(index + 1)
		button.set_pressed_no_signal(not members.is_empty() and _selected_units == members)


func _create_score_panel() -> void:
	_score_panel.name = "FactionScores"
	_score_panel.add_theme_stylebox_override("panel", _unit_panel.get_theme_stylebox("panel"))
	var contents := VBoxContainer.new()
	var toggle := Button.new()
	toggle.text = "Faction scores"
	toggle.toggle_mode = true
	toggle.toggled.connect(func(open: bool) -> void:
		_score_list.visible = open
		_score_panel.reset_size()
		_queue_hud_layout())
	contents.add_child(toggle)
	contents.add_child(_score_list)
	contents.add_child(_boon_status)
	_score_list.hide()
	_boon_status.hide()
	_score_panel.add_child(contents)
	$HUD.add_child(_score_panel)


func _refresh_score_panel() -> void:
	if _displayed_score_revision != _strength.revision:
		_displayed_score_revision = _strength.revision
		for child in _score_list.get_children():
			_score_list.remove_child(child)
			child.queue_free()
		var rank := 0
		for side in _strength.ranked():
			rank += 1
			var row := Label.new()
			row.modulate = MatchRegion.accent_color(side).lightened(0.25)
			row.text = "%d. %s   %d" % [rank, _side_label(side), roundi(_strength.scores[side])]
			row.add_theme_font_size_override("font_size", 14)
			_score_list.add_child(row)
		_score_panel.reset_size()
	var text := " · ".join(_battle.objectives.active_boons(PLAYER, _battle.elapsed_time()))
	if _boon_status.text != text:
		_boon_status.text = text
		_boon_status.visible = not text.is_empty()
		_score_panel.reset_size()


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


func _clear_region_selection() -> void:
	_select_region(&"")
	_refresh_hud()


func _clear_inspection() -> void:
	_select_unit(MatchBattle.NO_TARGET)
	_select_fortification(MatchBattle.NO_TARGET)
	_refresh_hud()


func _queue_hud_layout() -> void:
	var tree := get_tree()
	if not tree.process_frame.is_connected(_layout_hud):
		tree.process_frame.connect(_layout_hud, CONNECT_ONE_SHOT)


func _layout_hud() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var hud_width := viewport_size.x - 2.0 * HUD_MARGIN
	var top_contents := _top_bar.get_child(0) as Control
	var scout_controls := _top_bar.get_child(1) as Control
	_top_bar.vertical = top_contents.get_combined_minimum_size().x \
		+ scout_controls.get_combined_minimum_size().x + _top_bar.get_theme_constant("separation") > hud_width
	_top_bar.offset_bottom = _top_bar.offset_top + _top_bar.get_combined_minimum_size().y
	var actions := _economy_row.get_node(^"Actions") as Control
	var padding := _economy_panel.get_theme_stylebox("panel").get_minimum_size().x
	var single_row_width := _resource_readouts.get_combined_minimum_size().x \
		+ actions.get_combined_minimum_size().x + _economy_row.get_theme_constant("separation") + padding
	var bottom_width := minf(single_row_width, hud_width)
	_economy_row.vertical = bottom_width < single_row_width
	_economy_panel.size = Vector2(bottom_width, _economy_panel.get_combined_minimum_size().y)
	_economy_panel.position = Vector2((viewport_size.x - _economy_panel.size.x) * 0.5,
		viewport_size.y - HUD_MARGIN - _economy_panel.size.y)

	var top := _top_bar.get_rect().end.y + HUD_GAP
	_score_panel.position = Vector2(HUD_MARGIN, top)
	var bottom := _economy_panel.position.y - HUD_GAP
	var group_size := _group_bar.get_combined_minimum_size()
	_group_bar.size = group_size
	_group_bar.position = Vector2((viewport_size.x - group_size.x) * 0.5, bottom - group_size.y)
	_group_bar.visible = not _placement_panel.visible and group_size.x <= hud_width
	var dock_width := minf(HUD_DOCK_WIDTH, viewport_size.x - 2.0 * HUD_MARGIN)
	var dock_origin := Vector2(viewport_size.x - HUD_MARGIN - dock_width, top)
	var available := maxf(bottom - top, 0.0)
	_context_scroll.position = dock_origin
	_context_scroll.size = Vector2(dock_width, minf(available, _context_cards.get_combined_minimum_size().y))
	_build_menu.position = dock_origin
	_build_menu.size = Vector2(dock_width, minf(available,
		_build_menu.get_combined_minimum_size().y + _build_list.get_combined_minimum_size().y))
	_income_sources.position = dock_origin
	_income_sources.size = Vector2(dock_width, minf(available,
		_income_sources.get_combined_minimum_size().y + _income_source_text.get_combined_minimum_size().y))

	_placement_panel.size = Vector2(minf(520.0, bottom_width), _placement_panel.get_combined_minimum_size().y)
	_placement_panel.position = Vector2((viewport_size.x - _placement_panel.size.x) * 0.5,
		bottom - _placement_panel.size.y)


func _update_context_visibility() -> void:
	var show_context := (_region_panel.visible or _unit_panel.visible) \
		and not (_build_menu.visible or _income_sources.visible or _placement_panel.visible)
	if _context_scroll.visible != show_context:
		_context_scroll.visible = show_context
		_queue_hud_layout()


func _close_income_sources() -> void:
	if _income_sources.visible:
		var readout := _resource_readouts.get_node(NodePath(_selected_resource)) as Button
		_show_income_sources(&"")
		readout.grab_focus()


func _show_income_sources(resource_id: StringName) -> void:
	if not resource_id.is_empty():
		_cancel_placement()
	_selected_resource = resource_id
	_income_sources.visible = not resource_id.is_empty()
	_income_source_scroll.scroll_vertical = 0
	for readout: Button in _resource_readouts.get_children():
		readout.set_pressed_no_signal(readout.name == resource_id)
	if _income_sources.visible:
		_refresh_resource_readouts()
	_update_context_visibility()
	_queue_hud_layout()


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
			if _income_source_text.text != _income_details[resource_id]:
				_income_source_text.text = _income_details[resource_id]
				_queue_hud_layout()


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


func _refresh_cpu_status_controls() -> void:
	for side in _cpu_hp_labels:
		if side != CPU:
			var label := _cpu_hp_labels[side]
			label.get_parent().remove_child(label)
			label.queue_free()
	_cpu_hp_labels = {CPU: _cpu_hp_label}
	for i in range(1, cpu_opponent_count):
		var side := (CPU + i) as MatchRegion.Owner
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", MatchRegion.accent_color(side))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_cpu_hp_label.get_parent().add_child(label)
		_cpu_hp_labels[side] = label
	_active_difficulty.text = "CPU %s" % DifficultyProfile.display_name(cpu_difficulty)
	_active_difficulty.visible = cpu_opponent_count == 1
	_active_difficulty.tooltip_text = DifficultyProfile.get_profile(cpu_difficulty).description


func _refresh_hud() -> void:
	_player_hp_label.text = "Player base · %s HP" % _stat_number(_battle.base_hp(PLAYER))
	_player_hp_label.tooltip_text = _breakdown_text("Maximum HP", _battle.base_health_stat(PLAYER))
	for side in _cpu_hp_labels:
		var label := _cpu_hp_labels[side]
		var status := "%s HP" % _stat_number(_battle.base_hp(side))
		if cpu_opponent_count > 1 and not _battle.is_side_active(side):
			status = "Eliminated"
		label.text = "%s base · %s" % [_side_label(side), status]
		if _battle.is_side_active(side) and not _battle.can_see(PLAYER, _battle._bases[side]):
			label.text = "%s base · Known start" % _side_label(side)
			label.tooltip_text = ""
			continue
		var details := _breakdown_text("Maximum HP", _battle.base_health_stat(side))
		if cpu_opponent_count > 1:
			details = "%s\n%s" % [DifficultyProfile.display_name(_cpu_level(side - CPU)), details]
		label.tooltip_text = details
	_outcome_label.text = OUTCOME_LABELS[_battle.outcome()]
	_outcome_label.visible = _battle.is_finished()
	_update_missile_warning()
	_refresh_score_panel()
	_refresh_resource_readouts()
	_refresh_build_options()
	_build_button.disabled = _battle.is_finished()
	if not _selected_units.is_empty():
		_update_unit_selection()
	_update_fortification_inspection()
	_refresh_claim_control()
	_refresh_scout_roster()
	_refresh_claim_markers()


func _refresh_claim_control() -> void:
	var region := get_region(_selected_region_id)
	_region_panel.visible = region != null
	if region == null:
		_claim_button.disabled = true
		_update_context_visibility()
		return

	_claim_button.text = "Claim · %s" % MatchEconomy.cost_text(_expeditions.claim_price(PLAYER))
	if not region_live(PLAYER, region):
		_claim_button.hide()
		_region_claim_progress.hide()
		var memory: Dictionary = _intelligence[PLAYER].regions.get(region.region_id, {})
		_region_label.text = str(region.region_id).capitalize() + (" · Last seen" if not memory.is_empty() else " · Uncharted")
		_region_label.tooltip_text = ""
		_region_slots.text = ""
		_region_slots.tooltip_text = ""
		_region_status.text = "Scout this region to inspect it" if memory.is_empty() else region.specialty_text()
		if _inspected_radar != null and _battle.radar.contacts_for(PLAYER).has(_inspected_radar) \
				and not _battle.can_see(PLAYER, _inspected_radar.point):
			var names := PackedStringArray()
			for type in _inspected_radar.composition:
				names.append("%d %s" % [_inspected_radar.composition[type], UnitCatalog.DEFINITIONS[type].label])
			_region_status.text += "\nRadar · %s · %.0fs old" % [" / ".join(names),
				_battle.elapsed_time() - _inspected_radar.recorded_at]
		_region_status.show()
		var remembered := _landmarks.get(region.region_id) as LegendaryLandmark
		_landmark_details.visible = remembered != null and landmark_known(PLAYER, remembered)
		_landmark_details.tooltip_text = ""
		if _landmark_details.visible:
			_landmark_details.text = remembered.display_name + " · " + _legendary_effect(remembered.stat, remembered.magnitude)
		_update_context_visibility()
		return

	var reason := _expeditions.block_reason(PLAYER, _selected_region_id)
	var expedition := _expeditions.assignments.get(_selected_region_id) as ScoutExpeditions.Scout
	if expedition != null and expedition.side != PLAYER and not _battle.can_see(PLAYER, expedition.site):
		expedition = null
		if reason == "Expedition assigned":
			reason = "Site temporarily unavailable"
	_claim_button.visible = region.region_owner == MatchRegion.Owner.NEUTRAL and expedition == null \
		and not region.ruined and not _battle.is_finished()
	_claim_button.disabled = not reason.is_empty()
	_claim_button.tooltip_text = reason
	_update_claim_progress(_region_claim_progress, expedition)

	var occupancy := region_occupancy(_selected_region_id, PLAYER)
	_region_slots.text = "Slots %d/%d%s" % [occupancy.used, occupancy.capacity,
		" · Full" if occupancy.free == 0 else ""]
	_region_slots.tooltip_text = _slot_breakdown(occupancy)
	var owner := "Neutral" if region.region_owner == MatchRegion.Owner.NEUTRAL else _side_label(region.region_owner)
	_region_label.text = "%s · %s" % [str(_selected_region_id).capitalize(), owner]
	_region_label.tooltip_text = ""
	_region_status.text = reason if _claim_button.visible else ""
	if expedition != null:
		_region_status.text = _expedition_text(expedition)
	var outpost := _outposts_by_region.get(_selected_region_id) as MatchBattle.Outpost
	if outpost != null:
		_region_status.text = "Outpost · %s/%s HP" % [_stat_number(outpost.hp), _stat_number(outpost.max_hp)]
		_region_label.tooltip_text = _breakdown_text("Maximum HP", outpost.health_stat())
	if not region.specialty_text().is_empty():
		_region_status.text = "\n".join(PackedStringArray([_region_status.text, region.specialty_text()])).strip_edges()
	if region.ruined:
		_region_status.text = "Permanently ruined · Passable terrain"
	_region_status.visible = not _region_status.text.is_empty()

	var landmark := _landmarks.get(_selected_region_id) as LegendaryLandmark
	_landmark_details.visible = landmark != null and landmark.visible
	if _landmark_details.visible:
		var contribution := faction_stats.inspect_source(landmark.stat, landmark.source_id)
		var side := get_region(landmark.region_id).region_owner
		var active: bool = not contribution.breakdown.is_empty() and contribution.breakdown[0].active
		var controller := "Neutral" if side == MatchRegion.Owner.NEUTRAL else "%s-controlled" % _side_label(side)
		_landmark_details.text = "%s · %s\n%s" % [landmark.display_name,
			"Active" if active else "Inactive", _legendary_effect(landmark.stat, contribution.total) if active
			else "On claim · " + _legendary_effect(landmark.stat, landmark.magnitude)]
		var is_income := MatchEconomy.RESOURCES.has(landmark.stat)
		_landmark_details.tooltip_text = controller + "\n" + _breakdown_text(
			"Landmark contribution", contribution, "/s" if is_income else "", is_income)
	_update_context_visibility()


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
	_cancel_placement()
	_show_income_sources(&"")
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
		var state := _scout_state_text(scout)
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
	var region_has_progress := scout.assigned() and scout.region_id == _selected_region_id
	if region_has_progress:
		_unit_intent.text = "Expedition to " + str(scout.region_id).capitalize()
	elif scout.assigned():
		_unit_intent.text = _expedition_text(scout) + " · " + str(scout.region_id).capitalize()
	else:
		_unit_intent.text = _scout_state_text(scout)
	_recall_button.visible = scout.side == PLAYER and scout.assigned() and not _battle.is_finished()
	_unit_order_hint.visible = _selected_unit_can_receive_orders()
	_unit_order_hint.text = "Right-click ground to move"
	_update_claim_progress(_unit_claim_progress, null if region_has_progress else scout)
	if not unit.waypoints.is_empty() and (unit.side == PLAYER or _battle.visibility == null) \
			and (unit.target == MatchBattle.NO_TARGET or _target_label(unit) != "None"):
		_draw_unit_route(unit)


func _scout_state_text(scout: ScoutExpeditions.Scout) -> String:
	var unit := _battle.get_unit(scout.unit_id)
	if scout.state == ScoutExpeditions.State.AVAILABLE and unit != null and not unit.waypoints.is_empty():
		return "Moving"
	return ScoutExpeditions.State.keys()[scout.state].capitalize()


func _expedition_text(scout: ScoutExpeditions.Scout) -> String:
	return "◆ %s · %ds" % [_scout_state_text(scout),
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
		label.modulate = _faction_accent(scout.side).albedo_color.lightened(0.35)
		label.text = _expedition_text(scout)
		_update_claim_progress(marker.get_node("Readouts/Progress"), scout)
		var point := _world_position(scout.site) + Vector3.UP * 0.35
		var view := _unit_views.get(scout.unit_id) as MeshInstance3D
		marker.visible = view != null and not _camera.is_position_behind(point) \
			and (scout.side == PLAYER or (_battle.can_see(PLAYER, scout.site) \
				and _battle.can_observe_unit(PLAYER, _battle.get_unit(scout.unit_id))))
		if marker.visible:
			marker.position = _camera.unproject_position(point) - Vector2(marker.size.x * 0.5, marker.size.y)
			var scout_screen := _camera.unproject_position(view.global_position)
			if marker.get_rect().grow(16.0).has_point(scout_screen):
				marker.position.y = scout_screen.y + 16.0


func region_live(side: MatchRegion.Owner, region: MatchRegion) -> bool:
	return region.region_owner == side or _battle.can_see(side, Vector2(region.position.x, region.position.z))


func landmark_known(side: MatchRegion.Owner, landmark: LegendaryLandmark) -> bool:
	return _battle.visibility == null or _battle.can_see(side, landmark.footprint.get_center()) \
		or (_intelligence.has(side) and _intelligence[side].landmarks.get(landmark.region_id, false))


func _reset_intelligence() -> void:
	_intelligence.clear()
	_next_intel_observation = 0.0
	for child in _intel_root.get_children():
		_intel_root.remove_child(child)
		child.queue_free()
	_intel_markers.clear()
	_radar_contacts_view.clear()
	_fog_overlay.configure(_battle.visibility, PLAYER, _layout.boundary)
	for side in _bases:
		var intel := FactionIntelligence.new()
		intel.starts.assign(_battle._bases)
		_intelligence[side] = intel
	_refresh_intelligence()


func _refresh_intelligence() -> void:
	if _battle.visibility == null:
		return
	_fog_overlay.refresh()
	_observe_intelligence()
	var intel := _intelligence[PLAYER]
	var desired: Dictionary[StringName, Dictionary] = {}
	for side in _bases:
		if _battle.is_side_active(side) and side != PLAYER and not _battle.can_see(PLAYER, _battle._bases[side]):
			desired[_base_structure_id(side)] = {"point": intel.starts[side], "label": _side_label(side) + " start"}
		_bases[side].visible = _battle.is_side_active(side) and (side == PLAYER or _battle.can_see(PLAYER, _battle._bases[side]))
	for placed in _fortifications.values():
		var fort: MatchBattle.Fortification = placed.defense
		placed.view.visible = fort.side == PLAYER or _battle.can_see(PLAYER, fort.position) \
			or _battle._charging_silos.has(fort.id)
	for id in _outposts_by_region:
		var outpost := _outposts_by_region[id]
		_outpost_views[id].visible = outpost.side == PLAYER or _battle.can_see(PLAYER, outpost.position)
	for id in _landmarks:
		var landmark := _landmarks[id]
		var location := landmark.footprint.get_center()
		landmark.visible = _battle.can_see(PLAYER, location) and _battle._landmark_footprints.has(landmark.footprint)
		if not _battle.can_see(PLAYER, location) and intel.landmarks.get(id, false):
			desired[landmark.source_id] = {"point": location, "label": landmark.display_name + " · Last seen"}
	for ruin: Node3D in _ruins.get_children():
		ruin.visible = _battle.can_see(PLAYER, _map_position(ruin.global_position))
	for region in _regions_by_id.values():
		var memory: Dictionary = intel.regions.get(region.region_id, {})
		region.display_ownership(memory.get("side", MatchRegion.Owner.NEUTRAL), memory.get("ruined", false), not memory.is_empty())
	for id in intel.structures:
		var contact := intel.structures[id]
		if not _battle.can_see(PLAYER, contact.point):
			desired[id] = {"point": contact.point, "label": contact.label + " · Last seen"}
	var launches := _battle.public_missile_launches()
	for id in launches:
		var launch := launches[id]
		var remaining: float = launch.launches_at - _battle.elapsed_time()
		desired[StringName("launch/%d" % id)] = {"point": launch.point,
			"label": "MISSILE · %.0fs" % ceilf(remaining),
			"color": Color("#ff715b") if fmod(_battle.elapsed_time(), 0.7) < 0.45 else Color("#ffd4a5")}
	for camp in _battle.objectives.camps:
		if not camp.observed.has(PLAYER):
			continue
		var id := StringName("camp/%d" % camp.id)
		var visible_now := _battle.can_see(PLAYER, camp.point)
		var label := "Stronghold" if camp.major else "Jungle Camp"
		if visible_now and camp.drop_until > _battle.elapsed_time():
			label = "Collect siege boon" if camp.major else "Collect camp boon"
		elif not visible_now:
			label += " · Last seen"
		elif camp.guard_id == MatchBattle.NO_TARGET:
			label += " · Respawning"
		desired[id] = {"point": camp.point, "label": label, "color": Color("#e7bb72")}
	_radar_contacts_view.refresh(_battle, PLAYER)
	var inspected := selected_unit()
	if inspected != null and not _battle.can_observe_unit(PLAYER, inspected):
		_select_unit(MatchBattle.NO_TARGET)
	_refresh_intel_markers(desired)


func _observe_intelligence() -> void:
	if _battle.visibility == null or _intelligence.is_empty():
		return
	var now := _battle.elapsed_time()
	if now + MatchBattle.TIME_EPSILON < _next_intel_observation:
		return
	_next_intel_observation = now + fog_update_interval
	_record_sightings(now)


func _record_sightings(now: float) -> void:
	for side in _intelligence:
		var intel := _intelligence[side]
		for id in intel.structures.keys():
			if _battle.can_see(side, intel.structures[id].point):
				intel.structures.erase(id)
		for placed in _fortifications.values():
			var fort: MatchBattle.Fortification = placed.defense
			if fort.side != side and _battle.can_see(side, fort.position):
				intel.remember_structure(fort.source_id, fort.side, fort.position, fort.profile.label, now)
		for outpost in _outposts_by_region.values():
			if outpost.side != side and _battle.can_see(side, outpost.position):
				intel.remember_structure(outpost.source_id, outpost.side, outpost.position, "Outpost", now)
		for region in _regions_by_id.values():
			if region_live(side, region):
				intel.regions[region.region_id] = {"side": region.region_owner, "ruined": region.ruined}
		for landmark in _landmarks.values():
			if _battle.can_see(side, landmark.footprint.get_center()):
				intel.landmarks[landmark.region_id] = _battle._landmark_footprints.has(landmark.footprint)


func _refresh_intel_markers(desired: Dictionary[StringName, Dictionary]) -> void:
	for id in _intel_markers.keys():
		if not desired.has(id):
			_intel_markers[id].queue_free()
			_intel_markers.erase(id)
	for id in desired:
		var marker := _intel_markers.get(id) as Label3D
		if marker == null:
			marker = Label3D.new()
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.no_depth_test = true
			marker.font_size = 22
			marker.pixel_size = 0.016
			marker.modulate = Color("#b3c6d3")
			_intel_root.add_child(marker)
			_intel_markers[id] = marker
		marker.modulate = desired[id].get("color", Color("#b3c6d3"))
		marker.text = desired[id].label
		marker.global_position = _world_position(desired[id].point) + Vector3.UP * 0.6



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
