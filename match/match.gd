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
var _battle := MatchBattle.new()
var _time_until_cpu_decision := CPU_DECISION_INTERVAL

@onready var _slots := {
	PLAYER: $Regions/PlayerStart/BarracksSlots.get_children(),
	CPU: $Regions/CPUStart/BarracksSlots.get_children(),
}
@onready var _units: Node3D = $Units
@onready var _energy_label: Label = %Energy
@onready var _income_label: Label = %Income
@onready var _barracks_label: Label = %BarracksCount
@onready var _build_button: Button = %Build
@onready var _upgrade_button: Button = %Upgrade


func _ready() -> void:
	_battle.unit_produced.connect(_spawn_unit)
	_income_label.text = "Income +%d/s" % MatchEconomy.INCOME_PER_SECOND
	_build_button.text = "Build · %d" % MatchEconomy.BARRACKS_COST
	_build_button.pressed.connect(func() -> void: try_build(PLAYER))
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_refresh_hud()


func _process(delta: float) -> void:
	# Apply income and production up to each decision before making its purchase.
	while delta >= _time_until_cpu_decision:
		_advance_simulation(_time_until_cpu_decision)
		delta -= _time_until_cpu_decision
		_time_until_cpu_decision = CPU_DECISION_INTERVAL
		_try_cpu_purchase()

	_advance_simulation(delta)
	_time_until_cpu_decision -= delta
	_refresh_hud()


func try_build(side: MatchRegion.Owner) -> bool:
	if not economy.try_build(side):
		return false

	var slot_index := economy.barracks_count(side) - 1
	var slot: Marker3D = _slots[side][slot_index]
	slot.add_child(BARRACKS.instantiate())
	_battle.add_barracks(side, slot_index)
	_refresh_hud()
	return true


func try_upgrade(side: MatchRegion.Owner) -> bool:
	if not economy.try_upgrade(side):
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


func _spawn_unit(side: MatchRegion.Owner, slot_index: int) -> void:
	var slot: Marker3D = _slots[side][slot_index]
	var offset := Vector3(1.75 if side == PLAYER else -1.75, 0.0, 0.0)
	var unit := UNIT.instantiate() as MeshInstance3D
	unit.material_override = UNIT_MATERIALS[side]
	unit.position = _units.to_local(slot.to_global(offset))
	_units.add_child(unit)


func _refresh_hud() -> void:
	_energy_label.text = "Energy %d" % floori(economy.energy(PLAYER))
	_barracks_label.text = "Barracks %d/%d" % [
		economy.barracks_count(PLAYER), MatchEconomy.BARRACKS_CAPACITY,
	]
	_build_button.disabled = not economy.can_build(PLAYER)
	_upgrade_button.disabled = not economy.can_upgrade(PLAYER)
	_upgrade_button.text = (
		"Upgraded" if economy.has_upgrade(PLAYER) else "Upgrade · %d" % MatchEconomy.UPGRADE_COST
	)
