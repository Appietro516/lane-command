extends RefCounted
## Assign a limited number of explicit orders alongside the autonomous combat force.

const Catalog := preload("res://match/unit_catalog.gd")
const Order := MatchBattle.Order
const Stance := MatchBattle.Stance
const ORDER_BUDGET := 16
const DEFENSE_HUBS := 3
const MAX_RESERVES := 4
const ASSAULT_SIZE := 4
const RESERVE_TIME := 12.0
const ROUTE_RETRY := 6.0
const ORDER_ANGLES := [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]

enum Role { RESERVE, DEFEND, ASSAULT, INTERCEPT, CAMP }


class Threat:
	var region: MatchRegion
	var hub: Vector2
	var enemies := PackedVector2Array()
	var composition := {}
	var nearest := Vector2.INF
	var score := 0.0
	var allies := 0

	func pressure() -> float:
		return score + allies * 0.5


class Assignment:
	var role: Role
	var region: StringName
	var anchor: Vector2
	var objective := MatchBattle.NO_TARGET
	var release_at := INF

	func _init(kind: Role, region_id: StringName, point: Vector2) -> void:
		role = kind
		region = region_id
		anchor = point


var _assignments: Dictionary[int, Assignment] = {}
var _retry_at: Dictionary[int, float] = {}
var _orders_left: int


func decide(scene: Node3D, side: MatchRegion.Owner, difficulty: Dictionary, owned: Array[MatchRegion],
		units: Array[MatchBattle.Unit], threats: Array[Threat], now: float) -> void:
	var battle: MatchBattle = scene._battle
	var base: Vector2 = battle._bases[side]
	var available: Array[MatchBattle.Unit] = []
	var enemies: Array[MatchBattle.Unit] = []
	var living := {}
	for unit in units:
		if unit.hp <= 0.0 or unit.type_id == Catalog.SCOUT:
			continue
		if unit.side != side:
			enemies.append(unit)
			continue
		living[unit.id] = true
		# An explicit order supplied outside this planner can run independently.
		if unit.order == Order.AUTONOMOUS or _assignments.has(unit.id):
			available.append(unit)
	for id in _assignments.keys():
		if not living.has(id):
			_assignments.erase(id)
	for id in _retry_at.keys():
		if not living.has(id) or now >= _retry_at[id]:
			_retry_at.erase(id)

	var danger := threats.filter(func(threat: Threat) -> bool:
		return threat.pressure() > float(difficulty.threat_threshold))
	danger.sort_custom(func(a: Threat, b: Threat) -> bool:
		var first := a.pressure()
		var second := b.pressure()
		return a.region.region_id < b.region.region_id if first == second else first > second)

	var objective: MatchBattle.Outpost
	if not available.is_empty():
		objective = _attack_objective(scene, side, base, enemies)
	var reserve_size := mini(MAX_RESERVES, floori(available.size() / 3.0)) if danger.is_empty() else 0
	var rally: MatchRegion
	var goal: Vector2
	if reserve_size > 0:
		goal = objective.position if objective != null else battle._bases[battle.nearest_hostile_base(side, base)]
		rally = _rally_region(scene, owned, side, goal)
	_set_producer_stances(scene, side, danger, rally, difficulty)

	_orders_left = ORDER_BUDGET
	var guard_budget := mini(available.size() - 1, ceili(available.size() * 0.6))
	for threat: Threat in danger.slice(0, DEFENSE_HUBS):
		if guard_budget <= 0:
			break
		var covered := has_cover(scene, side, threat.hub)
		var demand := maxi(1, ceili(threat.pressure() * 0.7) - int(covered))
		var post := Assignment.new(Role.DEFEND, threat.region.region_id, threat.hub)
		guard_budget -= _staff_post(battle, side, available, post, threat.region, threat.nearest,
			mini(guard_budget, demand), covered, now)

	if rally != null:
		var anchor := _site(rally)
		var post := Assignment.new(Role.RESERVE, rally.region_id, anchor)
		_staff_post(battle, side, available, post, rally, goal, reserve_size, false, now)

	_intercept_launches(battle, side, available)
	if danger.is_empty():
		_contest_camps(battle, side, available, now)
	_attack(scene, side, difficulty, available, enemies, objective, now)


