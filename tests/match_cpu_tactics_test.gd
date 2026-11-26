extends SceneTree

const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const Tactics := preload("res://match/cpu_tactics.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const Order := MatchBattle.Order
const Stance := MatchBattle.Stance

var _failures := 0
var _scene: Node3D
var _battle: MatchBattle


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = Fixture.instantiate()
	_scene.map_seed = 17
	_scene.narrative_catalog = null
	root.add_child(_scene)
	_test_reserve_and_base_defense()
	_test_outposts()
	_test_blocked_route()
	_test_difficulty()
	_scene.free()
	if _failures == 0:
		print("CPU production stances, reserve rotation, defense, attacks and route recovery passed.")
	quit(int(_failures > 0))


func _prepare(level := 3) -> void:
	_scene.cpu_difficulty = level
	_scene.cpu_threat_radius = 5.0
	_scene.cpu_production_limit = 0
	_scene.cpu_expansion_limit = 0
	_scene.restart_match()
	_scene.set_process(false)
	_scene._cpu_strategy._next_defense = INF
	_battle = _scene._battle
	# Leave tactical decisions independent of opportunistic economic purchases.
	for resource in MatchEconomy.RESOURCES:
		_scene.economy.try_spend(CPU, {resource: int(_scene.economy.stockpile(CPU, resource))})


func _test_reserve_and_base_defense() -> void:
	_prepare()
	var home: Vector2 = _battle._bases[CPU]
	var army := _spawn_army(home + Vector2(-3.5, 2.0), 6)
	var base_region := _scene.get_region(TerritoryLayout.CPU_START) as MatchRegion
	_scene._try_cpu_purchase()
	var reserves := _with_order(army, Order.HOLD)
	_check(reserves.size() == 2 and _with_order(army, Order.AUTONOMOUS).size() == 4,
		"The CPU rallies a reserve in peacetime and sends the majority to attack.")
	for unit in reserves:
		_check(unit.stance == Stance.IDLE and unit.position != unit.ordered_destination
			and Geometry2D.is_point_in_polygon(unit.ordered_destination, base_region.polygon),
			"A reserve has a reachable rally post in friendly territory.")
		_scene._select_unit(unit.id)
		_check(not _scene._selected_unit_can_receive_orders()
			and not _battle.order_hold(PLAYER, unit.id), "CPU orders cannot be issued by the player.")

	if reserves.size() != 2:
		return
	var first: MatchBattle.Unit = reserves[0]
	var destination := first.ordered_destination
	_scene._try_cpu_purchase()
	_check(first.ordered_destination == destination
		and _scene._cpu_strategy._tactics._orders_left == Tactics.ORDER_BUDGET,
		"An unchanged tactical decision spends no new route requests.")
	_battle._base_health[PLAYER].hp = 1000.0
	var release_at: float = _scene._cpu_strategy._tactics._assignments[first.id].release_at
	_scene._advance_simulation(release_at + MatchBattle.STEP)
	_scene._try_cpu_purchase()
	_check(first.order == Order.AUTONOMOUS and first.stance != Stance.IDLE,
		"An expired reserve assignment releases the unit into Seek.")

	_prepare()
	home = _battle._bases[CPU]
	_scene.region_building_capacity = 12
	_scene.economy.advance(160.0)
	var kinds := [&"barracks", &"training_range", &"heavy_factory"]
	for kind: StringName in kinds:
		var point := _base_region_site(kind)
		_check(point.is_finite() and _scene.try_place_building(CPU, kind, _scene._world_position(point)),
			"The fixture purchases %s through the normal API." % kind)
	army = _spawn_army(home + Vector2(-3.0, 1.2), 6)
	var invaders: Array[MatchBattle.Unit] = []
	for offset in [-0.5, 0.0, 0.5]:
		invaders.append(_spawn(PLAYER, home + Vector2(-4.0, offset), Catalog.INFANTRY, Stance.IDLE))
	_scene._try_cpu_purchase()
	var guard := _with_order(army, Order.HOLD)
	_check(not guard.is_empty() and guard.size() < army.size()
		and guard.all(func(unit: MatchBattle.Unit) -> bool: return unit.stance != Stance.IDLE),
		"Base pressure creates a defensive line and leaves an attacking contingent.")
	_check(_battle._timers.size() == kinds.size() and _battle._timers.all(
		func(timer: MatchBattle.ProductionTimer) -> bool: return timer.default_stance == Stance.IDLE),
		"All three local producer kinds switch to Idle under pressure.")
	var deployed := {}
	_battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		if unit.side == CPU:
			deployed[unit.type_id] = unit.stance)
	_scene._advance_simulation(8.0)
	_check(deployed.size() == kinds.size() and deployed.values().all(
		func(stance: MatchBattle.Stance) -> bool: return stance == Stance.IDLE),
		"Mixed paid production inherits the configured defaults.")
	for unit in invaders:
		unit.hp = 0.0
	_scene._try_cpu_purchase()
	_check(_battle._timers.any(func(timer: MatchBattle.ProductionTimer) -> bool:
		return timer.default_stance != Stance.IDLE), "Ending pressure restores offensive production.")


