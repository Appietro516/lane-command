extends SceneTree

const ScoutFixture := preload("res://tests/scout_fixture.gd")

const MatchScene := preload("res://main.tscn")
const Fixture := preload("res://tests/prototype_match_fixture.gd")
const Pressure := preload("res://tests/capture_cpu_defense.gd")
const Rules := preload("res://match/fortification_rules.gd")
const Catalog := preload("res://match/unit_catalog.gd")
const CPU := MatchRegion.Owner.CPU
const PLAYER := MatchRegion.Owner.PLAYER
const NEUTRAL := MatchRegion.Owner.NEUTRAL
const PRODUCERS := [&"farm", &"mine", &"generator"]

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := MatchScene.instantiate()
	scene.map_seed = 17
	root.add_child(scene)
	var first := _economy_match(scene)
	scene.restart_match()
	_check(scene._fortifications.is_empty() and scene._outposts_by_region.is_empty()
		and ScoutFixture.combat_units(scene._battle).is_empty() and scene.economy.barracks_count(CPU) == 0,
		"Restart clears the CPU's deployments, construction and claims.")
	_check(first == _economy_match(scene), "Restart reproduces the seeded purchase and placement sequence.")
	_test_losses(scene)
	scene.free()

	scene = Fixture.instantiate()
	root.add_child(scene)
	var production_limit: int = scene.cpu_production_limit
	# Exercise both guns with slots available after the opening production purchases.
	scene.cpu_production_limit = 2
	_test_defense(scene)
	var defense := _snapshot(scene)
	scene.restart_match()
	_test_defense(scene)
	_check(defense == _snapshot(scene), "The same pressure produces the same walls after restart.")
	_test_defense_replacement(scene)
	scene.cpu_production_limit = production_limit
	_test_blocked_placement(scene)
	_test_scarcity(scene)
	scene.free()

	scene = MatchScene.instantiate()
	scene.region_count = 6
	scene.legendary_count = 0
	root.add_child(scene)
	_test_threat_opening(scene, Catalog.RANGED, true, &"heavy_factory")
	_test_threat_opening(scene, Catalog.HEAVY, false, &"heavy_factory")
	_test_threat_opening(scene, Catalog.HEAVY, true, &"training_range")
	_test_threat_opening(scene, Catalog.INFANTRY, false, &"raider_camp")
	_test_threat_opening(scene, Catalog.RAIDER, true, &"training_range")
	_test_existing_force(scene, Catalog.INFANTRY, &"heavy_factory")
	_test_existing_force(scene, Catalog.HEAVY, &"barracks")
	_test_existing_force(scene, Catalog.INFANTRY, &"aid_station", 10)
	_test_military_recovery(scene)
	_test_anti_tank_response(scene)
	scene.free()
	if _failures == 0:
		print("Seeded CPU economy, mixed production, claims, defenses, recovery and restart passed.")
	quit(int(_failures > 0))


