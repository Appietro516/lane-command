class_name MatchBattle
extends RefCounted

signal unit_produced(unit: Unit)
signal unit_removed(unit_id: int)
signal attack_resolved(attack: AttackResolved)
signal healing_resolved(heal: AttackResolved)
signal step_finished
signal base_destroyed(side: MatchRegion.Owner)
signal outpost_destroyed(outpost: Outpost)
signal fortification_destroyed(fortification: Fortification)
signal fortification_fired(fortification: Fortification, impact: Vector2)
signal missile_launched(silo: MissileSilo, flight: MissileFlight)
signal missile_cancelled(side: MatchRegion.Owner)
signal missile_impact(flight: MissileFlight)

const UnitCatalog := preload("res://match/unit_catalog.gd")
const Fortifications := preload("res://match/fortification_rules.gd")

enum MissileState { READY, CHARGING, EXHAUSTED }
enum Outcome { IN_PROGRESS, VICTORY, DEFEAT }
enum Order { AUTONOMOUS, MOVE, HOLD, ATTACK }
enum Stance { SEEK_NEAREST, SEEK_STRONGEST, IDLE }
enum TargetPriority { NEAREST, LOWEST_HP }

const PLAYER := MatchRegion.Owner.PLAYER
const CPU := MatchRegion.Owner.CPU
const INFANTRY := UnitCatalog.DEFINITIONS[UnitCatalog.INFANTRY]
const UNIT_HP := INFANTRY.hp
const BASE_HP := 420
const ATTACK_DAMAGE := INFANTRY.damage
const ATTACK_COOLDOWN := INFANTRY.cooldown
const MOVEMENT_SPEED := INFANTRY.speed
const UNIT_ATTACK_RANGE := INFANTRY.range
const BASE_ATTACK_RANGE := 1.8
const DEFAULT_BOUNDS := Rect2(-15.0, -9.0, 30.0, 18.0)
const DEFAULT_AGGRO_RADIUS := 4.0
const DEFAULT_THREAT_WEIGHTS := Vector2(2.0, 0.25)
const MILITARY_UNIT_CAP := 48
const LOCAL_REPATH_INTERVAL := 0.12
const LOCAL_ROUTE_PROBES := 4
const FORMATION_ROUTES_PER_STEP := 4
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
const DEFAULT_OUTPOST_HP := 40
const BASE_GUN := {"range": 4.25, "damage": 6.0, "interval": 0.9, "splash": 0.0}
const OUTPOST_GUN := {"range": 3.4, "damage": 2.5, "interval": 1.15, "splash": 0.0}
const HUB_ARMOR := 0.55
const BASE_ARMOR := 0.40
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
	var position: Vector2:
		set(value):
			if _grid != null and not _cell_bounds.has_point(value):
				_grid.erase(id, _cell, side)
				_set_cell(value)
				_grid.insert(id, _cell, side)
			position = value
			if _visibility != null:
				_visibility.move_registered_source(id, _vision_source, value)
	var _visibility: BattleVisibility
	var _vision_source: BattleVisibility.Source
	var _grid: BattleSpatialGrid
	var _cell: Vector2i
	var _cell_bounds: Rect2
	var heading := Vector2.RIGHT
	var stance := Stance.IDLE
	var order := Order.AUTONOMOUS
	var resume_stance_on_arrival := false
	var following_rally := false
	var support_replan_at := 0.0
	var next_healing_at := 0.0
	var support_scan_at := 0.0
	var ordered_destination := Vector2.INF
	var movement_destination := Vector2.INF
	var waypoints := PackedVector2Array()
	var route_revision := -1
	var strategic_destination := Vector2.INF
	var strategic_target := BASE_TARGET
	var strategic_base := MatchRegion.Owner.NEUTRAL
	var strategic_revision := -1
	var strategic_sites_revision := -1
	var chase_target := NO_TARGET
	var chase_repath_at := 0.0
	var blocked_revision := -1
	var blocked_objective := Vector2.INF
	var wall_approach: Dictionary
	var hp: float
	var step_distance: float
	var target := NO_TARGET
	var target_base := MatchRegion.Owner.NEUTRAL
	var attack_order_id := NO_TARGET
	var attack_order_side := MatchRegion.Owner.NEUTRAL
	var attack_order_point := Vector2.INF
	var attack_order_repath_at := 0.0
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
		step_distance = definition.speed * STEP
		side = owner
		position = spawn_position


	func _set_cell(point: Vector2) -> void:
		_cell = BattleSpatialGrid.cell_at(point)
		_cell_bounds = Rect2(Vector2(_cell) * BattleSpatialGrid.CELL_SIZE,
			Vector2.ONE * BattleSpatialGrid.CELL_SIZE)


## Position snapshots are in map coordinates at the attack step, before movement.
## BASE_TARGET marks a starting base. target_side identifies the one hit.
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
	var local_health_factor := 1.0
	var destroyed_by_missile := false
	var max_hp: float:
		get:
			return _stats.value(side, FactionStats.BUILDING_MAX_HP, base_max_hp * local_health_factor)
	var _stats: FactionStats

	func _init(stats: FactionStats, owner: MatchRegion.Owner, base_health: float) -> void:
		_stats = stats
		side = owner
		base_max_hp = base_health
		hp = max_hp

	func health_stat() -> Dictionary:
		return _stats.inspect(side, FactionStats.BUILDING_MAX_HP, base_max_hp * local_health_factor)


class Outpost extends BuildingHealth:
	var id: int
	var region_id: StringName
	var position: Vector2
	var obstacle: int
	var gun: Fortification


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


class MissileSilo extends Fortification:
	var missile_state := MissileState.READY
	var missile_target := Vector2.INF
	var launches_at := 0.0


class MissileFlight:
	var source: Vector2
	var target: Vector2
	var side: MatchRegion.Owner
	var started_at: float
	var impact_at: float


class ProductionTimer extends Fortification:
	var elapsed := 0.0
	var unit_type: StringName
	var default_stance := Stance.IDLE
	var rally_point := Vector2.INF
	var level := 1

	func interval(economy: MatchEconomy) -> float:
		return cycle_interval(economy, level)

	func cycle_interval(economy: MatchEconomy, production_level: int) -> float:
		var base: float = profile.interval
		if production_level == 2:
			base *= MatchEconomy.PRODUCTION_UPGRADE_FACTOR
		return economy.stats.value(side, FactionStats.BARRACKS_INTERVAL, base) if kind == &"barracks" else base

	func production_stat(economy: MatchEconomy) -> Dictionary:
		return economy.production_stat(side, active, profile.interval, kind == &"barracks", level == 2)

	func spawn_extent() -> Vector2:
		return MatchBattle.producer_spawn_extent(profile.size, unit_type)


