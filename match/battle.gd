class_name MatchBattle
extends RefCounted

signal unit_produced(unit: Unit)
signal unit_removed(unit_id: int)
signal base_destroyed(side: MatchRegion.Owner)
signal outpost_destroyed(outpost: Outpost)
signal fortification_destroyed(fortification: Fortification)
signal fortification_fired(fortification: Fortification, impact: Vector2)

const Fortifications := preload("res://match/fortification_rules.gd")

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
const DEFAULT_BOUNDS := Rect2(-15.0, -9.0, 30.0, 18.0)
const DEFAULT_AGGRO_RADIUS := 4.0
const BASE_FOOTPRINT := Vector2(1.5, 1.5)
const BARRACKS_FOOTPRINT := Vector2(1.41, 0.91)
const BARRACKS_SPAWN_CLEARANCE := BARRACKS_FOOTPRINT + Vector2.ONE * 0.24
const OUTPOST_FOOTPRINT := Vector2(0.52, 0.52)
const OUTPOST_CLEARANCE := OUTPOST_FOOTPRINT + Vector2(0.08, 0.08)
const OUTPOST_ATTACK_RANGE := 1.25
const DEFAULT_OUTPOST_HP := 24
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
	var strategic_target := BASE_TARGET
	var strategic_revision := -1
	var blocked_revision := -1
	var blocked_objective := Vector2.INF
	var wall_approach: Dictionary
	var hp := float(UNIT_HP)
	var target := NO_TARGET
	var can_attack_target := false
	var cooldown := 0.0
	var attack_interval := ATTACK_COOLDOWN

	func _init(unit_id: int, owner: MatchRegion.Owner, spawn_position: Vector2) -> void:
		id = unit_id
		side = owner
		position = spawn_position


class ProductionTimer:
	var source_id: StringName
	var side: MatchRegion.Owner
	var position: Vector2
	var elapsed := 0.0
	var active := true
	var obstacle: int

	func _init(owner: MatchRegion.Owner, building_position: Vector2) -> void:
		side = owner
		position = building_position


class BuildingHealth:
	var side: MatchRegion.Owner
	var source_id: StringName
	var hp: float
	var base_max_hp: float
	var max_hp: float:
		get:
			return _stats.value(side, FactionStats.BUILDING_MAX_HP, base_max_hp)
	var _stats: FactionStats

	func _init(stats: FactionStats, owner: MatchRegion.Owner, base_health: float) -> void:
		_stats = stats
		side = owner
		base_max_hp = base_health
		hp = max_hp

	func health_stat() -> Dictionary:
		return _stats.inspect(side, FactionStats.BUILDING_MAX_HP, base_max_hp)


class Outpost extends BuildingHealth:
	var id: int
	var region_id: StringName
	var position: Vector2
	var obstacle: int


class Fortification extends BuildingHealth:
	var id: int
	var kind: StringName
	var position: Vector2
	var angle: float
	var obstacle := -1
	var active := false
	var cooldown := 0.0
	var profile: Dictionary
	var attack_range: float:
		get:
			return profile.size.length() * 0.5 + UNIT_ATTACK_RANGE * 0.65


var stats: FactionStats
var aggro_radius: float
var target_priority := TargetPriority.NEAREST
var navigation: BattleNavigation
var _bases: Dictionary[MatchRegion.Owner, Vector2]
var _base_obstacles: Dictionary[MatchRegion.Owner, int] = {}
var _base_health: Dictionary[MatchRegion.Owner, BuildingHealth] = {}
var _timers: Array[ProductionTimer] = []
var _units: Dictionary[int, Unit] = {}
var _outposts: Dictionary[int, Outpost] = {}
var _fortifications: Dictionary[int, Fortification] = {}
var _next_structure_id := BASE_TARGET - 1
var _next_unit_id := 1
var _pending_time := 0.0
var _elapsed_time := 0.0
var _outcome := Outcome.IN_PROGRESS


