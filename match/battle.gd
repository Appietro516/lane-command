class_name MatchBattle
extends RefCounted

signal unit_produced(side: MatchRegion.Owner, slot_index: int)


class ProductionTimer:
	var side: MatchRegion.Owner
	var slot_index: int
	var elapsed := 0.0

	func _init(owner: MatchRegion.Owner, index: int) -> void:
		side = owner
		slot_index = index


var _timers: Array[ProductionTimer] = []


func add_barracks(side: MatchRegion.Owner, slot_index: int) -> void:
	_timers.append(ProductionTimer.new(side, slot_index))


func advance(delta: float, economy: MatchEconomy) -> void:
	for timer in _timers:
		# Upgrades shorten the current cycle while keeping elapsed production time.
		var interval := economy.production_interval(timer.side)
		timer.elapsed += delta
		while timer.elapsed >= interval:
			timer.elapsed -= interval
			unit_produced.emit(timer.side, timer.slot_index)