var stats: FactionStats
var aggro_radius: float
## Defensive shot priority for Hold. Autonomous pursuit uses the unit's stance.
var target_priority := TargetPriority.NEAREST
## Threat score = effective DPS * weight.x + current HP * weight.y.
var threat_weights := DEFAULT_THREAT_WEIGHTS
var navigation: BattleNavigation
var visibility: BattleVisibility
var radar := BattleRadar.new()
var objectives := NeutralObjectives.new()
var _bases: Dictionary[MatchRegion.Owner, Vector2] = {}
var _base_obstacles: Dictionary[MatchRegion.Owner, int] = {}
var _base_guns: Dictionary[MatchRegion.Owner, Fortification] = {}
var _base_health: Dictionary[MatchRegion.Owner, BuildingHealth] = {}
var _timers: Array[ProductionTimer] = []
var _units: Dictionary[int, Unit] = {}
var _support_units: Dictionary[int, Unit] = {}
var _queued_orders: Dictionary[int, Dictionary] = {}
var _military_count: Dictionary[MatchRegion.Owner, int] = {}
var _unit_grid := BattleSpatialGrid.new()
var _structure_grid := BattleSpatialGrid.new()
var _structure_extent := OUTPOST_ATTACK_RANGE - UNIT_ATTACK_RANGE
var _candidate_ids: Array[int] = []
var _nearby_cache: Dictionary[Vector4i, Array] = {}
var _hold_targets: Dictionary[Vector4, int] = {}
var _outposts: Dictionary[int, Outpost] = {}
var _fortifications: Dictionary[int, Fortification] = {}
var _landmark_footprints: Dictionary[Rect2, int] = {}
var _charging_silos: Dictionary[int, MissileSilo] = {}
var _missile_threats: Dictionary[MatchRegion.Owner, float] = {}
var protected_starting_regions: Array[PackedVector2Array] = []
var _missile_flights: Array[MissileFlight] = []
var _next_structure_id := BASE_TARGET - 1
var _next_unit_id := 1
var _pending_time := 0.0
var _elapsed_time := 0.0
var _combat_step := 0
var _strategic_sites_revision := 0
var _outcome := Outcome.IN_PROGRESS


func _init(player_base: Vector2, cpu_base: Vector2, detection_radius := DEFAULT_AGGRO_RADIUS,
		bounds := DEFAULT_BOUNDS, faction_stats: FactionStats = null,
		starting_bases: Dictionary[MatchRegion.Owner, Vector2] = {},
		boundary := PackedVector2Array()) -> void:
	stats = faction_stats if faction_stats != null else FactionStats.new()
	aggro_radius = detection_radius
	navigation = BattleNavigation.new(bounds, boundary)
	if starting_bases.is_empty():
		_bases[PLAYER] = player_base
		_bases[CPU] = cpu_base
	else:
		_bases.assign(starting_bases)
	for side in _bases:
		_military_count[side] = 0
		var building := BuildingHealth.new(stats, side, BASE_HP)
		building.source_id = StringName("base/%d" % side)
		_base_health[side] = building
		_base_obstacles[side] = _add_footprint(_bases[side], BASE_FOOTPRINT)
		_base_guns[side] = _hub_gun(side, _bases[side], _base_obstacles[side], BASE_GUN)
	stats.stat_changed.connect(_on_stat_changed)


func enable_visibility(bounds: Rect2, interval := BattleVisibility.UPDATE_INTERVAL) -> void:
	visibility = BattleVisibility.new(bounds)
	visibility.interval = interval
	for side in _base_obstacles:
		visibility.set_source(_base_vision_id(side), side, _bases[side], BattleVisibility.BASE_RADIUS)
	for unit in _units.values():
		_register_unit_vision(unit)
	for outpost in _outposts.values():
		visibility.set_source(outpost.id, outpost.side, outpost.position, BattleVisibility.OUTPOST_RADIUS)
	for structure in _fortifications.values():
		if structure.active:
			_register_structure_vision(structure)
	visibility.advance(_elapsed_time)


static func _base_vision_id(side: MatchRegion.Owner) -> int:
	return -1000000000 - side


func can_see(side: MatchRegion.Owner, point: Vector2) -> bool:
	return visibility == null or side == MatchRegion.Owner.NEUTRAL or visibility.can_see(side, point)


func can_observe_unit(side: MatchRegion.Owner, unit: Unit) -> bool:
	return unit.side == side or can_see(side, unit.position)


func visible_units(side: MatchRegion.Owner) -> Array[Unit]:
	var observed: Array[Unit] = []
	for unit in _units.values():
		if unit.hp > 0.0 and can_observe_unit(side, unit):
			observed.append(unit)
	return observed


func _register_unit_vision(unit: Unit) -> void:
	if visibility == null or unit.side == MatchRegion.Owner.NEUTRAL:
		return
	unit._visibility = visibility
	var radius := BattleVisibility.SCOUT_RADIUS if unit.type_id == UnitCatalog.SCOUT else BattleVisibility.UNIT_RADIUS
	unit._vision_source = visibility.set_source(unit.id, unit.side, unit.position, radius, false)


func _register_structure_vision(fort: Fortification) -> void:
	if visibility != null:
		var radius: float = fort.profile.get("vision", maxf(BattleVisibility.STRUCTURE_RADIUS,
			float(fort.profile.get("range", 0.0))))
		visibility.set_source(fort.id, fort.side, fort.position, radius)


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
	outpost.gun = _hub_gun(side, position, outpost.obstacle, OUTPOST_GUN)
	_outposts[outpost.id] = outpost
	_strategic_sites_revision += 1
	_structure_grid.insert(outpost.id, BattleSpatialGrid.cell_at(position), 0)
	if visibility != null:
		visibility.set_source(outpost.id, side, position, BattleVisibility.OUTPOST_RADIUS)
	return outpost


func get_outpost(id: int) -> Outpost:
	return _outposts.get(id)


func add_fortification(kind: StringName, side: MatchRegion.Owner, position: Vector2,
		angle := 0.0) -> Fortification:
	return add_structure(kind, Fortifications.PROFILES[kind], side, position, angle)


func add_structure(kind: StringName, profile: Dictionary, side: MatchRegion.Owner,
		position: Vector2, angle := 0.0) -> Fortification:
	var fort: Fortification
	if kind == Fortifications.SILO:
		fort = MissileSilo.new(stats, side, profile.hp)
	else:
		fort = Fortification.new(stats, side, profile.hp)
	_register_structure(fort, kind, profile, position, angle)
	return fort


func prepare_missile(side: MatchRegion.Owner, id: int, target: Vector2) -> bool:
	var silo := get_fortification(id) as MissileSilo
	if is_finished() or not is_side_active(side) or silo == null or silo.side != side \
			or silo.hp <= 0.0 or not silo.active or silo.missile_state != MissileState.READY \
			or not navigation.contains(target):
		return false
	silo.missile_state = MissileState.CHARGING
	silo.missile_target = target
	silo.launches_at = _elapsed_time + Fortifications.MISSILE_CHARGE
	_charging_silos[id] = silo
	_missile_threats[side] = _elapsed_time + Fortifications.RETALIATION_DURATION
	_strategic_sites_revision += 1
	return true


func public_missile_launches() -> Dictionary[int, Dictionary]:
	var announcements: Dictionary[int, Dictionary] = {}
	for id in _charging_silos:
		var silo := _charging_silos[id]
		announcements[id] = {"side": silo.side, "point": silo.position, "launches_at": silo.launches_at}
	return announcements


func missile_protected(point: Vector2) -> bool:
	for polygon in protected_starting_regions:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func retaliation_target(side: MatchRegion.Owner, origin: Vector2) -> MatchRegion.Owner:
	var best := MatchRegion.Owner.NEUTRAL
	var distance := INF
	for rival in _missile_threats:
		if rival == side or not is_side_active(rival) or _elapsed_time >= _missile_threats[rival]:
			continue
		var candidate := origin.distance_squared_to(_bases[rival])
		if candidate < distance or (candidate == distance and rival < best):
			distance = candidate
			best = rival
	return best


