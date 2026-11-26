class_name MatchBattle
extends RefCounted

signal unit_produced(unit: Unit)
signal unit_removed(unit_id: int)
signal attack_resolved(attack: AttackResolved)
signal step_finished
signal base_destroyed(side: MatchRegion.Owner)
signal outpost_destroyed(outpost: Outpost)
signal fortification_destroyed(fortification: Fortification)
signal fortification_fired(fortification: Fortification, impact: Vector2)

const UnitCatalog := preload("res://match/unit_catalog.gd")
const Fortifications := preload("res://match/fortification_rules.gd")

enum Outcome { IN_PROGRESS, VICTORY, DEFEAT }
enum Order { AUTONOMOUS, MOVE, HOLD }
enum Stance { SEEK_NEAREST, SEEK_STRONGEST, IDLE }
enum TargetPriority { NEAREST, LOWEST_HP }

const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const INFANTRY := UnitCatalog.DEFINITIONS[UnitCatalog.INFANTRY]
const UNIT_HP := INFANTRY.hp
const BASE_HP := 80
const ATTACK_DAMAGE := INFANTRY.damage
const ATTACK_COOLDOWN := INFANTRY.cooldown
const MOVEMENT_SPEED := INFANTRY.speed
const UNIT_ATTACK_RANGE := INFANTRY.range
const BASE_ATTACK_RANGE := 1.8
const DEFAULT_BOUNDS := Rect2(-15.0, -9.0, 30.0, 18.0)
const DEFAULT_AGGRO_RADIUS := 4.0
const DEFAULT_THREAT_WEIGHTS := Vector2(2.0, 0.25)
const COMBAT_CELL_SIZE := 4.0
const BASE_FOOTPRINT := Vector2(1.5, 1.5)
const BARRACKS_FOOTPRINT := Vector2(1.41, 0.91)
const SPAWN_EXIT_OFFSET := 0.08
const BARRACKS_HP := 32
const BARRACKS_PROFILE := {
	"label": "Barracks", "hp": BARRACKS_HP, "size": BARRACKS_FOOTPRINT * 2.0,
	"unit_type": UnitCatalog.INFANTRY, "interval": MatchEconomy.PRODUCTION_INTERVAL,
}
const OUTPOST_FOOTPRINT := Vector2(0.52, 0.52)
const OUTPOST_CLEARANCE := OUTPOST_FOOTPRINT + Vector2(0.08, 0.08)
const OUTPOST_ATTACK_RANGE := 1.25
const DEFAULT_OUTPOST_HP := 24
const STRATEGIC_SAMPLE_COUNT := 16
const STEP := 1.0 / 60.0
const TIME_EPSILON := 1e-9
const RANGE_EPSILON := 0.00001
const NO_TARGET := 0
const BASE_TARGET := -1


class Unit:
	var id: int
	var type_id: StringName
	var definition: Dictionary
	var side: MatchRegion.Owner
	var position: Vector2
	var heading := Vector2.RIGHT
	var stance := Stance.SEEK_NEAREST
	var order := Order.AUTONOMOUS
	var resume_stance_on_arrival := false
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
	var hp: float
	var target := NO_TARGET
	var can_attack_target := false
	var scout_committed := false
	var cooldown := 0.0
	var attack_interval: float

	func _init(unit_id: int, owner: MatchRegion.Owner, spawn_position: Vector2,
			unit_type := UnitCatalog.INFANTRY) -> void:
		id = unit_id
		type_id = unit_type
		definition = UnitCatalog.DEFINITIONS[type_id]
		hp = definition.hp
		attack_interval = definition.cooldown
		side = owner
		position = spawn_position


## Position snapshots are in map coordinates at the attack step, before movement.
## BASE_TARGET is shared by both bases. target_side identifies the one hit.
class AttackResolved:
	var attacker_id: int
	var attacker_type: StringName
	var attacker_side: MatchRegion.Owner
	var target_id: int
	var target_side: MatchRegion.Owner
	var attack_position: Vector2
	var impact_position: Vector2
	var simulation_time: float

	func _init(unit: Unit, victim_side: MatchRegion.Owner, impact: Vector2, time: float) -> void:
		attacker_id = unit.id
		attacker_type = unit.type_id
		attacker_side = unit.side
		target_id = unit.target
		target_side = victim_side
		attack_position = unit.position
		impact_position = impact
		simulation_time = time


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

	func unit_attack_range(weapon_range: float) -> float:
		return profile.size.length() * 0.5 + weapon_range * 0.65