func _init(player_base: Vector2, cpu_base: Vector2, detection_radius := DEFAULT_AGGRO_RADIUS,
		bounds := DEFAULT_BOUNDS, faction_stats: FactionStats = null) -> void:
	stats = faction_stats if faction_stats != null else FactionStats.new()
	aggro_radius = detection_radius
	navigation = BattleNavigation.new(bounds)
	_bases = {PLAYER: player_base, CPU: cpu_base}
	for side in _bases:
		var building := BuildingHealth.new(stats, side, BASE_HP)
		building.source_id = StringName("base/%d" % side)
		_base_health[side] = building
		_base_obstacles[side] = _add_footprint(_bases[side], BASE_FOOTPRINT)
	stats.stat_changed.connect(_on_stat_changed)


func add_barracks(side: MatchRegion.Owner, position: Vector2) -> ProductionTimer:
	var timer := ProductionTimer.new(side, position)
	timer.source_id = StringName("barracks/%d" % _timers.size())
	timer.obstacle = _add_footprint(position, BARRACKS_FOOTPRINT)
	_timers.append(timer)
	return timer


func set_barracks_active(timer: ProductionTimer, active: bool) -> void:
	if timer.active == active:
		return
	timer.active = active
	if active:
		timer.obstacle = _add_footprint(timer.position, BARRACKS_FOOTPRINT)
	else:
		navigation.remove_obstacle(timer.obstacle)
	stats.set_source_active(timer.source_id, active)


func add_outpost(region_id: StringName, side: MatchRegion.Owner, position: Vector2,
		max_hp: int) -> Outpost:
	var outpost := Outpost.new(stats, side, max_hp)
	outpost.id = _next_structure_id
	_next_structure_id -= 1
	outpost.region_id = region_id
	outpost.source_id = StringName("outpost/%d" % outpost.id)
	outpost.position = position
	outpost.obstacle = _add_footprint(position, OUTPOST_FOOTPRINT)
	_outposts[outpost.id] = outpost
	return outpost


func get_outpost(id: int) -> Outpost:
	return _outposts.get(id)


func add_fortification(kind: StringName, side: MatchRegion.Owner, position: Vector2,
		angle := 0.0) -> Fortification:
	return add_structure(kind, Fortifications.PROFILES[kind], side, position, angle)


func add_structure(kind: StringName, profile: Dictionary, side: MatchRegion.Owner,
		position: Vector2, angle := 0.0) -> Fortification:
	var fort := Fortification.new(stats, side, profile.hp)
	fort.id = _next_structure_id
	_next_structure_id -= 1
	fort.kind = kind
	fort.profile = profile
	fort.position = position
	fort.angle = angle
	fort.source_id = StringName("fortification/%d" % fort.id)
	_fortifications[fort.id] = fort
	set_fortification_active(fort, true)
	return fort


func get_fortification(id: int) -> Fortification:
	return _fortifications.get(id)


func set_fortification_active(fort: Fortification, active: bool) -> void:
	if fort.active == active:
		return
	fort.active = active
	if active:
		fort.obstacle = navigation.add_obstacle(_footprint(fort.position, fort.profile.size * 0.5), fort.angle)
	else:
		navigation.remove_obstacle(fort.obstacle)
		fort.obstacle = -1
	stats.set_source_active(fort.source_id, active)


func fortification_site_clear(polygon: PackedVector2Array, fortifications_only := false) -> bool:
	if not fortifications_only:
		for center in _bases.values():
			if _footprints_overlap(polygon, center, BASE_FOOTPRINT * 2.0):
				return false
		for timer in _timers:
			if _footprints_overlap(polygon, timer.position, BARRACKS_SPAWN_CLEARANCE * 2.0):
				return false
		for outpost in _outposts.values():
			if _footprints_overlap(polygon, outpost.position, OUTPOST_CLEARANCE * 2.0):
				return false
	for fort: Fortification in _fortifications.values():
		if _footprints_overlap(polygon, fort.position, fort.profile.size, fort.angle):
			return false
	return true


static func _footprints_overlap(polygon: PackedVector2Array, center: Vector2,
		size: Vector2, angle := 0.0) -> bool:
	return not Geometry2D.intersect_polygons(polygon,
		Fortifications.footprint(center, size, angle)).is_empty()