func _advance_missiles() -> void:
	while not _missile_flights.is_empty() and _elapsed_time + TIME_EPSILON >= _missile_flights[0].impact_at:
		_resolve_missile(_missile_flights.pop_front())
	for id in _charging_silos.keys():
		var silo := _charging_silos[id]
		if silo.hp <= 0.0 or base_hp(silo.side) <= 0.0 or not silo.active:
			_charging_silos.erase(id)
			silo.missile_state = MissileState.EXHAUSTED
			missile_cancelled.emit(silo.side)
		elif _elapsed_time + TIME_EPSILON >= silo.launches_at:
			_charging_silos.erase(id)
			silo.missile_state = MissileState.EXHAUSTED
			var flight := MissileFlight.new()
			flight.source = silo.position
			flight.target = silo.missile_target
			flight.side = silo.side
			flight.started_at = _elapsed_time
			flight.impact_at = _elapsed_time + Fortifications.MISSILE_FLIGHT
			_missile_flights.append(flight)
			missile_launched.emit(silo, flight)


func _resolve_missile(flight: MissileFlight) -> void:
	var target := flight.target
	var reach := ceili(Fortifications.MISSILE_RADIUS / BattleSpatialGrid.CELL_SIZE)
	var cell := BattleSpatialGrid.cell_at(target)
	_candidate_ids.clear()
	for side in _bases:
		_unit_grid.append_ids(cell, reach, side, _candidate_ids)
	for id in _candidate_ids:
		var unit := get_unit(id)
		if target.distance_squared_to(unit.position) <= Fortifications.MISSILE_RADIUS ** 2 \
				and not missile_protected(unit.position):
			unit.hp = 0.0
	for outpost in _outposts.values():
		if not missile_protected(outpost.position) and Fortifications.blast_hits(target, outpost.position, OUTPOST_FOOTPRINT * 2.0):
			_destroy_in_blast(outpost)
	for fort: Fortification in _fortifications.values():
		if not missile_protected(fort.position) and Fortifications.blast_hits(target, fort.position, fort.profile.size, fort.angle):
			_destroy_in_blast(fort)
	missile_impact.emit(flight)


static func _destroy_in_blast(building: BuildingHealth) -> void:
	if building.hp > 0.0:
		building.hp = 0.0
		building.destroyed_by_missile = true


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
	_structure_extent = maxf(_structure_extent, profile.size.length() * 0.5)
	_structure_grid.insert(fort.id, BattleSpatialGrid.cell_at(position), 0)
	set_fortification_active(fort, true)


func get_fortification(id: int) -> Fortification:
	return _fortifications.get(id)


## Configure an owned producer, including one paused by loss of territory.
func set_producer_stance(side: MatchRegion.Owner, id: int, stance: Stance) -> bool:
	var timer := get_fortification(id) as ProductionTimer
	if is_finished() or not is_side_active(side) or timer == null or timer.side != side \
			or timer.hp <= 0.0 or not Stance.values().has(stance):
		return false
	timer.default_stance = stance
	return true


func upgrade_producer(side: MatchRegion.Owner, id: int, economy: MatchEconomy) -> bool:
	var timer := get_fortification(id) as ProductionTimer
	if is_finished() or timer == null or timer.side != side or timer.hp <= 0.0 or timer.level != 1:
		return false
	if not economy.try_spend(side, MatchEconomy.UPGRADE_COST):
		return false
	timer.level = 2
	return true


## Infinity clears a producer's rally. Finite points must be reachable from its exit.
func set_producer_rally(side: MatchRegion.Owner, id: int, point: Vector2) -> bool:
	var timer := get_fortification(id) as ProductionTimer
	if is_finished() or not is_side_active(side) or timer == null or timer.side != side or timer.hp <= 0.0:
		return false
	if point == timer.rally_point:
		return true
	if point != Vector2.INF:
		var direction := timer.position.direction_to(point)
		var spawn := _spawn_position(timer, direction)
		var clearance: float = UnitCatalog.DEFINITIONS[timer.unit_type].clearance
		if navigation.with_clearance(clearance).path(spawn, point).is_empty():
			return false
	timer.rally_point = point
	return true


func set_fortification_active(fort: Fortification, active: bool) -> void:
	if fort.active == active or not _fortifications.has(fort.id):
		return
	fort.active = active
	if active:
		if fort.kind == BattleRadar.RADAR:
			radar.register_radar(fort.id, fort.side)
		_register_structure_vision(fort)
		fort.obstacle = navigation.add_obstacle(_footprint(fort.position, fort.profile.size * 0.5), fort.angle)
	else:
		if fort.kind == BattleRadar.RADAR:
			radar.disable_radar(fort.id)
		if visibility != null:
			visibility.remove_source(fort.id)
		navigation.remove_obstacle(fort.obstacle)
		fort.obstacle = -1
	stats.set_source_active(fort.source_id, active)


func add_landmark_footprint(footprint: Rect2) -> void:
	_landmark_footprints[footprint] = navigation.add_obstacle(footprint)


func remove_landmark_footprint(footprint: Rect2) -> bool:
	if not _landmark_footprints.has(footprint):
		return false
	navigation.remove_obstacle(_landmark_footprints[footprint])
	_landmark_footprints.erase(footprint)
	return true


func fortification_site_clear(polygon: PackedVector2Array, include_hubs := true) -> bool:
	if not navigation.contains_footprint(polygon):
		return false
	for footprint in _landmark_footprints:
		if not Geometry2D.intersect_polygons(polygon, BattleNavigation.corners_of(footprint)).is_empty():
			return false
	if include_hubs:
		for side in _base_obstacles:
			var center := _bases[side]
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
	var exits := BattleNavigation.corners_of(exit_area)
	if not navigation.contains_footprint(exits):
		return false
	var footprint := Fortifications.footprint(position, profile.size)
	if not fortification_site_clear(footprint):
		return false
	for rect in _landmark_footprints:
		if rect.intersects(exit_area):
			return false
	for side in _base_obstacles:
		var center := _bases[side]
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
	for side in _base_obstacles:
		var center := _bases[side]
		if footprint.intersects(_footprint(center, BASE_FOOTPRINT)):
			return false
	for outpost in _outposts.values():
		if footprint.intersects(_footprint(outpost.position, OUTPOST_FOOTPRINT)):
			return false
	return fortification_site_clear(BattleNavigation.corners_of(footprint), false)


## Deploy a catalog unit for either faction. Pass an economy for paid production.
## Invalid spawns leave Food and unit IDs untouched.
func spawn_unit(side: MatchRegion.Owner, position: Vector2,
		type_id := UnitCatalog.INFANTRY, economy: MatchEconomy = null,
		stance := Stance.IDLE) -> Unit:
	if type_id not in UnitCatalog.COMBAT_TYPES or not Stance.values().has(stance):
		return null
	return _spawn_unit(side, position, type_id, economy, stance)


func spawn_neutral_guard(point: Vector2, major: bool) -> Unit:
	if not navigation.is_passable(point):
		return null
	var type := UnitCatalog.STRONGHOLD_GUARD if major else UnitCatalog.CAMP_GUARD
	var unit := Unit.new(_next_unit_id, MatchRegion.Owner.NEUTRAL, point, type)
	_index_unit(unit)
	_units[unit.id] = unit
	_next_unit_id += 1
	unit_produced.emit(unit)
	return unit