class ProductionTimer extends Fortification:
	var elapsed := 0.0
	var unit_type: StringName

	func interval(economy: MatchEconomy) -> float:
		return economy.production_interval(side) if kind == &"barracks" else profile.interval

	func spawn_extent() -> Vector2:
		return MatchBattle.producer_spawn_extent(profile.size, unit_type)


var stats: FactionStats
var aggro_radius: float
## Defensive shot priority for Hold. Autonomous pursuit uses the unit's stance.
var target_priority := TargetPriority.NEAREST
## Threat score = effective DPS * weight.x + current HP * weight.y.
var threat_weights := DEFAULT_THREAT_WEIGHTS
var navigation: BattleNavigation
var _bases: Dictionary[MatchRegion.Owner, Vector2]
var _base_obstacles: Dictionary[MatchRegion.Owner, int] = {}
var _base_health: Dictionary[MatchRegion.Owner, BuildingHealth] = {}
var _timers: Array[ProductionTimer] = []
var _units: Dictionary[int, Unit] = {}
var _outposts: Dictionary[int, Outpost] = {}
var _fortifications: Dictionary[int, Fortification] = {}
var _landmark_footprints: Array[Rect2] = []
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
	return add_producer(&"barracks", BARRACKS_PROFILE, side, position)


func add_producer(kind: StringName, profile: Dictionary, side: MatchRegion.Owner,
		position: Vector2) -> ProductionTimer:
	var timer := ProductionTimer.new(stats, side, profile.hp)
	timer.unit_type = profile.unit_type
	_register_structure(timer, kind, profile, position, 0.0)
	_timers.append(timer)
	return timer


func active_barracks_count(side: MatchRegion.Owner) -> int:
	var count := 0
	for timer in _timers:
		if timer.side == side and timer.active and timer.kind == &"barracks":
			count += 1
	return count


func set_barracks_active(timer: ProductionTimer, active: bool) -> void:
	set_fortification_active(timer, active)


static func producer_spawn_extent(size: Vector2, unit_type: StringName) -> Vector2:
	var clearance: float = UnitCatalog.DEFINITIONS[unit_type].clearance
	# Leave room both for the spawn offset from this producer and for nearby obstacle clearance.
	return size * 0.5 + Vector2.ONE * maxf(0.24, SPAWN_EXIT_OFFSET * 2.0 + clearance) \
		+ Vector2.ONE * clearance


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
	_register_structure(fort, kind, profile, position, angle)
	return fort


func _register_structure(fort: Fortification, kind: StringName, profile: Dictionary,
		position: Vector2, angle: float) -> void:
	fort.id = _next_structure_id
	_next_structure_id -= 1
	fort.kind = kind
	fort.profile = profile
	fort.position = position
	fort.angle = angle
	fort.source_id = StringName("fortification/%d" % fort.id)
	_fortifications[fort.id] = fort
	set_fortification_active(fort, true)


func get_fortification(id: int) -> Fortification:
	return _fortifications.get(id)


func set_fortification_active(fort: Fortification, active: bool) -> void:
	if fort.active == active or not _fortifications.has(fort.id):
		return
	fort.active = active
	if active:
		fort.obstacle = navigation.add_obstacle(_footprint(fort.position, fort.profile.size * 0.5), fort.angle)
	else:
		navigation.remove_obstacle(fort.obstacle)
		fort.obstacle = -1
	stats.set_source_active(fort.source_id, active)


func add_landmark_footprint(footprint: Rect2) -> void:
	_landmark_footprints.append(footprint)
	navigation.add_obstacle(footprint)


