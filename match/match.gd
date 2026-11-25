extends Node3D

const BARRACKS := preload("res://match/barracks.tscn")
const PLAYER := MatchRegion.Owner.PLAYER

var economy := MatchEconomy.new()

@onready var _slots := {
	MatchRegion.Owner.PLAYER: $Regions/PlayerStart/BarracksSlots.get_children(),
	MatchRegion.Owner.CPU: $Regions/CPUStart/BarracksSlots.get_children(),
}
@onready var _energy_label: Label = %Energy
@onready var _income_label: Label = %Income
@onready var _barracks_label: Label = %BarracksCount
@onready var _build_button: Button = %Build
@onready var _upgrade_button: Button = %Upgrade


func _ready() -> void:
	_income_label.text = "Income +%d/s" % MatchEconomy.INCOME_PER_SECOND
	_build_button.text = "Build · %d" % MatchEconomy.BARRACKS_COST
	_build_button.pressed.connect(func() -> void: try_build(PLAYER))
	_upgrade_button.pressed.connect(func() -> void: try_upgrade(PLAYER))
	_refresh_hud()


func _process(delta: float) -> void:
	economy.advance(delta)
	_refresh_hud()


func try_build(side: MatchRegion.Owner) -> bool:
	if not economy.try_build(side):
		return false

	var slot: Marker3D = _slots[side][economy.barracks_count(side) - 1]
	slot.add_child(BARRACKS.instantiate())
	_refresh_hud()
	return true


func try_upgrade(side: MatchRegion.Owner) -> bool:
	if not economy.try_upgrade(side):
		return false

	_refresh_hud()
	return true


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