func _spawn_unit(side: MatchRegion.Owner, position: Vector2, type_id: StringName,
		economy: MatchEconomy = null, stance := Stance.IDLE) -> Unit:
	var definition: Dictionary = UnitCatalog.DEFINITIONS.get(type_id, {})
	if is_finished() or not is_side_active(side) or definition.is_empty():
		return null
	if type_id != UnitCatalog.SCOUT and _military_count[side] >= MILITARY_UNIT_CAP:
		return null
	if not navigation.with_clearance(definition.clearance).is_passable(position):
		return null
	if economy != null and not economy.try_spend(side, {MatchEconomy.FOOD: definition.food}):
		return null
	var unit := Unit.new(_next_unit_id, side, position, type_id)
	unit.stance = stance
	unit.hp = _unit_max_hp(unit)
	unit.heading = position.direction_to(_bases[nearest_hostile_base(side, position)])
	if type_id != UnitCatalog.SCOUT:
		_military_count[side] += 1
	_index_unit(unit)
	_units[unit.id] = unit
	_next_unit_id += 1
	unit_produced.emit(unit)
	return unit


func _index_unit(unit: Unit) -> void:
	unit.step_distance = stats.value(unit.side, FactionStats.UNIT_SPEED, unit.definition.speed) * STEP
	_register_unit_vision(unit)
	unit._grid = _unit_grid
	unit._set_cell(unit.position)
	_unit_grid.insert(unit.id, unit._cell, unit.side)
	if unit.definition.has("support"):
		_support_units[unit.id] = unit


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
		if unit.definition.damage <= 0.0 or not routes.is_passable(destination):
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


## Focus a currently visible enemy. Loss of sight leaves only the last observed point.
func order_attack(side: MatchRegion.Owner, id: int, target_id: int,
		base_side := MatchRegion.Owner.NEUTRAL) -> bool:
	var unit := _commandable_unit(side, id)
	if unit == null or unit.definition.damage <= 0.0:
		return false
	var observation := _attack_observation(side, target_id, base_side, unit.definition.range)
	if observation.is_empty():
		return false
	_queued_orders.erase(id)
	_set_order(unit, Order.ATTACK, observation.point, PackedVector2Array())
	unit.attack_order_id = target_id
	unit.attack_order_side = base_side
	unit.attack_order_point = observation.point
	unit.attack_order_repath_at = 0.0
	return true


func _attack_observation(side: MatchRegion.Owner, target_id: int, base_side: MatchRegion.Owner,
		weapon_range: float) -> Dictionary:
	if target_id == BASE_TARGET:
		if base_side != side and is_side_active(base_side) and can_see(side, _bases[base_side]):
			return {"point": _bases[base_side], "obstacle": _base_obstacles[base_side],
				"range": weapon_range + BASE_ATTACK_RANGE - UNIT_ATTACK_RANGE}
	elif target_id > NO_TARGET:
		var target := get_unit(target_id)
		if target != null and target.hp > 0.0 and target.side != side and can_observe_unit(side, target):
			return {"point": target.position, "obstacle": -1, "range": weapon_range}
	else:
		var fort := get_fortification(target_id)
		if fort != null and fort.hp > 0.0 and fort.side != side and can_see(side, fort.position):
			return {"point": fort.position, "obstacle": fort.obstacle, "range": fort.unit_attack_range(weapon_range)}
		var outpost := get_outpost(target_id)
		if outpost != null and outpost.hp > 0.0 and outpost.side != side and can_see(side, outpost.position):
			return {"point": outpost.position, "obstacle": outpost.obstacle,
				"range": weapon_range + OUTPOST_ATTACK_RANGE - UNIT_ATTACK_RANGE}
	return {}


func _plan_attack_order(unit: Unit) -> bool:
	var observation := _attack_observation(unit.side, unit.attack_order_id, unit.attack_order_side,
		unit.definition.range)
	if observation.is_empty():
		if can_see(unit.side, unit.attack_order_point) or unit.position.distance_squared_to(unit.attack_order_point) < 1.0:
			_resume_stance(unit)
		else:
			_route_to(unit, unit.attack_order_point)
		return false

	var point: Vector2 = observation.point
	unit.attack_order_point = point
	if _can_attack_structure(unit.position, point, observation.obstacle, observation.range):
		unit.target_base = unit.attack_order_side
		return _aim_at(unit, unit.attack_order_id, point)
	if _elapsed_time < unit.attack_order_repath_at:
		return false
	unit.attack_order_repath_at = _elapsed_time + 0.24
	var route := _find_attack_route(unit, point, observation.obstacle, observation.range)
	if not route.is_empty():
		_set_route(unit, route[-1], route)
	return false


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


## Assign formation slots immediately and stagger route searches across fixed steps.
func order_formation(side: MatchRegion.Owner, ids: Array, destination: Vector2,
		order: Order, resume_stance: bool) -> int:
	if not navigation.contains(destination) or order not in [Order.MOVE, Order.HOLD]:
		return 0
	var members: Array[Unit] = []
	var center := Vector2.ZERO
	var spacing := 0.6
	for id in ids:
		var unit := _commandable_unit(side, id)
		if unit == null or (order == Order.HOLD and unit.type_id == UnitCatalog.SCOUT):
			continue
		members.append(unit)
		center += unit.position
		spacing = maxf(spacing, float(unit.definition.clearance) * 2.0 + 0.35)
	if members.is_empty():
		return 0
	var forward := (center / members.size()).direction_to(destination)
	if forward.is_zero_approx():
		forward = Vector2.UP
	var right := forward.orthogonal()
	members.sort_custom(func(a: Unit, b: Unit) -> bool:
		var across_a := a.position.dot(right)
		var across_b := b.position.dot(right)
		return a.id < b.id if across_a == across_b else across_a < across_b)
	var slots: Array[Vector2] = [destination]
	var rings := maxi(3, ceili(sqrt(members.size() * 0.5)))
	for ring in range(1, rings + 1):
		for index in 8 * ring:
			var angle := TAU * index / (8 * ring)
			slots.append(destination + (right * cos(angle) + forward * sin(angle)) * spacing * ring)
	# Choose the nearest available slot to each unit's offset across the formation.
	var assigned := 0
	var columns := ceili(sqrt(members.size()))
	for index in members.size():
		var unit := members[index]
		var desired := destination + right * spacing * clampf((index - (members.size() - 1) * 0.5)
			/ columns, -columns * 0.5, columns * 0.5)
		var routes := _unit_navigation(unit)
		var best := -1
		var distance := INF
		for candidate in slots.size():
			var score := desired.distance_squared_to(slots[candidate])
			if score < distance and routes.is_passable(slots[candidate]):
				best = candidate
				distance = score
		if best < 0:
			continue
		_queued_orders[unit.id] = {"point": slots[best], "order": order, "resume": resume_stance,
			"rally": false}
		slots.remove_at(best)
		assigned += 1
	return assigned


func _process_queued_orders() -> void:
	var budget := FORMATION_ROUTES_PER_STEP
	for id in _queued_orders.keys():
		var request := _queued_orders[id]
		_queued_orders.erase(id)
		var unit := get_unit(id)
		if unit == null or _commandable_unit(unit.side, id) == null:
			continue
		var route := _unit_navigation(unit).path(unit.position, request.point)
		if not route.is_empty():
			_set_order(unit, request.order, request.point, route)
			unit.resume_stance_on_arrival = request.resume
			unit.following_rally = request.rally
		budget -= 1
		if budget == 0:
			break