func fortification_site_clear(polygon: PackedVector2Array, include_hubs := true) -> bool:
	for footprint in _landmark_footprints:
		if not Geometry2D.intersect_polygons(polygon, BattleNavigation.corners_of(footprint)).is_empty():
			return false
	if include_hubs:
		for center in _bases.values():
			if _footprints_overlap(polygon, center, BASE_FOOTPRINT * 2.0):
				return false
		for outpost in _outposts.values():
			if _footprints_overlap(polygon, outpost.position, OUTPOST_CLEARANCE * 2.0):
				return false
	for fort: Fortification in _fortifications.values():
		var size: Vector2 = fort.profile.size
		if fort is ProductionTimer:
			size = fort.spawn_extent() * 2.0
		if _footprints_overlap(polygon, fort.position, size, fort.angle):
			return false
	return true


func producer_site_clear(position: Vector2, profile: Dictionary) -> bool:
	var extent := producer_spawn_extent(profile.size, profile.unit_type)
	# Reserve enough room for a unit to leave on every side, including near the map edge.
	var exit_area := _footprint(position, extent)
	if not navigation._bounds.encloses(exit_area):
		return false
	var footprint := Fortifications.footprint(position, profile.size)
	if not fortification_site_clear(footprint):
		return false
	var exits := BattleNavigation.corners_of(exit_area)
	for rect in _landmark_footprints:
		if rect.intersects(exit_area):
			return false
	for center in _bases.values():
		if _footprint(center, BASE_FOOTPRINT).intersects(exit_area):
			return false
	for outpost in _outposts.values():
		if _footprint(outpost.position, OUTPOST_CLEARANCE).intersects(exit_area):
			return false
	for fort: Fortification in _fortifications.values():
		if _footprints_overlap(exits, fort.position, fort.profile.size, fort.angle):
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
	for outpost in _outposts.values():
		if footprint.intersects(_footprint(outpost.position, OUTPOST_FOOTPRINT)):
			return false
	return fortification_site_clear(BattleNavigation.corners_of(footprint), false)


## Deploy a catalog unit for either faction. Pass an economy for paid production.
## Invalid spawns leave Food and unit IDs untouched.
func spawn_unit(side: MatchRegion.Owner, position: Vector2,
		type_id := UnitCatalog.INFANTRY, economy: MatchEconomy = null) -> Unit:
	if type_id == UnitCatalog.SCOUT:
		return null
	return _spawn_unit(side, position, type_id, economy)


func _spawn_unit(side: MatchRegion.Owner, position: Vector2, type_id: StringName,
		economy: MatchEconomy = null) -> Unit:
	var definition: Dictionary = UnitCatalog.DEFINITIONS.get(type_id, {})
	if is_finished() or not _bases.has(side) or definition.is_empty():
		return null
	if not navigation.with_clearance(definition.clearance).is_passable(position):
		return null
	if economy != null and not economy.try_spend(side, {MatchEconomy.FOOD: definition.food}):
		return null
	var unit := Unit.new(_next_unit_id, side, position, type_id)
	unit.hp = _unit_max_hp(unit)
	unit.heading = position.direction_to(_bases[_opponent(side)])
	_units[unit.id] = unit
	_next_unit_id += 1
	unit_produced.emit(unit)
	return unit


func get_unit(id: int) -> Unit:
	return _units.get(id)


## Set the default for an owned combat unit. Cancel the order to apply it now.
func set_unit_stance(side: MatchRegion.Owner, id: int, stance: Stance,
		cancel_order := false) -> bool:
	var unit := _commandable_unit(side, id)
	if unit == null or unit.type_id == UnitCatalog.SCOUT or not Stance.values().has(stance):
		return false
	unit.stance = stance
	if cancel_order or unit.order == Order.AUTONOMOUS:
		_resume_stance(unit)
	return true


func issue_move(id: int, destination: Vector2, resume_stance := false) -> bool:
	return order_move(PLAYER, id, destination, resume_stance)