func _test_outposts() -> void:
	_prepare()
	var home: Vector2 = _battle._bases[CPU]
	var friendly := _make_outpost(CPU, home)
	var target := _make_outpost(PLAYER, _battle._bases[PLAYER])
	_battle._base_health[PLAYER].hp = 200.0
	target.hp = 6.0
	var army := _spawn_army(friendly.position + Vector2(1.5, 0.0), 8)
	var attacker := _spawn(PLAYER, friendly.position + Vector2(0.0, -2.5), Catalog.INFANTRY, Stance.IDLE)
	_scene._try_cpu_purchase()
	var guards := _with_order(army, Order.HOLD)
	var strike := _with_order(army, Order.MOVE)
	_check(not guards.is_empty() and guards.all(func(unit: MatchBattle.Unit) -> bool:
		return Geometry2D.is_point_in_polygon(unit.ordered_destination, _scene.get_region(friendly.region_id).polygon)),
		"The CPU holds positions inside a threatened outpost region.")
	_check(not strike.is_empty() and strike.size() <= Tactics.ASSAULT_SIZE
		and strike.all(func(unit: MatchBattle.Unit) -> bool:
			return unit.resume_stance_on_arrival and unit.ordered_destination.distance_to(target.position) <= 3.2),
		"A bounded strike group moves to the vulnerable enemy outpost and resumes Seek on arrival.")
	attacker.hp = 0.0
	friendly.hp = 0.0
	_scene._advance_simulation(MatchBattle.STEP)
	_scene._try_cpu_purchase()
	_check(_scene.owns_region(NEUTRAL, friendly.region_id) and guards.all(
		func(unit: MatchBattle.Unit) -> bool: return unit.order != Order.HOLD \
			or not Geometry2D.is_point_in_polygon(unit.ordered_destination, _scene.get_region(friendly.region_id).polygon)),
		"Outpost destruction releases obsolete defense orders.")
	_scene._advance_simulation(15.0)
	_check(_battle.get_outpost(target.id) == null and _scene.owns_region(NEUTRAL, target.region_id),
		"The attacking force can reach and destroy the enemy outpost.")
	_scene._try_cpu_purchase()
	_check(_scene._cpu_strategy._tactics._assignments.values().all(
		func(assignment: Tactics.Assignment) -> bool: return assignment.objective != target.id),
		"Destroyed assault objectives are discarded.")
	_scene._process(30.0)
	_check(_battle.outcome() == MatchBattle.Outcome.DEFEAT,
		"The CPU can finish the match after taking an outpost.")