func _commandable_unit(side: MatchRegion.Owner, id: int) -> Unit:
	var unit := get_unit(id)
	if is_finished() or unit == null or unit.side != side or unit.scout_committed or unit.hp <= 0.0:
		return null
	return unit


func _order_move(unit: Unit, destination: Vector2, route: PackedVector2Array) -> void:
	_set_order(unit, Order.MOVE, destination, route)


func _set_order(unit: Unit, order: Order, destination: Vector2, route: PackedVector2Array) -> void:
	_queued_orders.erase(unit.id)
	unit.following_rally = false
	unit.chase_target = NO_TARGET
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


func is_side_active(side: MatchRegion.Owner) -> bool:
	return _base_obstacles.has(side)


func nearest_hostile_base(side: MatchRegion.Owner, position: Vector2) -> MatchRegion.Owner:
	var nearest := MatchRegion.Owner.NEUTRAL
	var distance := INF
	for hostile in _base_obstacles:
		if hostile == side:
			continue
		var candidate := position.distance_squared_to(_bases[hostile])
		if candidate < distance:
			nearest = hostile
			distance = candidate
	return nearest


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
	if stat == FactionStats.UNIT_SPEED:
		for unit in _units.values():
			unit.step_distance = stats.value(unit.side, stat, unit.definition.speed) * STEP
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
		_step_combat(economy)
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
		if not timer.active or timer.hp <= 0.0 or not is_side_active(timer.side):
			continue
		# Upgrades shorten the current cycle while keeping elapsed production time.
		var interval := timer.interval(economy)
		timer.elapsed += delta
		while timer.active and timer.hp > 0.0 and timer.elapsed + TIME_EPSILON >= interval:
			if _military_count[timer.side] >= MILITARY_UNIT_CAP:
				timer.elapsed = interval
				break
			timer.elapsed = maxf(0.0, timer.elapsed - interval)
			var hostile := nearest_hostile_base(timer.side, timer.position)
			var goal := timer.rally_point if timer.rally_point.is_finite() else _bases[hostile]
			var direction := timer.position.direction_to(goal)
			var position := _spawn_position(timer, direction)
			var unit := spawn_unit(timer.side, position, timer.unit_type, economy, timer.default_stance)
			if unit == null:
				timer.elapsed = interval
				break
			if timer.rally_point.is_finite():
				_queued_orders[unit.id] = {"point": timer.rally_point, "order": Order.MOVE,
					"resume": true, "rally": true}


func _spawn_position(timer: ProductionTimer, direction: Vector2) -> Vector2:
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
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


func deploy_decoy(side: MatchRegion.Owner, station_id: int, point: Vector2) -> bool:
	var station := get_fortification(station_id)
	return not is_finished() and station != null and station.side == side \
		and station.kind == BattleRadar.COUNTERINTELLIGENCE and station.active and station.hp > 0.0 \
		and navigation.contains(point) and radar.deploy(side, station_id, point, _elapsed_time)


func _step_combat(economy: MatchEconomy) -> void:
	# Plan against the same positions before either side moves or takes damage.
	_process_queued_orders()
	var units := active_units()
	var attacks: Array[Unit] = []
	_combat_step += 1
	var stagger_pursuit := _bases.size() > 2
	var stagger_garrisons := units.size() >= 96
	if _unit_grid.count != units.size():
		for unit in units:
			if unit._grid == null:
				_index_unit(unit)
	for side in _missile_threats.keys():
		if _elapsed_time >= _missile_threats[side]:
			_missile_threats.erase(side)
			_strategic_sites_revision += 1
	for unit in units:
		unit.cooldown = maxf(0.0, unit.cooldown - STEP)
		if unit.hp <= 0.0:
			continue
		# In large battles, refresh stationary target searches in four phases.
		# A defender with a target still replans immediately when its weapon is ready.
		var stationary := (unit.order == Order.HOLD and unit.position == unit.ordered_destination) \
			or (unit.order == Order.AUTONOMOUS and unit.stance == Stance.IDLE)
		if stagger_garrisons and stationary and (unit.id + _combat_step) % 4 != 0 \
				and (unit.target == NO_TARGET or unit.cooldown > TIME_EPSILON):
			continue
		if unit.order == Order.MOVE and unit.target == NO_TARGET \
				and unit.route_revision == navigation.revision \
				and unit.movement_destination == unit.ordered_destination \
				and not unit.waypoints.is_empty():
			continue
		# Established autonomous targets can reuse their last plan for one step.
		# Movement still steps at 60 Hz and every shot rechecks range and sight.
		if stagger_pursuit and (unit.id + _combat_step) % 2 == 0 \
				and unit.order == Order.AUTONOMOUS and unit.target != NO_TARGET \
				and unit.route_revision == navigation.revision \
				and (not unit.can_attack_target or unit.cooldown > TIME_EPSILON):
			continue
		unit.can_attack_target = _plan_turn(unit, units)
		if unit.can_attack_target and unit.cooldown <= TIME_EPSILON:
			attacks.append(unit)

	_fire_fortifications(units)
	_nearby_cache.clear()
	_hold_targets.clear()
	# Attacks committed while alive still resolve if the attacker falls this step.
	# Resolve against the same positions used to authorize range and facing.
	var report_attacks := attack_resolved.has_connections()
	for unit in attacks:
		_resolve_attack(unit, report_attacks)
	if not _charging_silos.is_empty() or not _missile_flights.is_empty():
		_advance_missiles()
	for unit in units:
		if unit.hp <= 0.0:
			continue
		if unit.target > NO_TARGET and (_units[unit.target].hp <= 0.0 or (
				unit.position.distance_squared_to(_units[unit.target].position) > BattleVisibility.UNIT_RADIUS ** 2
				and not can_observe_unit(unit.side, _units[unit.target]))):
			continue
		# A placement callback can run between planning and movement.
		if unit.route_revision != navigation.revision \
				and not unit.waypoints.is_empty() and not _retain_route(unit):
			continue
		_move(unit)

	if not _support_units.is_empty():
		var report_heals := healing_resolved.has_connections()
		for unit in _support_units.values():
			if unit.hp > 0.0 and unit.cooldown <= TIME_EPSILON and unit.support_scan_at <= _elapsed_time:
				_heal_ally(unit, report_heals)

	var eliminated: Array[MatchRegion.Owner] = []
	for side in _base_obstacles.keys():
		if base_hp(side) > 0.0:
			continue
		navigation.remove_obstacle(_base_obstacles[side])
		_base_obstacles.erase(side)
		_base_guns.erase(side)
		if visibility != null:
			visibility.remove_source(_base_vision_id(side))
		_strategic_sites_revision += 1
		economy.eliminate(side)
		stats.remove_source(base_source_id(side))
		eliminated.append(side)
	if not is_side_active(PLAYER):
		_outcome = Outcome.DEFEAT
	elif _base_obstacles.size() == 1:
		_outcome = Outcome.VICTORY

	# A fallen faction immediately loses its army, outposts, and structures.
	for unit in units:
		if unit.hp <= 0.0 or (unit.side != MatchRegion.Owner.NEUTRAL and not is_side_active(unit.side)):
			_unit_grid.erase(unit.id, unit._cell, unit.side)
			unit._grid = null
			if unit._visibility != null:
				visibility.remove_source(unit.id)
				unit._visibility = null
				unit._vision_source = null
			_units.erase(unit.id)
			_support_units.erase(unit.id)
			_queued_orders.erase(unit.id)
			if _military_count.has(unit.side) and unit.type_id != UnitCatalog.SCOUT:
				_military_count[unit.side] -= 1
			unit_removed.emit(unit.id)

	var destroyed_outposts: Array[Outpost] = []
	for outpost in _outposts.values():
		if outpost.hp == 0 or not is_side_active(outpost.side):
			_structure_grid.erase(outpost.id, BattleSpatialGrid.cell_at(outpost.position), 0)
			_outposts.erase(outpost.id)
			if visibility != null:
				visibility.remove_source(outpost.id)
			_strategic_sites_revision += 1
			navigation.remove_obstacle(outpost.obstacle)
			stats.remove_source(outpost.source_id)
			destroyed_outposts.append(outpost)

	for fort: Fortification in _fortifications.values():
		if fort.hp <= 0.0 or not is_side_active(fort.side):
			set_fortification_active(fort, false)
			_structure_grid.erase(fort.id, BattleSpatialGrid.cell_at(fort.position), 0)
			_fortifications.erase(fort.id)
			radar.remove_station(fort.id)
			if fort is ProductionTimer:
				_timers.erase(fort)
			stats.remove_source(fort.source_id)
			fortification_destroyed.emit(fort)

	for unit in _units.values():
		if (unit.target > NO_TARGET and not _units.has(unit.target)) \
				or (unit.target == BASE_TARGET and not is_side_active(unit.target_base)) \
				or (unit.target < BASE_TARGET and not _outposts.has(unit.target)
					and not _fortifications.has(unit.target)):
			unit.target = NO_TARGET
			unit.can_attack_target = false
			_clear_route(unit)

	for outpost in destroyed_outposts:
		outpost_destroyed.emit(outpost)

	if visibility != null:
		visibility.advance(_elapsed_time)
	radar.advance(self, units, _elapsed_time)
	if not is_finished():
		objectives.advance(self, economy, _elapsed_time)
	navigation.update()
	for side in eliminated:
		base_destroyed.emit(side)