func order_move(side: MatchRegion.Owner, id: int, destination: Vector2,
		resume_stance := false) -> bool:
	var unit := _commandable_unit(side, id)
	if unit == null:
		return false
	var routes := _unit_navigation(unit)
	var route := routes.path(unit.position, destination)
	var breach := {}
	if route.is_empty():
		if unit.type_id == UnitCatalog.SCOUT or not routes.is_passable(destination):
			return false
		breach = _find_wall_approach(unit, destination)
		if breach.is_empty():
			return false
	_order_move(unit, destination, route)
	unit.resume_stance_on_arrival = resume_stance
	if not breach.is_empty():
		unit.blocked_revision = navigation.revision
		unit.blocked_objective = destination
		unit.wall_approach = breach
	return true


## With no destination, establish a post at the unit's current position.
func order_hold(side: MatchRegion.Owner, id: int, destination: Variant = null) -> bool:
	var unit := _commandable_unit(side, id)
	if unit == null or unit.type_id == UnitCatalog.SCOUT \
			or (destination != null and not destination is Vector2):
		return false
	var point: Vector2 = unit.position if destination == null else destination
	var route := PackedVector2Array()
	if point != unit.position:
		route = _unit_navigation(unit).path(unit.position, point)
		if route.is_empty():
			return false
	_set_order(unit, Order.HOLD, point, route)
	return true


func _commandable_unit(side: MatchRegion.Owner, id: int) -> Unit:
	var unit := get_unit(id)
	if is_finished() or unit == null or unit.side != side or unit.scout_committed or unit.hp <= 0.0:
		return null
	return unit


func _order_move(unit: Unit, destination: Vector2, route: PackedVector2Array) -> void:
	_set_order(unit, Order.MOVE, destination, route)


func _set_order(unit: Unit, order: Order, destination: Vector2, route: PackedVector2Array) -> void:
	unit.order = order
	unit.ordered_destination = destination
	unit.resume_stance_on_arrival = false
	unit.target = NO_TARGET
	unit.can_attack_target = false
	unit.strategic_revision = -1
	unit.blocked_revision = -1
	unit.wall_approach.clear()
	_set_route(unit, destination, route)


func _resume_stance(unit: Unit) -> void:
	_set_order(unit, Order.AUTONOMOUS, Vector2.INF, PackedVector2Array())


func active_units() -> Array[Unit]:
	return _units.values()


func base_hp(side: MatchRegion.Owner) -> float:
	return _base_health[side].hp


func base_health_stat(side: MatchRegion.Owner) -> Dictionary:
	return _base_health[side].health_stat()


func base_source_id(side: MatchRegion.Owner) -> StringName:
	return _base_health[side].source_id


func unit_dps_stat(unit: Unit) -> Dictionary:
	return stats.inspect(unit.side, FactionStats.UNIT_DPS, _base_dps(unit))


func unit_health_stat(unit: Unit) -> Dictionary:
	return stats.inspect(unit.side, FactionStats.UNIT_MAX_HP, unit.definition.hp)


func unit_speed_stat(unit: Unit) -> Dictionary:
	return stats.inspect(unit.side, FactionStats.UNIT_SPEED, unit.definition.speed)


func _base_dps(unit: Unit) -> float:
	return unit.definition.damage / unit.attack_interval


func _unit_max_hp(unit: Unit) -> float:
	return stats.value(unit.side, FactionStats.UNIT_MAX_HP, unit.definition.hp)


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
	if stat == FactionStats.UNIT_MAX_HP:
		for unit in _units.values():
			unit.hp = minf(unit.hp, _unit_max_hp(unit))
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


## Returns the delta used before a decision interrupted the frame.
func advance(delta: float, economy: MatchEconomy, accrue_income := false,
		should_interrupt := Callable()) -> float:
	if delta < 0.0 or is_finished():
		return 0.0

	# An upgrade can make an existing timer due immediately.
	_advance_production(0.0, economy)
	if should_interrupt.is_valid() and should_interrupt.call():
		return 0.0
	_pending_time += delta
	while _pending_time + TIME_EPSILON >= STEP and not is_finished():
		_pending_time = maxf(0.0, _pending_time - STEP)
		_elapsed_time += STEP
		if accrue_income:
			economy.advance(STEP)
		_step_combat()
		if not is_finished():
			_advance_production(STEP, economy)
		step_finished.emit()
		if should_interrupt.is_valid() and should_interrupt.call():
			var used := clampf(delta - _pending_time, 0.0, delta)
			_pending_time = 0.0
			return used
	return delta


