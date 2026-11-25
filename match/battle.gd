class_name MatchBattle
extends RefCounted

signal unit_produced(unit: Unit)
signal unit_removed(unit_id: int)
signal base_destroyed(side: MatchRegion.Owner)

enum Outcome { IN_PROGRESS, VICTORY, DEFEAT }

const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const UNIT_HP := 12
const BASE_HP := 80
const ATTACK_DAMAGE := 3
const ATTACK_COOLDOWN := 1.0
const MOVEMENT_SPEED := 2.4
const UNIT_ATTACK_RANGE := 0.9
const BASE_ATTACK_RANGE := 1.8
const DEPLOYMENT_DISTANCE := 1.75
const STEP := 1.0 / 60.0
const TIME_EPSILON := 1e-9
const NO_TARGET := 0
const BASE_TARGET := -1


class Unit:
	var id: int
	var side: MatchRegion.Owner
	var position: float
	var hp := UNIT_HP
	var target := NO_TARGET
	var cooldown := 0.0

	func _init(unit_id: int, owner: MatchRegion.Owner, spawn_position: float) -> void:
		id = unit_id
		side = owner
		position = spawn_position


class ProductionTimer:
	var side: MatchRegion.Owner
	var elapsed := 0.0

	func _init(owner: MatchRegion.Owner) -> void:
		side = owner


var _corridor_length: float
var _base_hp: Dictionary[MatchRegion.Owner, int] = {PLAYER: BASE_HP, CPU: BASE_HP}
var _timers: Array[ProductionTimer] = []
var _units: Dictionary[int, Unit] = {}
var _next_unit_id := 1
var _pending_time := 0.0
var _elapsed_time := 0.0
var _outcome := Outcome.IN_PROGRESS


func _init(corridor_length: float) -> void:
	_corridor_length = corridor_length


func add_barracks(side: MatchRegion.Owner) -> void:
	_timers.append(ProductionTimer.new(side))


func active_units() -> Array[Unit]:
	return _units.values()


func base_hp(side: MatchRegion.Owner) -> int:
	return _base_hp[side]


func is_finished() -> bool:
	return _outcome != Outcome.IN_PROGRESS


func outcome() -> Outcome:
	return _outcome


func elapsed_time() -> float:
	return _elapsed_time


func advance(delta: float, economy: MatchEconomy) -> void:
	if delta < 0.0 or is_finished():
		return

	# An upgrade can make an existing timer due immediately.
	_advance_production(0.0, economy)
	_pending_time += delta
	while _pending_time + TIME_EPSILON >= STEP and not is_finished():
		_pending_time = maxf(0.0, _pending_time - STEP)
		_elapsed_time += STEP
		_step_combat()
		if not is_finished():
			_advance_production(STEP, economy)


func _advance_production(delta: float, economy: MatchEconomy) -> void:
	for timer in _timers:
		# Upgrades shorten the current cycle while keeping elapsed production time.
		var interval := economy.production_interval(timer.side)
		timer.elapsed += delta
		while timer.elapsed + TIME_EPSILON >= interval:
			timer.elapsed = maxf(0.0, timer.elapsed - interval)
			var spawn_position := DEPLOYMENT_DISTANCE if timer.side == PLAYER else (
				_corridor_length - DEPLOYMENT_DISTANCE
			)
			var unit := Unit.new(_next_unit_id, timer.side, spawn_position)
			_units[unit.id] = unit
			_next_unit_id += 1
			unit_produced.emit(unit)


func _step_combat() -> void:
	# Choose targets before any movement or damage so both sides see the same state.
	var units := active_units()
	for unit in units:
		unit.target = _choose_target(unit, units)

	for unit in units:
		unit.cooldown = maxf(0.0, unit.cooldown - STEP)
		var opposing_side := CPU if unit.side == PLAYER else PLAYER
		if unit.target == NO_TARGET:
			unit.position = move_toward(unit.position, _base_attack_position(unit.side),
				MOVEMENT_SPEED * STEP)
		elif unit.cooldown <= TIME_EPSILON:
			# Every unit alive at the start of the step gets to resolve its attack.
			if unit.target == BASE_TARGET:
				_base_hp[opposing_side] = maxi(0, base_hp(opposing_side) - ATTACK_DAMAGE)
			else:
				_units[unit.target].hp -= ATTACK_DAMAGE
			unit.cooldown = ATTACK_COOLDOWN

	for unit in units:
		if unit.hp <= 0:
			_units.erase(unit.id)
			unit_removed.emit(unit.id)

	for unit in _units.values():
		if unit.target > NO_TARGET and not _units.has(unit.target):
			unit.target = NO_TARGET

	if base_hp(PLAYER) == 0:
		_outcome = Outcome.DEFEAT
	elif base_hp(CPU) == 0:
		_outcome = Outcome.VICTORY

	if base_hp(PLAYER) == 0:
		base_destroyed.emit(PLAYER)
	if base_hp(CPU) == 0:
		base_destroyed.emit(CPU)


func _choose_target(unit: Unit, units: Array[Unit]) -> int:
	var nearest := NO_TARGET
	var nearest_distance := UNIT_ATTACK_RANGE
	for opponent in units:
		if opponent.side == unit.side:
			continue
		var distance := absf(opponent.position - unit.position)
		if distance <= UNIT_ATTACK_RANGE and (nearest == NO_TARGET or distance < nearest_distance):
			nearest = opponent.id
			nearest_distance = distance
	if nearest != NO_TARGET:
		return nearest

	var distance_to_base := _corridor_length - unit.position if unit.side == PLAYER else unit.position
	return BASE_TARGET if distance_to_base <= BASE_ATTACK_RANGE + TIME_EPSILON else NO_TARGET


func _base_attack_position(side: MatchRegion.Owner) -> float:
	return _corridor_length - BASE_ATTACK_RANGE if side == PLAYER else BASE_ATTACK_RANGE