func outpost_site_clear(position: Vector2) -> bool:
	var footprint := _footprint(position, OUTPOST_CLEARANCE)
	for center in _bases.values():
		if footprint.intersects(_footprint(center, BASE_FOOTPRINT)):
			return false
	for timer in _timers:
		if footprint.intersects(_footprint(timer.position, BARRACKS_FOOTPRINT)):
			return false
	for outpost in _outposts.values():
		if footprint.intersects(_footprint(outpost.position, OUTPOST_FOOTPRINT)):
			return false
	return fortification_site_clear(BattleNavigation.corners_of(footprint), true)


func get_unit(id: int) -> Unit:
	return _units.get(id)


func issue_move(id: int, destination: Vector2) -> bool:
	var unit := get_unit(id)
	if is_finished() or unit == null or unit.side != PLAYER:
		return false
	var route := navigation.path(unit.position, destination)
	if route.is_empty() and (not navigation.is_passable(destination)
			or _find_wall_approach(unit).is_empty()):
		return false
	unit.order = Order.MOVE
	unit.ordered_destination = destination
	unit.target = NO_TARGET
	unit.can_attack_target = false
	_set_route(unit, destination, route)
	return true


func active_units() -> Array[Unit]:
	return _units.values()


func base_hp(side: MatchRegion.Owner) -> float:
	return _base_health[side].hp


func base_health_stat(side: MatchRegion.Owner) -> Dictionary:
	return _base_health[side].health_stat()


func base_source_id(side: MatchRegion.Owner) -> StringName:
	return _base_health[side].source_id


func unit_dps_stat(unit: Unit) -> Dictionary:
	return stats.inspect(unit.side, FactionStats.UNIT_DPS, ATTACK_DAMAGE / unit.attack_interval)


func unit_attack_stat(unit: Unit) -> Dictionary:
	var result := unit_dps_stat(unit)
	result.total *= unit.attack_interval
	for entry: Dictionary in result.breakdown:
		entry.stat = &"attack_damage"
		entry.magnitude *= unit.attack_interval
		if entry.has("configured_magnitude"):
			entry.configured_magnitude *= unit.attack_interval
	return result


func _on_stat_changed(stat: StringName) -> void:
	if stat != FactionStats.BUILDING_MAX_HP:
		return
	# Cap reductions discard surplus HP. Higher caps never heal existing buildings.
	for building in _base_health.values():
		building.hp = minf(building.hp, building.max_hp)
	for outpost in _outposts.values():
		outpost.hp = minf(outpost.hp, outpost.max_hp)
	for fort: Fortification in _fortifications.values():
		fort.hp = minf(fort.hp, fort.max_hp)


func is_finished() -> bool:
	return _outcome != Outcome.IN_PROGRESS


func outcome() -> Outcome:
	return _outcome


func elapsed_time() -> float:
	return _elapsed_time


func advance(delta: float, economy: MatchEconomy, accrue_income := false) -> void:
	if delta < 0.0 or is_finished():
		return

	# An upgrade can make an existing timer due immediately.
	_advance_production(0.0, economy)
	_pending_time += delta
	while _pending_time + TIME_EPSILON >= STEP and not is_finished():
		_pending_time = maxf(0.0, _pending_time - STEP)
		_elapsed_time += STEP
		if accrue_income:
			economy.advance(STEP)
		_step_combat()
		if not is_finished():
			_advance_production(STEP, economy)