func _advance_production(delta: float, economy: MatchEconomy) -> void:
	for timer: ProductionTimer in _timers.duplicate():
		if not timer.active or timer.hp <= 0.0:
			continue
		# Upgrades shorten the current cycle while keeping elapsed production time.
		var interval := timer.interval(economy)
		timer.elapsed += delta
		while timer.active and timer.hp > 0.0 and timer.elapsed + TIME_EPSILON >= interval:
			timer.elapsed = maxf(0.0, timer.elapsed - interval)
			var direction := timer.position.direction_to(_bases[_opponent(timer.side)])
			var position := _spawn_position(timer, direction)
			if spawn_unit(timer.side, position, timer.unit_type, economy) == null:
				timer.elapsed = interval
				break


func _spawn_position(timer: ProductionTimer, direction: Vector2) -> Vector2:
	var exits := [direction, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	var clearance: float = UnitCatalog.DEFINITIONS[timer.unit_type].clearance
	var routes := navigation.with_clearance(clearance)
	var extent: Vector2 = timer.profile.size * 0.5 + Vector2.ONE * (SPAWN_EXIT_OFFSET + clearance)
	var closest := Vector2.INF
	var best_alignment := -INF
	for exit: Vector2 in exits:
		if exit.is_zero_approx():
			continue
		var distance := 1.0 / maxf(absf(exit.x) / extent.x, absf(exit.y) / extent.y)
		var candidate := timer.position + exit * distance
		if routes.is_passable(candidate) and exit.dot(direction) > best_alignment:
			closest = candidate
			best_alignment = exit.dot(direction)
	return closest


func _step_combat() -> void:
	# Plan against the same positions before either side moves or takes damage.
	var units := active_units()
	var cells: Dictionary[Vector3i, Array] = {}
	for unit in units:
		var cell := Vector2i((unit.position / COMBAT_CELL_SIZE).floor())
		var occupants: Array = cells.get_or_add(Vector3i(cell.x, cell.y, unit.side), [])
		occupants.append(unit)

	var attacks: Array[Unit] = []
	for unit in units:
		unit.cooldown = maxf(0.0, unit.cooldown - STEP)
		if unit.hp <= 0.0:
			continue
		unit.can_attack_target = _plan_turn(unit, units, cells)
		if unit.can_attack_target and unit.cooldown <= TIME_EPSILON:
			attacks.append(unit)

	_fire_fortifications(units, cells)
	# Attacks committed while alive still resolve if the attacker falls this step.
	# Resolve against the same positions used to authorize range and facing.
	var report_attacks := attack_resolved.has_connections()
	for unit in attacks:
		_resolve_attack(unit, report_attacks)
	for unit in units:
		if unit.hp <= 0.0:
			continue
		if unit.target > NO_TARGET and _units[unit.target].hp <= 0.0:
			continue
		_move(unit)

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
		if fort.hp <= 0.0:
			set_fortification_active(fort, false)
			_fortifications.erase(fort.id)
			if fort is ProductionTimer:
				_timers.erase(fort)
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


func _resolve_attack(unit: Unit, report_attack: bool) -> void:
	var damage := stats.value(unit.side, FactionStats.UNIT_DPS, _base_dps(unit)) * unit.attack_interval
	if damage <= 0.0:
		unit.cooldown = unit.attack_interval
		return

	var target_side := _opponent(unit.side)
	var impact: Vector2
	if unit.target > NO_TARGET:
		var target := _units[unit.target]
		if target.hp <= 0.0:
			return
		target.hp -= damage
		impact = target.position
	else:
		var building: BuildingHealth
		if unit.target == BASE_TARGET:
			building = _base_health[target_side]
			impact = _bases[target_side]
		else:
			var outpost := get_outpost(unit.target)
			if outpost != null:
				building = outpost
				impact = outpost.position
			else:
				var structure := get_fortification(unit.target)
				building = structure
				impact = structure.position
		if building.hp <= 0.0:
			return
		damage *= unit.definition.structure_damage_multiplier
		building.hp = maxf(0.0, building.hp - damage)

	unit.cooldown = unit.attack_interval
	if report_attack:
		attack_resolved.emit(AttackResolved.new(unit, target_side, impact, _elapsed_time))


func _nearby_enemies(units: Array[Unit], cells: Dictionary[Vector3i, Array], position: Vector2,
		side: MatchRegion.Owner, radius: float) -> Array[Unit]:
	# For small forces or very wide queries, scanning the snapshot is cheaper.
	var cells_per_axis := 2.0 * radius / COMBAT_CELL_SIZE + 1.0
	if (not is_finite(radius) or side == MatchRegion.Owner.NEUTRAL
			or cells_per_axis * cells_per_axis >= units.size()):
		return units
	var reach := Vector2.ONE * radius
	var low := Vector2i(((position - reach) / COMBAT_CELL_SIZE).floor())
	var high := Vector2i(((position + reach) / COMBAT_CELL_SIZE).floor())
	var enemy := _opponent(side)
	var nearby: Array[Unit] = []
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var cell := Vector3i(x, y, enemy)
			if cells.has(cell):
				nearby.append_array(cells[cell])
	return nearby


func _fire_fortifications(units: Array[Unit], cells: Dictionary[Vector3i, Array]) -> void:
	for fort: Fortification in _fortifications.values():
		if not fort.active or fort.profile.get("range", 0.0) <= 0.0:
			continue
		fort.cooldown = maxf(0.0, fort.cooldown - STEP)
		if fort.cooldown > TIME_EPSILON:
			continue

		var target: Unit
		var range_squared := float(fort.profile.range) ** 2
		var nearest := range_squared
		var nearby := _nearby_enemies(units, cells, fort.position, fort.side, fort.profile.range)
		for unit in nearby:
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
			for unit in nearby:
				if unit != target and unit.side != fort.side and unit.hp > 0.0 \
						and fort.position.distance_squared_to(unit.position) <= range_squared \
						and target.position.distance_squared_to(unit.position) <= radius_squared:
					unit.hp -= fort.profile.damage
		fort.cooldown = fort.profile.interval
		fortification_fired.emit(fort, target.position)


func _plan_turn(unit: Unit, units: Array[Unit], cells: Dictionary[Vector3i, Array]) -> bool:
	unit.target = NO_TARGET
	match unit.order:
		Order.MOVE:
			if unit.blocked_revision == navigation.revision and not unit.wall_approach.is_empty():
				return _plan_breach(unit, unit.ordered_destination, true)
			_route_to(unit, unit.ordered_destination)
			return unit.type_id != UnitCatalog.SCOUT and unit.waypoints.is_empty() \
				and unit.position != unit.ordered_destination \
				and _plan_breach(unit, unit.ordered_destination, true)
		Order.HOLD:
			if unit.position != unit.ordered_destination:
				_route_to(unit, unit.ordered_destination)
				return false
		Order.AUTONOMOUS:
			if unit.stance == Stance.IDLE:
				if unit.movement_destination.is_finite():
					_clear_route(unit)
				return false
	if unit.type_id == UnitCatalog.SCOUT:
		return false

	var holding := unit.order == Order.HOLD
	var radius := absf(aggro_radius)
	if holding:
		radius = minf(radius, unit.definition.range + RANGE_EPSILON)
	var nearby := _nearby_enemies(units, cells, unit.position, unit.side, radius)
	if _plan_local_engagement(unit, nearby, radius, holding):
		return unit.waypoints.is_empty()

	var side := _opponent(unit.side)
	var weapon_range: float = unit.definition.range
	if _can_attack_structure(unit.position, _bases[side], _base_obstacles[side],
			weapon_range + BASE_ATTACK_RANGE - UNIT_ATTACK_RANGE):
		return _aim_at(unit, BASE_TARGET, _bases[side])
	for outpost in _outposts.values():
		if outpost.side != unit.side and _can_attack_structure(unit.position, outpost.position,
				outpost.obstacle, weapon_range + OUTPOST_ATTACK_RANGE - UNIT_ATTACK_RANGE):
			return _aim_at(unit, outpost.id, outpost.position)
	for fort: Fortification in _fortifications.values():
		if fort.side != unit.side and _can_attack_structure(unit.position, fort.position,
				fort.obstacle, fort.unit_attack_range(weapon_range)):
			return _aim_at(unit, fort.id, fort.position)

	if holding:
		return false
	if unit.strategic_revision != navigation.revision:
		_plan_strategic_approach(unit, side)
	_route_to(unit, unit.strategic_destination)
	if not unit.waypoints.is_empty():
		unit.target = unit.strategic_target
		return false
	return _plan_breach(unit, _bases[side], false)


func _aim_at(unit: Unit, target: int, position: Vector2) -> bool:
	unit.target = target
	unit.heading = unit.position.direction_to(position)
	_clear_route(unit)
	return true


func _plan_breach(unit: Unit, objective: Vector2, explicit_move: bool) -> bool:
	if unit.blocked_revision != navigation.revision or unit.blocked_objective != objective:
		unit.blocked_revision = navigation.revision
		unit.blocked_objective = objective
		unit.wall_approach = _find_wall_approach(unit, objective if explicit_move else Vector2.INF)
	if unit.wall_approach.is_empty():
		return false
	var wall := get_fortification(unit.wall_approach.id)
	if _can_attack_structure(unit.position, wall.position, wall.obstacle,
			wall.unit_attack_range(unit.definition.range)):
		return _aim_at(unit, wall.id, wall.position)
	unit.target = wall.id
	_route_to(unit, unit.wall_approach.point)
	return false


func _find_wall_approach(unit: Unit, destination := Vector2.INF) -> Dictionary:
	var result := {}
	var nearest := INF
	for fort: Fortification in _fortifications.values():
		if fort.side == unit.side or fort.kind != Fortifications.WALL or not fort.active:
			continue
		var distance := unit.position.distance_squared_to(fort.position)
		if distance >= nearest:
			continue
		var point := _find_structure_approach(unit, fort.position, fort.obstacle,
			fort.unit_attack_range(unit.definition.range))
		if not point.is_finite():
			continue
		if destination.is_finite() and not navigation.reachable_without_obstacle(
				unit.position, destination, unit.definition.clearance, fort.obstacle):
			continue
		nearest = distance
		result = {"id": fort.id, "point": point}
	return result


func _plan_local_engagement(unit: Unit, units: Array[Unit], radius: float, holding: bool) -> bool:
	var selected: Unit
	var best_distance := INF
	var best_priority := INF
	var weapon_range: float = unit.definition.range
	var best_route := PackedVector2Array()
	for opponent in units:
		if opponent.side != _opponent(unit.side) or opponent.hp <= 0.0:
			continue
		var distance := unit.position.distance_squared_to(opponent.position)
		if distance > radius * radius:
			continue
		var priority := 0.0
		if holding and target_priority == TargetPriority.LOWEST_HP:
			priority = opponent.hp
		elif not holding and unit.stance == Stance.SEEK_STRONGEST:
			var dps := stats.value(opponent.side, FactionStats.UNIT_DPS, _base_dps(opponent))
			priority = -(threat_weights.x * dps + threat_weights.y * opponent.hp)
		if selected != null and (priority > best_priority or (priority == best_priority and (
				distance > best_distance or (distance == best_distance and opponent.id > selected.id)))):
			continue
		var can_fire := distance <= (weapon_range + RANGE_EPSILON) ** 2 \
			and navigation.line_clear(unit.position, opponent.position)
		var route := PackedVector2Array()
		if not can_fire:
			if holding:
				continue
			route = _unit_navigation(unit).path(unit.position, opponent.position)
			if route.is_empty():
				route = _find_attack_route(unit, opponent.position, -1, weapon_range)
			if route.is_empty():
				continue
		selected = opponent
		best_priority = priority
		best_distance = distance
		best_route = route
	if selected == null:
		return false
	if best_route.is_empty():
		return _aim_at(unit, selected.id, selected.position)
	unit.target = selected.id
	_set_route(unit, best_route[-1], best_route)
	return true


func _plan_strategic_approach(unit: Unit, opponent: MatchRegion.Owner) -> void:
	var weapon_range: float = unit.definition.range
	unit.strategic_revision = navigation.revision
	unit.strategic_target = BASE_TARGET
	var nearest := INF
	for outpost in _outposts.values():
		var distance := unit.position.distance_squared_to(outpost.position)
		if outpost.side == unit.side or distance >= nearest:
			continue
		var destination := _find_structure_approach(unit, outpost.position,
			outpost.obstacle, weapon_range + OUTPOST_ATTACK_RANGE - UNIT_ATTACK_RANGE)
		if destination.is_finite():
			nearest = distance
			unit.strategic_target = outpost.id
			unit.strategic_destination = destination
	if unit.strategic_target == BASE_TARGET:
		unit.strategic_destination = _find_structure_approach(unit, _bases[opponent],
			_base_obstacles[opponent], weapon_range + BASE_ATTACK_RANGE - UNIT_ATTACK_RANGE)


func _can_attack_structure(position: Vector2, center: Vector2, obstacle: int,
		attack_range: float) -> bool:
	return position.distance_squared_to(center) <= (attack_range + RANGE_EPSILON) ** 2 \
		and navigation.is_passable(position) \
		and navigation.line_clear(position, center, obstacle)


func _find_structure_approach(unit: Unit, center: Vector2, obstacle: int,
		attack_range: float) -> Vector2:
	var route := _find_attack_route(unit, center, obstacle, attack_range)
	return route[-1] if not route.is_empty() else Vector2.INF


func _find_attack_route(unit: Unit, center: Vector2, obstacle: int,
		attack_range: float) -> PackedVector2Array:
	var outward := center.direction_to(unit.position)
	if outward.is_zero_approx():
		outward = Vector2.RIGHT
	var best := PackedVector2Array()
	var best_length := INF
	var routes := _unit_navigation(unit)
	for i in range(STRATEGIC_SAMPLE_COUNT):
		var candidate := center + outward.rotated(TAU * i / STRATEGIC_SAMPLE_COUNT) * attack_range
		if not _can_attack_structure(candidate, center, obstacle, attack_range):
			continue
		var route := routes.path(unit.position, candidate)
		if route.is_empty():
			continue
		# The direct radial approach is the shortest possible route.
		if i == 0 and route.size() == 1:
			return route
		var length := 0.0
		var previous := unit.position
		for point in route:
			length += previous.distance_to(point)
			previous = point
		if length < best_length:
			best = route
			best_length = length
	return best


func _unit_navigation(unit: Unit) -> BattleNavigation:
	return navigation.with_clearance(unit.definition.clearance)


func _route_to(unit: Unit, destination: Vector2) -> void:
	if unit.movement_destination != destination or unit.route_revision != navigation.revision:
		_set_route(unit, destination, _unit_navigation(unit).path(unit.position, destination))


func _set_route(unit: Unit, destination: Vector2, route: PackedVector2Array) -> void:
	unit.movement_destination = destination
	unit.waypoints = route
	unit.route_revision = navigation.revision


func _clear_route(unit: Unit) -> void:
	_set_route(unit, Vector2.INF, PackedVector2Array())


func _move(unit: Unit) -> void:
	var remaining := stats.value(unit.side, FactionStats.UNIT_SPEED, unit.definition.speed) * STEP
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
		if unit.resume_stance_on_arrival:
			_resume_stance(unit)
		else:
			unit.order = Order.HOLD


func _add_footprint(center: Vector2, half_size: Vector2) -> int:
	return navigation.add_obstacle(_footprint(center, half_size))


static func _footprint(center: Vector2, half_size: Vector2) -> Rect2:
	return Rect2(center - half_size, half_size * 2.0)


static func _opponent(side: MatchRegion.Owner) -> MatchRegion.Owner:
	return CPU if side == PLAYER else PLAYER
