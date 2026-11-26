extends SceneTree

const MatchScene := preload("res://main.tscn")
const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Scouts := preload("res://tests/scout_fixture.gd")
const Expeditions := preload("res://match/scout_expeditions.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const Rules := preload("res://match/fortification_rules.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const ENERGY := MatchEconomy.ENERGY
const FOOD := MatchEconomy.FOOD

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Fixture.instantiate()
	scene.map_seed = 17
	root.add_child(scene)
	var first := _parallel_claims(scene)
	_check(first == _parallel_claims(scene), "Restart reproduces targets, scout IDs and payment.")
	_test_claim_preferences(scene)
	_test_economy_and_defense(scene)
	_test_replacement(scene)
	scene.free()

	scene = MatchScene.instantiate()
	scene.map_seed = 17
	scene.region_count = 3
	scene.map_height = 18.0
	scene.legendary_count = 0
	scene.narrative_catalog = null
	root.add_child(scene)
	_test_no_routes(scene)
	_test_competition(scene)
	scene.free()

	_test_frontier_scale(24)
	_test_frontier_scale(128)
	if _failures == 0:
		print("CPU scout cadence, route choices, pressure, slots, costs, loss and restart passed.")
	quit(int(_failures > 0))


func _parallel_claims(scene: Node) -> Array:
	_prepare(scene)
	var battle: MatchBattle = scene._battle
	var expeditions: Expeditions = scene._expeditions
	_check(expeditions.slots[CPU].size() == 2 and expeditions.available(CPU).size() == 2,
		"Both CPU scouts are initially free.")
	var energy: float = scene.economy.energy(CPU)
	scene._try_cpu_purchase()
	var targets := expeditions.assignments.keys()
	_check(targets.size() == 1 and expeditions.available(CPU).size() == 1
		and scene.economy.energy(CPU) == energy - scene.claim_energy, "One cadence decision pays for one scout.")
	if targets.size() != 1:
		return []
	var target: StringName = targets[0]
	var first: Expeditions.Scout = expeditions.assignments[target]
	var unit := battle.get_unit(first.unit_id)
	var origin := unit.position
	_check(first.state == Expeditions.State.TRAVELING and not unit.waypoints.is_empty()
		and scene.owns_region(NEUTRAL, target) and scene._outposts_by_region.is_empty(),
		"The CPU uses real scout travel toward a still-neutral target.")
	_check(not scene.try_place_building(CPU, &"generator", scene._world_position(first.site)),
		"An active expedition grants no construction rights.")
	scene._try_cpu_purchase()
	_check(expeditions.assignments.size() == 1, "A decision before dispatch cooldown cannot double order.")
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(unit.position != origin and first.state == Expeditions.State.TRAVELING
		and first.remaining == scene.claim_duration, "Travel moves the Scout before the countdown starts.")
	var arrival: Array[float] = []
	battle.step_finished.connect(func() -> void:
		if first.state == Expeditions.State.CLAIMING and arrival.is_empty():
			arrival.append(first.remaining))
	# Simulate through the normal decision cadence and keep the first expedition active.
	scene._process(scene.cpu_scout_dispatch_interval)
	targets = expeditions.assignments.keys()
	_check(unit.position != origin and targets.size() == 2 and expeditions.available(CPU).is_empty(),
		"The one free scout takes a distinct target on a later decision.")
	if targets.size() != 2:
		return []
	var second: Expeditions.Scout = expeditions.assignments[targets[1]]
	_check(first.region_id == target and first.assigned() and second.unit_id != first.unit_id,
		"New opportunities do not redirect a productive expedition.")
	var paid: float = scene.economy.energy(CPU)
	scene._try_cpu_purchase()
	_check(expeditions.assignments.size() == 2 and scene.economy.energy(CPU) == paid,
		"Zero free scouts issue no further assignments or charges.")
	for step in ceili(expeditions.eta(first) / MatchBattle.STEP) + 2:
		if first.state == Expeditions.State.CLAIMING:
			break
		battle.advance(MatchBattle.STEP, scene.economy)
	_check(first.state == Expeditions.State.CLAIMING and arrival == [scene.claim_duration],
		"The claim countdown starts only on arrival.")
	battle.advance(first.remaining - MatchBattle.STEP, scene.economy)
	_check(scene.owns_region(NEUTRAL, target) and not scene._outposts_by_region.has(target),
		"Ownership and the outpost wait for the final claim tick.")
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(scene.owns_region(CPU, target) and scene._outposts_by_region.has(target)
		and first.state == Expeditions.State.AVAILABLE, "Timed completion creates an outpost and releases the Scout.")
	return [targets, first.unit_id, second.unit_id, paid]


func _test_claim_preferences(scene: Node) -> void:
	_prepare(scene)
	scene.cpu_scout_capacity_weight = 5.0
	scene.cpu_scout_connection_weight = 0.0
	scene.cpu_scout_travel_weight = 0.0
	scene.cpu_scout_landmark_weight = 0.0
	scene.cpu_scout_production_weight = 0.0
	var baseline := _dispatch_target(scene)
	if baseline.is_empty():
		_check(false, "The preference fixture has a reachable frontier.")
		return
	var original: Expeditions.Scout = scene._expeditions.assignments[baseline]
	var site := original.site
	_prepare(scene)
	# Consume every slot except the mandatory outpost slot in the original favorite.
	var covered: Array[StringName] = [baseline]
	for i in scene.region_building_capacity - 1:
		scene._register_region_structure(StringName("test/%d" % i), scene.LEGENDARY_KIND, covered)
	var candidate := _dispatch_target(scene)
	_check(not baseline.is_empty() and not candidate.is_empty() and candidate != baseline
		and scene.region_occupancy(baseline).free == 1,
		"Equal routes prefer room for future production after paying the outpost slot.")

	_prepare(scene)
	scene.economy.advance(15.0)
	var battle: MatchBattle = scene._battle
	var enemy := battle.spawn_unit(PLAYER, site, Catalog.INFANTRY)
	_check(enemy != null, "The pressure fixture places an enemy at the original favorite.")
	scene.cpu_threat_radius = 4.0
	candidate = _dispatch_target(scene)
	_check(not candidate.is_empty() and candidate != baseline,
		"Enemy presence at %s (%s, base %s) favors a safer alternative. Selected %s, retry %s." %
			[baseline, site, battle._bases[CPU], candidate, scene._cpu_strategy._claim_retry_at])
	scene.cpu_threat_radius = 10.0
	scene.cpu_scout_capacity_weight = 1.4
	scene.cpu_scout_connection_weight = 1.0
	scene.cpu_scout_travel_weight = 2.0
	scene.cpu_scout_landmark_weight = 1.2
	scene.cpu_scout_production_weight = 0.5


func _test_economy_and_defense(scene: Node) -> void:
	_prepare(scene)
	var energy: float = scene.economy.energy(CPU)
	scene.economy.try_spend(CPU, {ENERGY: int(energy) - scene.claim_energy})
	scene._try_cpu_purchase()
	_check(scene._expeditions.assignments.is_empty() and scene._cpu_strategy._claim_retry_at.is_empty()
		and scene.economy.energy(CPU) == scene.claim_energy,
		"An affordable claim waits when it would consume the defense reserve.")
	scene.economy.advance(10.0)
	_check(not _dispatch_target(scene).is_empty(), "Scout expansion resumes after replenishing the reserve.")

	_prepare(scene)
	scene.economy.set_income_source(CPU, FOOD, &"test_supply", "Test supply", -1.0)
	scene.economy.try_spend(CPU, {FOOD: int(scene.economy.stockpile(CPU, FOOD))})
	scene._try_cpu_purchase()
	_check(scene._expeditions.assignments.is_empty() and scene._fortifications.values().any(
		func(placed) -> bool: return placed.defense.kind == &"farm"),
		"A food shortage funds production income before an expedition.")

	_prepare(scene)
	var battle: MatchBattle = scene._battle
	var enemy := battle.spawn_unit(PLAYER, battle._bases[CPU] + Vector2(-4.0, 1.0), Catalog.INFANTRY)
	_check(enemy != null, "The defense fixture places a hostile unit near the CPU base.")
	scene._try_cpu_purchase()
	_check(scene._expeditions.assignments.is_empty() and scene._fortifications.values().any(
		func(placed) -> bool: return placed.defense.kind == Rules.NEST),
		"A threat to held ground prompts a defensive purchase before expansion.")


func _test_replacement(scene: Node) -> void:
	_prepare(scene)
	var target := _dispatch_target(scene)
	var battle: MatchBattle = scene._battle
	var expeditions: Expeditions = scene._expeditions
	if target.is_empty():
		return
	var scout: Expeditions.Scout = expeditions.assignments[target]
	var old_id := scout.unit_id
	battle.get_unit(old_id).hp = 0.0
	battle.advance(MatchBattle.STEP, scene.economy)
	var paid: float = scene.economy.energy(CPU)
	scene._try_cpu_purchase()
	_check(scout.state == Expeditions.State.DEAD and scene.economy.energy(CPU) == paid
		and scene.owns_region(NEUTRAL, target) and not expeditions.assignments.has(target),
		"Scout death releases a paid claim and imposes the shared replacement delay.")
	battle.advance(scene.cpu_scout_dispatch_interval, scene.economy)
	var alternate := _dispatch_target(scene)
	_check(not alternate.is_empty() and alternate != target,
		"The surviving scout pursues an alternative during the interruption backoff.")
	battle.advance(scene.scout_replacement_delay, scene.economy)
	scene._try_cpu_purchase()
	_check(scout.state == Expeditions.State.DEAD, "The replacement preserves the same Energy reserve.")
	scene.economy.advance(10.0)
	paid = scene.economy.energy(CPU)
	scene._try_cpu_purchase()
	_check(scout.state == Expeditions.State.AVAILABLE and scout.unit_id != old_id
		and scene.economy.energy(CPU) == paid - scene.scout_replacement_energy
		and expeditions.slots[CPU].size() == 2,
		"A replacement uses the shared price and roster slot. State %s, spent %s, targets %s, time %s." %
			[scout.state, paid - scene.economy.energy(CPU), expeditions.assignments.keys(), battle.elapsed_time()])


func _test_no_routes(scene: Node) -> void:
	_prepare(scene)
	var battle: MatchBattle = scene._battle
	var x: float = battle._bases[CPU].x * 0.5
	var wall := Rect2(x, scene._layout.bounds.position.y, 0.3, scene._layout.bounds.size.y)
	var blocker := battle.navigation.add_obstacle(wall)
	var energy: float = scene.economy.energy(CPU)
	var target := _first_frontier(scene)
	scene._try_cpu_purchase()
	var deadline: float = scene._cpu_strategy._claim_retry_at.get(target, 0.0)
	scene._try_cpu_purchase()
	_check(deadline > 0.0 and scene._cpu_strategy._claim_retry_at.get(target) == deadline
		and scene.economy.energy(CPU) == energy and scene._expeditions.assignments.is_empty(),
		"An unreachable target backs off without charging or repeating path probes.")
	battle.navigation.remove_obstacle(blocker)
	battle.advance(scene.cpu_placement_retry, scene.economy)
	_check(_dispatch_target(scene) == target, "After backoff the CPU retries a newly reachable route.")
	var expedition: Expeditions.Scout = scene._expeditions.assignments.get(target)
	if expedition == null:
		return
	battle.navigation.add_obstacle(wall)
	battle.advance(MatchBattle.STEP, scene.economy)
	_check(not expedition.assigned() and scene.economy.energy(CPU) == energy - scene.claim_energy
		and scene._cpu_strategy._claim_retry_at.get(target, 0.0) > battle.elapsed_time()
		and scene.owns_region(NEUTRAL, target), "A newly blocked route interrupts and backs off a paid expedition.")


func _test_competition(scene: Node) -> void:
	_prepare(scene)
	var target := _first_frontier(scene)
	# A full region is ineligible even where it has a clear physical route.
	var covered: Array[StringName] = [target]
	for i in scene.region_building_capacity:
		scene._register_region_structure(StringName("full/%d" % i), scene.LEGENDARY_KIND, covered)
	var energy: float = scene.economy.energy(CPU)
	scene._try_cpu_purchase()
	_check(scene._expeditions.assignments.is_empty() and scene.economy.energy(CPU) == energy
		and scene._cpu_strategy._claim_retry_at.is_empty(), "A full frontier is rejected before route probing.")

	_prepare(scene)
	_check(Scouts.dispatch(scene, PLAYER, target), "The human reserves the shared frontier first.")
	var human: Expeditions.Scout = scene._expeditions.assignments.get(target)
	scene._try_cpu_purchase()
	_check(scene._expeditions.assignments.get(target) == human and scene.economy.energy(CPU) == energy,
		"A competing expedition holds the reservation without charging the CPU.")
	if human == null:
		return
	scene._expeditions.recall(PLAYER, human.unit_id)
	_check(_dispatch_target(scene) == target, "Once the reservation clears, the CPU can dispatch there.")
	_prepare(scene)
	_check(Scouts.claim(scene, PLAYER, target), "The human can secure the only frontier.")
	scene._try_cpu_purchase()
	_check(scene._expeditions.assignments.is_empty() and scene.economy.energy(CPU) == energy,
		"Ownership changes leave no eligible regions and trigger no scout spending.")


func _test_frontier_scale(count: int) -> void:
	var scene := MatchScene.instantiate()
	scene.map_seed = 17
	scene.region_count = count
	scene.map_width = 80.0
	scene.map_height = 55.0
	scene.cpu_start_count = count / 3
	scene.legendary_count = 0
	scene.narrative_catalog = null
	root.add_child(scene)
	_prepare(scene)
	scene._battle.add_landmark_footprint(scene._layout.bounds)
	scene._try_cpu_purchase()
	var probes: int = scene._cpu_strategy._claim_retry_at.size()
	_check(scene._regions_by_id.size() == count and probes > 0 and probes <= 4
		and scene._expeditions.assignments.is_empty(), "The %d-region map caps failed route searches per decision." % count)
	scene.free()


func _prepare(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	scene.cpu_production_limit = 1
	scene.economy.advance(60.0)
	scene.economy.set_income_source(CPU, FOOD, &"test_supply", "Test supply", 5.0)
	var base: MatchRegion = scene.get_region(TerritoryLayout.CPU_START)
	var point := base.interior_point(func(site: Vector2) -> bool:
		return scene._placement_block_reason(CPU, &"barracks", scene._world_position(site)).is_empty())
	_check(point.is_finite() and scene.try_place_building(CPU, &"barracks", scene._world_position(point))
		and scene.try_upgrade(CPU, Scouts.barracks(scene._battle, CPU).id), "The fixture buys the opening producer and upgrade.")
	var battle: MatchBattle = scene._battle
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		unit.order = MatchBattle.Order.HOLD
		unit.ordered_destination = unit.position)
	battle.spawn_unit(CPU, battle._bases[CPU] + Vector2(2.0, 1.0), Catalog.INFANTRY)


func _dispatch_target(scene: Node) -> StringName:
	var before: Array = scene._expeditions.assignments.keys()
	scene._try_cpu_purchase()
	for target in scene._expeditions.assignments:
		if target not in before:
			return target
	return &""


func _first_frontier(scene: Node) -> StringName:
	return scene.get_region(TerritoryLayout.CPU_START).neighbor_ids[0]


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