func _resolve_attack(unit: Unit, report_attack: bool) -> void:
	var damage := stats.value(unit.side, FactionStats.UNIT_DPS, _base_dps(unit)) * unit.attack_interval
	if damage <= 0.0:
		unit.cooldown = unit.attack_interval
		return

	var target_side := unit.target_base
	var impact: Vector2
	if unit.target > NO_TARGET:
		var target := _units[unit.target]
		if target.hp <= 0.0:
			return
		if unit.type_id == UnitCatalog.RANGED and objectives.has_boon(unit.side, NeutralObjectives.Reward.RANGED_DAMAGE, _elapsed_time):
			damage *= 1.25
		target.hp -= damage * UnitCatalog.damage_multiplier(unit.definition, target.definition)
		impact = target.position
		target_side = target.side
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
		target_side = building.side
		if building.hp <= 0.0:
			return
		damage *= structure_damage_multiplier(unit, unit.target)
		building.hp = maxf(0.0, building.hp - damage)

	unit.cooldown = unit.attack_interval
	if report_attack:
		attack_resolved.emit(AttackResolved.new(unit, target_side, impact, _elapsed_time))


func structure_damage_multiplier(unit: Unit, target_id: int) -> float:
	var factor: float = unit.definition.structure_damage_multiplier
	var fort := get_fortification(target_id)
	var armored := target_id == BASE_TARGET or get_outpost(target_id) != null \
		or (fort != null and (fort.profile.has("range") or fort.kind == Fortifications.SILO))
	if not armored:
		return factor
	if unit.type_id != UnitCatalog.HEAVY:
		factor *= BASE_ARMOR if target_id == BASE_TARGET else HUB_ARMOR
	if objectives.has_boon(unit.side, NeutralObjectives.Reward.SIEGE, _elapsed_time):
		factor *= 1.65
	return factor


func _heal_ally(medic: Unit, report_heal: bool) -> void:
	var support: Dictionary = medic.definition.support
	var radius_squared := float(support.radius) ** 2
	_candidate_ids.clear()
	_unit_grid.append_ids(medic._cell, ceili(support.radius / BattleSpatialGrid.CELL_SIZE),
		medic.side, _candidate_ids)
	var recipient: Unit
	var best_recovery := 0.0
	for id in _candidate_ids:
		var ally := _units[id]
		if ally == medic or ally.hp <= 0.0 or _elapsed_time < ally.next_healing_at \
				or medic.position.distance_squared_to(ally.position) > radius_squared:
			continue
		var recovery := minf(support.heal, _unit_max_hp(ally) - ally.hp)
		if recovery > best_recovery or (recipient != null and recovery == best_recovery and id < recipient.id):
			recipient = ally
			best_recovery = recovery
	if recipient == null:
		medic.support_scan_at = _elapsed_time + 0.12
		return
	recipient.hp += best_recovery
	recipient.next_healing_at = _elapsed_time + float(support.recovery)
	medic.cooldown = medic.attack_interval
	if report_heal:
		var cue := AttackResolved.new(medic, recipient.side, recipient.position, _elapsed_time)
		cue.target_id = recipient.id
		healing_resolved.emit(cue)


func _plan_support(unit: Unit) -> void:
	if _elapsed_time < unit.support_replan_at and _retain_route(unit):
		return
	unit.support_replan_at = _elapsed_time + 0.25
	var follow_range: float = unit.definition.support.follow_range
	_candidate_ids.clear()
	_unit_grid.append_ids(unit._cell, ceili(follow_range / BattleSpatialGrid.CELL_SIZE),
		unit.side, _candidate_ids)
	var nearest := follow_range * follow_range
	var leader: Unit
	for id in _candidate_ids:
		var ally := _units[id]
		if ally.hp <= 0.0 or ally.definition.damage <= 0.0:
			continue
		var distance := unit.position.distance_squared_to(ally.position)
		if distance < nearest or (leader != null and distance == nearest and id < leader.id):
			nearest = distance
			leader = ally
	if leader == null or nearest <= float(unit.definition.support.radius * 0.65) ** 2:
		_clear_route(unit)
		return
	var destination := leader.position.move_toward(unit.position, unit.definition.support.radius * 0.55)
	_route_to(unit, destination)


## Broad-phase candidates for a strategic threat scan. Callers test exact range.
func nearby_units(units: Array[Unit], position: Vector2, radius: float) -> Array[Unit]:
	if not is_finite(radius):
		return units
	var reach := ceili(radius / BattleSpatialGrid.CELL_SIZE)
	var width := 2 * reach + 1
	if width * width * MatchRegion.Owner.size() >= units.size():
		return units
	_candidate_ids.clear()
	var cell := BattleSpatialGrid.cell_at(position)
	for group in MatchRegion.Owner.values():
		_unit_grid.append_ids(cell, reach, group, _candidate_ids)
	# Strategic callers retain the original unit-ID order across bucket moves.
	_candidate_ids.sort()
	var nearby: Array[Unit] = []
	for id in _candidate_ids:
		nearby.append(_units[id])
	return nearby