func _test_blocked_route() -> void:
	_prepare()
	var target := _make_outpost(PLAYER, _battle._bases[PLAYER])
	var army := _spawn_army(_battle._bases[CPU] + Vector2(-2.5, 1.5), 2)
	_scene._try_cpu_purchase()
	_check(_with_order(army, Order.MOVE).size() == 2, "The route fixture starts with valid assault orders.")
	var barrier_x := (target.position.x + army[0].position.x) * 0.5
	var bounds: Rect2 = _scene._layout.bounds
	var obstacle := _battle.navigation.add_obstacle(Rect2(barrier_x - 0.25, bounds.position.y, 0.5, bounds.size.y))
	_scene._advance_simulation(MatchBattle.STEP)
	_scene._try_cpu_purchase()
	_check(army.all(func(unit: MatchBattle.Unit) -> bool:
		return unit.order == Order.AUTONOMOUS and unit.stance != Stance.IDLE),
		"A newly blocked assault releases the units into Seek.")
	_scene._try_cpu_purchase()
	_check(_scene._cpu_strategy._tactics._orders_left == Tactics.ORDER_BUDGET,
		"Blocked orders back off without retrying on the next decision.")
	_battle.navigation.remove_obstacle(obstacle)
	_scene._advance_simulation(Tactics.ROUTE_RETRY + MatchBattle.STEP)
	_scene._try_cpu_purchase()
	_check(army.any(func(unit: MatchBattle.Unit) -> bool:
		return unit.order == Order.MOVE or unit.target == target.id),
		"The force can resume the attack when the route opens.")
	army[0].hp = 0.0
	_scene._advance_simulation(MatchBattle.STEP)
	_scene._try_cpu_purchase()
	_check(not _scene._cpu_strategy._tactics._assignments.has(army[0].id),
		"Dead units release their tactical assignments.")


func _test_difficulty() -> void:
	for level in [1, 5]:
		_prepare(level)
		var home: Vector2 = _battle._bases[CPU]
		var army := _spawn_army(home + Vector2(-2.5, 2.0), 4)
		_spawn(PLAYER, home + Vector2(-4.0, 0.0), Catalog.INFANTRY, Stance.IDLE)
		_scene._try_cpu_purchase()
		var held := _with_order(army, Order.HOLD)
		_check(not held.is_empty() and held.all(func(unit: MatchBattle.Unit) -> bool:
			return unit.stance == (Stance.IDLE if level == 1 else Stance.SEEK_NEAREST)),
			"Relaxed keeps a reserve against light pressure while Expert stations defenders.")


func _base_region_site(kind: StringName) -> Vector2:
	var region := _scene.get_region(TerritoryLayout.CPU_START) as MatchRegion
	return region.interior_point(func(site: Vector2) -> bool:
		return _scene._placement_block_reason(CPU, kind, _scene._world_position(site)).is_empty())


func _make_outpost(side: MatchRegion.Owner, toward: Vector2) -> MatchBattle.Outpost:
	var neutral: Array[MatchRegion] = []
	for region: MatchRegion in _scene._regions_by_id.values():
		if region.region_owner == NEUTRAL:
			neutral.append(region)
	neutral.sort_custom(func(a: MatchRegion, b: MatchRegion) -> bool:
		return a.interior_point().distance_squared_to(toward) < b.interior_point().distance_squared_to(toward))
	var region: MatchRegion = neutral[0]
	_scene._complete_claim(side, region.region_id, 0, region.interior_point(_battle.outpost_site_clear))
	return _scene._outposts_by_region[region.region_id]


func _spawn_army(center: Vector2, count: int) -> Array[MatchBattle.Unit]:
	var army: Array[MatchBattle.Unit] = []
	for i in count:
		army.append(_spawn(CPU, center + Vector2(0.0, 0.2 * i), Catalog.COMBAT_TYPES[i % 3]))
	return army


func _spawn(side: MatchRegion.Owner, position: Vector2, type: StringName,
		stance := Stance.SEEK_NEAREST) -> MatchBattle.Unit:
	var routes := _battle.navigation.with_clearance(Catalog.DEFINITIONS[type].clearance)
	for ring in range(5):
		for angle in range(8):
			var point := position + Vector2.from_angle(angle * TAU / 8.0) * 0.5 * ring
			if routes.is_passable(point):
				return _battle.spawn_unit(side, point, type, null, stance)
	assert(false, "The fixture needs a valid combat spawn.")
	return null


func _with_order(army: Array[MatchBattle.Unit], order: MatchBattle.Order) -> Array[MatchBattle.Unit]:
	return army.filter(func(unit: MatchBattle.Unit) -> bool: return unit.order == order)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