func _economy_match(scene: Node) -> Array:
	scene.set_process(false)
	var deployments: Array[int] = []
	var garrison: Array[MatchBattle.Unit] = []
	var deployed_types := {}
	# Hold the match open and cap the test garrison while counting every deployment.
	var battle: MatchBattle = scene._battle
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void:
		if unit.side == CPU and unit.type_id != Catalog.SCOUT:
			deployments.append(unit.id)
			deployed_types[unit.type_id] = true
			unit.order = MatchBattle.Order.HOLD
			unit.ordered_destination = unit.position
			garrison.append(unit)
			if garrison.size() > 5:
				var retired: MatchBattle.Unit = garrison.pop_front()
				retired.hp = 0.0)
	scene._process(2.0)
	_check(battle.active_barracks_count(CPU) == 1 and is_equal_approx(scene.economy.energy(CPU), 14.5),
		"The opening barracks is paid for at the shared cost.")
	var blocked_stock := _stock(scene)
	var enemy_base: Vector2 = battle._bases[PLAYER]
	_check(not scene.try_place_building(CPU, &"mine", scene._world_position(enemy_base))
		and not scene.try_place_building(CPU, Rules.MORTAR, scene._world_position(battle._bases[CPU]))
		and not scene.try_place_wall(CPU, scene._world_position(enemy_base),
			scene._world_position(enemy_base + Vector2(0, 2)))
		and _stock(scene) == blocked_stock, "Unaffordable and illegal construction leaves all stockpiles intact.")
	scene._process(70.0)
	for kind in PRODUCERS:
		var count := _structures(scene, kind).size()
		_check(count >= 1 and count <= (1 if kind == &"mine" else 2),
			"Resource demand results in enough %s without runaway duplication. Found %d." % [kind, count])
	_check(not scene._outposts_by_region.is_empty(), "The CPU buys an outpost on the expanded map.")
	_check(_structures(scene, Rules.NEST).is_empty() and _structures(scene, Rules.MORTAR).is_empty()
		and _structures(scene, Rules.WALL).is_empty(), "The CPU saves combat spending in an uncontested match.")
	_check(scene._outposts_by_region.size() <= scene.cpu_expansion_limit, "The expansion limit bounds claims.")
	# Larger producers need the next round of economic investment and a clear site.
	scene._process(40.0)
	_check(battle.active_barracks_count(CPU) >= 1 and ScoutFixture.barracks(battle, CPU).level == 2
		and deployments.size() >= 24, "The CPU upgrades its Barracks and sustains deployments under normal income. Deployments: %d." % deployments.size())
	_check(deployed_types.has(Catalog.INFANTRY) and deployed_types.has(Catalog.RANGED)
		and deployed_types.has(Catalog.HEAVY) and not deployed_types.has(Catalog.RAIDER),
		"A peaceful economy deploys its original combined-arms roster and saves Raiders for infantry threats.")
	var food_demand := 0.0
	for timer in battle._timers:
		if timer.side == CPU and timer.active:
			food_demand += float(Catalog.DEFINITIONS[timer.unit_type].food) / timer.interval(scene.economy)
	_check(scene.economy.income_rate(CPU, MatchEconomy.FOOD) >= food_demand,
		"The mature economy can pay for every active producer's ongoing deployments.")
	var fielded_types := {}
	for unit in garrison:
		fielded_types[unit.type_id] = true
	_check(fielded_types.size() >= 2, "Different CPU unit types operate together in the field.")
	_check(battle._timers.size() <= scene.cpu_production_limit,
		"Sustained economic growth respects the military construction limit.")
	_check_ownership(scene)
	return _snapshot(scene)


func _test_losses(scene: Node) -> void:
	var mines := _structures(scene, &"mine")
	var battle: MatchBattle = scene._battle
	if mines.is_empty() or scene._outposts_by_region.is_empty():
		_check(false, "The recovery fixture requires a working mine and owned outpost.")
		return
	var mine: MatchBattle.Fortification = mines[0]
	var outpost: MatchBattle.Outpost
	var installed: MatchBattle.Fortification
	for placed in scene._fortifications.values():
		if placed.defense == mine or placed.defense.kind not in PRODUCERS:
			continue
		outpost = scene._outposts_by_region.get(placed.regions[0])
		if outpost != null:
			installed = placed.defense
			break
	if installed == null:
		_check(false, "The recovery fixture needs a resource producer at an outpost.")
		return
	scene.economy.advance(60.0)
	scene.cpu_expansion_limit = 0
	mine.hp = 0.0
	outpost.hp = 0.0
	scene._advance_simulation(MatchBattle.STEP)
	_check(battle.get_fortification(mine.id) == null and not installed.active
		and scene.owns_region(NEUTRAL, outpost.region_id), "Loss removes income and disables the exposed producer.")
	scene._process(36.0)
	_check(installed.active and scene.owns_region(CPU, outpost.region_id),
		"The CPU prioritizes reclaiming the outpost with a dormant investment.")
	# Depleted materials should prompt mine replacement, even after an established economy.
	scene.economy.try_spend(CPU, {MatchEconomy.MATERIALS: int(scene.economy.stockpile(CPU, MatchEconomy.MATERIALS))})
	scene._process(30.0)
	_check(_structures(scene, &"mine").size() == 1 and battle.active_barracks_count(CPU) >= 1,
		"The CPU recovers from producer loss and keeps its barracks active.")