func _staff_post(battle: MatchBattle, side: MatchRegion.Owner, available: Array[MatchBattle.Unit],
		post: Assignment, region: MatchRegion, toward: Vector2, count: int, covered: bool, now: float) -> int:
	var direction := post.anchor.direction_to(toward)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var scores := {}
	for unit in available:
		var current: Assignment = _assignments.get(unit.id)
		if _keeps_post(battle, unit, current, post, direction, now):
			scores[unit.id] = -INF
		elif not _retry_at.has(unit.id) and (post.role != Role.RESERVE or (not unit.can_attack_target
				and (current == null or current.role != Role.RESERVE or now < current.release_at))):
			var ranged := unit.type_id == Catalog.RANGED
			var travel := unit.position.distance_to(post.anchor) / float(unit.definition.speed)
			scores[unit.id] = travel - (1.5 if ranged == covered else 0.0)
	var candidates := available.filter(func(unit: MatchBattle.Unit) -> bool: return scores.has(unit.id))
	candidates.sort_custom(func(a: MatchBattle.Unit, b: MatchBattle.Unit) -> bool:
		return a.id < b.id if scores[a.id] == scores[b.id] else scores[a.id] < scores[b.id])
	var stationed := 0
	for unit: MatchBattle.Unit in candidates:
		if stationed >= count:
			break
		if scores[unit.id] != -INF:
			if _orders_left == 0:
				break
			if not _order_post(battle, side, unit, post, region, direction, now):
				continue
		available.erase(unit)
		stationed += 1
	return stationed


func _keeps_post(battle: MatchBattle, unit: MatchBattle.Unit, current: Assignment, post: Assignment,
		direction: Vector2, now: float) -> bool:
	if current == null or current.role != post.role or current.region != post.region \
			or current.anchor != post.anchor or now >= current.release_at or unit.order != Order.HOLD:
		return false
	var from_hub := unit.ordered_destination - post.anchor
	return (post.role == Role.RESERVE or from_hub.dot(direction) >= -0.5) \
		and _order_progresses(battle, unit)


func _order_post(battle: MatchBattle, side: MatchRegion.Owner, unit: MatchBattle.Unit, post: Assignment,
		region: MatchRegion, direction: Vector2, now: float) -> bool:
	var defense := post.role == Role.DEFEND
	var reach := 2.4
	if defense:
		reach = 2.2 if unit.type_id == Catalog.RANGED else 3.2
	# Spread across the approach with a deterministic offset per unit.
	var bearing := direction.rotated((unit.id % 3 - 1) * PI / 12.0)
	var destination := _find_post(battle, side, unit, post.anchor, region.polygon, bearing, reach)
	if not destination.is_finite():
		_retry_at[unit.id] = now + ROUTE_RETRY
		return false
	var assignment := Assignment.new(post.role, post.region, post.anchor)
	if not defense:
		var travel := unit.position.distance_to(destination) / float(unit.definition.speed)
		assignment.release_at = now + RESERVE_TIME + travel
	_assignments[unit.id] = assignment
	_apply_stance(battle, side, unit, Stance.SEEK_NEAREST if defense else Stance.IDLE, false)
	return true


func _find_post(battle: MatchBattle, side: MatchRegion.Owner, unit: MatchBattle.Unit,
		anchor: Vector2, polygon: PackedVector2Array, bearing: Vector2, reach: float) -> Vector2:
	# Small territories can need a tighter line around the hub.
	var routes := battle.navigation.with_clearance(unit.definition.clearance)
	for radius: float in [reach, reach * 0.72]:
		for angle: float in ORDER_ANGLES:
			if _orders_left == 0:
				return Vector2.INF
			var point := anchor + bearing.rotated(angle) * radius
			if not Geometry2D.is_point_in_polygon(point, polygon) or not routes.is_passable(point):
				continue
			_orders_left -= 1
			if battle.order_hold(side, unit.id, point):
				return point
	return Vector2.INF


