class_name MatchBattle
extends RefCounted

signal unit_produced(unit: Unit)
signal unit_removed(unit_id: int)
signal base_destroyed(side: MatchRegion.Owner)

enum Outcome { IN_PROGRESS, VICTORY, DEFEAT }
enum Order { AUTONOMOUS, MOVE, HOLD }
enum TargetPriority { NEAREST, LOWEST_HP }

const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const UNIT_HP := 12
const BASE_HP := 80
const ATTACK_DAMAGE := 3
const ATTACK_COOLDOWN := 1.0
const MOVEMENT_SPEED := 2.4
const UNIT_ATTACK_RANGE := 0.9
const BASE_ATTACK_RANGE := 1.8
const DEFAULT_AGGRO_RADIUS := 4.0
const BASE_FOOTPRINT := Vector2(1.5, 1.5)
const BARRACKS_FOOTPRINT := Vector2(1.41, 0.91)
const STRATEGIC_SAMPLE_COUNT := 16
const STEP := 1.0 / 60.0
const TIME_EPSILON := 1e-9
const NO_TARGET := 0
const BASE_TARGET := -1


class Unit:
	var id: int
	var side: MatchRegion.Owner
	var position: Vector2
	var heading := Vector2.RIGHT
	var order := Order.AUTONOMOUS
	var ordered_destination := Vector2.INF
	var movement_destination := Vector2.INF
	var waypoints := PackedVector2Array()
	var route_revision := -1
	var strategic_destination := Vector2.INF
	var strategic_revision := -1
	var hp := UNIT_HP
	var target := NO_TARGET
	var cooldown := 0.0

	func _init(unit_id: int, owner: MatchRegion.Owner, spawn_position: Vector2) -> void:
		id = unit_id
		side = owner
		position = spawn_position


class ProductionTimer:
	var side: MatchRegion.Owner
	var position: Vector2
	var elapsed := 0.0

	func _init(owner: MatchRegion.Owner, building_position: Vector2) -> void:
		side = owner
		position = building_position


var aggro_radius: float
var target_priority := TargetPriority.NEAREST
var navigation: BattleNavigation
var _bases: Dictionary[MatchRegion.Owner, Vector2]
var _base_obstacles: Dictionary[MatchRegion.Owner, int] = {}
var _base_hp: Dictionary[MatchRegion.Owner, int] = {PLAYER: BASE_HP, CPU: BASE_HP}
var _timers: Array[ProductionTimer] = []
var _units: Dictionary[int, Unit] = {}
var _next_unit_id := 1
var _pending_time := 0.0
var _elapsed_time := 0.0
var _outcome := Outcome.IN_PROGRESS


func _init(player_base: Vector2, cpu_base: Vector2, detection_radius := DEFAULT_AGGRO_RADIUS,
		bounds := TerritoryLayout.BOUNDS) -> void:
	aggro_radius = detection_radius
	navigation = BattleNavigation.new(bounds)
	_bases = {PLAYER: player_base, CPU: cpu_base}
	for side in _bases:
		_base_obstacles[side] = _add_footprint(_bases[side], BASE_FOOTPRINT)


func add_barracks(side: MatchRegion.Owner, position: Vector2) -> void:
	_add_footprint(position, BARRACKS_FOOTPRINT)
	_timers.append(ProductionTimer.new(side, position))


func get_unit(id: int) -> Unit:
	return _units.get(id)


func issue_move(id: int, destination: Vector2) -> bool:
	var unit := get_unit(id)
	if is_finished() or unit == null or unit.side != PLAYER:
		return false
	var route := navigation.path(unit.position, destination)
	if route.is_empty():
		return false
	unit.order = Order.MOVE
	unit.ordered_destination = destination
	unit.target = NO_TARGET
	_set_route(unit, destination, route)
	return true


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
			var direction := timer.position.direction_to(_bases[_opponent(timer.side)])
			var unit := Unit.new(_next_unit_id, timer.side, _spawn_position(timer.position, direction))
			unit.heading = unit.position.direction_to(_bases[_opponent(timer.side)])
			_units[unit.id] = unit
			_next_unit_id += 1
			unit_produced.emit(unit)


