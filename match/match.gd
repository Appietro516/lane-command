extends Node3D

const BARRACKS := preload("res://match/barracks.tscn")
const UNIT := preload("res://match/unit.tscn")
const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const CPU_DECISION_INTERVAL := 2.0

const UNIT_MATERIALS := {
	PLAYER: preload("res://match/player_unit_material.tres"),
	CPU: preload("res://match/cpu_unit_material.tres"),
}

var economy := MatchEconomy.new()
var _battle: MatchBattle
var _unit_views: Dictionary[int, MeshInstance3D] = {}
var _corridor_start: Vector3
var _corridor_direction: Vector3
var _time_until_cpu_decision := CPU_DECISION_INTERVAL

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


func _ready() -> void:
	_corridor_start = _units.to_local(_bases[PLAYER].global_position)
	var corridor := _units.to_local(_bases[CPU].global_position) - _corridor_start
	_corridor_direction = corridor.normalized()
	_battle = MatchBattle.new(corridor.length())
	_battle.unit_produced.connect(_spawn_unit)
	_battle.unit_removed.connect(_remove_unit)
	_battle.base_destroyed.connect(_hide_base)
	_income_label.text = "Income +%d/s" % MatchEconomy.INCOME_PER_SECOND
	_build_button.text = "Build · %d" % MatchEconomy.BARRACKS_COST
	_build_button.pressed.connect(func() -> void: try_build(PLAYER))
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_refresh_hud()


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
	slot.add_child(BARRACKS.instantiate())
	_battle.add_barracks(side, slot_index)
	_refresh_hud()
	return true


func try_upgrade(side: MatchRegion.Owner) -> bool:
	if _battle.is_finished() or not economy.try_upgrade(side):
		return false

	_refresh_hud()
	return true


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
	view.material_override = UNIT_MATERIALS[unit.side]
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
	_energy_label.text = "Energy %d" % floori(economy.energy(PLAYER))
	_barracks_label.text = "Barracks %d/%d" % [
		economy.barracks_count(PLAYER), MatchEconomy.BARRACKS_CAPACITY,
	]
	_build_button.disabled = _battle.is_finished() or not economy.can_build(PLAYER)
	_upgrade_button.disabled = _battle.is_finished() or not economy.can_upgrade(PLAYER)
	_upgrade_button.text = (
		"Upgraded" if economy.has_upgrade(PLAYER) else "Upgrade · %d" % MatchEconomy.UPGRADE_COST
	)