func _intercept_launches(battle: MatchBattle, side: MatchRegion.Owner,
		available: Array[MatchBattle.Unit]) -> void:
	if battle._charging_silos.is_empty():
		return
	var assigned := 0
	var candidates := available.duplicate()
	for unit: MatchBattle.Unit in candidates:
		var previous: Assignment = _assignments.get(unit.id)
		if previous != null and previous.role == Role.INTERCEPT and _order_progresses(battle, unit):
			var target: MatchBattle.MissileSilo = battle._charging_silos.get(previous.objective)
			if target != null and target.side != side:
				available.erase(unit)
				assigned += 1
	if assigned >= ASSAULT_SIZE:
		return
	for unit in available.duplicate():
		if _orders_left <= 0 or assigned >= ASSAULT_SIZE:
			break
		if unit.definition.damage <= 0.0:
			continue
		var nearest: MatchBattle.MissileSilo
		var best_time := INF
		for silo: MatchBattle.MissileSilo in battle._charging_silos.values():
			if silo.side == side or silo.hp <= 0.0:
				continue
			var reach := silo.unit_attack_range(unit.definition.range)
			var eta: float = maxf(0.0, unit.position.distance_to(silo.position) - reach) / unit.definition.speed
			if eta < best_time and eta + 1.0 < silo.launches_at - battle.elapsed_time():
				nearest = silo
				best_time = eta
		if nearest == null:
			continue
		var reach := nearest.unit_attack_range(unit.definition.range)
		var direction := nearest.position.direction_to(unit.position)
		for angle: float in ORDER_ANGLES:
			var point := nearest.position + direction.rotated(angle) * (reach - 0.02)
			if not battle.navigation.line_clear(point, nearest.position, nearest.obstacle):
				continue
			_orders_left -= 1
			if battle.order_hold(side, unit.id, point):
				var assignment := Assignment.new(Role.INTERCEPT, &"", nearest.position)
				assignment.objective = nearest.id
				_assignments[unit.id] = assignment
				available.erase(unit)
				assigned += 1
				break
			if _orders_left <= 0:
				break


func _contest_camps(battle: MatchBattle, side: MatchRegion.Owner, available: Array[MatchBattle.Unit],
		now: float) -> void:
	if available.is_empty() or battle.objectives.camps.is_empty() or _orders_left <= 0:
		return
	var fighters := available.filter(func(unit: MatchBattle.Unit) -> bool:
		return unit.definition.damage > 0.0)
	var target: NeutralObjectives.Camp
	var best := INF
	var anchor: Vector2 = battle._bases[side]
	for camp in battle.objectives.camps:
		var sight: Dictionary = camp.observed.get(side, {})
		if sight.is_empty() or (sight.guard == MatchBattle.NO_TARGET and not sight.drop):
			continue
		var seen: bool = battle.can_see(side, camp.point)
		if sight.drop and (not seen or now - sight.seen_at > 1.0):
			continue
		var minimum := 9 if camp.major else 4
		if not sight.drop and fighters.size() < maxi(3, ceili(minimum * float(sight.hp_fraction))):
			continue
		var distance := anchor.distance_to(camp.point)
		var score := distance - (16.0 if sight.drop else (7.0 if camp.major else 0.0))
		if score < best:
			best = score
			target = camp
	if target == null:
		return
	var intel: Dictionary = target.observed[side]
	var collect: bool = intel.drop
	var required := 1 if collect else (mini(12, fighters.size()) if target.major else mini(6, fighters.size()))
	var candidates := available.duplicate() if collect else fighters
	candidates.sort_custom(func(a: MatchBattle.Unit, b: MatchBattle.Unit) -> bool:
		var first := a.position.distance_squared_to(target.point)
		var second := b.position.distance_squared_to(target.point)
		return a.id < b.id if first == second else first < second)
	for unit: MatchBattle.Unit in candidates:
		if required <= 0 or _orders_left <= 0:
			break
		var current: Assignment = _assignments.get(unit.id)
		var same_order := current != null and current.role == Role.CAMP and current.objective == target.id \
			and ((collect and unit.order == Order.MOVE) or (not collect and unit.order == Order.ATTACK))
		if not same_order:
			var ordered := false
			if not collect and battle.can_see(side, target.point):
				ordered = battle.order_attack(side, unit.id, intel.guard)
			else:
				ordered = battle.order_move(side, unit.id, target.point, true)
			_orders_left -= 1
			if not ordered:
				continue
			var assignment := Assignment.new(Role.CAMP, &"", target.point)
			assignment.objective = target.id
			_assignments[unit.id] = assignment
		available.erase(unit)
		required -= 1



