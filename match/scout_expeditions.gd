extends RefCounted

signal expedition_completed(side: MatchRegion.Owner, region_id: StringName, scout_id: int,
		outpost_site: Vector2)
signal expedition_failed(side: MatchRegion.Owner, message: String)
signal assignment_interrupted(side: MatchRegion.Owner, region_id: StringName, elapsed: float)

enum State { AVAILABLE, TRAVELING, CLAIMING, RETURNING, DEAD }

const UnitCatalog := preload("res://match/unit_catalog.gd")
const CAPACITY := 2
const ARRIVAL_MARGIN := MatchBattle.OUTPOST_FOOTPRINT.x + UnitCatalog.DEFINITIONS[UnitCatalog.SCOUT].clearance + 0.2


class Scout:
	var side: MatchRegion.Owner
	var unit_id := MatchBattle.NO_TARGET
	var state := State.DEAD
	var replace_at := 0.0
	var region_id: StringName
	var site: Vector2
	var departure: Vector2
	var remaining := 0.0

	func _init(faction: MatchRegion.Owner) -> void:
		side = faction

	func assigned() -> bool:
		return state == State.TRAVELING or state == State.CLAIMING


class ClaimRoute:
	var unit_id: int
	var site: Vector2
	var waypoints: PackedVector2Array
	var travel_time: float
	var rank: float


var slots: Dictionary[MatchRegion.Owner, Array] = {}
var assignments: Dictionary[StringName, Scout] = {}
var claim_cost: Dictionary
var replacement_cost: Dictionary
var duration: float
var replacement_delay: float
var _battle: MatchBattle
var _economy: MatchEconomy
var _outpost_slot_block_reason: Callable
var _regions: Dictionary[StringName, MatchRegion]


func _init(battle: MatchBattle, economy: MatchEconomy,
		regions: Dictionary[StringName, MatchRegion], settings: Dictionary) -> void:
	_battle = battle
	_economy = economy
	_regions = regions
	_outpost_slot_block_reason = settings.outpost_slot_block_reason
	claim_cost = {MatchEconomy.ENERGY: settings.claim_energy}
	replacement_cost = {MatchEconomy.ENERGY: settings.replacement_energy}
	duration = settings.duration
	replacement_delay = settings.replacement_delay
	for side in battle._bases:
		var roster: Array[Scout] = []
		slots[side] = roster
		for index in CAPACITY:
			var scout := Scout.new(side)
			roster.append(scout)
			_deploy(scout, _spawn_point(side))
	battle.step_finished.connect(_step)


func scout_for(unit_id: int) -> Scout:
	if unit_id != MatchBattle.NO_TARGET:
		for roster in slots.values():
			for scout: Scout in roster:
				if scout.unit_id == unit_id:
					return scout
	return null


func available(side: MatchRegion.Owner) -> Array[Scout]:
	var scouts: Array[Scout] = []
	for scout: Scout in slots.get(side, []):
		var unit := _battle.get_unit(scout.unit_id)
		if scout.state == State.AVAILABLE and unit != null and unit.hp > 0.0 \
				and not unit.scout_committed and unit.waypoints.is_empty():
			scouts.append(scout)
	return scouts


func eligibility(side: MatchRegion.Owner, region_id: StringName) -> String:
	if not slots.has(side):
		return "Invalid faction"
	if not _battle.is_side_active(side):
		return "Faction eliminated"
	var region := _regions.get(region_id) as MatchRegion
	if region == null:
		return "Select a region"
	if region.ruined:
		return "Permanently ruined"
	if region.region_owner != MatchRegion.Owner.NEUTRAL:
		return MatchRegion.side_label(region.region_owner, slots.size() > 2) + "-owned"
	if _battle.is_finished():
		return "Match ended"
	for neighbor in region.neighbor_ids:
		if _regions[neighbor].region_owner == side:
			return _outpost_slot_block_reason.call(region_id)
	return "Not adjacent"


func block_reason(side: MatchRegion.Owner, region_id: StringName) -> String:
	var reason := eligibility(side, region_id)
	if not reason.is_empty():
		return reason
	if assignments.has(region_id):
		return "Expedition assigned"
	if available(side).is_empty():
		return "No scouts available"
	return _economy.cost_block_reason(side, claim_cost)