func _test_defense(scene: Node) -> void:
	var shots := Pressure.exercise(scene, 14)
	for kind in [Rules.NEST, Rules.MORTAR]:
		_check(_structures(scene, kind).size() == 1 and shots.has(kind)
			and (shots.get(kind, []) as Array).has(true),
			"The CPU builds one %s at the threatened base and it damages enemies in profile range." % kind)
	var walls := _structures(scene, Rules.WALL)
	_check(walls.size() == 2, "The CPU responds with one two-segment barrier.")
	if walls.size() == 2:
		var battle: MatchBattle = scene._battle
		var wall: MatchBattle.Fortification = walls[0]
		var center := (wall.position + walls[1].position) * 0.5
		var normal := Vector2.from_angle(wall.angle).orthogonal()
		var start := center + normal * 0.75
		var end := center - normal * 0.75
		var nav := battle.navigation
		_check(not nav.line_clear(start, end) and not nav.path(start, end).is_empty(),
			"The CPU wall stops direct movement and leaves a navigable detour.")
		var friendly := MatchBattle.Unit.new(2000, CPU, start)
		battle._units[friendly.id] = friendly
		battle.unit_produced.emit(friendly)
		friendly.order = MatchBattle.Order.MOVE
		friendly.ordered_destination = end
		for unit in battle.active_units():
			if unit.side == PLAYER:
				unit.hp = 0.0
		scene._advance_simulation(3.0)
		_check(friendly.position.distance_to(end) < 0.1, "Friendly infantry takes the detour around the barrier.")
	_check_ownership(scene)


func _test_defense_replacement(scene: Node) -> void:
	var nests := _structures(scene, Rules.NEST)
	if nests.is_empty():
		return
	var nest: MatchBattle.Fortification = nests[0]
	nest.hp = 0.0
	scene._advance_simulation(MatchBattle.STEP)
	_check(_structures(scene, Rules.NEST).is_empty(), "The destroyed nest releases its site.")
	Pressure.exercise(scene, 4)
	nests = _structures(scene, Rules.NEST)
	_check(nests.size() == 1 and nests[0].id != nest.id,
		"Continued pressure prompts one replacement after a defensive loss.")


