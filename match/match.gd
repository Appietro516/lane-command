extends Node3D

const BARRACKS := preload("res://match/barracks.tscn")
const UNIT := preload("res://match/unit.tscn")
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
var _battle: MatchBattle
var _regions_by_id: Dictionary[StringName, MatchRegion] = {}
var _initial_owners: Dictionary[StringName, MatchRegion.Owner] = {}
var _selected_region_id: StringName = &""
var _pending_pick := Vector2.INF
var _unit_views: Dictionary[int, MeshInstance3D] = {}
var _corridor_start: Vector3
var _corridor_direction: Vector3
var _time_until_cpu_decision: float

@onready var _slots := {
	PLAYER: $Regions/PlayerStart/BarracksSlots.get_children(),
	CPU: $Regions/CPUStart/BarracksSlots.get_children(),
}
@onready var _bases: Dictionary[MatchRegion.Owner, Node3D] = {
	PLAYER: $Regions/PlayerStart/PlayerBase,
	CPU: $Regions/CPUStart/CPUBase,
}
@onready var _units: Node3D = $Units
@onready var _energy_label: Label = %Energy
@onready var _income_label: Label = %Income
@onready var _barracks_label: Label = %BarracksCount
@onready var _build_button: Button = %Build
@onready var _upgrade_button: Button = %Upgrade
@onready var _claim_button: Button = %Claim
@onready var _region_label: Label = %SelectedRegion
@onready var _camera: Camera3D = $Camera
@onready var _player_hp_label: Label = %PlayerHP
@onready var _cpu_hp_label: Label = %CPUHP
@onready var _outcome_label: Label = %Outcome
@onready var _restart_button: Button = %Restart


func _ready() -> void:
	for region: MatchRegion in $Regions.get_children():
		_regions_by_id[region.region_id] = region
		_initial_owners[region.region_id] = region.region_owner
	for side in _bases:
		_bases[side].get_node("Core").material_override = FACTION_ACCENTS[side]
	_income_label.text = "Income +%d/s" % MatchEconomy.INCOME_PER_SECOND
	_build_button.text = "Build · %d" % MatchEconomy.BARRACKS_COST
	_build_button.pressed.connect(func() -> void: try_build(PLAYER))
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_claim_button.text = "Claim · %d" % MatchEconomy.CLAIM_COST
	_claim_button.pressed.connect(func() -> void: try_claim(PLAYER, _selected_region_id))
	_restart_button.pressed.connect(restart_match)
	restart_match()


func restart_match() -> void:
	if _battle != null:
		_battle.unit_produced.disconnect(_spawn_unit)
		_battle.unit_removed.disconnect(_remove_unit)
		_battle.base_destroyed.disconnect(_hide_base)
	for unit_id in _unit_views.keys():
		_remove_unit(unit_id)
	for side in _slots:
		for slot: Marker3D in _slots[side]:
			for building in slot.get_children():
				slot.remove_child(building)
				building.queue_free()
		_bases[side].show()
	for region_id in _initial_owners:
		_regions_by_id[region_id].region_owner = _initial_owners[region_id]
	_select_region(&"")
	_pending_pick = Vector2.INF

	economy = MatchEconomy.new()
	_time_until_cpu_decision = CPU_DECISION_INTERVAL
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
		set_process(false)

	for unit in _battle.active_units():
		_unit_views[unit.id].position = _corridor_start + _corridor_direction * unit.position
	_refresh_hud()


func try_build(side: MatchRegion.Owner) -> bool:
	if _battle.is_finished() or not economy.try_build(side):
		return false

	var slot_index := economy.barracks_count(side) - 1
	var slot: Marker3D = _slots[side][slot_index]
	var barracks := BARRACKS.instantiate()
	barracks.get_node("RoofMarking").material_override = FACTION_ACCENTS[side]
	slot.add_child(barracks)
	_battle.add_barracks(side, slot_index)
	_refresh_hud()
	return true


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
	var region: MatchRegion = _regions_by_id.get(region_id)
	return region != null and region.region_owner == side



func _claim_block_reason(region_id: StringName) -> String:
	var region: MatchRegion = _regions_by_id.get(region_id)
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pending_pick = event.position
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _pending_pick == Vector2.INF:
		return
	var origin := _camera.project_ray_origin(_pending_pick)
	var end := origin + _camera.project_ray_normal(_pending_pick) * _camera.far
	_pending_pick = Vector2.INF
	var query := PhysicsRayQueryParameters3D.create(origin, end, MatchRegion.PICK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var region: MatchRegion = null
	if not hit.is_empty():
		region = hit.collider.get_parent() as MatchRegion
	_select_region(region.region_id if region != null else &"")
	_refresh_claim_control()


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
		try_build(CPU)
	elif not economy.has_upgrade(CPU):
		try_upgrade(CPU)


func _spawn_unit(unit: MatchBattle.Unit, _slot_index: int) -> void:
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
	_build_button.disabled = _battle.is_finished() or not economy.can_build(PLAYER)
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