func dispatch(side: MatchRegion.Owner, region_id: StringName, rank_route := Callable()) -> String:
	var reason := block_reason(side, region_id)
	if not reason.is_empty():
		return reason
	var plan := _best_route(side, region_id, rank_route)
	if plan == null:
		return "No reachable outpost site"
	if not _economy.try_spend(side, claim_cost):
		return _economy.cost_block_reason(side, claim_cost)

	var scout := scout_for(plan.unit_id)
	var unit := _battle.get_unit(plan.unit_id)
	scout.departure = unit.position
	scout.region_id = region_id
	scout.site = plan.site
	scout.remaining = duration
	scout.state = State.TRAVELING
	assignments[region_id] = scout
	unit.scout_committed = true
	_battle._order_move(unit, plan.waypoints[-1], plan.waypoints)
	return ""


## Preview the route dispatch would choose. An optional ranker can prefer safer routes
## or reject a route by returning INF. Lower ranks win, then lower unit IDs.
func preview_claim(side: MatchRegion.Owner, region_id: StringName,
		rank_route := Callable()) -> ClaimRoute:
	if not block_reason(side, region_id).is_empty():
		return null
	return _best_route(side, region_id, rank_route)


func _best_route(side: MatchRegion.Owner, region_id: StringName, rank_route: Callable) -> ClaimRoute:
	var best: ClaimRoute
	for scout in available(side):
		var unit := _battle.get_unit(scout.unit_id)
		var plan := _claim_route(unit, region_id)
		if plan == null:
			continue
		plan.rank = rank_route.call(unit, plan) if rank_route.is_valid() else plan.travel_time
		if is_finite(plan.rank) and (best == null or plan.rank < best.rank
				or (plan.rank == best.rank and plan.unit_id < best.unit_id)):
			best = plan
	return best


func _claim_route(unit: MatchBattle.Unit, region_id: StringName) -> ClaimRoute:
	var routes := _battle._unit_navigation(unit)
	var region := _regions[region_id]
	var site := region.interior_point(func(point: Vector2) -> bool:
		# Claims reserve space in the target region for the whole outpost.
		var footprint := Rect2(point - MatchBattle.OUTPOST_FOOTPRINT, MatchBattle.OUTPOST_FOOTPRINT * 2.0)
		for corner in BattleNavigation.corners_of(footprint):
			if not Geometry2D.is_point_in_polygon(corner, region.polygon):
				return false
		if not _battle.outpost_site_clear(point):
			return false
		return not _approach_route(region, routes, unit.position, point).is_empty())
	if not site.is_finite():
		return null
	var plan := ClaimRoute.new()
	plan.unit_id = unit.id
	plan.site = site
	plan.waypoints = _approach_route(region, routes, unit.position, site)
	var previous := unit.position
	var distance := 0.0
	for waypoint in plan.waypoints:
		distance += previous.distance_to(waypoint)
		previous = waypoint
	plan.travel_time = distance / maxf(0.01, _battle.unit_speed_stat(unit).total)
	return plan


func recall(side: MatchRegion.Owner, unit_id: int) -> bool:
	var scout := scout_for(unit_id)
	if _battle.is_finished() or scout == null or scout.side != side or not scout.assigned():
		return false
	_cancel(scout, "Expedition recalled")
	return true


func replacement_wait(scout: Scout) -> float:
	return maxf(0.0, scout.replace_at - _battle.elapsed_time())


func replacement_block_reason(scout: Scout) -> String:
	if _battle.is_finished() or not _battle.is_side_active(scout.side) or scout.state != State.DEAD:
		return "Replacement unavailable"
	if replacement_wait(scout) > MatchBattle.TIME_EPSILON:
		return "Replacement ready in %ds" % ceili(replacement_wait(scout))
	return _economy.cost_block_reason(scout.side, replacement_cost)


func replace(side: MatchRegion.Owner, index: int) -> bool:
	var roster: Array = slots.get(side, [])
	if index < 0 or index >= roster.size():
		return false
	var scout := roster[index] as Scout
	if not replacement_block_reason(scout).is_empty():
		return false
	var point := _spawn_point(side)
	if not point.is_finite() or not _economy.try_spend(side, replacement_cost):
		return false
	_deploy(scout, point)
	return true


func eta(scout: Scout) -> float:
	var seconds := scout.remaining
	if scout.state == State.TRAVELING:
		var unit := _battle.get_unit(scout.unit_id)
		if unit == null:
			return seconds
		var previous := unit.position
		var distance := 0.0
		for waypoint in unit.waypoints:
			distance += previous.distance_to(waypoint)
			previous = waypoint
		seconds += distance / maxf(0.01, _battle.unit_speed_stat(unit).total)
	return seconds


func _step() -> void:
	for roster in slots.values():
		for scout: Scout in roster:
			_step_scout(scout)