func _spawn_position(building: Vector2, direction: Vector2) -> Vector2:
	var exits := [direction, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var closest := building
	var best_alignment := -INF
	for exit: Vector2 in exits:
		if exit.is_zero_approx():
			continue
		var extent := BARRACKS_FOOTPRINT + Vector2.ONE * 0.08
		var distance := 1.0 / maxf(absf(exit.x) / extent.x, absf(exit.y) / extent.y)
		var candidate := building + exit * distance
		if navigation.is_passable(candidate) and exit.dot(direction) > best_alignment:
			closest = candidate
			best_alignment = exit.dot(direction)
	return closest


func _step_combat() -> void:
	# Plan against the same positions before either side moves or takes damage.
	var units := active_units()
	var attacks: Array[Unit] = []
	for unit in units:
		unit.cooldown = maxf(0.0, unit.cooldown - STEP)
		if _plan_turn(unit, units) and unit.cooldown <= TIME_EPSILON:
			attacks.append(unit)

	for unit in units:
		_move(unit)

	# A unit killed this step still resolves the attack it planned.
	for unit in attacks:
		if unit.target == BASE_TARGET:
			var side := _opponent(unit.side)
			_base_hp[side] = maxi(0, base_hp(side) - ATTACK_DAMAGE)
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
			_clear_route(unit)

	if base_hp(PLAYER) == 0:
		_outcome = Outcome.DEFEAT
	elif base_hp(CPU) == 0:
		_outcome = Outcome.VICTORY

	if base_hp(PLAYER) == 0:
		base_destroyed.emit(PLAYER)
	if base_hp(CPU) == 0:
		base_destroyed.emit(CPU)


func _plan_turn(unit: Unit, units: Array[Unit]) -> bool:
	unit.target = NO_TARGET
	if _plan_local_engagement(unit, units):
		return unit.waypoints.is_empty()

	var side := _opponent(unit.side)
	var base := _bases[side]
	var at_hold_point := unit.order == Order.HOLD and unit.position == unit.ordered_destination
	if (unit.order == Order.AUTONOMOUS or at_hold_point) and _can_attack_base(unit.position, side):
		unit.target = BASE_TARGET
		unit.heading = unit.position.direction_to(base)
		_clear_route(unit)
		return true

	if unit.order == Order.AUTONOMOUS:
		unit.target = BASE_TARGET
		if unit.strategic_revision != navigation.revision:
			unit.strategic_destination = _find_base_approach(unit.position, side)
			unit.strategic_revision = navigation.revision
		_route_to(unit, unit.strategic_destination)
	else:
		_route_to(unit, unit.ordered_destination)
	return false


func _plan_local_engagement(unit: Unit, units: Array[Unit]) -> bool:
	var nearest: Unit
	var nearest_distance := INF
	var best_priority := INF
	var detection_squared := aggro_radius * aggro_radius
	var best_route := PackedVector2Array()
	for opponent in units:
		if opponent.side == unit.side:
			continue
		var distance := unit.position.distance_squared_to(opponent.position)
		var priority := opponent.hp if target_priority == TargetPriority.LOWEST_HP else 0
		if distance > detection_squared or priority > best_priority \
				or (priority == best_priority and distance >= nearest_distance):
			continue
		if unit.order == Order.HOLD \
				and opponent.position.distance_squared_to(unit.ordered_destination) > detection_squared:
			continue
		var route := PackedVector2Array()
		if distance > UNIT_ATTACK_RANGE * UNIT_ATTACK_RANGE \
				or not navigation.line_clear(unit.position, opponent.position):
			route = navigation.path(unit.position, opponent.position)
			if route.is_empty() or not _within_hold_area(unit, route):
				continue
		nearest = opponent
		best_priority = priority
		nearest_distance = distance
		best_route = route
	if nearest == null:
		return false
	unit.target = nearest.id
	if best_route.is_empty():
		unit.heading = unit.position.direction_to(nearest.position)
		_clear_route(unit)
	else:
		_set_route(unit, nearest.position, best_route)
	return true


func _within_hold_area(unit: Unit, route: PackedVector2Array) -> bool:
	if unit.order == Order.HOLD:
		for point in route:
			if point.distance_squared_to(unit.ordered_destination) > aggro_radius * aggro_radius:
				return false
	return true


func _can_attack_base(position: Vector2, side: MatchRegion.Owner) -> bool:
	return position.distance_squared_to(_bases[side]) <= pow(BASE_ATTACK_RANGE + 0.00001, 2) \
		and navigation.is_passable(position) \
		and navigation.line_clear(position, _bases[side], _base_obstacles[side])


func _find_base_approach(position: Vector2, side: MatchRegion.Owner) -> Vector2:
	var base := _bases[side]
	var outward := base.direction_to(position)
	if outward.is_zero_approx():
		outward = Vector2.RIGHT
	var best := Vector2.INF
	var best_length := INF
	for i in range(STRATEGIC_SAMPLE_COUNT):
		var candidate := base + outward.rotated(TAU * i / STRATEGIC_SAMPLE_COUNT) * BASE_ATTACK_RANGE
		if not _can_attack_base(candidate, side):
			continue
		var route := navigation.path(position, candidate)
		if route.is_empty():
			continue
		# The direct radial approach is the shortest possible route.
		if i == 0 and route.size() == 1:
			return candidate
		var length := 0.0
		var previous := position
		for point in route:
			length += previous.distance_to(point)
			previous = point
		if length < best_length:
			best = candidate
			best_length = length
	return best


func _route_to(unit: Unit, destination: Vector2) -> void:
	if unit.movement_destination != destination or unit.route_revision != navigation.revision:
		_set_route(unit, destination, navigation.path(unit.position, destination))


func _set_route(unit: Unit, destination: Vector2, route: PackedVector2Array) -> void:
	unit.movement_destination = destination
	unit.waypoints = route
	unit.route_revision = navigation.revision


func _clear_route(unit: Unit) -> void:
	_set_route(unit, Vector2.INF, PackedVector2Array())


func _move(unit: Unit) -> void:
	var remaining := MOVEMENT_SPEED * STEP
	while remaining > 0.0 and not unit.waypoints.is_empty():
		var waypoint := unit.waypoints[0]
		var distance := unit.position.distance_to(waypoint)
		if distance > 0.0:
			unit.heading = unit.position.direction_to(waypoint)
		unit.position = unit.position.move_toward(waypoint, remaining)
		remaining -= distance
		if remaining >= 0.0:
			unit.waypoints.remove_at(0)
	if unit.order == Order.MOVE and unit.position == unit.ordered_destination:
		unit.order = Order.HOLD


func _add_footprint(center: Vector2, half_size: Vector2) -> int:
	return navigation.add_obstacle(Rect2(center - half_size, half_size * 2.0))


static func _opponent(side: MatchRegion.Owner) -> MatchRegion.Owner:
	return CPU if side == PLAYER else PLAYER