func _advance_production(delta: float, economy: MatchEconomy) -> void:
	for timer in _timers:
		if not timer.active:
			continue
		# Upgrades shorten the current cycle while keeping elapsed production time.
		var interval := economy.production_interval(timer.side)
		timer.elapsed += delta
		while timer.elapsed + TIME_EPSILON >= interval:
			if not economy.try_spend(timer.side, MatchEconomy.UNIT_COST):
				timer.elapsed = interval
				break
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
		unit.can_attack_target = _plan_turn(unit, units)
		if unit.can_attack_target and unit.cooldown <= TIME_EPSILON:
			attacks.append(unit)

	_fire_fortifications(units)
	for unit in units:
		_move(unit)

	# A unit killed this step still resolves the attack it planned.
	for unit in attacks:
		var damage := stats.value(unit.side, FactionStats.UNIT_DPS,
			ATTACK_DAMAGE / unit.attack_interval) * unit.attack_interval
		if unit.target == BASE_TARGET:
			var side := _opponent(unit.side)
			_base_health[side].hp = maxf(0.0, base_hp(side) - damage)
		elif unit.target < BASE_TARGET:
			var building: BuildingHealth = _outposts.get(unit.target)
			if building == null:
				building = _fortifications[unit.target]
			building.hp = maxf(0.0, building.hp - damage)
		else:
			_units[unit.target].hp -= damage
		unit.cooldown = unit.attack_interval

	for unit in units:
		if unit.hp <= 0:
			_units.erase(unit.id)
			unit_removed.emit(unit.id)

	var destroyed_outposts: Array[Outpost] = []
	for outpost in _outposts.values():
		if outpost.hp == 0:
			_outposts.erase(outpost.id)
			navigation.remove_obstacle(outpost.obstacle)
			stats.remove_source(outpost.source_id)
			destroyed_outposts.append(outpost)

	for fort: Fortification in _fortifications.values():
		if fort.hp == 0:
			_fortifications.erase(fort.id)
			navigation.remove_obstacle(fort.obstacle)
			stats.remove_source(fort.source_id)
			fortification_destroyed.emit(fort)

	for unit in _units.values():
		if (unit.target > NO_TARGET and not _units.has(unit.target)) \
				or (unit.target < BASE_TARGET and not _outposts.has(unit.target)
					and not _fortifications.has(unit.target)):
			unit.target = NO_TARGET
			unit.can_attack_target = false
			_clear_route(unit)

	for outpost in destroyed_outposts:
		outpost_destroyed.emit(outpost)

	if base_hp(PLAYER) == 0:
		_outcome = Outcome.DEFEAT
	elif base_hp(CPU) == 0:
		_outcome = Outcome.VICTORY

	if base_hp(PLAYER) == 0:
		stats.remove_source(base_source_id(PLAYER))
		base_destroyed.emit(PLAYER)
	if base_hp(CPU) == 0:
		stats.remove_source(base_source_id(CPU))
		base_destroyed.emit(CPU)


func _fire_fortifications(units: Array[Unit]) -> void:
	for fort: Fortification in _fortifications.values():
		if not fort.active or fort.profile.get("range", 0.0) <= 0.0:
			continue
		fort.cooldown = maxf(0.0, fort.cooldown - STEP)
		if fort.cooldown > TIME_EPSILON:
			continue

		var target: Unit
		var range_squared := float(fort.profile.range) ** 2
		var nearest := range_squared
		for unit in units:
			var distance := fort.position.distance_squared_to(unit.position)
			if unit.side == fort.side or unit.hp <= 0.0 or distance > nearest:
				continue
			if target != null and distance == nearest and unit.id > target.id:
				continue
			if fort.profile.splash == 0.0 and not navigation.line_clear(
					fort.position, unit.position, fort.obstacle):
				continue
			target = unit
			nearest = distance
		if target == null:
			continue

		target.hp -= fort.profile.damage
		if fort.profile.splash > 0.0:
			var radius_squared := float(fort.profile.splash) ** 2
			for unit in units:
				if unit != target and unit.side != fort.side and unit.hp > 0.0 \
						and fort.position.distance_squared_to(unit.position) <= range_squared \
						and target.position.distance_squared_to(unit.position) <= radius_squared:
					unit.hp -= fort.profile.damage
		fort.cooldown = fort.profile.interval
		fortification_fired.emit(fort, target.position)