func _step_scout(scout: Scout) -> void:
	if scout.state == State.DEAD:
		return
	var unit := _battle.get_unit(scout.unit_id)
	if unit == null:
		var was_assigned := scout.assigned()
		var region_id := scout.region_id
		_release(scout)
		scout.state = State.DEAD
		scout.replace_at = _battle.elapsed_time() + replacement_delay
		if was_assigned:
			assignment_interrupted.emit(scout.side, region_id, _battle.elapsed_time())
		expedition_failed.emit(scout.side, "Scout killed · Energy spent" if was_assigned else "Scout killed")
		return
	if _battle.is_finished():
		if scout.assigned():
			_cancel(scout, "Match ended")
		return
	if scout.state == State.RETURNING:
		if unit.waypoints.is_empty():
			_make_available(scout, unit)
		return
	if not scout.assigned():
		return

	var region := _regions[scout.region_id]
	if not eligibility(scout.side, scout.region_id).is_empty():
		_cancel(scout, "Target no longer eligible")
	elif not _battle.outpost_site_clear(scout.site):
		_cancel(scout, "Outpost site blocked")
	elif scout.state == State.TRAVELING:
		if unit.position == unit.ordered_destination:
			scout.state = State.CLAIMING
		elif unit.waypoints.is_empty():
			_cancel(scout, "Route blocked")
	elif not Geometry2D.is_point_in_polygon(unit.position, region.polygon) \
			or not _battle._unit_navigation(unit).is_passable(unit.position):
		_cancel(scout, "Scout displaced")
	else:
		scout.remaining = maxf(0.0, scout.remaining - MatchBattle.STEP)
		if scout.remaining <= MatchBattle.TIME_EPSILON:
			var region_id := scout.region_id
			_release(scout)
			_make_available(scout, unit)
			expedition_completed.emit(scout.side, region_id, unit.id, scout.site)


func _cancel(scout: Scout, reason: String) -> void:
	var region_id := scout.region_id
	_release(scout)
	var unit := _battle.get_unit(scout.unit_id)
	var route := _battle._unit_navigation(unit).path(unit.position, scout.departure)
	if _battle.is_finished() or route.is_empty() or unit.position == scout.departure:
		_make_available(scout, unit)
	else:
		scout.state = State.RETURNING
		_battle._order_move(unit, scout.departure, route)
	assignment_interrupted.emit(scout.side, region_id, _battle.elapsed_time())
	expedition_failed.emit(scout.side, reason + " · Energy spent")


func _release(scout: Scout) -> void:
	assignments.erase(scout.region_id)
	scout.region_id = &""


func _make_available(scout: Scout, unit: MatchBattle.Unit) -> void:
	scout.state = State.AVAILABLE
	unit.scout_committed = false
	unit.order = MatchBattle.Order.HOLD
	unit.ordered_destination = unit.position
	_battle._clear_route(unit)


func _deploy(scout: Scout, point: Vector2) -> void:
	var unit := _battle._spawn_unit(scout.side, point, UnitCatalog.SCOUT)
	if unit != null:
		scout.unit_id = unit.id
		_make_available(scout, unit)


func _spawn_point(side: MatchRegion.Owner) -> Vector2:
	if _battle.is_finished() or not _battle.is_side_active(side):
		return Vector2.INF
	var base := _battle._bases[side]
	var routes := _battle.navigation.with_clearance(UnitCatalog.DEFINITIONS[UnitCatalog.SCOUT].clearance)
	var facing := base.direction_to(_battle._bases[_battle.nearest_hostile_base(side, base)])
	var units := _battle.active_units()
	for radius in [2.35, 3.1, 3.85]:
		for offset in [0.45, -0.45, 0.0, 0.9, -0.9, 1.35, -1.35, PI]:
			var point: Vector2 = base + facing.rotated(offset) * radius
			if routes.is_passable(point) and not units.any(func(unit: MatchBattle.Unit) -> bool:
				return unit.position.distance_squared_to(point) < 0.85 * 0.85):
				return point
	return Vector2.INF


func _approach_route(region: MatchRegion, routes: BattleNavigation,
		start: Vector2, site: Vector2) -> PackedVector2Array:
	var facing := site.direction_to(start)
	if facing == Vector2.ZERO:
		facing = Vector2.RIGHT
	for offset in [0.0, PI / 4, -PI / 4, PI / 2, -PI / 2, PI]:
		var point := site + facing.rotated(offset) * ARRIVAL_MARGIN * sqrt(2.0)
		if Geometry2D.is_point_in_polygon(point, region.polygon):
			var route := routes.path(start, point)
			if not route.is_empty():
				return route
	return PackedVector2Array()