func _attack(scene: Node3D, side: MatchRegion.Owner, difficulty: Dictionary,
		available: Array[MatchBattle.Unit], enemies: Array[MatchBattle.Unit],
		objective: MatchBattle.Outpost, now: float) -> void:
	var battle: MatchBattle = scene._battle
	var unassigned: Array[MatchBattle.Unit] = []
	var committed := 0
	# Keep existing strike orders ahead of new candidates to avoid turning the
	# entire army into units executing long Moves without returning fire.
	for unit in available:
		var current: Assignment = _assignments.get(unit.id)
		var target := battle.get_outpost(current.objective) if current != null and current.role == Role.ASSAULT else null
		if not _is_attack_objective(scene, side, target) or not _order_progresses(battle, unit):
			unassigned.append(unit)
			continue
		if unit.order == Order.MOVE and _in_contact(battle, unit, enemies):
			_apply_stance(battle, side, unit, _attack_stance(unit.type_id, difficulty))
		committed += 1

	for unit in unassigned:
		var stance := _attack_stance(unit.type_id, difficulty)
		# A route invalidated during travel falls back to Seek before it is retried.
		if _assignments.has(unit.id) and not _order_progresses(battle, unit):
			_retry_at[unit.id] = now + ROUTE_RETRY
		_assignments.erase(unit.id)
		if objective != null and committed < ASSAULT_SIZE and _orders_left > 0 \
				and not _retry_at.has(unit.id) and not _in_contact(battle, unit, enemies):
			if _order_attack(battle, side, unit, objective, stance, now):
				committed += 1
				continue
		_apply_stance(battle, side, unit, stance)


func _order_attack(battle: MatchBattle, side: MatchRegion.Owner, unit: MatchBattle.Unit,
		target: MatchBattle.Outpost, stance: MatchBattle.Stance, now: float) -> bool:
	var distance: float = unit.definition.range + MatchBattle.OUTPOST_ATTACK_RANGE - MatchBattle.UNIT_ATTACK_RANGE
	if unit.position.distance_squared_to(target.position) <= distance ** 2 \
			and battle.navigation.line_clear(unit.position, target.position, target.obstacle):
		return false
	var outward := target.position.direction_to(unit.position)
	var routes := battle.navigation.with_clearance(unit.definition.clearance)
	for angle: float in ORDER_ANGLES:
		var point := target.position + outward.rotated(angle) * (distance - 0.01)
		if not routes.is_passable(point) or not battle.navigation.line_clear(point, target.position, target.obstacle):
			continue
		if _orders_left == 0:
			break
		_orders_left -= 1
		if battle.order_move(side, unit.id, point, true):
			var assignment := Assignment.new(Role.ASSAULT, target.region_id, target.position)
			assignment.objective = target.id
			_assignments[unit.id] = assignment
			_apply_stance(battle, side, unit, stance, false)
			return true
	_retry_at[unit.id] = now + ROUTE_RETRY
	return false


func _attack_objective(scene: Node3D, side: MatchRegion.Owner, base: Vector2,
		enemies: Array[MatchBattle.Unit]) -> MatchBattle.Outpost:
	var best: MatchBattle.Outpost
	var best_score := INF
	var battle: MatchBattle = scene._battle
	var priority := battle.retaliation_target(side, base)
	for target: MatchBattle.Outpost in scene._outposts_by_region.values():
		if not _is_attack_objective(scene, side, target):
			continue
		var guards := 0
		for unit in enemies:
			if unit.side == target.side and unit.position.distance_squared_to(target.position) <= 4.0 ** 2:
				guards += 1
		var score := base.distance_to(target.position) + 5.0 * target.hp / target.max_hp + 1.5 * guards
		if target.side == priority:
			score -= 30.0
		if score < best_score or (score == best_score and target.region_id < best.region_id):
			best = target
			best_score = score
	return best


static func _is_attack_objective(scene: Node3D, side: MatchRegion.Owner,
		target: MatchBattle.Outpost) -> bool:
	return target != null and target.side != side and target.hp > 0.0 \
		and scene._battle.is_side_active(target.side) and scene._battle.can_see(side, target.position)