func _plan_turn(unit: Unit, units: Array[Unit]) -> bool:
	unit.target = NO_TARGET
	if _plan_local_engagement(unit, units):
		return unit.waypoints.is_empty()

	var side := _opponent(unit.side)
	var base := _bases[side]
	var at_hold_point := unit.order == Order.HOLD and unit.position == unit.ordered_destination
	if unit.order == Order.AUTONOMOUS or at_hold_point:
		if _can_attack_structure(unit.position, base, _base_obstacles[side], BASE_ATTACK_RANGE):
			unit.target = BASE_TARGET
			unit.heading = unit.position.direction_to(base)
			_clear_route(unit)
			return true
		for outpost in _outposts.values():
			if outpost.side != unit.side and _can_attack_structure(unit.position, outpost.position,
					outpost.obstacle, OUTPOST_ATTACK_RANGE):
				unit.target = outpost.id
				unit.heading = unit.position.direction_to(outpost.position)
				_clear_route(unit)
				return true

		for fort: Fortification in _fortifications.values():
			if fort.side != unit.side and _can_attack_structure(unit.position, fort.position,
					fort.obstacle, fort.attack_range):
				unit.target = fort.id
				unit.heading = unit.position.direction_to(fort.position)
				_clear_route(unit)
				return true

	if unit.order == Order.AUTONOMOUS:
		if unit.strategic_revision != navigation.revision:
			_plan_strategic_approach(unit, side)
		unit.target = unit.strategic_target
		_route_to(unit, unit.strategic_destination)
	else:
		_route_to(unit, unit.ordered_destination)
	if unit.waypoints.is_empty():
		var objective := _bases[side] if unit.order == Order.AUTONOMOUS else unit.ordered_destination
		if unit.position.is_equal_approx(objective):
			return false
		if unit.blocked_revision != navigation.revision or unit.blocked_objective != objective:
			unit.blocked_revision = navigation.revision
			unit.blocked_objective = objective
			unit.wall_approach = _find_wall_approach(unit)
		if not unit.wall_approach.is_empty():
			var wall := get_fortification(unit.wall_approach.id)
			unit.target = wall.id
			if _can_attack_structure(unit.position, wall.position, wall.obstacle, wall.attack_range):
				unit.heading = unit.position.direction_to(wall.position)
				_clear_route(unit)
				return true
			_route_to(unit, unit.wall_approach.point)
	return false


func _find_wall_approach(unit: Unit) -> Dictionary:
	var result := {}
	var nearest := INF
	for fort: Fortification in _fortifications.values():
		if fort.side == unit.side or fort.kind != Fortifications.WALL or not fort.active:
			continue
		var distance := unit.position.distance_squared_to(fort.position)
		if distance >= nearest:
			continue
		var point := _find_structure_approach(unit.position, fort.position, fort.obstacle, fort.attack_range)
		if point.is_finite():
			nearest = distance
			result = {"id": fort.id, "point": point}
	return result


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
		var priority := opponent.hp if target_priority == TargetPriority.LOWEST_HP else 0.0
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


func _plan_strategic_approach(unit: Unit, opponent: MatchRegion.Owner) -> void:
	unit.strategic_revision = navigation.revision
	unit.strategic_target = BASE_TARGET
	var nearest := INF
	for outpost in _outposts.values():
		var distance := unit.position.distance_squared_to(outpost.position)
		if outpost.side == unit.side or distance >= nearest:
			continue
		var destination := _find_structure_approach(unit.position, outpost.position,
			outpost.obstacle, OUTPOST_ATTACK_RANGE)
		if destination.is_finite():
			nearest = distance
			unit.strategic_target = outpost.id
			unit.strategic_destination = destination
	if unit.strategic_target == BASE_TARGET:
		unit.strategic_destination = _find_structure_approach(unit.position, _bases[opponent],
			_base_obstacles[opponent], BASE_ATTACK_RANGE)


func _can_attack_structure(position: Vector2, center: Vector2, obstacle: int,
		attack_range: float) -> bool:
	return position.distance_squared_to(center) <= pow(attack_range + 0.00001, 2) \
		and navigation.is_passable(position) \
		and navigation.line_clear(position, center, obstacle)


func _find_structure_approach(position: Vector2, center: Vector2, obstacle: int,
		attack_range: float) -> Vector2:
	var outward := center.direction_to(position)
	if outward.is_zero_approx():
		outward = Vector2.RIGHT
	var best := Vector2.INF
	var best_length := INF
	for i in range(STRATEGIC_SAMPLE_COUNT):
		var candidate := center + outward.rotated(TAU * i / STRATEGIC_SAMPLE_COUNT) * attack_range
		if not _can_attack_structure(candidate, center, obstacle, attack_range):
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
	return navigation.add_obstacle(_footprint(center, half_size))


static func _footprint(center: Vector2, half_size: Vector2) -> Rect2:
	return Rect2(center - half_size, half_size * 2.0)


static func _opponent(side: MatchRegion.Owner) -> MatchRegion.Owner:
	return CPU if side == PLAYER else PLAYER
