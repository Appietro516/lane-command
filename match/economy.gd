class_name MatchEconomy
extends RefCounted

const STARTING_ENERGY := 50.0
const INCOME_PER_SECOND := 3.0
const BARRACKS_COST := 40
const BARRACKS_CAPACITY := 2
const UPGRADE_COST := 60
const CLAIM_COST := 50
const PRODUCTION_INTERVAL := 3.5
const UPGRADED_PRODUCTION_INTERVAL := 2.5

class SideState:
	var energy := STARTING_ENERGY
	var barracks_count := 0
	var production_interval := PRODUCTION_INTERVAL


var _sides: Dictionary[MatchRegion.Owner, SideState] = {
	MatchRegion.Owner.PLAYER: SideState.new(),
	MatchRegion.Owner.CPU: SideState.new(),
}


func advance(delta: float) -> void:
	for state in _sides.values():
		state.energy += INCOME_PER_SECOND * maxf(delta, 0.0)


func energy(side: MatchRegion.Owner) -> float:
	return _sides[side].energy


func barracks_count(side: MatchRegion.Owner) -> int:
	return _sides[side].barracks_count


func production_interval(side: MatchRegion.Owner) -> float:
	return _sides[side].production_interval


func has_upgrade(side: MatchRegion.Owner) -> bool:
	return production_interval(side) == UPGRADED_PRODUCTION_INTERVAL


func can_build(side: MatchRegion.Owner) -> bool:
	return (_sides.has(side) and barracks_count(side) < BARRACKS_CAPACITY
		and energy(side) >= BARRACKS_COST)


func can_upgrade(side: MatchRegion.Owner) -> bool:
	return _sides.has(side) and not has_upgrade(side) and energy(side) >= UPGRADE_COST


func try_build(side: MatchRegion.Owner) -> bool:
	if not can_build(side):
		return false

	var state := _sides[side]
	state.energy -= BARRACKS_COST
	state.barracks_count += 1
	return true


func try_upgrade(side: MatchRegion.Owner) -> bool:
	if not can_upgrade(side):
		return false

	var state := _sides[side]
	state.energy -= UPGRADE_COST
	state.production_interval = UPGRADED_PRODUCTION_INTERVAL
	return true



func try_spend_energy(side: MatchRegion.Owner, cost: int) -> bool:
	if not _sides.has(side) or cost < 0 or energy(side) < cost:
		return false

	_sides[side].energy -= cost
	return true