func _rally_region(scene: Node3D, owned: Array[MatchRegion], side: MatchRegion.Owner, goal: Vector2) -> MatchRegion:
	var best: MatchRegion
	var best_distance := INF
	for region in owned:
		var frontier := region.neighbor_ids.any(func(id: StringName) -> bool:
			return not scene.owns_region(side, id))
		if not frontier:
			continue
		var distance := goal.distance_squared_to(_site(region))
		if distance < best_distance or (distance == best_distance and region.region_id < best.region_id):
			best = region
			best_distance = distance
	return best


func _set_producer_stances(scene: Node3D, side: MatchRegion.Owner, danger: Array[Threat],
		rally: MatchRegion, difficulty: Dictionary) -> void:
	var battle: MatchBattle = scene._battle
	var reserve_producer: MatchBattle.ProductionTimer
	var closest := INF
	if rally != null:
		for timer in battle._timers:
			if timer.side != side or not timer.active or timer.hp <= 0.0:
				continue
			var distance := timer.position.distance_squared_to(_site(rally))
			if distance < closest or (distance == closest and timer.id > reserve_producer.id):
				closest = distance
				reserve_producer = timer
	for timer in battle._timers:
		if timer.side != side or not timer.active or timer.hp <= 0.0:
			continue
		var stance := _attack_stance(timer.unit_type, difficulty)
		var placed: RefCounted = scene._fortifications.get(timer.id)
		var local_pressure := danger.any(func(threat: Threat) -> bool:
			return (placed != null and threat.region.region_id in placed.regions) \
				or timer.position.distance_squared_to(threat.hub) <= float(scene.cpu_threat_radius) ** 2)
		if timer == reserve_producer or local_pressure:
			stance = Stance.IDLE
		if timer.default_stance != stance:
			battle.set_producer_stance(side, timer.id, stance)
		if timer != reserve_producer:
			if timer.rally_point.is_finite():
				battle.set_producer_rally(side, timer.id, Vector2.INF)
			continue
		var anchor := _site(rally)
		if timer.rally_point.distance_squared_to(anchor) <= 3.0 ** 2:
			continue
		var facing := anchor.direction_to(timer.position)
		if facing.is_zero_approx():
			facing = Vector2.RIGHT
		for angle: float in ORDER_ANGLES:
			var point := anchor + facing.rotated(angle) * 2.3
			if scene._layout.region_at(point) == rally.region_id \
					and battle.set_producer_rally(side, timer.id, point):
				break


static func has_cover(scene: Node3D, side: MatchRegion.Owner, hub: Vector2) -> bool:
	for placed in scene._fortifications.values():
		var fort: MatchBattle.Fortification = placed.defense
		if fort.side == side and fort.active and fort.hp > 0.0 and fort.profile.has("range") \
				and fort.position.distance_squared_to(hub) <= float(fort.profile.range) ** 2:
			return true
	return false


static func _order_progresses(battle: MatchBattle, unit: MatchBattle.Unit) -> bool:
	return unit.order == Order.AUTONOMOUS or unit.position == unit.ordered_destination \
		or unit.route_revision != battle.navigation.revision or not unit.waypoints.is_empty() \
		or not unit.wall_approach.is_empty()


static func _in_contact(battle: MatchBattle, unit: MatchBattle.Unit, enemies: Array[MatchBattle.Unit]) -> bool:
	for enemy in enemies:
		if unit.position.distance_squared_to(enemy.position) <= 2.5 ** 2 \
				and battle.navigation.line_clear(unit.position, enemy.position):
			return true
	return false


static func _attack_stance(type: StringName, difficulty: Dictionary) -> MatchBattle.Stance:
	if type == Catalog.RANGED and difficulty.local_threat_weight >= 2:
		return Stance.SEEK_STRONGEST
	return Stance.SEEK_NEAREST


static func _apply_stance(battle: MatchBattle, side: MatchRegion.Owner, unit: MatchBattle.Unit,
		stance: MatchBattle.Stance, cancel_order := true) -> void:
	if unit.stance != stance or (cancel_order and unit.order != Order.AUTONOMOUS):
		battle.set_unit_stance(side, unit.id, stance, cancel_order)


static func _site(region: MatchRegion) -> Vector2:
	return Vector2(region.position.x, region.position.z)