func _nearby_enemies(units: Array[Unit], position: Vector2,
		side: MatchRegion.Owner, radius: float) -> Array[Unit]:
	# Cache each cell/side search for this snapshot. The callers filter the
	# exact radius from the cached neighborhood before using a target.
	if not is_finite(radius) or side == MatchRegion.Owner.NEUTRAL:
		return units
	var reach := ceili(radius / BattleSpatialGrid.CELL_SIZE)
	var width := 2 * reach + 1
	if width * width * (_base_obstacles.size() - 1) >= units.size():
		return units
	var cell := BattleSpatialGrid.cell_at(position)
	var key := Vector4i(cell.x, cell.y, side, reach)
	if _nearby_cache.has(key):
		return _nearby_cache[key]
	var nearby: Array[Unit] = []
	_candidate_ids.clear()
	for hostile in MatchRegion.Owner.values():
		if hostile != side:
			_unit_grid.append_ids(cell, reach, hostile, _candidate_ids)
	for id in _candidate_ids:
		nearby.append(_units[id])
	_nearby_cache[key] = nearby
	return nearby


func _hub_gun(side: MatchRegion.Owner, point: Vector2, obstacle: int, profile: Dictionary) -> Fortification:
	var gun := Fortification.new(stats, side, 1.0)
	gun.kind = &"hub_gun"
	gun.profile = profile
	gun.position = point
	gun.obstacle = obstacle
	return gun


func _fire_fortifications(units: Array[Unit]) -> void:
	if units.is_empty():
		return
	for side in _base_guns:
		if base_hp(side) > 0.0:
			_fire_gun(_base_guns[side], units)
	for outpost in _outposts.values():
		if outpost.hp > 0.0:
			_fire_gun(outpost.gun, units)
	for fort in _fortifications.values():
		if fort.active and fort.hp > 0.0 and fort.profile.get("range", 0.0) > 0.0:
			_fire_gun(fort, units)


func _fire_gun(fort: Fortification, units: Array[Unit]) -> void:
	fort.cooldown = maxf(0.0, fort.cooldown - STEP)
	if fort.cooldown > TIME_EPSILON:
		return
	var target: Unit
	var range_squared := float(fort.profile.range) ** 2
	var nearest := range_squared
	var best_multiplier := -INF
	var prefer_class: bool = fort.profile.get("prefer_damage_class", false)
	var nearby := _nearby_enemies(units, fort.position, fort.side, fort.profile.range)
	for unit in nearby:
		var distance := fort.position.distance_squared_to(unit.position)
		if unit.side == fort.side or unit.hp <= 0.0 or distance > range_squared:
			continue
		var multiplier := UnitCatalog.damage_multiplier(fort.profile, unit.definition) if prefer_class else 1.0
		if multiplier < best_multiplier or (multiplier == best_multiplier and (
				distance > nearest or (distance == nearest and target != null and unit.id > target.id))):
			continue
		if fort.profile.splash == 0.0 and not navigation.line_clear(
				fort.position, unit.position, fort.obstacle):
			continue
		target = unit
		nearest = distance
		best_multiplier = multiplier
	if target == null:
		return

	var damage: float = fort.profile.damage
	if objectives.has_boon(fort.side, NeutralObjectives.Reward.DEFENSE, _elapsed_time):
		damage *= 1.25
	target.hp -= damage * UnitCatalog.damage_multiplier(fort.profile, target.definition)
	if fort.profile.splash > 0.0:
		var radius_squared := float(fort.profile.splash) ** 2
		for unit in nearby:
			if unit != target and unit.side != fort.side and unit.hp > 0.0 \
					and fort.position.distance_squared_to(unit.position) <= range_squared \
					and target.position.distance_squared_to(unit.position) <= radius_squared:
				unit.hp -= damage
	fort.cooldown = fort.profile.interval
	fortification_fired.emit(fort, target.position)


func _plan_turn(unit: Unit, units: Array[Unit]) -> bool:
	unit.target = NO_TARGET
	match unit.order:
		Order.ATTACK:
			return _plan_attack_order(unit)
		Order.MOVE:
			if unit.blocked_revision == navigation.revision and not unit.wall_approach.is_empty():
				return _plan_breach(unit, unit.ordered_destination, true)
			_route_to(unit, unit.ordered_destination)
			if unit.following_rally:
				if unit.waypoints.is_empty() and unit.position != unit.ordered_destination:
					_resume_stance(unit)
				return false
			return unit.definition.damage > 0.0 and unit.waypoints.is_empty() \
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
				if unit.definition.damage <= 0.0:
					return false
				var local_range: float = unit.definition.range + RANGE_EPSILON
				return _plan_local_engagement(unit, _nearby_enemies(units, unit.position, unit.side, local_range),
					local_range, true)
	if unit.definition.damage <= 0.0:
		if unit.definition.has("support") and unit.order == Order.AUTONOMOUS:
			_plan_support(unit)
		return false

	var holding := unit.order == Order.HOLD
	var radius := absf(aggro_radius)
	if holding:
		radius = minf(radius, unit.definition.range + RANGE_EPSILON)
	var nearby := _nearby_enemies(units, unit.position, unit.side, radius)
	if holding:
		var key := Vector4(unit.position.x, unit.position.y, unit.side, radius)
		if _hold_targets.has(key):
			var target := get_unit(_hold_targets[key])
			if target != null:
				return _aim_at(unit, target.id, target.position)
		else:
			var can_fire := _plan_local_engagement(unit, nearby, radius, true)
			_hold_targets[key] = unit.target
			if can_fire:
				return true
	elif _plan_local_engagement(unit, nearby, radius, false):
		return unit.waypoints.is_empty()
	unit.chase_target = NO_TARGET

	var weapon_range: float = unit.definition.range
	var attack_range := weapon_range + BASE_ATTACK_RANGE - UNIT_ATTACK_RANGE
	var nearest := (attack_range + RANGE_EPSILON) ** 2
	var target_base := MatchRegion.Owner.NEUTRAL
	for side in _base_obstacles:
		if side == unit.side:
			continue
		var distance := unit.position.distance_squared_to(_bases[side])
		if distance <= nearest and _can_attack_structure(unit.position, _bases[side],
				_base_obstacles[side], attack_range):
			target_base = side
			nearest = distance
	if target_base != MatchRegion.Owner.NEUTRAL:
		unit.target_base = target_base
		return _aim_at(unit, BASE_TARGET, _bases[target_base])
	var structure := _nearby_structure_target(unit, weapon_range)
	if structure != null:
		return _aim_at(unit, structure.id, structure.position)

	if holding:
		return false
	return _plan_strategic_turn(unit)


func _plan_strategic_turn(unit: Unit) -> bool:
	var known_outpost := get_outpost(unit.strategic_target)
	var target_exists := is_side_active(unit.strategic_base) if unit.strategic_target == BASE_TARGET \
		else known_outpost != null and can_see(unit.side, known_outpost.position)
	if unit.strategic_revision < 0 or not target_exists or (
			unit.strategic_sites_revision != _strategic_sites_revision
			and (unit.waypoints.is_empty() or (unit.id + _combat_step) % 8 == 0)):
		_plan_strategic_approach(unit)
	_route_to(unit, unit.strategic_destination)
	if unit.strategic_revision != navigation.revision:
		if unit.waypoints.is_empty():
			_plan_strategic_approach(unit)
			_route_to(unit, unit.strategic_destination)
		else:
			unit.strategic_revision = navigation.revision
	if not unit.waypoints.is_empty():
		if unit.strategic_target != BASE_TARGET or can_see(unit.side, _bases[unit.strategic_base]):
			unit.target = unit.strategic_target
			unit.target_base = unit.strategic_base
		return false
	return _plan_breach(unit, _bases[unit.strategic_base], false)