func _test_blocked_placement(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	scene._battle.add_landmark_footprint(scene._layout.bounds)
	scene._process(2.0)
	var retry_at: Dictionary = scene._cpu_strategy._retry_at
	var deadline: float = retry_at.get(&"barracks", 0.0)
	_check(deadline > scene._battle.elapsed_time() and scene.economy.barracks_count(CPU) == 0
		and is_equal_approx(scene.economy.energy(CPU), 54.5), "A blocked site search backs off without charging the CPU.")
	scene._process(2.0)
	_check(retry_at.get(&"barracks", 0.0) == deadline and is_equal_approx(scene.economy.energy(CPU), 59.0),
		"The next decision does not repeat a failed site search.")


func _test_scarcity(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	var costs := {}
	for resource in MatchEconomy.RESOURCES:
		costs[resource] = int(scene.economy.stockpile(CPU, resource))
	scene.economy.try_spend(CPU, costs)
	scene._process(10.0)
	var stock := _stock(scene)
	_check(scene._battle._timers.is_empty() and scene._cpu_strategy._retry_at.is_empty()
		and is_equal_approx(stock[MatchEconomy.ENERGY], 22.5)
		and is_equal_approx(stock[MatchEconomy.MATERIALS], 14.5)
		and is_equal_approx(stock[MatchEconomy.FOOD], 10.0),
		"Resource scarcity waits without site searches or spending.")
	scene._process(8.0)
	_check(_structures(scene, &"barracks").size() == 1
		and is_equal_approx(scene.economy.energy(CPU), 40.5 - MatchEconomy.BARRACKS_COST[MatchEconomy.ENERGY]),
		"The CPU resumes affordable production as soon as starting income covers the shared price.")


func _test_threat_opening(scene: Node, enemy_type: StringName, covered: bool, expected: StringName) -> void:
	_prepare_military_case(scene)
	if covered:
		_check(_place_cpu(scene, Rules.NEST), "A gun covers the CPU base in the defended opening.")
	_seed_force(scene, PLAYER, enemy_type, 3)
	var before := _stock(scene)
	scene._try_cpu_purchase()
	_check(_structures(scene, expected).size() == 1,
		"The opening against %s with cover %s selects %s." % [enemy_type, covered, expected])
	for resource in MatchEconomy.RESOURCES:
		_check(scene.economy.stockpile(CPU, resource) == before[resource]
			- scene.BUILDINGS[expected].cost.get(resource, 0), "The specialized opening pays the shared price.")


func _test_existing_force(scene: Node, allied_type: StringName, expected: StringName, reinforcements := 5) -> void:
	_prepare_military_case(scene)
	_check(_place_cpu(scene, &"barracks") and _place_cpu(scene, &"training_range"),
		"The existing force fixture starts with two kinds of producers.")
	_check(scene.try_upgrade(CPU, ScoutFixture.barracks(scene._battle, CPU).id), "The existing force fixture has an upgraded Barracks.")
	scene.economy.set_income_source(CPU, MatchEconomy.ENERGY, &"test_grid", "Test grid", 5.0)
	scene.economy.set_income_source(CPU, MatchEconomy.MATERIALS, &"test_mine", "Test mine", 5.0)
	_seed_force(scene, CPU, Catalog.RANGED, 1)
	_seed_force(scene, CPU, allied_type, reinforcements)
	var count := _structures(scene, expected).size()
	scene._try_cpu_purchase()
	_check(_structures(scene, expected).size() == count + 1,
		"Existing forces reinforced with %s shift investment toward %s. Buildings: %s."
			% [allied_type, expected, _snapshot(scene)[0]])


func _test_military_recovery(scene: Node) -> void:
	_prepare_military_case(scene)
	# Keep economic investment from displacing the production recovery decision.
	scene.economy.set_income_source(CPU, MatchEconomy.ENERGY, &"test_grid", "Test grid", 5.0)
	scene.economy.set_income_source(CPU, MatchEconomy.MATERIALS, &"test_mine", "Test mine", 5.0)
	scene.cpu_production_target = 2
	scene.cpu_production_limit = 3
	_check(_place_cpu(scene, &"barracks") and _place_cpu(scene, &"training_range")
		and scene.try_upgrade(CPU, ScoutFixture.barracks(scene._battle, CPU).id), "The recovery fixture starts at its peacetime cap without Heavy production.")
	_seed_force(scene, PLAYER, Catalog.RANGED, 4)
	scene._process(2.0)
	var factories := _structures(scene, &"heavy_factory")
	_check(factories.size() == 1, "Incoming Ranged units prompt a counter investment above the peacetime cap. Buildings: %s."
		% [_snapshot(scene)[0]])
	if factories.is_empty():
		return
	var battle: MatchBattle = scene._battle
	var original: MatchBattle.Fortification = factories[0]
	original.hp = 0.0
	scene._advance_simulation(MatchBattle.STEP)
	_check(battle.get_fortification(original.id) == null, "Losing a factory removes its production timer.")
	# Make the replacement decision while the same visible ranged threat remains.
	scene._try_cpu_purchase()
	factories = _structures(scene, &"heavy_factory")
	_check(factories.size() == 1 and factories[0].id != original.id and battle._timers.size() == 3,
		"The CPU replaces lost counter production without exceeding the construction cap. Buildings: %s."
			% [_snapshot(scene)[0]])
	if factories.is_empty():
		return
	var replacement := factories[0] as MatchBattle.ProductionTimer
	var deployments: Array[MatchBattle.Unit] = []
	battle.unit_produced.connect(func(unit: MatchBattle.Unit) -> void: deployments.append(unit))
	battle.advance(replacement.interval(scene.economy), scene.economy)
	_check(deployments.any(func(unit: MatchBattle.Unit) -> bool:
		return unit.side == CPU and unit.type_id == Catalog.HEAVY),
		"The replacement factory completes a normal Heavy deployment.")
	_check_ownership(scene)


func _test_anti_tank_response(scene: Node) -> void:
	_prepare_military_case(scene)
	_check(_place_cpu(scene, &"barracks"), "The armor-defense fixture can support a military opening.")
	scene._cpu_strategy._next_defense = 0.0
	_seed_force(scene, PLAYER, Catalog.HEAVY, 3)
	scene._try_cpu_purchase()
	_check(_structures(scene, Rules.ANTI_TANK).size() == 1,
		"Several visible Heavy attackers prompt an anti-tank emplacement.")


func _prepare_military_case(scene: Node) -> void:
	scene.restart_match()
	scene.set_process(false)
	scene.cpu_expansion_limit = 0
	scene.economy.advance(100.0)
	scene.economy.set_income_source(CPU, MatchEconomy.FOOD, &"test_supply", "Test supply", 10.0)
	# The defense tests exercise new fortification purchases separately.
	scene._cpu_strategy._next_defense = 60.0


func _place_cpu(scene: Node, kind: StringName) -> bool:
	var region: MatchRegion = scene.get_region(TerritoryLayout.CPU_START)
	var point := region.interior_point(func(site: Vector2) -> bool:
		return scene._placement_block_reason(CPU, kind, scene._world_position(site)).is_empty())
	return point.is_finite() and scene.try_place_building(CPU, kind, scene._world_position(point))


func _seed_force(scene: Node, side: MatchRegion.Owner, type: StringName, count: int) -> void:
	var battle: MatchBattle = scene._battle
	var base: Vector2 = battle._bases[CPU]
	var distance := -6.0 if side == PLAYER else 1.5
	for index in range(count):
		var position := base + Vector2(distance, 3.0 + index * 0.35)
		var unit := battle.spawn_unit(side, position, type)
		if unit == null:
			for candidate in 16:
				var offset := Vector2.from_angle(TAU * candidate / 16.0) * 3.0
				unit = battle.spawn_unit(side, position + offset, type)
				if unit != null:
					break
		_check(unit != null, "The scenario can position its starting force.")
		if unit != null:
			unit.order = MatchBattle.Order.HOLD
			unit.ordered_destination = unit.position


func _check_ownership(scene: Node) -> void:
	for region_id in scene._regions_by_id:
		if scene.owns_region(CPU, region_id):
			var occupancy: Dictionary = scene.region_occupancy(region_id)
			_check(occupancy.used <= occupancy.capacity, "CPU construction stays within each region's capacity.")
	for placed in scene._fortifications.values():
		if placed.defense.side == CPU:
			for region_id in placed.regions:
				_check(scene.owns_region(CPU, region_id), "The CPU builds structures in owned regions only.")


func _snapshot(scene: Node) -> Array:
	var buildings := []
	for placed in scene._fortifications.values():
		var fort: MatchBattle.Fortification = placed.defense
		if fort.side == CPU:
			buildings.append([fort.kind, fort.position, fort.angle, fort.active])
	return [buildings, scene._outposts_by_region.keys(), _stock(scene)]


func _stock(scene: Node) -> Dictionary:
	var stocks := {}
	for resource in MatchEconomy.RESOURCES:
		stocks[resource] = scene.economy.stockpile(CPU, resource)
	return stocks


func _structures(scene: Node, kind: StringName) -> Array[MatchBattle.Fortification]:
	var result: Array[MatchBattle.Fortification] = []
	for placed in scene._fortifications.values():
		if placed.defense.kind == kind and placed.defense.side == CPU and placed.defense.active:
			result.append(placed.defense)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