func _nearby_structure_target(unit: Unit, weapon_range: float) -> BuildingHealth:
	var reach := ceili((weapon_range + _structure_extent + RANGE_EPSILON)
		/ BattleSpatialGrid.CELL_SIZE)
	_candidate_ids.clear()
	_structure_grid.append_ids(unit._cell, reach, 0, _candidate_ids)
	var best_outpost: Outpost
	var best_fort: Fortification
	for id in _candidate_ids:
		var outpost := get_outpost(id)
		if outpost != null:
			if outpost.side != unit.side and (best_outpost == null or id > best_outpost.id) \
					and _can_attack_structure(unit.position, outpost.position, outpost.obstacle,
						weapon_range + OUTPOST_ATTACK_RANGE - UNIT_ATTACK_RANGE):
				best_outpost = outpost
			continue
		var fort := get_fortification(id)
		var urgent := not _charging_silos.is_empty() and _charging_silos.has(id)
		if fort.side != unit.side and (urgent or best_fort == null or id > best_fort.id) \
				and (unit.position.distance_squared_to(fort.position) <= BattleVisibility.UNIT_RADIUS ** 2
					or can_see(unit.side, fort.position)) \
				and _can_attack_structure(unit.position, fort.position, fort.obstacle,
					fort.unit_attack_range(weapon_range)):
			if urgent:
				return fort
			best_fort = fort
	return best_outpost if best_outpost != null else best_fort


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
		if fort.side == unit.side or fort.kind != Fortifications.WALL or not fort.active \
				or not can_see(unit.side, fort.position):
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
	var weapon_range: float = unit.definition.range
	var fire_range_squared := (weapon_range + RANGE_EPSILON) ** 2
	var radius_squared := radius * radius
	var prioritize_health := holding and target_priority == TargetPriority.LOWEST_HP
	var prioritize_strength := not holding and unit.stance == Stance.SEEK_STRONGEST
	var unreachable: Array[int] = []
	# Rank nearby candidates before probing routes. Only blocked targets need
	# a second pass, and a crowded free-for-all has a fixed route-probe budget.
	var multi_cpu := _bases.size() > 2
	var attempts := LOCAL_ROUTE_PROBES if multi_cpu else units.size()
	for attempt in attempts:
		var selected: Unit
		var best_distance := INF
		var best_priority := INF
		for opponent in units:
			if opponent.side == unit.side or opponent.hp <= 0.0 \
					or (not unreachable.is_empty() and unreachable.has(opponent.id)):
				continue
			var distance := unit.position.distance_squared_to(opponent.position)
			if distance > radius_squared or (distance > BattleVisibility.UNIT_RADIUS ** 2
					and not can_observe_unit(unit.side, opponent)):
				continue
			var priority := 0.0
			if prioritize_health:
				priority = opponent.hp
			elif prioritize_strength:
				var dps := stats.value(opponent.side, FactionStats.UNIT_DPS, _base_dps(opponent))
				priority = -(threat_weights.x * dps + threat_weights.y * opponent.hp)
			if selected != null and (priority > best_priority or (priority == best_priority and (
					distance > best_distance or (distance == best_distance and opponent.id > selected.id)))):
				continue
			if holding and (distance > fire_range_squared
					or not navigation.line_clear(unit.position, opponent.position)):
				continue
			selected = opponent
			best_priority = priority
			best_distance = distance
		if selected == null:
			break
		if holding or (best_distance <= fire_range_squared
				and navigation.line_clear(unit.position, selected.position)):
			return _aim_at(unit, selected.id, selected.position)
		if unit.chase_target == selected.id and _elapsed_time < unit.chase_repath_at \
				and not unit.waypoints.is_empty() and _retain_route(unit):
			unit.target = selected.id
			return true
		var route := _unit_navigation(unit).path(unit.position, selected.position)
		var detour := route.size() > 1
		if route.is_empty():
			route = _find_attack_route(unit, selected.position, -1, weapon_range)
			detour = true
		if not route.is_empty():
			unit.target = selected.id
			unit.chase_target = selected.id if detour else NO_TARGET
			unit.chase_repath_at = _elapsed_time + LOCAL_REPATH_INTERVAL
			_set_route(unit, route[-1], route)
			return true
		unreachable.append(selected.id)
	return false


func _plan_strategic_approach(unit: Unit) -> void:
	var weapon_range: float = unit.definition.range
	unit.strategic_revision = navigation.revision
	unit.strategic_sites_revision = _strategic_sites_revision
	unit.strategic_target = BASE_TARGET
	unit.strategic_base = nearest_hostile_base(unit.side, unit.position)
	var nearest := INF
	var priority := retaliation_target(unit.side, unit.position) if unit.side != PLAYER else MatchRegion.Owner.NEUTRAL
	for outpost in _outposts.values():
		var distance := unit.position.distance_squared_to(outpost.position)
		if priority != MatchRegion.Owner.NEUTRAL and outpost.side != priority:
			continue
		if outpost.side == unit.side or distance >= nearest or not can_see(unit.side, outpost.position):
			continue
		var destination := _find_structure_approach(unit, outpost.position,
			outpost.obstacle, weapon_range + OUTPOST_ATTACK_RANGE - UNIT_ATTACK_RANGE)
		if destination.is_finite():
			nearest = distance
			unit.strategic_target = outpost.id
			unit.strategic_destination = destination
	if unit.strategic_target != BASE_TARGET:
		return
	unit.strategic_destination = Vector2.INF
	var hostiles := _base_obstacles.keys()
	hostiles.erase(unit.side)
	hostiles.sort_custom(func(a: MatchRegion.Owner, b: MatchRegion.Owner) -> bool:
		if a == priority or b == priority:
			return a == priority and b != priority
		var first := unit.position.distance_squared_to(_bases[a])
		var second := unit.position.distance_squared_to(_bases[b])
		return a < b if first == second else first < second)
	for side: MatchRegion.Owner in hostiles:
		var destination := _find_structure_approach(unit, _bases[side],
			_base_obstacles[side], weapon_range + BASE_ATTACK_RANGE - UNIT_ATTACK_RANGE)
		if destination.is_finite():
			unit.strategic_base = side
			unit.strategic_destination = destination
			return


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
	if unit.movement_destination != destination or not _retain_route(unit):
		_set_route(unit, destination, _unit_navigation(unit).path(unit.position, destination))


func _retain_route(unit: Unit) -> bool:
	if unit.route_revision == navigation.revision:
		return true
	if _unit_navigation(unit).route_affected(unit.position, unit.movement_destination,
			unit.waypoints, unit.route_revision):
		return false
	unit.route_revision = navigation.revision
	return true


func _set_route(unit: Unit, destination: Vector2, route: PackedVector2Array) -> void:
	unit.movement_destination = destination
	unit.waypoints = route
	unit.route_revision = navigation.revision


func _clear_route(unit: Unit) -> void:
	_set_route(unit, Vector2.INF, PackedVector2Array())


func _move(unit: Unit) -> void:
	if unit.waypoints.is_empty() and unit.order != Order.MOVE:
		return
	var remaining := unit.step_distance
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
